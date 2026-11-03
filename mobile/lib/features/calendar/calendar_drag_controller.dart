import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../data/models/models.dart';
import 'calendar_schedule.dart';

class CalendarDayGeometry {
  CalendarDayGeometry(this.key, this.day, this.constraints);
  final GlobalKey key;
  final DateTime day;
  final CalendarConstraints constraints;
  Rect? get rect {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class CalendarDragIntent {
  CalendarDragIntent(this.record, this.anchor, this.schedule, this.constraints);
  final Record record;
  final DateTime anchor;
  final CalendarSchedule schedule;
  final CalendarConstraints constraints;
}

/// Geometry and preview only: this controller never writes canonical task data.
class CalendarDragController extends ChangeNotifier {
  CalendarDragController({
    required TickerProvider vsync,
    required this.scroll,
    required this.viewport,
    required this.allowed,
  }) {
    _ticker = vsync.createTicker(_tick);
  }
  final ScrollController scroll;
  final GlobalKey viewport;
  final bool Function() allowed;
  final targets = <Object, CalendarDayGeometry>{};
  final loadedMonths = <Object, CalendarDayGeometry>{};
  late final Ticker _ticker;
  CalendarDragIntent? intent;
  CalendarDayGeometry? target;
  Offset pointer = Offset.zero;
  int generation = 0;
  Duration? _previous, _edgeSince;
  int _edge = 0;
  bool get active => intent != null;
  Rect? get bounds {
    final box = viewport.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  CalendarDayGeometry? hit(Offset point) {
    if (bounds?.contains(point) != true) return null;
    for (final value in targets.values) {
      if (value.rect?.contains(point) == true) return value;
    }
    return null;
  }

  bool begin(Record record, Offset point, CalendarConstraints constraints) {
    cancel();
    if (!allowed() ||
        record.fields['capabilities'] is! Map ||
        record.fields['capabilities']['reschedule'] != true) {
      return false;
    }
    final day = hit(point);
    if (day == null) return false;
    try {
      final schedule = CalendarSchedule.fromRecord(record);
      intent = CalendarDragIntent(record, day.day, schedule, constraints);
      pointer = point;
      target = day;
      generation++;
      _previous = null;
      _edgeSince = null;
      _edge = 0;
      _ticker.start();
      notifyListeners();
      return true;
    } on FormatException {
      return false;
    }
  }

  void update(Offset point) {
    if (!active) return;
    if (!allowed()) {
      cancel();
      return;
    }
    pointer = point;
    target = hit(point);
    notifyListeners();
  }

  CalendarSchedule? get preview {
    final value = intent, day = target;
    if (value == null || day == null) return null;
    final delta = businessDayDelta(value.anchor, day.day);
    if (delta == 0) return value.schedule;
    try {
      return value.schedule.move(delta, value.constraints);
    } on FormatException {
      return null;
    }
  }

  void _tick(Duration elapsed) {
    if (!active || !allowed()) {
      cancel();
      return;
    }
    final area = bounds;
    if (area == null || !scroll.hasClients) {
      cancel();
      return;
    }
    final current = hit(pointer);
    if (target?.day != current?.day) {
      target = current;
      notifyListeners();
    }
    final edge = pointer.dy < area.top + 40
        ? -1
        : pointer.dy > area.bottom - 40
        ? 1
        : 0;
    // Headers and trailing blank cells inside a loaded month are traversable.
    // Loading/failed months never register a region and cannot drive scrolling.
    final loaded = loadedMonths.values.any(
      (month) =>
          month.rect?.contains(pointer) == true &&
          month.constraints.contains(month.day),
    );
    if (edge == 0 ||
        !(loaded ||
            current != null && current.constraints.contains(current.day))) {
      _edge = 0;
      _edgeSince = null;
      _previous = elapsed;
      return;
    }
    if (edge != _edge) {
      _edge = edge;
      _edgeSince = elapsed;
      _previous = elapsed;
      return;
    }
    final dt = (elapsed - (_previous ?? elapsed)).inMicroseconds / 1000000;
    _previous = elapsed;
    if (elapsed - (_edgeSince ?? elapsed) < const Duration(milliseconds: 500)) {
      return;
    }
    final position = scroll.position;
    final next = (position.pixels + edge * area.height * dt.clamp(0, .05))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next == position.pixels) return;
    scroll.jumpTo(next);
    target = hit(pointer);
    notifyListeners();
  }

  void observe(Iterable<Record> records) {
    final source = intent?.record;
    if (source == null) return;
    final matches = records.where((r) => r.id == source.id);
    if (matches.any(
      (r) =>
          r.version != source.version ||
          r.fields['capabilities'] is! Map ||
          r.fields['capabilities']['reschedule'] != true,
    )) {
      cancel();
    }
  }

  void cancel() {
    generation++;
    intent = null;
    target = null;
    _ticker.stop();
    _edge = 0;
    _edgeSince = null;
    _previous = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
