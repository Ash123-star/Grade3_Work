import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/calendar/calendar_month_preview.dart';
import 'package:pandora_mobile/features/calendar/calendar_preview_lane.dart';

void main() {
  DateTime day(int date) => DateTime.utc(2026, 11, date);

  for (final count in [0, 1, 4, 5, 6, 10, 31]) {
    test(
      '$count tasks retain complete counts with at most five preview rows',
      () {
        final result = calendarMonthPreview(
          first: day(1),
          last: day(1),
          intervals: [
            for (var index = 0; index < count; index++)
              CalendarLaneInterval('task-$index', day(1), day(1), index),
          ],
        )[day(1)]!;
        expect(result.total, count);
        expect(result.lanes.length, count > 5 ? 4 : count);
        expect(result.remaining, count > 5 ? count - 4 : 0);
        expect(result.rows, lessThanOrEqualTo(5));
        if (count > 0) expect(result.lanes.keys.first, 'task-0');
      },
    );
  }

  test(
    'high global lanes on quiet dates remain visible; duplicates do not count twice',
    () {
      final result = calendarMonthPreview(
        first: day(1),
        last: day(2),
        intervals: [
          for (var index = 0; index < 6; index++)
            CalendarLaneInterval('busy-$index', day(1), day(1), index),
          CalendarLaneInterval('long', day(1), day(2), 6),
          CalendarLaneInterval('long', day(1), day(2), 6),
          CalendarLaneInterval('invalid', day(2), day(1), 7),
        ],
      );
      expect(result[day(1)]!.total, 7);
      expect(result[day(1)]!.remaining, 3);
      expect(result[day(1)]!.lanes.containsKey('long'), isFalse);
      expect(result[day(2)]!.total, 1);
      expect(result[day(2)]!.lanes, {'long': 0});
    },
  );

  test(
    'stable order and fragments retain the same ID when hidden or compacted',
    () {
      final intervals = [
        CalendarLaneInterval('long', day(1), day(4), 5),
        for (var index = 0; index < 5; index++)
          CalendarLaneInterval('busy-$index', day(2), day(2), index),
      ];
      Map<DateTime, CalendarFoldedDay> build(
        Iterable<CalendarLaneInterval> items,
      ) => calendarMonthPreview(first: day(1), last: day(4), intervals: items);
      final result = build(intervals);
      final reversed = build(intervals.reversed);
      expect(result[day(2)]!.lanes, reversed[day(2)]!.lanes);
      final segments = calendarVisibleSegments(
        taskId: 'long',
        first: day(1),
        last: day(4),
        days: result,
      );
      expect(segments, hasLength(2));
      expect(segments.map((e) => e.id), everyElement('long'));
      expect(segments.first.first, day(1));
      expect(segments.first.last, day(1));
      expect(segments.last.first, day(3));
      expect(segments.last.last, day(4));
    },
  );
}
