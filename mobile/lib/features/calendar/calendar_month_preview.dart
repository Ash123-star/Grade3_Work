import 'calendar_preview_lane.dart';

/// A day's read-only projection. The complete records remain in the month read.
class CalendarFoldedDay {
  const CalendarFoldedDay(this.lanes, this.total);

  final Map<String, int> lanes;
  final int total;
  int get remaining => total > 5 ? total - 4 : 0;
  int get rows => remaining > 0
      ? 5
      : lanes.values.fold(0, (rows, lane) => lane + 1 > rows ? lane + 1 : rows);
}

/// Fold by date, rather than truncating global lanes: a task occupying a high
/// lane in a crowded earlier week must still appear on a later quiet date.
Map<DateTime, CalendarFoldedDay> calendarMonthPreview({
  required DateTime first,
  required DateTime last,
  required Iterable<CalendarLaneInterval> intervals,
}) {
  final unique = <String, CalendarLaneInterval>{};
  for (final interval in intervals) {
    if (!interval.last.isBefore(interval.first)) {
      unique.putIfAbsent(interval.id, () => interval);
    }
  }
  final ordered = unique.values.toList()
    ..sort((a, b) {
      final result = a.lane.compareTo(b.lane);
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
  return {
    for (
      var day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    )
      day: (() {
        final active = ordered
            .where((e) => !e.first.isAfter(day) && !e.last.isBefore(day))
            .toList();
        final visible = active.take(active.length > 5 ? 4 : 5).toList();
        final compact = visible.any(
          (e) => e.lane >= (active.length > 5 ? 4 : 5),
        );
        return CalendarFoldedDay({
          for (var index = 0; index < visible.length; index++)
            visible[index].id: compact ? index : visible[index].lane,
        }, active.length);
      })(),
  };
}

/// Split only when folding hides a task or changes its visible lane. All
/// fragments retain the same task ID and actual business dates.
List<CalendarLaneInterval> calendarVisibleSegments({
  required String taskId,
  required DateTime first,
  required DateTime last,
  required Map<DateTime, CalendarFoldedDay> days,
}) {
  final result = <CalendarLaneInterval>[];
  DateTime? beginning;
  int? lane;
  for (
    var day = first;
    !day.isAfter(last.add(const Duration(days: 1)));
    day = day.add(const Duration(days: 1))
  ) {
    final next = day.isAfter(last) ? null : days[day]?.lanes[taskId];
    if (next != lane) {
      if (beginning != null && lane != null) {
        result.add(
          CalendarLaneInterval(
            taskId,
            beginning,
            day.subtract(const Duration(days: 1)),
            lane,
          ),
        );
      }
      beginning = next == null ? null : day;
      lane = next;
    }
  }
  return result;
}
