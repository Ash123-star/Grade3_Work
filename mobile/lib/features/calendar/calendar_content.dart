import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';

class CalendarEvent {
  const CalendarEvent(
    this.record,
    this.resource,
    this.day,
    this.start,
    this.end,
  );
  final Record record;
  final String resource;
  final DateTime day;
  final int? start, end;
  bool get timed => start != null && end != null;
  Color get color =>
      resource == 'tasks' ? const Color(0xFFFFE5D2) : CuteTokens.mint;
  static String clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String get time => timed
      ? '${clock(start!)} — ${clock(end!)}'
      : resource == 'tasks'
      ? '截止 ${clock(day.hour * 60 + day.minute)}'
      : '未设时段';
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class CalendarContent extends ConsumerStatefulWidget {
  const CalendarContent({super.key});
  @override
  ConsumerState<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends ConsumerState<CalendarContent> {
  bool showTasks = true, showLogs = true;
  @override
  Widget build(BuildContext context) {
    final date = ref.watch(selectedDateProvider),
        period = ref.watch(periodProvider);
    final tasks = ref.watch(datedRecordsProvider('tasks')),
        logs = ref.watch(datedRecordsProvider('logs'));
    final events = <CalendarEvent>[];
    for (final pair in [
      (tasks.valueOrNull?.items ?? <Record>[], 'tasks'),
      (logs.valueOrNull?.items ?? <Record>[], 'logs'),
    ]) {
      if (pair.$2 == 'tasks' ? !showTasks : !showLogs) continue;
      for (final record in pair.$1) {
        final day = businessEventTime(
          pair.$2 == 'tasks'
              ? record.fields['deadline']
              : record.fields['businessDate'],
        );
        if (day == null) continue;
        final start = businessEventTime(record.fields['startAt']),
            end = businessEventTime(record.fields['endAt']);
        final timed =
            start != null &&
            end != null &&
            end.isAfter(start) &&
            sameDay(start, day);
        events.add(
          CalendarEvent(
            record,
            pair.$2,
            day,
            timed ? start.hour * 60 + start.minute : null,
            timed
                ? math.min(
                    1440,
                    end
                        .difference(DateTime(day.year, day.month, day.day))
                        .inMinutes,
                  )
                : null,
          ),
        );
      }
    }
    List<CalendarEvent> onDay(DateTime d) =>
        events.where((e) => sameDay(e.day, d)).toList()
          ..sort((a, b) => (a.start ?? 1440).compareTo(b.start ?? 1440));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              toggled: showTasks,
              child: TextButton(
                onPressed: () => setState(() => showTasks = !showTasks),
                child: Text(
                  '${showTasks ? '●' : '○'} 任务',
                  style: const TextStyle(color: Color(0xFFA7460E)),
                ),
              ),
            ),
            Semantics(
              toggled: showLogs,
              child: TextButton(
                onPressed: () => setState(() => showLogs = !showLogs),
                child: Text(
                  '${showLogs ? '■' : '□'} 日志',
                  style: const TextStyle(color: Color(0xFF246447)),
                ),
              ),
            ),
          ],
        ),
        if (tasks.isLoading || logs.isLoading)
          const LoadingSkeleton()
        else if (tasks.hasError || logs.hasError)
          ErrorPanel(
            '${tasks.error ?? logs.error}',
            retry: () => ref.invalidate(datedRecordsProvider),
          )
        else if (period == '月') ...[
          _MonthGrid(
            date: date,
            events: events,
            onChanged: (d) => ref.read(selectedDateProvider.notifier).state = d,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${date.month}月${date.day}日 周${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${onDay(date).length} 条记录',
                style: const TextStyle(color: CuteTokens.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (onDay(date).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('这一天没有任务或日志，可选择其他日期'),
            ),
          for (final event in onDay(date))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EventRow(event),
            ),
        ] else ...[
          if (period == '日')
            _WeekStrip(
              date: date,
              onChanged: (d) =>
                  ref.read(selectedDateProvider.notifier).state = d,
            ),
          const SizedBox(height: 12),
          Text(
            period == '周' ? '周一至周日 · 横向滑动查看' : '未设时段与截止时点',
            style: const TextStyle(color: CuteTokens.muted, fontSize: 12),
          ),
          if (period == '日') ...[
            for (final event in onDay(date).where((e) => !e.timed))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _EventRow(event),
              ),
          ],
          const SizedBox(height: 12),
          _TimeGrid(
            key: ValueKey('$period:${date.year}-${date.month}-${date.day}'),
            date: date,
            week: period == '周',
            events: events,
          ),
        ],
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.date,
    required this.events,
    required this.onChanged,
  });
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(date.year, date.month),
        start = first.subtract(Duration(days: first.weekday - 1));
    final weeks =
        ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
            .ceil();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return PaperSurface(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CuteTokens.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = start.add(Duration(days: w * 7 + col)),
                            entries = events
                                .where(
                                  (e) => sameDay(
                                    e.day,
                                    start.add(Duration(days: w * 7 + col)),
                                  ),
                                )
                                .toList();
                        final selected = sameDay(day, date),
                            today = sameDay(
                              day,
                              shanghaiWallTime(DateTime.now()),
                            );
                        return Semantics(
                          label:
                              '${day.year}年${day.month}月${day.day}日${today ? '，今天' : ''}，${entries.where((e) => e.resource == 'tasks').length}项任务，${entries.where((e) => e.resource != 'tasks').length}份日志',
                          selected: selected,
                          child: Material(
                            color: selected
                                ? const Color(0xFFFF8A24)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: today && !selected
                                  ? const BorderSide(color: Color(0xFFFF8A24))
                                  : BorderSide.none,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => onChanged(day),
                              child: SizedBox(
                                height: math.max(58, 44 * scale + 12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 1,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                          color: day.month == date.month
                                              ? CuteTokens.ink
                                              : CuteTokens.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      if (entries.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? CuteTokens.cream
                                                : entries.first.color,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            entries.length > 1
                                                ? '${entries.length}项'
                                                : entries.first.resource ==
                                                      'tasks'
                                                ? '任务'
                                                : '日志',
                                            maxLines: 1,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: CuteTokens.ink,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event);
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: event.color,
    onTap: () => openItem(context, event.resource, event.record.id),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${event.time}  ${event.record.title}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${event.resource == 'tasks' ? '任务' : '日志'} · ${event.record.fields['主负责人'] ?? event.record.subtitle}',
                style: const TextStyle(fontSize: 12, color: CuteTokens.muted),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 18),
      ],
    ),
  );
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    final start = date.subtract(Duration(days: date.weekday - 1));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Semantics(
              selected: i == date.weekday - 1,
              label:
                  '${start.add(Duration(days: i)).year}年${start.add(Duration(days: i)).month}月${start.add(Duration(days: i)).day}日',
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  backgroundColor: i == date.weekday - 1
                      ? const Color(0xFFFFE5D2)
                      : null,
                ),
                onPressed: () => onChanged(start.add(Duration(days: i))),
                child: Text(
                  '${['一', '二', '三', '四', '五', '六', '日'][i]}\n${start.add(Duration(days: i)).day}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeGrid extends StatefulWidget {
  const _TimeGrid({
    super.key,
    required this.date,
    required this.week,
    required this.events,
  });
  final DateTime date;
  final bool week;
  final List<CalendarEvent> events;
  @override
  State<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<_TimeGrid> {
  final vertical = ScrollController(initialScrollOffset: 8 * 72);
  final headerHorizontal = ScrollController();
  final gridHorizontal = ScrollController();
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    headerHorizontal.addListener(() => sync(headerHorizontal, gridHorizontal));
    gridHorizontal.addListener(() => sync(gridHorizontal, headerHorizontal));
  }

  void sync(ScrollController source, ScrollController target) {
    if (syncing || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < .5) return;
    syncing = true;
    target.jumpTo(offset);
    syncing = false;
  }

  @override
  void dispose() {
    vertical.dispose();
    headerHorizontal.dispose();
    gridHorizontal.dispose();
    super.dispose();
  }

  String get storageId =>
      '${widget.week ? 'week' : 'day'}:${widget.date.year}-${widget.date.month}-${widget.date.day}';

  @override
  Widget build(BuildContext context) {
    final first = widget.week
        ? widget.date.subtract(Duration(days: widget.date.weekday - 1))
        : widget.date;
    final days = widget.week ? 7 : 1;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final dateHeight = math.max(36.0, 28 * scale);
    final hasUntimed = widget.week && widget.events.any((e) => !e.timed);
    final untimedHeight = hasUntimed ? 96.0 : 0.0;
    return SizedBox(
      height: 480,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = widget.week
              ? math.max(128.0, 96 * scale)
              : constraints.maxWidth - 48;
          List<CalendarEvent> daily(DateTime day) =>
              widget.events.where((e) => sameDay(e.day, day)).toList();
          return Column(
            children: [
              // Keep context visible while the 24-hour grid scrolls.
              SizedBox(
                key: const ValueKey('calendar-sticky-header'),
                height: dateHeight + untimedHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: hasUntimed
                          ? const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Text(
                                '未设\n时段',
                                style: TextStyle(fontSize: 10),
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey('header:$storageId'),
                        controller: headerHorizontal,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < days; i++)
                              SizedBox(
                                width: width,
                                height: dateHeight + untimedHeight,
                                child: Builder(
                                  builder: (context) {
                                    final day = first.add(Duration(days: i));
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          height: dateHeight,
                                          child: Semantics(
                                            header: true,
                                            selected: sameDay(day, widget.date),
                                            label:
                                                '${day.year}年${day.month}月${day.day}日',
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                              child: Text(
                                                '${day.month}/${day.day} 周${['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1]}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (hasUntimed)
                                          Expanded(
                                            child: ListView(
                                              key: PageStorageKey(
                                                'untimed:$storageId:$i',
                                              ),
                                              padding: EdgeInsets.zero,
                                              children: [
                                                for (final e in daily(
                                                  day,
                                                ).where((e) => !e.timed))
                                                  TextButton(
                                                    style: TextButton.styleFrom(
                                                      minimumSize: const Size(
                                                        48,
                                                        48,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                    ),
                                                    onPressed: () => openItem(
                                                      context,
                                                      e.resource,
                                                      e.record.id,
                                                    ),
                                                    child: Text(
                                                      '${e.time} · ${e.record.title}',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  key: PageStorageKey('hours:$storageId'),
                  controller: vertical,
                  child: SizedBox(
                    height: 24 * 72 + 24,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 24 * 72 + 24,
                          child: Stack(
                            children: [
                              for (var h = 0; h <= 24; h++)
                                Positioned(
                                  top: h * 72,
                                  left: 0,
                                  child: Text(
                                    '${h.toString().padLeft(2, '0')}:00',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: CuteTokens.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            key: PageStorageKey('grid:$storageId'),
                            controller: gridHorizontal,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < days; i++)
                                  SizedBox(
                                    width: width,
                                    height: 24 * 72 + 24,
                                    child: eventColumn(
                                      context,
                                      first.add(Duration(days: i)),
                                      daily(first.add(Duration(days: i))),
                                      width,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget eventColumn(
    BuildContext context,
    DateTime day,
    List<CalendarEvent> daily,
    double width,
  ) {
    final timed = daily.where((e) => e.timed).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final ends = <int>[], lanes = <int>[];
    for (final e in timed) {
      var lane = ends.indexWhere((end) => end <= e.start!);
      if (lane < 0) {
        lane = ends.length;
        ends.add(e.end!);
      } else {
        ends[lane] = e.end!;
      }
      lanes.add(lane);
    }
    final count = math.max(1, ends.length);
    final now = shanghaiWallTime(DateTime.now());
    return Stack(
      children: [
        for (var h = 0; h <= 24; h++)
          Positioned(
            top: h * 72,
            left: 0,
            right: 0,
            child: const Divider(height: 1),
          ),
        for (final (index, e) in timed.indexed)
          Positioned(
            top: e.start! * 1.2,
            left: 4 + lanes[index] * (width - 8) / count,
            width: (width - 8) / count - 4,
            height: math.max(48, (e.end! - e.start!) * 1.2),
            child: Material(
              color: e.color,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => openItem(context, e.resource, e.record.id),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      '${e.time}\n${e.record.title}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // A deadline is a point, never a fabricated meeting duration.
        for (final e in daily.where((e) => !e.timed && e.resource == 'tasks'))
          Positioned(
            top: (e.day.hour * 60 + e.day.minute) * 1.2,
            left: 4,
            right: 4,
            child: Semantics(
              label: '${e.time}，${e.record.title}，截止时点',
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFFA7460E)),
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () =>
                          openItem(context, e.resource, e.record.id),
                      child: Text(
                        '${e.time} · ${e.record.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (sameDay(day, now))
          Positioned(
            top: (now.hour * 60 + now.minute) * 1.2,
            left: 0,
            right: 0,
            child: Semantics(
              label: '当前时间 ${CalendarEvent.clock(now.hour * 60 + now.minute)}',
              child: const Divider(
                height: 1,
                color: Color(0xFFB33643),
                thickness: 2,
              ),
            ),
          ),
      ],
    );
  }
}
