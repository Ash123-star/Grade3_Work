import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

class CalendarEvent {
  const CalendarEvent(
    this.record,
    this.day,
    this.start,
    this.end, {
    this.spanStart,
    this.spanEnd,
  });
  final Record record;
  final DateTime day;
  final int? start, end;
  final DateTime? spanStart, spanEnd;
  DateTime get firstDay => DateTime(
    (spanStart ?? day).year,
    (spanStart ?? day).month,
    (spanStart ?? day).day,
  );
  DateTime get lastDay => DateTime(
    (spanEnd ?? day).year,
    (spanEnd ?? day).month,
    (spanEnd ?? day).day,
  );
  bool get timed => start != null && end != null;
  Color get color {
    final tagged = _tagColor(
      record.fields['tagColor'] ?? record.fields['tag_color'],
    );
    return tagged ?? SunnyPalette.blue;
  }

  static String clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String get time => timed
      ? '${clock(start!)} — ${clock(end!)}'
      : '截止 ${clock(day.hour * 60 + day.minute)}';
}

Color? _tagColor(dynamic value) {
  if (value is Color) return value;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  final normalized = text.startsWith('#') ? text.substring(1) : text;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(normalized.length <= 6 ? 0xFF000000 | parsed : parsed);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class CalendarContent extends ConsumerStatefulWidget {
  const CalendarContent({
    super.key,
    this.availableHeight = 0,
    this.ownerId,
    this.monthOnly = false,
  });
  final double availableHeight;
  final String? ownerId;
  final bool monthOnly;
  @override
  ConsumerState<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends ConsumerState<CalendarContent> {
  @override
  Widget build(BuildContext context) {
    final dateProvider = widget.ownerId == null
        ? selectedDateProvider
        : memberCalendarDateProvider(widget.ownerId!);
    final date = ref.watch(dateProvider),
        period = widget.monthOnly ? '月' : ref.watch(periodProvider);
    if (period == '月') {
      return _StableMonthPager(
        selectedDate: date,
        ownerId: widget.ownerId,
        availableHeight: widget.availableHeight,
        onMonthChanged: (next) {
          ref.read(dateProvider.notifier).state = next;
        },
        onDayChanged: (next, events) {
          final session = ref.read(sessionProvider);
          ref.read(dateProvider.notifier).state = next;
          showTuantuanFocusSheet<void>(
            context: context,
            title: dayHeading(next),
            child: Consumer(
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
                return ListView(
                  key: const ValueKey('month-day-agenda'),
                  padding: const EdgeInsets.all(20),
                  children: [
                    _DayAgenda(date: next, events: eventsOnDay(events, next)),
                  ],
                );
              },
            ),
          );
        },
      );
    }
    final tasks = ref.watch(datedRecordsProvider('tasks'));
    final events = <CalendarEvent>[];
    for (final record in tasks.valueOrNull?.items ?? <Record>[]) {
      final day = businessEventTime(record.fields['deadline']);
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
          spanStart: start,
          spanEnd: day,
        ),
      );
    }
    final selectedEvents = eventsOnDay(events, date);
    void selectDay(DateTime day) {
      final session = ref.read(sessionProvider);
      ref.read(dateProvider.notifier).state = day;
      showTuantuanBottomSheet<void>(
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
              child: TuantuanSheet(
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
                          _DayAgenda(
                            date: day,
                            events: eventsOnDay(events, day),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tasks.isLoading)
          period == '月'
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: SunnyLoadingIndicator()),
                )
              : const LoadingSkeleton()
        else if (tasks.hasError)
          ErrorPanel(
            '${tasks.error}',
            retry: () => ref.invalidate(datedRecordsProvider('tasks')),
          )
        else if (period == '月') ...[
          _MonthGrid(
            date: date,
            events: events,
            onChanged: selectDay,
            availableHeight: widget.availableHeight,
          ),
        ] else if (period == '周')
          _WeekOverview(
            date: date,
            events: events,
            onChanged: selectDay,
            minimumHeight: widget.availableHeight,
          )
        else ...[
          _WeekStrip(
            date: date,
            onChanged: (day) => ref.read(dateProvider.notifier).state = day,
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

int _monthIndex(DateTime date) => date.year * 12 + date.month - 1;

DateTime _monthFromIndex(int index) => DateTime(index ~/ 12, index % 12 + 1);

class _StableMonthPager extends StatefulWidget {
  const _StableMonthPager({
    required this.selectedDate,
    required this.ownerId,
    required this.availableHeight,
    required this.onMonthChanged,
    required this.onDayChanged,
  });
  final DateTime selectedDate;
  final String? ownerId;
  final double availableHeight;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime, List<CalendarEvent>) onDayChanged;

  @override
  State<_StableMonthPager> createState() => _StableMonthPagerState();
}

class _StableMonthPagerState extends State<_StableMonthPager> {
  static const _baseMonth = 2000 * 12;
  late final PageController _controller = PageController(
    initialPage: _monthIndex(widget.selectedDate) - _baseMonth,
  );
  int? _lastPage;

  @override
  void didUpdateWidget(covariant _StableMonthPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate.year == widget.selectedDate.year &&
        oldWidget.selectedDate.month == widget.selectedDate.month) {
      return;
    }
    if (!_controller.hasClients) return;
    final target = _monthIndex(widget.selectedDate) - _baseMonth;
    if (_controller.page?.round() == target) return;
    _controller.jumpToPage(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.availableHeight > 0
        ? widget.availableHeight
        : MediaQuery.sizeOf(context).width * 1.6;
    return SizedBox(
      height: height,
      child: PageView.builder(
        key: const ValueKey('calendar-month-timeline'),
        controller: _controller,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(),
        onPageChanged: (page) {
          if (_lastPage == page) return;
          _lastPage = page;
          final month = _monthFromIndex(_baseMonth + page);
          if (_monthIndex(widget.selectedDate) == _monthIndex(month)) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onMonthChanged(month);
          });
        },
        itemBuilder: (context, page) => _StableMonthPage(
          month: _monthFromIndex(_baseMonth + page),
          ownerId: widget.ownerId,
          availableHeight: height,
          onDayChanged: widget.onDayChanged,
        ),
      ),
    );
  }
}

class _StableMonthPage extends ConsumerWidget {
  const _StableMonthPage({
    required this.month,
    required this.ownerId,
    required this.availableHeight,
    required this.onDayChanged,
  });
  final DateTime month;
  final String? ownerId;
  final double availableHeight;
  final void Function(DateTime, List<CalendarEvent>) onDayChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      calendarMonthTasksProvider((ownerId, _monthIndex(month))),
    );
    return state.when(
      loading: () => const Center(child: SunnyLoadingIndicator()),
      error: (error, _) => Center(
        child: _MonthRetry(
          message: '$error',
          onPressed: () => ref.invalidate(
            calendarMonthTasksProvider((ownerId, _monthIndex(month))),
          ),
        ),
      ),
      data: (page) {
        final events = _calendarEvents(page.items);
        return _MonthGrid(
          date: month,
          events: events,
          onChanged: (day) => onDayChanged(day, events),
          availableHeight: availableHeight,
        );
      },
    );
  }
}

