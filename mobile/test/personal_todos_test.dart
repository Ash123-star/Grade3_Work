import 'package:flutter/cupertino.dart';
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
  Future<TodoPage> day(String date, String cursor) async {
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
  Future<void> waitForRepair(WidgetTester tester) async {
    final indicator = find.byKey(const ValueKey('todo-list-repair'));
    for (var frame = 0; frame < 20 && indicator.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(indicator, findsOneWidget);
  }

  for (final changesTotal in [false, true]) {
    testWidgets(
      'pagination re-reads after concurrent ${changesTotal ? 'total change' : 'same-total ordering change'}',
      (tester) async {
        final repo = MovingTodoRepository(changeTotal: changesTotal)
          ..repairGate = Completer<void>();
        await tester.pumpWidget(host(const DailyTodosSection(), repo));
        await tester.pumpAndSettle();
        expect(find.text('并发事项30'), findsNothing);
        await tester.ensureVisible(find.text('加载更多事项'));
        await tester.tap(find.text('加载更多事项'));
        await waitForRepair(tester);
        expect(find.text('并发事项0'), findsOneWidget);
        expect(find.textContaining('31件事项'), findsOneWidget);
        repo.repairGate!.complete();
        await tester.pumpAndSettle();

        for (var i = 0; i < (changesTotal ? 32 : 31); i++) {
          expect(find.text('并发事项$i'), findsOneWidget);
        }
        expect(find.text('加载更多事项'), findsNothing);
        expect(find.byKey(const ValueKey('todo-list-repair')), findsNothing);
        expect(repo.reads, ['0', '30', '0', '30']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pagination recovery failure preserves rows and retries once on request',
    (tester) async {
      final repo = MovingTodoRepository(failRepair: true);
      await tester.pumpWidget(host(const DailyTodosSection(), repo));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('加载更多事项'));
      await tester.tap(find.text('加载更多事项'));
      await tester.pumpAndSettle();
      expect(repo.reads, ['0', '30', '0']);
      expect(find.text('并发事项0'), findsOneWidget);
      expect(find.text('并发事项29'), findsOneWidget);
      expect(find.text('并发事项30'), findsNothing);
      expect(find.textContaining('尚未加载完整'), findsOneWidget);
      expect(find.text('加载更多事项'), findsNothing);
      repo.failRepair = false;
      final retry = find.byKey(const ValueKey('retry-todo-list-repair'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('并发事项30'), findsOneWidget);
      expect(repo.reads, ['0', '30', '0', '0', '30']);
      expect(find.textContaining('尚未加载完整'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial background refresh keeps stable rows when reordered pages overlap and the last page fails',
    (tester) async {
      final date = civilDate(shanghaiToday());
      TodoPage page(int start, int end, String? next) => TodoPage(
        [
          for (var i = start; i < end; i++)
            PersonalTodo(
              id: 'refresh-$i',
              title: '刷新事项$i',
              note: '',
              date: date,
              completed: false,
              version: 1,
            ),
        ],
        61,
        next,
      );
      var refreshing = false;
      final refreshes = {
        for (final cursor in ['0', '30', '60']) cursor: Completer<TodoPage>(),
      };
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session(id: 'alice')),
          todoMonthProvider.overrideWith((ref, month) async => {}),
          todoDayProvider.overrideWith((ref, key) async {
            if (refreshing) return refreshes[key.$2]!.future;
            return switch (key.$2) {
              '0' => page(0, 30, '30'),
              '30' => page(30, 60, '60'),
              _ => page(60, 61, null),
            };
          }),
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
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('加载更多事项'));
        await tester.tap(find.text('加载更多事项'));
        await tester.pumpAndSettle();
      }

      refreshing = true;
      container.invalidate(todoDayProvider);
      await tester.pump();
      // The second page sees the old order; the first sees a completed item
      // moved past its boundary. Neither partial snapshot may replace the list.
      refreshes['30']!.complete(page(30, 60, '60'));
      await tester.pump();
      refreshes['0']!.complete(page(1, 31, '30'));
      await tester.pump();
      for (var i = 0; i < 61; i++) {
        expect(find.text('刷新事项$i'), findsOneWidget);
      }
      expect(find.textContaining('61件事项'), findsOneWidget);

      refreshes['60']!.completeError(
        const ApiFailure(FailureKind.unavailable, '末页重新读取断网'),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 61; i++) {
        expect(find.text('刷新事项$i'), findsOneWidget);
      }
      expect(find.textContaining('尚未加载完整'), findsOneWidget);
      expect(find.text('加载更多事项'), findsNothing);
      expect(find.byKey(const ValueKey('todo-list-repair')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination recovery cannot restore a previous account response',
    (tester) async {
      final alice = MovingTodoRepository()..repairGate = Completer<void>();
      final bob = DemoTodoRepository();
      await bob.execute(
        TodoCommand('POST', null, {'title': 'Bob独立事项', 'date': alice.date}),
      );
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session(id: 'alice')),
          todoRepositoryProvider.overrideWith(
            (ref) => ref.watch(sessionProvider).id == 'alice' ? alice : bob,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: DailyTodosSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('加载更多事项'));
      await tester.tap(find.text('加载更多事项'));
      await waitForRepair(tester);
      container.read(sessionProvider.notifier).state = const Session(id: 'bob');
      await tester.pumpAndSettle();
      expect(find.text('Bob独立事项'), findsNWidgets(2));
      expect(find.text('并发事项0'), findsNothing);
      alice.repairGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Bob独立事项'), findsNWidgets(2));
      expect(find.textContaining('并发事项'), findsNothing);
      expect(find.byKey(const ValueKey('todo-list-repair')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Alice private'), findsNWidgets(2));
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
  testWidgets(
    'month heading selects a month and cancel keeps the current day',
    (tester) async {
      final repo = DemoTodoRepository();
      await tester.pumpWidget(host(const DailyTodosSection(), repo));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
      final heading = find.byKey(const ValueKey('todo-month-picker'));
      await tester.tap(heading);
      await tester.pumpAndSettle();
      final wheel = tester.widget<CupertinoDatePicker>(
        find.byKey(const ValueKey('todo-month-wheel')),
      );
      expect(wheel.mode, CupertinoDatePickerMode.monthYear);
      expect(wheel.minimumYear, 1900);
      expect(wheel.maximumYear, 2100);
      wheel.onDateTimeChanged(DateTime(2028, 2));
      await tester.tap(find.byKey(const ValueKey('todo-month-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('2028年 2月'), findsOneWidget);
      expect(find.text('2月1日'), findsOneWidget);
      await tester.tap(heading);
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(
            find.byKey(const ValueKey('todo-month-wheel')),
          )
          .onDateTimeChanged(DateTime(1900, 1));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('2028年 2月'), findsOneWidget);
      await tester.tap(heading);
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(
            find.byKey(const ValueKey('todo-month-wheel')),
          )
          .onDateTimeChanged(DateTime(2100, 12));
      await tester.tap(find.byKey(const ValueKey('todo-month-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('2100年 12月'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下个月',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
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
        await tester.tap(find.byKey(const ValueKey('todo-month-picker')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('新增事项'));
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
