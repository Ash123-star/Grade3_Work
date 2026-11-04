/// Inclusive business-date intervals. Layout has no repository or write access.
class CalendarLaneInterval {
  const CalendarLaneInterval(this.id, this.first, this.last, this.lane);
  final String id;
  final DateTime first, last;
  final int lane;
}

/// Preserve every existing lane and put the candidate in the first free lane.
/// Call for each weekly segment, so a busy later week cannot hide an earlier one.
int calendarPreviewLane({
  required String taskId,
  required DateTime first,
  required DateTime last,
  required Iterable<CalendarLaneInterval> occupied,
}) {
  final blocked = <int>{};
  for (final interval in occupied) {
    if (interval.id != taskId &&
        !interval.last.isBefore(first) &&
        !interval.first.isAfter(last)) {
      blocked.add(interval.lane);
    }
  }
  var lane = 0;
  while (blocked.contains(lane)) {
    lane++;
  }
  return lane;
}