class _MonthRetry extends StatelessWidget {
  const _MonthRetry({required this.message, required this.onPressed});
  final String message;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onPressed,
    radius: 28,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('该月记录暂不可用', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text('轻触重试', style: TextStyle(color: SunnyPalette.primaryStrong)),
        ],
      ),
    ),
  );
}

List<CalendarEvent> _calendarEvents(Iterable<Record> records) {
  final events = <CalendarEvent>[];
  for (final record in records) {
    final day = businessEventTime(record.fields['deadline']);
    if (day == null) continue;
    final start = businessEventTime(record.fields['startAt']);
    final end = businessEventTime(record.fields['endAt']);
    final timed =
        start != null &&
        end != null &&
        end.isAfter(start) &&
        sameDay(start, day);
    events.add(
      CalendarEvent(
        record,
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
        spanStart: start,
        spanEnd: day,
      ),
    );
  }
  return events;
}

List<CalendarEvent> eventsOnDay(List<CalendarEvent> events, DateTime day) =>
    events
        .where(
          (e) =>
              !DateTime(day.year, day.month, day.day).isBefore(e.firstDay) &&
              !DateTime(day.year, day.month, day.day).isAfter(e.lastDay),
        )
        .toList()
      ..sort((a, b) {
        int minute(CalendarEvent e) =>
            e.start ?? e.day.hour * 60 + e.day.minute;
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
          child: Text('暂无记录，可选择其他日期'),
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
    key: ValueKey('agenda:tasks:${event.record.id}'),
    onTap: () => openItem(context, 'tasks', event.record.id),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: event.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const TuantuanIcon('task', size: 34),
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
              Text(event.time, style: Theme.of(context).textTheme.bodySmall),
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
  const _EventPreview(this.event);
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: event.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.alphaBlend(
            SunnyPalette.primaryStrong.withValues(alpha: .16),
            event.color,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        event.record.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 1.15, color: SunnyPalette.ink),
      ),
    );
  }
}

