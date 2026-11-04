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
import 'package:pandora_mobile/features/personal_todos/presentation/todo_editor.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';
import 'package:pandora_mobile/features/dashboard/dashboard_home.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class TodoAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool fail = false, malformed = false;
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
        : {'items': [], 'total': 0, 'nextCursor': malformed ? '0' : null};
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
  testWidgets('account switch clears prior day and pending command', (
    tester,
  ) async {
    final old = DemoTodoRepository();
    final date = civilDate(shanghaiToday());
    await old.execute(
      TodoCommand('POST', null, {'title': 'Alice private', 'date': date}),
    );
    final waiting = Completer<TodoPage>();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => const Session(id: 'alice')),
        todoDayProvider.overrideWith(
          (ref, key) => ref.watch(sessionProvider).id == 'alice'
              ? old.day(key.$1, key.$2)
              : waiting.future,
        ),
        todoMonthProvider.overrideWith((ref, month) => old.calendar(month)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DailyTodosSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice private'), findsOneWidget);
    container.read(pendingTodoCommandProvider.notifier).state = TodoCommand(
      'POST',
      null,
      {'title': 'Alice pending', 'date': date},
    );
    container.read(sessionProvider.notifier).state = const Session(id: 'bob');
    await tester.pump();
    await tester.pump();
    expect(find.text('Alice private'), findsNothing);
    expect(container.read(pendingTodoCommandProvider), isNull);
    waiting.complete(const TodoPage([], 0, null));
    await tester.pumpAndSettle();
  });
  testWidgets('homepage exposes new sections and no personal task/log cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const Session(id: 'alice', role: UserRole.employee),
          ),
          homePreviewProvider.overrideWith(
            (ref, resource) async => const PageResult([]),
          ),
          todoRepositoryProvider.overrideWithValue(DemoTodoRepository()),
        ],
        child: MaterialApp(theme: appTheme(), home: const DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('事件纪'), findsOneWidget);
    expect(find.text('任务看板'), findsOneWidget);
    expect(find.text('每日事项'), findsOneWidget);
    expect(find.text('个人日志'), findsNothing);
    expect(find.text('个人十大任务'), findsNothing);
    expect(find.byTooltip('派发任务'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
  for (final width in [320.0, 360.0, 390.0, 480.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('month and editor fit $width at $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            const Padding(
              padding: EdgeInsets.all(12),
              child: DailyTodosSection(),
            ),
            DemoTodoRepository(),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('事项'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('请填写事项标题'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      });
    }
  }
}
