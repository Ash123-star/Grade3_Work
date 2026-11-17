import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/personal_todos/application/todo_providers.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/daily_todos_section.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/todo_calendar_source.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/todo_editor.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';

class TodoAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool fail = false, malformed = false;
  List<Map<String, dynamic>> rows = [];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(o);
    if (fail) {
      throw DioException(
        requestOptions: o,
        type: DioExceptionType.receiveTimeout,
      );
    }
    final body = o.method == 'POST'
        ? {
            'id': 't1',
            ...o.data as Map,
            'note': '',
            'completed': false,
            'version': 1,
          }
        : {
            'items': rows,
            'total': rows.length,
            'nextCursor': malformed ? '0' : null,
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class UncertainTodoRepository extends DemoTodoRepository {
  bool uncertain = true;
  final commands = <TodoCommand>[];
  @override
  Future<void> execute(TodoCommand c) async {
    commands.add(c);
    await super.execute(c);
    if (uncertain) throw const ApiFailure(FailureKind.unavailable, 'network');
  }
}

/// The next OFFSET page observes a concurrent completion or insertion.
class MovingTodoRepository extends DemoTodoRepository {
  MovingTodoRepository({this.changeTotal = false, this.failRepair = false});
  final bool changeTotal;
  bool failRepair, changed = false;
  Completer<void>? repairGate;
  final reads = <String>[];
  final date = civilDate(shanghaiToday());
  PersonalTodo row(int index, {bool completed = false}) => PersonalTodo(
    id: 'moving-$index',
    title: '并发事项$index',
    note: '',
    date: date,
    completed: completed,
    version: completed ? 2 : 1,
  );

  @override
  Future<TodoPage> month(String month, String cursor) async {
    reads.add(cursor);
    if (cursor == '0' && changed) {
      await repairGate?.future;
      if (failRepair) {
        throw const ApiFailure(FailureKind.unavailable, '重新读取断网');
      }
    }
    if (!changed && cursor == '30') {
      changed = true;
      return changeTotal
          ? TodoPage([row(30), row(31)], 32, null)
          : TodoPage([row(0, completed: true)], 31, null);
    }
    final rows = [
      if (changed && !changeTotal) ...[
        for (var i = 1; i < 31; i++) row(i),
        row(0, completed: true),
      ] else ...[
        for (var i = 0; i < (changed && changeTotal ? 32 : 31); i++) row(i),
      ],
    ];
    final start = int.parse(cursor);
    return TodoPage(
      rows.skip(start).take(30).toList(),
      rows.length,
      start + 30 < rows.length ? '${start + 30}' : null,
    );
  }
}

Widget host(Widget child, TodoRepository repo, {double scale = 1}) =>
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => const Session(id: 'alice')),
        todoRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  test(
    'HTTP month accepts adjacent grid days and rejects outside rows',
    () async {
      final adapter = TodoAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://unit.test/api'));
      dio.httpClientAdapter = adapter;
      final repo = HttpTodoRepository(dio);
      Map<String, dynamic> row(String date) => {
        'id': date,
        'title': date,
        'note': '',
        'date': date,
        'endDate': date,
        'completed': false,
        'version': 1,
      };
      adapter.rows = [row('2026-10-26'), row('2026-12-06')];
      final page = await repo.month('2026-11', '0');
      expect(page.items.map((t) => t.date), ['2026-10-26', '2026-12-06']);
      expect(adapter.requests.single.path, '/personal-todos/month');
      expect(adapter.requests.single.queryParameters, {
        'month': '2026-11',
        'cursor': '0',
        'limit': 100,
      });
      for (final date in ['2026-10-25', '2026-12-07']) {
        adapter.rows = [row(date)];
        await expectLater(
          repo.month('2026-11', '0'),
          throwsA(isA<ApiFailure>()),
        );
      }
    },
  );
  test(
    'month records cover the shared full week grid including adjacent days',
    () async {
      final repo = DemoTodoRepository();
      for (final date in [
        '2026-10-25',
        '2026-10-26',
        '2026-12-06',
        '2026-12-07',
      ]) {
        await repo.execute(
          TodoCommand('POST', null, {'title': date, 'date': date}),
        );
      }
      final page = await repo.month('2026-11', '0');
      expect(page.items.map((t) => t.date), ['2026-10-26', '2026-12-06']);
      expect(page.total, 2);
    },
  );
  for (final changeTotal in [false, true]) {
    test(
      'month pagination retries a concurrent ${changeTotal ? 'count' : 'ordering'} change once',
      () async {
        final repo = MovingTodoRepository(changeTotal: changeTotal);
        final c = ProviderContainer(
          overrides: [todoRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(c.dispose);
        final p = todoCalendarRecordsProvider(
          civilDate(shanghaiToday()).substring(0, 7),
        );
        final subscription = c.listen(p, (_, _) {});
        addTearDown(subscription.close);
        final page = await c.read(p.future);
        expect(page.total, changeTotal ? 32 : 31);
        expect(page.items.map((r) => r.id).toSet().length, page.total);
        expect(repo.reads, ['0', '30', '0', '30']);
      },
    );
  }
  test(
    'month pagination exposes a failed recovery instead of a partial month',
    () async {
      final repo = MovingTodoRepository(failRepair: true);
      final c = ProviderContainer(
        overrides: [todoRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final p = todoCalendarRecordsProvider(
        civilDate(shanghaiToday()).substring(0, 7),
      );
      final subscription = c.listen(p, (_, _) {});
      addTearDown(subscription.close);
      await expectLater(c.read(p.future), throwsA(isA<ApiFailure>()));
      expect(repo.reads, ['0', '30', '0']);
    },
  );
  for (final width in [320.0, 360.0, 390.0, 480.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('shared month and todo editor fit $width at $scale', (
        t,
      ) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          host(const DailyTodosSection(), DemoTodoRepository(), scale: scale),
        );
        await t.pumpAndSettle();
        expect(find.byType(CalendarContent), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-month-timeline')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.tap(find.text('新增事项'));
        await t.pumpAndSettle();
        await t.tap(find.text('保存'));
        await t.pumpAndSettle();
        expect(find.text('请填写事项标题'), findsOneWidget);
        await t.tap(find.text('取消'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
  test('civil dates reject invalid inputs and span leap/year boundaries', () {
    expect(() => parseCivilDate('2026-02-30'), throwsFormatException);
    expect(() => parseCivilDate('1899-12-31'), throwsFormatException);
    expect(monthDays(DateTime(2028, 2)).where((d) => d.month == 2).length, 29);
    expect(monthDays(DateTime(2027, 1)).first, DateTime(2026, 12, 28));
    expect(
      civilDate(shanghaiToday(DateTime.utc(2026, 11, 4, 16))),
      '2026-11-05',
    );
  });
  test(
    'HTTP uses private path; uncertain retry keeps immutable command/key',
    () async {
      final adapter = TodoAdapter(),
          dio = Dio(BaseOptions(baseUrl: 'https://unit.test/api'));
      dio.httpClientAdapter = adapter;
      final repo = HttpTodoRepository(dio);
      final command = TodoCommand('POST', null, {
        'title': '阅读',
        'date': '2026-11-04',
      });
      adapter.fail = true;
      await expectLater(repo.execute(command), throwsA(isA<ApiFailure>()));
      adapter.fail = false;
      await repo.execute(command);
      expect(
        adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {command.key},
      );
      expect(adapter.requests.every((r) => r.path == '/personal-todos'), true);
      expect(() => command.body['title'] = 'changed', throwsUnsupportedError);
      adapter.malformed = true;
      await expectLater(
        repo.day('2026-11-04', '0'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('demo lifecycle supports version conflict and delete replay', () async {
    final repo = DemoTodoRepository();
    final c = TodoCommand('POST', null, {'title': '阅读', 'date': '2026-11-04'});
    await repo.execute(c);
    final original = await repo.detail(c.key);
    final done = TodoCommand('PUT', c.key, {
      ...original.editBody,
      'completed': true,
    });
    await repo.execute(done);
    await repo.execute(done);
    expect((await repo.detail(c.key)).version, 2);
    await expectLater(
      repo.execute(TodoCommand('PUT', c.key, original.editBody)),
      throwsA(isA<ApiFailure>()),
    );
    final remove = TodoCommand('DELETE', c.key, {'version': 2});
    await repo.execute(remove);
    await repo.execute(remove);
    expect((await repo.day('2026-11-04', '0')).items, isEmpty);
  });
  testWidgets('editor preserves uncertain request across close and retry', (
    tester,
  ) async {
    final repo = UncertainTodoRepository();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTodoEditor(context, date: '2026-11-04'),
            child: const Text('open'),
          ),
        ),
        repo,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('todo-title')), '保留输入');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('稍后确认'), findsOneWidget);
    await tester.tap(find.text('稍后确认'));
    await tester.pumpAndSettle();
    repo.uncertain = false;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('保留输入'), findsOneWidget);
    await tester.tap(find.text('重试原操作'));
    await tester.pumpAndSettle();
    expect(repo.commands.length, 2);
    expect(repo.commands[0].key, repo.commands[1].key);
    expect((await repo.day('2026-11-04', '0')).total, 1);
  });
}