class _WeekOverview extends StatelessWidget {
  const _WeekOverview({
    required this.date,
    required this.events,
    required this.onChanged,
    this.minimumHeight = 0,
  });
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onChanged;
  final double minimumHeight;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    return PaperSurface(
      key: const ValueKey('calendar-week-overview'),
      decorated: true,
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
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          72 * MediaQuery.textScalerOf(context).scale(1),
                          (minimumHeight - 16) / 7,
                        ),
                      ),
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
                                              'week-pill:tasks:${event.record.id}',
                                            ),
                                            width: constraints.maxWidth,
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
    required this.availableHeight,
  });
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onChanged;
  final double availableHeight;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(date.year, date.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks =
        ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
            .ceil();
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    return PaperSurface(
      key: const ValueKey('calendar-month-grid'),
      decorated: true,
      skin: TuantuanAssets.surfaces['warm'],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / 7;
          final weekdayHeight = math.max(
            34.0,
            MediaQuery.textScalerOf(context).scale(12) * 1.5 + 8,
          );
          final height = availableHeight > 0
              ? availableHeight
              : constraints.maxWidth * 1.6;
          final cellHeight = math.max(
            0.0,
            (height - 16 - weekdayHeight) / weeks,
          );
          final recordTop = math.max(
            24.0,
            MediaQuery.textScalerOf(context).scale(13) * 1.15 + 6,
          );
          final barHeight =
              MediaQuery.textScalerOf(context).scale(_monthRecordFontSize) *
                  1.15 +
              3;
          final capacity = ((cellHeight - recordTop - 2 + 1) / (barHeight + 1))
              .floor()
              .clamp(0, 5);
          final lanes = _monthLanes(
            events,
            gridStart,
            gridStart.add(Duration(days: weeks * 7 - 1)),
            capacity,
          );
          return Column(
            children: [
              SizedBox(
                height: weekdayHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < _weekdays.length; i++)
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  _weekdays[i],
                                  key: ValueKey(
                                    'month-weekday:${_weekdays[i]}',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                            Positioned(
                              top: -2,
                              right: 0,
                              child: DogAvatar(
                                index: DogAssets.weekdayAvatars[i],
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              for (var week = 0; week < weeks; week++)
                SizedBox(
                  height: cellHeight,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (var col = 0; col < 7; col++)
                        Builder(
                          builder: (context) {
                            final day = start.add(
                              Duration(days: week * 7 + col),
                            );
                            final selected = sameDay(day, date),
                                today = sameDay(
                                  day,
                                  shanghaiWallTime(DateTime.now()),
                                );
                            final currentMonth = day.month == date.month;
                            return Positioned(
                              left: col * cellWidth,
                              top: 0,
                              width: cellWidth,
                              height: cellHeight,
                              child: Semantics(
                                label: currentMonth
                                    ? '${dayHeading(day)}${today ? '，今天' : ''}，查看当天全部记录'
                                    : null,
                                selected: selected,
                                child: InkWell(
                                  key: ValueKey(
                                    'month-day:${day.year}-${day.month}-${day.day}',
                                  ),
                                  onTap: currentMonth
                                      ? () => onChanged(day)
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                      vertical: 2,
                                    ),
                                    padding: const EdgeInsets.only(
                                      left: 3,
                                      top: 3,
                                    ),
                                    alignment: Alignment.topLeft,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? SunnyPalette.orange.withValues(
                                              alpha: .18,
                                            )
                                          : null,
                                      border: Border(
                                        right: BorderSide(
                                          color: SunnyPalette.ink.withValues(
                                            alpha: .08,
                                          ),
                                        ),
                                        bottom: BorderSide(
                                          color: SunnyPalette.ink.withValues(
                                            alpha: .08,
                                          ),
                                        ),
                                        top: today
                                            ? BorderSide(
                                                color: SunnyPalette.primary,
                                                width: 1.5,
                                              )
                                            : BorderSide.none,
                                      ),
                                    ),
                                    child: currentMonth
                                        ? Stack(
                                            children: [
                                              Positioned(
                                                left: 3,
                                                top: 3,
                                                child: Text(
                                                  '${day.day}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    height: 1.15,
                                                    fontWeight:
                                                        selected || today
                                                        ? FontWeight.w700
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                              if (eventsOnDay(events, day).any(
                                                (event) => !lanes.containsKey(
                                                  _calendarEventKey(event),
                                                ),
                                              ))
                                                Positioned(
                                                  right: 1,
                                                  top: 3,
                                                  child: Text(
                                                    '+${eventsOnDay(events, day).where((event) => !lanes.containsKey(_calendarEventKey(event))).length}',
                                                    key: ValueKey(
                                                      'month-overflow:${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              if (today &&
                                                  cellWidth >= 38 &&
                                                  eventsOnDay(
                                                    events,
                                                    day,
                                                  ).every(
                                                    (event) =>
                                                        lanes.containsKey(
                                                          _calendarEventKey(
                                                            event,
                                                          ),
                                                        ),
                                                  ))
                                                const Positioned(
                                                  top: 1,
                                                  right: 1,
                                                  child: DogAvatar(
                                                    index:
                                                        DogAssets.todayAvatar,
                                                    size: 22,
                                                  ),
                                                ),
                                            ],
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ..._monthWeekBars(
                        context,
                        events,
                        start.add(Duration(days: week * 7)),
                        cellWidth,
                        lanes,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

List<Widget> _monthWeekBars(
  BuildContext context,
  List<CalendarEvent> events,
  DateTime weekStart,
  double cellWidth,
  Map<String, int> lanes,
) {
  final weekEnd = weekStart.add(const Duration(days: 6));
  final candidates =
      events
          .where(
            (e) =>
                !e.lastDay.isBefore(weekStart) && !e.firstDay.isAfter(weekEnd),
          )
          .toList()
        ..sort((a, b) => a.firstDay.compareTo(b.firstDay));
  final bars = <Widget>[];
  for (final event in candidates) {
    final lane = lanes[_calendarEventKey(event)];
    if (lane == null) continue;
    final from = event.firstDay.isBefore(weekStart)
        ? weekStart
        : event.firstDay;
    final to = event.lastDay.isAfter(weekEnd) ? weekEnd : event.lastDay;
    final col = from.difference(weekStart).inDays,
        days = to.difference(from).inDays + 1;
    final starts = sameDay(from, event.firstDay),
        continuesAtWeekStart = col == 0 && !starts,
        ends = sameDay(to, event.lastDay);
    final recordTop = math.max(
      24.0,
      MediaQuery.textScalerOf(context).scale(13) * 1.15 + 6,
    );
    final fontSize = _monthRecordFontSize;
    final barHeight =
        MediaQuery.textScalerOf(context).scale(fontSize) * 1.15 + 3;
    final top = recordTop + lane * (barHeight + 1);
    bars.add(
      Positioned(
        key: ValueKey(
          'month-span:tasks:${event.record.id}:${weekStart.toIso8601String()}',
        ),
        left: col * cellWidth + (col == 0 ? 2 : 0),
        top: top,
        width:
            days * cellWidth -
            (col == 0 ? 2 : 0) -
            (sameDay(to, weekEnd) ? 2 : 0),
        height: barHeight,
        child: IgnorePointer(
          child: Material(
            color: event.color,
            borderRadius: BorderRadius.horizontal(
              left: starts ? const Radius.circular(4) : Radius.zero,
              right: ends ? const Radius.circular(4) : Radius.zero,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: starts || continuesAtWeekStart
                  ? SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2, right: 10),
                        child: Text(
                          key: ValueKey(
                            'month-span-label:tasks:${event.record.id}:${weekStart.toIso8601String()}',
                          ),
                          event.record.title,
                          semanticsLabel: event.record.title,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: SunnyPalette.ink,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
  return bars;
}

String _calendarEventKey(CalendarEvent event) => event.record.id;

// Text is bounded by the weekly segment, never by a fixed character count.
const double _monthRecordFontSize = 10.0;

Map<String, int> _monthLanes(
  List<CalendarEvent> events,
  DateTime gridStart,
  DateTime gridEnd,
  int capacity,
) {
  final candidates =
      events
          .where(
            (event) =>
                !event.lastDay.isBefore(gridStart) &&
                !event.firstDay.isAfter(gridEnd),
          )
          .toList()
        ..sort((a, b) {
          final start = a.firstDay.compareTo(b.firstDay);
          if (start != 0) return start;
          // Reserve the lane for a continuous span before same-day previews.
          final duration = b.lastDay.compareTo(a.lastDay);
          return duration != 0
              ? duration
              : _calendarEventKey(a).compareTo(_calendarEventKey(b));
        });
  final laneEvents = List.generate(capacity, (_) => <CalendarEvent>[]);
  final dailyCounts = <DateTime, int>{};
  final result = <String, int>{};
  for (final event in candidates) {
    final from = event.firstDay.isBefore(gridStart)
        ? gridStart
        : event.firstDay;
    final to = event.lastDay.isAfter(gridEnd) ? gridEnd : event.lastDay;
    var exceedsDayCapacity = false;
    for (
      var day = from;
      !day.isAfter(to);
      day = day.add(const Duration(days: 1))
    ) {
      if ((dailyCounts[day] ?? 0) >= capacity) {
        exceedsDayCapacity = true;
        break;
      }
    }
    if (exceedsDayCapacity) continue;
    final lane = laneEvents.indexWhere(
      (items) => items.every(
        (other) => other.lastDay.isBefore(from) || other.firstDay.isAfter(to),
      ),
    );
    if (lane < 0) continue;
    laneEvents[lane].add(event);
    result[_calendarEventKey(event)] = lane;
    for (
      var day = from;
      !day.isAfter(to);
      day = day.add(const Duration(days: 1))
    ) {
      dailyCounts[day] = (dailyCounts[day] ?? 0) + 1;
    }
  }
  return result;
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
