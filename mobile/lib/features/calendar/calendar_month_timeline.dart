import 'package:flutter/material.dart';

/// Two lazy slivers grow around the selected month. Months can grow without
/// clipping their final week or introducing a nested vertical scroll gesture.
class CalendarMonthTimeline extends StatefulWidget {
  const CalendarMonthTimeline({
    super.key,
    required this.selectedMonth,
    required this.controller,
    required this.dragging,
    required this.onMonthChanged,
    required this.monthBuilder,
  });
  final DateTime selectedMonth;
  final ScrollController controller;
  final bool dragging;
  final ValueChanged<DateTime> onMonthChanged;
  final Widget Function(DateTime) monthBuilder;
  @override
  State<CalendarMonthTimeline> createState() => _CalendarMonthTimelineState();
}

class _CalendarMonthTimelineState extends State<CalendarMonthTimeline> {
  final _center = GlobalKey(), _viewport = GlobalKey();
  final _months = <int, GlobalKey>{};
  late int _anchor = _index(widget.selectedMonth);
  late int _reported = _anchor;
  bool _scheduled = false;
  static int _index(DateTime date) => date.year * 12 + date.month - 1;
  static DateTime _date(int index) => DateTime.utc(index ~/ 12, index % 12 + 1);

  @override
  void didUpdateWidget(CalendarMonthTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _index(widget.selectedMonth);
    if (next != _index(oldWidget.selectedMonth) &&
        next != _reported &&
        !widget.dragging) {
      _anchor = _reported = next;
      if (widget.controller.hasClients) widget.controller.jumpTo(0);
    }
  }

  void _report() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final middle = viewport
          .localToGlobal(Offset(0, viewport.size.height / 2))
          .dy;
      for (final entry in _months.entries) {
        final box = entry.value.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (top <= middle && top + box.size.height > middle) {
          if (_reported != entry.key) {
            _reported = entry.key;
            widget.onMonthChanged(_date(entry.key));
          }
          break;
        }
      }
    });
  }

  Widget _month(int index) => _MonthAnchor(
    key: ValueKey(index),
    register: (key) => _months[index] = key,
    unregister: (key) {
      if (identical(_months[index], key)) _months.remove(index);
    },
    child: widget.monthBuilder(_date(index)),
  );

  @override
  Widget build(BuildContext context) {
    _report();
    return SizedBox(
      key: _viewport,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _report();
          return false;
        },
        child: CustomScrollView(
          key: const ValueKey('calendar-month-timeline'),
          controller: widget.controller,
          center: _center,
          physics: widget.dragging
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, index) => _month(_anchor - index - 1),
                childCount: _anchor - 2000 * 12,
              ),
            ),
            SliverList(
              key: _center,
              delegate: SliverChildBuilderDelegate(
                (_, index) => _month(_anchor + index),
                childCount: 10000 * 12 - _anchor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthAnchor extends StatefulWidget {
  const _MonthAnchor({
    super.key,
    required this.register,
    required this.unregister,
    required this.child,
  });
  final ValueChanged<GlobalKey> register, unregister;
  final Widget child;
  @override
  State<_MonthAnchor> createState() => _MonthAnchorState();
}

class _MonthAnchorState extends State<_MonthAnchor> {
  final geometry = GlobalKey();
  @override
  Widget build(BuildContext context) {
    widget.register(geometry);
    return SizedBox(key: geometry, child: widget.child);
  }

  @override
  void dispose() {
    widget.unregister(geometry);
    super.dispose();
  }
}
