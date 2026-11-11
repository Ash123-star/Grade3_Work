import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'support/local_test_state.dart';
import 'calendar_drag_widget_test.dart' show revealCalendarDay;
import 'calendar_drag_integration_widget_test.dart'
    show mountCalendar, taskBar, dayCell;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('release cannot replace the last displayed date between frames', (
    t,
  ) async {
    final (state, store) = await mountCalendar(t);
    final point = Offset(
      t.getCenter(dayCell(11, 3)).dx,
      t.getCenter(taskBar()).dy,
    );
    final gesture = await t.startGesture(point);
    await t.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(t.getCenter(dayCell(11, 10)));
    await t.pump();
    expect(state.drag.preview!.description, contains('2026-11-09 09:00'));
    // A final pointer update can arrive before the next painted preview.
    await gesture.moveTo(t.getCenter(dayCell(11, 11)));
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.textContaining('2026-11-09 09:00'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(store.records['reviews'], isEmpty);
  });

  testWidgets(
    'continuation pickup highlights the full interval and submits the same shift',
    (t) async {
      final (state, store) = await mountCalendar(t);
      final original = store.records['tasks']!.single;
      store.records['tasks'] = [
        Record(
          id: original.id,
          title: original.title,
          version: original.version,
          fields: {...original.fields, 'deadline': '2026-11-20T18:00:00+08:00'},
        ),
      ];
      state.ref.invalidate(calendarMonthTasksProvider);
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final continuation = find
          .byType(CalendarTaskHandle)
          .hitTestable(at: const Alignment(0, .9))
          .at(1);
      final point = Offset(
        t.getCenter(dayCell(11, 11)).dx,
        t.getCenter(continuation).dy,
      );
      final gesture = await t.startGesture(point);
      await t.pump(const Duration(milliseconds: 600));
      expect(state.drag.intent!.anchor, DateTime.utc(2026, 11, 11));
      await revealCalendarDay(t, state.widget.scroll, DateTime(2026, 11, 18));
      await gesture.moveTo(t.getCenter(dayCell(11, 18)));
      await t.pump();
      expect(
        find.byKey(const ValueKey('calendar-candidate:2026-11-09')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-candidate:2026-11-27')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-candidate:2026-11-28')),
        findsNothing,
      );
      expect(
        state.drag.preview!.end.difference(state.drag.preview!.start!),
        state.drag.intent!.schedule.end.difference(
          state.drag.intent!.schedule.start!,
        ),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.textContaining('2026-11-09 09:00'), findsOneWidget);
      expect(find.textContaining('2026-11-27 18:00'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), '续段跨周整体移动');
      await t.tap(find.text('提交审核'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(state.pending!.days, 7);
      expect(state.pending!.version, 7);
      expect(store.records['reviews'], hasLength(1));
      expect(
        store.records['tasks']!.single.fields['deadline'],
        '2026-11-20T18:00:00+08:00',
      );
    },
  );

  testWidgets(
    'leaving the viewport after a valid preview cancels without confirmation',
    (t) async {
      final (state, store) = await mountCalendar(t);
      final gesture = await t.startGesture(t.getCenter(taskBar()));
      await t.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(t.getCenter(dayCell(11, 10)));
      await t.pump();
      expect(state.drag.preview, isNotNull);
      await gesture.moveTo(const Offset(390, 890));
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.text('确认移动排期'), findsNothing);
      expect(store.records['reviews'], isEmpty);
      expect(state.drag.active, isFalse);
    },
  );
}
