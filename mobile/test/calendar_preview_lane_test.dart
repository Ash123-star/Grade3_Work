import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/calendar/calendar_preview_lane.dart';
import 'calendar_drag_widget_test.dart'
    show dragStore, realCalendarDay, revealCalendarDay;
import 'calendar_drag_integration_widget_test.dart' show mountCalendar;
import 'support/local_test_state.dart';

Finder dayCell(int month, int day) =>
    realCalendarDay(DateTime(2026, month, day));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  DateTime day(int n) => DateTime.utc(2026, 11, n);
  test(
    'inclusive intervals skip all occupied lanes, ignore self and reuse gaps',
    () {
      final occupied = [
        CalendarLaneInterval('self', day(2), day(30), 0),
        CalendarLaneInterval('a', day(9), day(10), 0),
        CalendarLaneInterval('b', day(11), day(12), 1),
        CalendarLaneInterval('c', day(13), day(14), 2),
      ];
      expect(
        calendarPreviewLane(
          taskId: 'self',
          first: day(10),
          last: day(13),
          occupied: occupied,
        ),
        3,
      );
      expect(
        calendarPreviewLane(
          taskId: 'self',
          first: day(11),
          last: day(12),
          occupied: occupied,
        ),
        0,
      );
      expect(
        calendarPreviewLane(
          taskId: 'self',
          first: day(15),
          last: day(18),
          occupied: occupied,
        ),
        0,
      );
      expect(
        calendarPreviewLane(
          taskId: 'self',
          first: day(2),
          last: day(30),
          occupied: [],
        ),
        0,
      );
    },
  );

  for (final (height, scale, count) in [
    (650.0, 1.0, 5),
    (430.0, 1.0, 5),
    (430.0, 1.5, 5),
    (430.0, 1.5, 10),
  ]) {
    testWidgets(
      'folded rows, overflow and candidate stay separate; cancellation restores: $height/$scale/$count',
      (t) async {
        final store = dragStore();
        final original = store.records['tasks']!.single;
        store.records['tasks']!.addAll(
          List.generate(
            count,
            (i) => Record(
              id: 'busy-$i',
              title: '已有任务$i',
              version: 1,
              fields: {
                ...original.fields,
                'startAt': '2026-11-09T09:00:00+08:00',
                'deadline': '2026-11-13T18:00:00+08:00',
              },
            ),
          ),
        );
        final (state, _) = await mountCalendar(
          t,
          fixture: store,
          height: height,
          textScale: scale,
        );
        final beforeHeight = t.getSize(dayCell(11, 10)).height;
        final emptyHeight = t.getSize(dayCell(11, 2)).height;
        final existing = find.byWidgetPredicate(
          (w) => w is CalendarTaskHandle && w.record.id.startsWith('busy-'),
        );
        expect(existing, findsNWidgets(count > 5 ? 4 : count));
        if (count > 5) {
          expect(find.text('+${count - 4}'), findsWidgets);
        }
        expect(
          beforeHeight,
          emptyHeight,
          reason: 'formal weeks reserve the same five slots',
        );
        final cellBefore = t.getRect(dayCell(11, 10));
        final rectangles = [
          for (final node in existing.evaluate())
            t.getRect(find.byWidget(node.widget)),
        ];
        for (var i = 0; i < rectangles.length; i++) {
          expect(rectangles[i].bottom, lessThanOrEqualTo(cellBefore.bottom));
          for (var j = i + 1; j < rectangles.length; j++) {
            expect(rectangles[i].overlaps(rectangles[j]), isFalse);
          }
        }
        final followingTop = t.getTopLeft(dayCell(11, 16)).dy;
        final scrollBefore = state.widget.scroll.offset;
        final source = find
            .byWidgetPredicate(
              (w) => w is CalendarTaskHandle && w.record.id == original.id,
            )
            .hitTestable()
            .first;
        final gesture = await t.startGesture(
          Offset(t.getCenter(dayCell(11, 3)).dx, t.getCenter(source).dy),
        );
        await t.pump(const Duration(milliseconds: 600));
        await revealCalendarDay(t, state.widget.scroll, DateTime(2026, 11, 10));
        await gesture.moveTo(t.getCenter(dayCell(11, 10)));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        expect(state.drag.target!.day, day(10));
        if (count > 5) {
          expect(
            find.text('+${count - 4}'),
            findsWidgets,
            reason: 'the candidate never changes the formal task count',
          );
        }
        final preview = t.getRect(
          find.byKey(const ValueKey('calendar-drag-bar')),
        );
        final visible = find
            .byWidgetPredicate(
              (w) => w is CalendarTaskHandle && w.record.id.startsWith('busy-'),
            )
            .hitTestable();
        expect(visible, findsNWidgets(count > 5 ? 4 : count));
        for (final node in visible.evaluate()) {
          final rect = t.getRect(find.byWidget(node.widget));
          expect(
            preview.overlaps(rect),
            isFalse,
            reason: 'candidate must not cover an existing task',
          );
          expect(preview.top, greaterThanOrEqualTo(rect.bottom));
        }
        final afterHeight = t.getSize(dayCell(11, 10)).height;
        if (height < 500) {
          expect(afterHeight, greaterThanOrEqualTo(beforeHeight));
          expect(
            t.getTopLeft(dayCell(11, 16)).dy -
                followingTop +
                state.widget.scroll.offset -
                scrollBefore,
            closeTo(afterHeight - beforeHeight, .1),
          );
        }
        expect(
          preview.bottom,
          lessThanOrEqualTo(t.getRect(dayCell(11, 10)).bottom),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(
          state.drag.target!.day,
          day(10),
          reason: 'hover must not drift after expansion',
        );
        await gesture.up();
        await t.pumpAndSettle();
        expect(find.textContaining('2026-11-09 09:00'), findsOneWidget);
        await t.tap(find.text('取消'));
        await t.pumpAndSettle();
        expect(t.getSize(dayCell(11, 10)).height, beforeHeight);
        expect(existing, findsNWidgets(count > 5 ? 4 : count));
        if (count > 5) {
          expect(find.text('+${count - 4}'), findsWidgets);
        }
        expect(store.records['reviews'], isEmpty);
        expect(find.byKey(const ValueKey('calendar-drag-bar')), findsNothing);
        if (count == 10) {
          // Simulate the subsequent authorized server read after approval,
          // rather than promoting the transient candidate in local state.
          store.records['tasks']![0] = Record(
            id: original.id,
            title: original.title,
            version: original.version + 1,
            fields: {
              ...original.fields,
              'startAt': '2026-11-09T09:00:00+08:00',
              'deadline': '2026-11-11T18:00:00+08:00',
            },
          );
          state.ref.invalidate(calendarMonthTasksProvider);
          await settleLocalIo(t);
          await t.pumpAndSettle();
          expect(find.text('+7'), findsWidgets);
          final overflow = find.byKey(
            const ValueKey('month-overflow:2026-11-10'),
          );
          await t.tap(overflow);
          await t.pumpAndSettle();
          expect(find.text('11 条记录'), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'expansion above a long-task landing keeps the hovered day fixed',
    (t) async {
      final store = dragStore();
      final task = store.records['tasks']!.single;
      store.records['tasks'] = [
        Record(
          id: task.id,
          title: task.title,
          version: task.version,
          fields: {...task.fields, 'deadline': '2026-11-20T18:00:00+08:00'},
        ),
        for (var i = 0; i < 3; i++)
          Record(
            id: 'later-$i',
            title: '月底已有任务$i',
            fields: {
              ...task.fields,
              'startAt': '2026-11-23T09:00:00+08:00',
              'deadline': '2026-11-30T18:00:00+08:00',
            },
          ),
      ];
      final (state, _) = await mountCalendar(t, fixture: store, height: 430);
      final continuation = find
          .byWidgetPredicate(
            (w) => w is CalendarTaskHandle && w.record.id == task.id,
          )
          .hitTestable()
          .at(1);
      final gesture = await t.startGesture(
        Offset(t.getCenter(dayCell(11, 11)).dx, t.getCenter(continuation).dy),
      );
      await t.pump(const Duration(milliseconds: 600));
      await t.ensureVisible(dayCell(11, 30));
      await t.pump();
      final landing = t.getCenter(dayCell(11, 30));
      await gesture.moveTo(landing);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(state.drag.target!.day, day(30));
      expect(state.drag.preview!.description, contains('2026-11-21 09:00'));
      expect(state.drag.hit(landing)!.day, day(30));
      await gesture.up();
      await t.pumpAndSettle();
      expect(find.textContaining('2026-11-21 09:00'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(store.records['reviews'], isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'external month selection and reverse scrolling retain the timeline position',
    (t) async {
      final (state, _) = await mountCalendar(t, height: 430);
      final dateController = state.ref.read(selectedDateProvider.notifier);
      dateController.state = DateTime(2026, 12, 10);
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(dayCell(12, 10).hitTestable(), findsOneWidget);
      state.widget.scroll.jumpTo(-430);
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(dateController.state.month, 11);
      expect(state.widget.scroll.offset, -430);
      // Five reserved slots make November taller than the old adaptive grid.
      // Scroll to the actual date instead of assuming a 430px month extent.
      await t.ensureVisible(dayCell(11, 10));
      await t.pumpAndSettle();
      expect(dayCell(11, 10).hitTestable(), findsOneWidget);
      final period = state.ref.read(periodProvider.notifier);
      period.state = '周';
      await t.pumpAndSettle();
      period.state = '月';
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.ensureVisible(dayCell(11, 10));
      await t.pumpAndSettle();
      expect(dateController.state.month, 11);
      expect(dayCell(11, 10).hitTestable(), findsOneWidget);
    },
  );
}
