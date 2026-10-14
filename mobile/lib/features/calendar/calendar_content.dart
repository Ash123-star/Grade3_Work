import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

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
      SunnyPalette.calendarEntries['$resource:${record.id}'.codeUnits.fold<int>(
            0,
            (sum, unit) => sum + unit,
          ) %
          SunnyPalette.calendarEntries.length];
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
    final selectedEvents = eventsOnDay(events, date);
    void selectDay(DateTime day) {
      final session = ref.read(sessionProvider);
      ref.read(selectedDateProvider.notifier).state = day;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Consumer(
          builder: (context, sheetRef, _) {
            final current = sheetRef.watch(sessionProvider);
            if (!current.canReadBusiness ||
                current.id != session.id ||
                current.token != session.token) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('账号权限已变化，请关闭后重新查看'),
              );
            }
            return FractionallySizedBox(
              heightFactor: .75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dayHeading(day),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭当天记录',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _DayAgenda(date: day, events: eventsOnDay(events, day)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            Semantics(
              toggled: showLogs,
              child: TextButton(
                onPressed: () => setState(() => showLogs = !showLogs),
                child: Text(
                  '${showLogs ? '■' : '□'} 日志',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
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
          _MonthGrid(date: date, events: events, onChanged: selectDay),
          const SizedBox(height: 16),
          _DayAgenda(date: date, events: selectedEvents),
        ] else if (period == '周')
          _WeekOverview(date: date, events: events, onChanged: selectDay)
        else ...[
          _WeekStrip(
            date: date,
            onChanged: (day) =>
                ref.read(selectedDateProvider.notifier).state = day,
          ),
          const SizedBox(height: 16),
          _DayAgenda(date: date, events: selectedEvents),
        ],
      ],
    );
  }
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
String dayHeading(DateTime day) =>
    '${day.month}月${day.day}日 周${_weekdays[day.weekday - 1]}';

List<CalendarEvent> eventsOnDay(List<CalendarEvent> events, DateTime day) =>
    events.where((e) => sameDay(e.day, day)).toList()..sort((a, b) {
      int minute(CalendarEvent e) =>
          e.start ??
          (e.resource == 'tasks' ? e.day.hour * 60 + e.day.minute : 1440);
      final result = minute(a).compareTo(minute(b));
      return result == 0 ? a.record.id.compareTo(b.record.id) : result;
    });

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({required this.date, required this.events});
  final DateTime date;
  final List<CalendarEvent> events;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            dayHeading(date),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${events.length} 条记录',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('这一天没有任务或日志，可选择其他日期'),
        ),
      for (final event in events)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _EventRow(event),
        ),
    ],
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event);
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) => PaperSurface(
    key: ValueKey('agenda:${event.resource}:${event.record.id}'),
    onTap: () => openItem(context, event.resource, event.record.id),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: event.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TuantuanIcon(
            event.resource == 'tasks' ? 'task' : 'log',
            size: 34,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.record.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${event.resource == 'tasks' ? '任务' : '日志'} · ${event.time}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (event.record.subtitle.isNotEmpty ||
                  event.record.fields['主负责人'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${event.record.fields['主负责人'] ?? event.record.subtitle}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 18),
      ],
    ),
  );
}

/// Compact colored text is a preview; the whole date opens accessible full rows.
class _EventPreview extends StatelessWidget {
  const _EventPreview(this.event, {this.month = false});
  final CalendarEvent event;
  final bool month;
  @override
  Widget build(BuildContext context) => AppLabelBadge(
    '${event.resource == 'tasks' ? '任' : '志'}·${event.record.title}',
    color: event.color,
    fontSize: month ? 10 : 12,
    compact: month,
  );
}

class _WeekOverview extends StatelessWidget {
  const _WeekOverview({
    required this.date,
    required this.events,
    required this.onChanged,
  });
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    return PaperSurface(
      key: const ValueKey('calendar-week-overview'),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final day = first.add(Duration(days: i));
                final entries = eventsOnDay(events, day);
                final selected = sameDay(day, date);
                return Semantics(
                  label: '${dayHeading(day)}，${entries.length}条记录，查看当天全部记录',
                  selected: selected,
                  child: InkWell(
                    key: ValueKey('week-day:${day.weekday}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(day),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: selected ? SunnyPalette.orange : null,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '周${_weekdays[i]}\n${day.month}/${day.day}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (entries.isEmpty)
                                      Text(
                                        '暂无记录',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      )
                                    else
                                      for (final event in entries.take(2))
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: SizedBox(
                                            key: ValueKey(
                                              'week-pill:${event.resource}:${event.record.id}',
                                            ),
                                            width: math.min(
                                              156,
                                              constraints.maxWidth,
                                            ),
                                            child: _EventPreview(event),
                                          ),
                                        ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 32,
                            child: Text(
                              entries.length > 2
                                  ? '+${entries.length - 2}'
                                  : '${entries.length}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
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
    final first = DateTime(date.year, date.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks =
        ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
            .ceil();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return PaperSurface(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in _weekdays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
          for (var week = 0; week < weeks; week++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = start.add(Duration(days: week * 7 + col));
                        final entries = eventsOnDay(events, day);
                        final currentMonth = day.month == date.month;
                        final selected = sameDay(day, date);
                        final today = sameDay(
                          day,
                          shanghaiWallTime(DateTime.now()),
                        );
                        return Semantics(
                          label: currentMonth
                              ? '${dayHeading(day)}${today ? '，今天' : ''}，${entries.length}条记录，查看当天全部记录'
                              : null,
                          selected: selected,
                          child: InkWell(
                            key: ValueKey(
                              'month-day:${day.year}-${day.month}-${day.day}',
                            ),
                            borderRadius: BorderRadius.circular(14),
                            onTap: currentMonth ? () => onChanged(day) : null,
                            child: Container(
                              height: 108 * math.max(1, scale),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1,
                                vertical: 3,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: selected ? SunnyPalette.orange : null,
                                borderRadius: BorderRadius.circular(14),
                                border: today && !selected
                                    ? Border.all(
                                        color: SunnyPalette.primary,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: currentMonth
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          '${day.day}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected || today
                                                ? FontWeight.w700
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        for (final event in entries.take(2))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 3,
                                            ),
                                            child: _EventPreview(
                                              event,
                                              month: true,
                                            ),
                                          ),
                                        if (entries.length > 2)
                                          Text(
                                            '+${entries.length - 2}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
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
              label: dayHeading(start.add(Duration(days: i))),
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  backgroundColor: i == date.weekday - 1
                      ? SunnyPalette.orange
                      : null,
                ),
                onPressed: () => onChanged(start.add(Duration(days: i))),
                child: Text(
                  '${_weekdays[i]}\n${start.add(Duration(days: i)).day}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
