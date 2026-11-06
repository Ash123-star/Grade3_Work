import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

DemoStore dragStore() {
  final store = DemoStore();
  store.records['tasks'] = [
    const Record(
      id: 'move-task',
      title: '移动排期任务',
      version: 7,
      fields: {
        'dispatcherId': 'u1',
        'participants': [
          {'id': 'u1', 'name': '本人'},
        ],
        'startAt': '2026-11-02T09:00:00+08:00',
        'deadline': '2026-11-04T18:00:00+08:00',
        'status': '进行中',
      },
    ),
  ];
  store.records['reviews'] = [];
  return store;
}

Future<CalendarInteractionSurfaceState> readyInteraction(
  WidgetTester tester,
) async {
  final state = tester.state<CalendarInteractionSurfaceState>(
    find.byType(CalendarInteractionSurface),
  );
  for (var i = 0; i < 100 && state.restoring; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(state.restoring, isFalse);
  return state;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'middle-day drag confirms interval and leaves pending task at original dates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = dragStore();
      // Share the same store for all reads and writes.
      final repository = MockRepository(
        const Session(),
        store: store,
        clock: () => DateTime(2026, 11, 2),
      );
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 11, 2)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        OwnedTestProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: CalendarContent(availableHeight: 650)),
          ),
        ),
      );
      await settleLocalIo(tester);
      await tester.pumpAndSettle();
      final interaction = await readyInteraction(tester);
      final bar = find.byKey(
        const ValueKey('month-span:tasks:move-task:2026-11-02T00:00:00.000'),
      );
      final anchor = tester.getRect(
        find.byKey(const ValueKey('month-day:2026-11-3')),
      );
      final target = tester.getRect(
        find.byKey(const ValueKey('month-day:2026-11-5')),
      );
      final gesture = await tester.startGesture(
        Offset(anchor.center.dx, tester.getCenter(bar).dy),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(interaction.drag.active, isTrue);
      await gesture.moveTo(Offset(target.center.dx, target.top + 36));
      await tester.pump();
      expect(find.textContaining('2026-11-06'), findsWidgets);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('确认移动排期'), findsOneWidget);
      expect(find.textContaining('新排期：2026-11-04 09:00'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '项目排期调整');
      await tester.tap(find.text('提交审核'));
      await settleLocalIo(tester);
      await tester.pumpAndSettle();
      expect(store.records['reviews'], hasLength(1));
      expect(store.records['tasks']!.single.version, 7);
      expect(
        store.records['tasks']!.single.fields['deadline'],
        '2026-11-04T18:00:00+08:00',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('same-day drop, invalid drop and second pointer do not write', (
    tester,
  ) async {
    final store = dragStore();
    final container = testContainer(
      overrides: [
        repositoryProvider.overrideWithValue(
          MockRepository(
            const Session(),
            store: store,
            clock: () => DateTime(2026, 11, 2),
          ),
        ),
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 11, 2)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      OwnedTestProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CalendarContent(availableHeight: 550)),
        ),
      ),
    );
    await settleLocalIo(tester);
    await tester.pumpAndSettle();
    final interaction = await readyInteraction(tester);
    final bar = find.byKey(
      const ValueKey('month-span:tasks:move-task:2026-11-02T00:00:00.000'),
    );
    var gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 600));
    expect(interaction.drag.active, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('确认移动排期'), findsNothing);
    gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(const Duration(milliseconds: 600));
    final second = await tester.startGesture(const Offset(10, 10), pointer: 2);
    await tester.pump();
    await second.up();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('确认移动排期'), findsNothing);
    expect(store.records['reviews'], isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'background, layout, session changes and newer data cancel preview without writes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = dragStore();
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(
              const Session(),
              store: store,
              clock: () => DateTime(2026, 11, 2),
            ),
          ),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 11, 2)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        OwnedTestProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: CalendarContent(availableHeight: 650)),
          ),
        ),
      );
      await settleLocalIo(tester);
      await tester.pumpAndSettle();
      final state = await readyInteraction(tester);
      Future<TestGesture> pickUp() async {
        final bar = find
            .byWidgetPredicate(
              (w) => w is CalendarTaskHandle && w.record.id == 'move-task',
            )
            .hitTestable()
            .first;
        final gesture = await tester.startGesture(tester.getCenter(bar));
        await tester.pump(const Duration(milliseconds: 600));
        expect(state.drag.active, isTrue);
        return gesture;
      }

      var gesture = await pickUp();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(state.drag.active, isFalse);
      await gesture.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleLocalIo(tester);
      await tester.pumpAndSettle();
      await readyInteraction(tester);
      gesture = await pickUp();
      tester.view.physicalSize = const Size(412, 900);
      await tester.pump();
      expect(state.drag.active, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      gesture = await pickUp();
      final epoch = container.read(sessionEpochProvider);
      container.read(sessionProvider.notifier).state = const Session(id: 'B');
      await tester.pump();
      container.read(sessionProvider.notifier).state = const Session();
      await settleLocalIo(tester);
      expect(container.read(sessionEpochProvider), isNot(epoch));
      expect(state.drag.active, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      await readyInteraction(tester);
      gesture = await pickUp();
      final original = store.records['tasks']!.single;
      store.records['tasks'] = [
        Record(
          id: original.id,
          title: original.title,
          version: 8,
          fields: {...original.fields, 'deadline': '2026-11-05T18:00:00+08:00'},
        ),
      ];
      container.invalidate(calendarMonthTasksProvider);
      await settleLocalIo(tester);
      await tester.pump();
      expect(state.drag.active, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.records['tasks']!.single.version, 8);
      expect(
        store.records['tasks']!.single.fields['deadline'],
        '2026-11-05T18:00:00+08:00',
      );
      expect(store.records['reviews'], isEmpty);
      expect(find.text('确认移动排期'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cross-year month continuations keep writable handles inside real month dates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = dragStore();
      store.records['tasks'] = [
        const Record(
          id: 'move-task',
          title: '跨年续段',
          version: 7,
          fields: {
            'dispatcherId': 'u1',
            'participants': [
              {'id': 'u1', 'name': '本人'},
            ],
            'startAt': '2026-12-31T09:00:00+08:00',
            'deadline': '2027-01-02T18:00:00+08:00',
          },
        ),
      ];
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(
              const Session(),
              store: store,
              clock: () => DateTime(2026, 11, 2),
            ),
          ),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 12, 31)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        OwnedTestProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: CalendarContent(availableHeight: 650)),
          ),
        ),
      );
      for (final day in [DateTime(2026, 12, 31), DateTime(2027, 1, 1)]) {
        container.read(selectedDateProvider.notifier).state = day;
        await settleLocalIo(tester);
        await tester.pumpAndSettle();
        final state = await readyInteraction(tester);
        final handle = find
            .byWidgetPredicate(
              (w) =>
                  w is CalendarTaskHandle &&
                  w.record.id == 'move-task' &&
                  w.constraints != null,
            )
            .hitTestable()
            .first;
        final rect = tester.getRect(handle);
        final point = rect.center;
        expect(state.drag.hit(point)?.day.month, day.month);
        final dateCell = tester.getRect(
          find
              .byKey(ValueKey('month-day:${day.year}-${day.month}-${day.day}'))
              .hitTestable(),
        );
        if (day.month == 12) {
          expect(rect.right, lessThanOrEqualTo(dateCell.right));
        } else {
          expect(rect.left, greaterThanOrEqualTo(dateCell.left));
        }
        final gesture = await tester.startGesture(point);
        await tester.pump(const Duration(milliseconds: 600));
        expect(state.drag.active, isTrue);
        expect(state.drag.intent!.anchor.month, day.month);
        state.drag.cancel();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(store.records['reviews'], isEmpty);
        expect(store.records['tasks']!.single.version, 7);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'date prefill is explicit and malformed route date never becomes today',
    (tester) async {
      final container = testContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        OwnedTestProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const FormPage(
              'dispatch',
              initialBusinessDate: '2026-02-29',
              scheduleConstraints: {
                'zone': 'Asia/Shanghai',
                'minDate': '2024-01-01',
                'maxDate': '2034-01-01',
                'revision': 'calendar-v1-2026',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await settleLocalIo(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('日期无效'), findsWidgets);
      expect(find.textContaining('月历所选日期：'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
