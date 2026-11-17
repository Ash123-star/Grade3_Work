import 'package:pandora_mobile/features/calendar/calendar_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/personal_todos/application/todo_providers.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/daily_todos_section.dart';
import 'package:pandora_mobile/features/personal_todos/presentation/todo_calendar_source.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ProviderContainer> mount(
    WidgetTester t,
    DemoTodoRepository repo,
  ) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith(
          (ref) => const Session(
            id: 'alice',
            role: UserRole.employee,
            dispatch: false,
          ),
        ),
        todoRepositoryProvider.overrideWith(
          (ref) => ref.watch(sessionProvider).id == 'alice'
              ? repo
              : DemoTodoRepository(),
        ),
        todoCalendarDateProvider.overrideWith((ref) => DateTime(2026, 11, 2)),
      ],
    );
    await t.pumpWidget(
      OwnedTestProviderScope(
        container: c,
        child: MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DailyTodosSection()),
          ),
        ),
      ),
    );
    await settleLocalIo(t);
    await t.pumpAndSettle();
    return c;
  }

  testWidgets(
    'home quick date selector jumps directly and rejects stale moves',
    (t) async {
      final repo = DemoTodoRepository();
      final command = TodoCommand('POST', null, {
        'title': '版本保护',
        'date': '2026-11-02',
      });
      await repo.execute(command);
      final c = await mount(t, repo);
      await t.tap(find.byKey(const ValueKey('todo-quick-date')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('quick-date-年')), '2028');
      await t.tap(find.byKey(const ValueKey('quick-date-confirm')));
      await t.pumpAndSettle();
      expect(c.read(todoCalendarDateProvider), DateTime(2028, 11, 2));
      final original = await repo.detail(command.key);
      await repo.execute(
        TodoCommand('PUT', original.id, {
          ...original.editBody,
          'title': '另一客户端更新',
        }),
      );
      final state = t.state<CalendarInteractionSurfaceState>(
        find.byType(CalendarInteractionSurface),
      );
      await state.move(
        todoCalendarRecord(original, 'alice'),
        1,
        CalendarConstraints(
          DateTime.utc(1900),
          DateTime.utc(2100, 12, 31),
          'calendar-v1-2026',
        ),
      );
      await t.pumpAndSettle();
      expect((await repo.detail(original.id)).date, '2026-11-02');
      expect(find.text('确认移动排期'), findsNothing);
      expect(find.textContaining('版本或权限已变化'), findsOneWidget);
      expect(find.textContaining('调休数据待更新'), findsNothing);
    },
  );

  testWidgets('private calendar accepts both supported year boundaries', (
    t,
  ) async {
    final c = await mount(t, DemoTodoRepository());
    for (final date in [DateTime(1900, 1, 1), DateTime(2100, 12, 31)]) {
      c.read(todoCalendarDateProvider.notifier).state = date;
      await t.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey('month-day:${date.year}-${date.month}-${date.day}'),
        ),
        findsWidgets,
      );
      expect(t.takeException(), isNull);
    }
  });

  testWidgets(
    'employee long presses a shared month cell to create a private todo',
    (t) async {
      final repo = DemoTodoRepository();
      final c = await mount(t, repo);
      final companyDate = c.read(selectedDateProvider);
      expect(find.byType(CalendarContent), findsOneWidget);
      await t.longPress(
        find.byKey(const ValueKey('month-day:2026-11-5')).hitTestable(),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('todo-title')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('todo-title')), '长按创建个人事项');
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(
        (await repo.day('2026-11-05', '0')).items.single.title,
        '长按创建个人事项',
      );
      expect(c.read(selectedDateProvider), companyDate);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'shared drag moves the full todo interval and keeps colour and completion',
    (t) async {
      final repo = DemoTodoRepository();
      final command = TodoCommand('POST', null, {
        'title': '跨天个人事项',
        'date': '2026-11-02',
        'endDate': '2026-11-04',
        'color': '#8FC7B0',
        'completed': true,
      });
      await repo.execute(command);
      await mount(t, repo);
      final state = t.state<CalendarInteractionSurfaceState>(
        find.byType(CalendarInteractionSurface),
      );
      final bar = find.byType(CalendarTaskHandle).hitTestable().first;
      final gesture = await t.startGesture(t.getCenter(bar));
      await t.pump(const Duration(milliseconds: 600));
      expect(state.drag.active, isTrue);
      final original = state.drag.intent!.schedule;
      await gesture.moveTo(
        t.getCenter(
          find.byKey(const ValueKey('month-day:2026-11-10')).hitTestable(),
        ),
      );
      await t.pump();
      final after = state.drag.preview!;
      expect(
        after.end.difference(after.start!),
        original.end.difference(original.start!),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.text('确认移动排期'), findsNothing);
      expect(find.text('事项日期已更新'), findsOneWidget);
      final moved = await repo.detail(command.key);
      expect(moved.date, isNot('2026-11-02'));
      expect(
        DateTime.parse(
          moved.lastDate,
        ).difference(DateTime.parse(moved.date)).inDays,
        2,
      );
      expect(moved.color, '#8FC7B0');
      expect(moved.completed, isTrue);
      expect(moved.version, 2);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'shared date agenda opens the private editor and moving crosses months',
    (t) async {
      final repo = DemoTodoRepository();
      final command = TodoCommand('POST', null, {
        'title': '仅本人事项',
        'date': '2026-11-02',
        'endDate': '2026-11-04',
        'color': '#8FC7B0',
      });
      await repo.execute(command);
      await mount(t, repo);
      await t.tap(
        find.byKey(const ValueKey('month-day:2026-11-2')).hitTestable(),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-day-agenda')), findsOneWidget);
      await t.tap(find.byKey(ValueKey('agenda:tasks:${command.key}')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('todo-title')))
            .controller!
            .text,
        '仅本人事项',
      );
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      Navigator.of(
        t.element(find.byKey(const ValueKey('calendar-day-agenda'))),
      ).pop();
      await t.pumpAndSettle();
      final state = t.state<CalendarInteractionSurfaceState>(
        find.byType(CalendarInteractionSurface),
      );
      final todo = await repo.detail(command.key);
      final record = todoCalendarRecord(todo, 'alice');
      final move = state.move(
        record,
        30,
        CalendarConstraints(
          DateTime.utc(1900),
          DateTime.utc(2100, 12, 31),
          'calendar-v1-2026',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('确认移动排期'), findsNothing);
      await move;
      expect((await repo.detail(command.key)).date, '2026-12-02');
      // December 2 is also visible in November's final shared calendar row.
      expect(
        (await repo.month('2026-11', '0')).items.single.date,
        '2026-12-02',
      );
      expect(
        (await repo.month('2026-12', '0')).items.single.lastDate,
        '2026-12-04',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'account switching clears private month records and resets its independent date',
    (t) async {
      final repo = DemoTodoRepository();
      await repo.execute(
        TodoCommand('POST', null, {'title': 'Alice私人事项', 'date': '2026-11-02'}),
      );
      final c = await mount(t, repo);
      expect(find.text('Alice私人事项'), findsWidgets);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'bob',
        role: UserRole.employee,
      );
      await t.pumpAndSettle();
      expect(find.text('Alice私人事项'), findsNothing);
      expect(c.read(pendingTodoCommandProvider), isNull);
      expect(t.takeException(), isNull);
    },
  );
}
