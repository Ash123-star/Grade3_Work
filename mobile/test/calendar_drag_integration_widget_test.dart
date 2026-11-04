import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'calendar_drag_widget_test.dart' show dragStore, readyInteraction;
import 'support/local_test_state.dart';

Future<(CalendarInteractionSurfaceState, DemoStore)> mountCalendar(
  WidgetTester t, {
  DemoStore? fixture,
  double height = 650,
  double textScale = 1,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final store = fixture ?? dragStore();
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
  await t.pumpWidget(
    OwnedTestProviderScope(
      container: container,
      child: MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: CalendarContent(availableHeight: height)),
      ),
    ),
  );
  await settleLocalIo(t);
  await t.pumpAndSettle();
  return (await readyInteraction(t), store);
}

Finder taskBar() => find
    .byType(CalendarTaskHandle)
    .hitTestable(at: const Alignment(0, .9))
    .first;
Finder dayCell(int month, int day) => find
    .byKey(ValueKey('month-day:2026-$month-$day'))
    .hitTestable(at: const Alignment(0, .9));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a non-movable bar never triggers blank-cell creation', (
    t,
  ) async {
    var creations = 0, taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onLongPress: () => creations++,
            child: CalendarTaskHandle(
              record: const Record(id: 'read-only', title: '不可移动任务'),
              constraints: null,
              onTap: (_) => taps++,
              child: const SizedBox(width: 200, height: 40),
            ),
          ),
        ),
      ),
    );
    await t.longPress(find.byType(CalendarTaskHandle));
    await t.pumpAndSettle();
    expect(creations, 0);
    await t.tap(find.byType(CalendarTaskHandle));
    expect(taps, 1);
  });

  testWidgets('trailing blank cells never highlight another month target', (
    t,
  ) async {
    final (state, _) = await mountCalendar(t);
    final targetDate = DateTime.utc(2026, 12, 1);
    state.drag.targetFeedback.value = (
      day: targetDate,
      valid: true,
      firstDay: null,
      lastDay: null,
    );
    await t.pump();
    final blank = find.byWidgetPredicate(
      (w) =>
          w is CalendarDayTarget &&
          w.day == targetDate &&
          w.constraints == null,
    );
    expect(blank, findsOneWidget);
    final decoration =
        t
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: blank,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.border, isNull);
  });

  testWidgets(
    'pickup lifts the original-size bar once and moves the whole interval across weeks',
    (t) async {
      final haptics = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (state, store) = await mountCalendar(t);
      final rect = t.getRect(taskBar());
      final point = Offset(t.getCenter(dayCell(11, 3)).dx, rect.center.dy);
      final gesture = await t.startGesture(point);
      await t.pump(const Duration(milliseconds: 600));
      expect(state.drag.active, isTrue);
      expect(haptics, hasLength(1));
      final replica = find.byKey(const ValueKey('calendar-drag-bar'));
      expect(t.getSize(replica), rect.size);
      var targetChanges = 0;
      state.drag.targetFeedback.addListener(() => targetChanges++);
      await gesture.moveBy(const Offset(2, 0));
      await gesture.moveBy(const Offset(1, 0));
      await t.pump();
      expect(
        targetChanges,
        0,
        reason: 'pointer-only motion must not rebuild date highlights',
      );
      await gesture.moveTo(t.getCenter(dayCell(11, 10)));
      await t.pump();
      expect(t.getSize(replica), rect.size);
      expect(
        state.drag.preview!.end.difference(state.drag.preview!.start!),
        state.drag.intent!.schedule.end.difference(
          state.drag.intent!.schedule.start!,
        ),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.textContaining('新排期：2026-11-09 09:00'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(replica, findsNothing);
      expect(store.records['reviews'], isEmpty);
      expect(store.records['tasks']!.single.version, 7);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'a drag continues after its source month and recognizer are recycled',
    (t) async {
      final (state, store) = await mountCalendar(t);
      final gesture = await t.startGesture(t.getCenter(taskBar()));
      await t.pump(const Duration(milliseconds: 600));
      expect(state.drag.active, isTrue);
      final pager = state.widget.scroll;
      pager.jumpTo(pager.offset + state.drag.bounds!.height * 4);
      await settleLocalIo(t);
      await t.pump(const Duration(milliseconds: 100));
      expect(
        find.byType(CalendarTaskHandle).hitTestable(at: const Alignment(0, .9)),
        findsNothing,
      );
      expect(state.drag.active, isTrue);
      final target = find
          .byKey(const ValueKey('month-day:2027-3-10'))
          .hitTestable(at: const Alignment(0, .9));
      await gesture.moveTo(t.getCenter(target));
      await t.pump();
      expect(state.drag.target!.day, DateTime.utc(2027, 3, 10));
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.text('确认移动排期'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(store.records['reviews'], isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'short taps open the day and movement before pickup scrolls without creating',
    (t) async {
      final (state, store) = await mountCalendar(t);
      await t.tap(taskBar());
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-day-agenda')), findsOneWidget);
      Navigator.of(
        t.element(find.byKey(const ValueKey('calendar-day-agenda'))),
      ).pop();
      await t.pumpAndSettle();
      final gesture = await t.startGesture(t.getCenter(taskBar()));
      await gesture.moveBy(const Offset(0, -90));
      await t.pump(const Duration(milliseconds: 600));
      expect(state.drag.active, isFalse);
      await gesture.up();
      await t.pumpAndSettle();
      expect(store.records['reviews'], isEmpty);
      expect(find.text('确认移动排期'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
