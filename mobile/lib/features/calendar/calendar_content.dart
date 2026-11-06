import 'holiday_data.dart';
import 'calendar_interaction.dart';
import 'calendar_schedule.dart';
import 'calendar_month_timeline.dart';
import 'calendar_preview_lane.dart';
import 'calendar_month_preview.dart';
import 'calendar_read_status.dart';
import '../../core/errors/api_failure.dart';
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
  DateTime get firstDay => DateTime.utc(
    (spanStart ?? day).year,
    (spanStart ?? day).month,
    (spanStart ?? day).day,
  );
  DateTime get lastDay => DateTime.utc(
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
        onDayChanged: (next, events, interaction, constraints) async {
          ref.read(dateProvider.notifier).state = next;
          final sheetEpoch = ref.read(sessionEpochProvider);
          final action = await showTuantuanFocusSheet<Object>(
            context: context,
            title: dayHeading(next),
            child: Consumer(
              builder: (context, sheetRef, _) {
                if (sheetRef.watch(sessionEpochProvider) != sheetEpoch ||
                    !sheetRef.watch(sessionProvider).canReadBusiness) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('账号权限已变化，请关闭后重新查看'),
                  );
                }
                return ListView(
                  key: const ValueKey('calendar-day-agenda'),
                  padding: const EdgeInsets.all(20),
                  children: [
                    _DayAgenda(
                      date: next,
                      events: eventsOnDay(events, next),
                      onMove:
                          interaction == null ||
                              constraints == null ||
                              widget.ownerId != null
                          ? null
                          : (record) => Navigator.pop(context, record),
                      onCreate:
                          interaction == null ||
                              constraints == null ||
                              widget.ownerId != null
                          ? null
                          : () => Navigator.pop(context, true),
                    ),
                  ],
                );
              },
            ),
          );
          if (!mounted || interaction == null || constraints == null) return;
          if (action is Record) {
            await interaction.accessible(action, constraints);
          } else if (action == true) {
            interaction.create(next, constraints);
          }
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
  final void Function(
    DateTime,
    List<CalendarEvent>,
    CalendarInteractionSurfaceState?,
    CalendarConstraints?,
  )
  onDayChanged;

  @override
  State<_StableMonthPager> createState() => _StableMonthPagerState();
}

class _StableMonthPagerState extends State<_StableMonthPager> {
  final _interaction = GlobalKey<CalendarInteractionSurfaceState>();
  // selectedDate is the anchor on re-entry. Restoring an old relative offset
  // as well would apply month navigation twice after switching day/week views.
  final _controller = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = widget.availableHeight > 0
        ? widget.availableHeight
        : (width > 0 && width.isFinite ? width : 320.0) * 1.6;
    return SizedBox(
      height: height,
      child: CalendarInteractionSurface(
        key: _interaction,
        scroll: _controller,
        readOnly: widget.ownerId != null,
        builder: (context, dragging) => LayoutBuilder(
          builder: (context, space) => CalendarMonthTimeline(
            selectedMonth: widget.selectedDate,
            controller: _controller,
            dragging: dragging,
            onMonthChanged: widget.onMonthChanged,
            monthBuilder: (month) => _StableMonthPage(
              month: month,
              ownerId: widget.ownerId,
              availableHeight: space.maxHeight,
              onDayChanged: widget.onDayChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class _StableMonthPage extends ConsumerStatefulWidget {
  const _StableMonthPage({
    required this.month,
    required this.ownerId,
    required this.availableHeight,
    required this.onDayChanged,
  });
  final DateTime month;
  final String? ownerId;
  final double availableHeight;
  final void Function(
    DateTime,
    List<CalendarEvent>,
    CalendarInteractionSurfaceState?,
    CalendarConstraints?,
  )
  onDayChanged;

  @override
  ConsumerState<_StableMonthPage> createState() => _StableMonthPageState();
}

class _StableMonthPageState extends ConsumerState<_StableMonthPage> {
  (int, String?, int)? _scope;
  PageResult? _lastComplete;

  @override
  Widget build(BuildContext context) {
    final month = widget.month, ownerId = widget.ownerId;
    final scope = (
      ref.watch(sessionEpochProvider),
      ownerId,
      _monthIndex(month),
    );
    if (_scope != scope) {
      _scope = scope;
      _lastComplete = null;
    }
    final state = ref.watch(
      calendarMonthTasksProvider((ownerId, _monthIndex(month))),
    );
    final holidays = ref.watch(holidayCalendarProvider(month.year));
    if (state is AsyncData<PageResult>) _lastComplete = state.value;
    Widget render(PageResult page, {bool readOnly = false}) {
      final events = _calendarEvents(page.items);
      final interaction = CalendarInteraction.of(context);
      CalendarConstraints? constraints;
      try {
        if (!readOnly) {
          constraints = CalendarConstraints.parse(page.scheduleConstraints);
        }
      } on FormatException {
        /* Read-only legacy server. */
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          if (readOnly && interaction?.drag.active == true) {
            interaction!.drag.cancel();
          } else {
            interaction?.drag.observe(page.items);
          }
        }
      });
      return CalendarLoadedMonth(
        month: month,
        constraints: constraints,
        child: _MonthGrid(
          date: month,
          holidays: holidays.valueOrNull ?? festivalCalendar(month.year),
          onRefreshHolidays: () =>
              ref.invalidate(holidayCalendarProvider(month.year)),
          events: events,
          onChanged: (day) =>
              widget.onDayChanged(day, events, interaction, constraints),
          constraints: constraints,
          availableHeight: widget.availableHeight,
        ),
      );
    }

    final failure = state.error;
    if (failure is ApiFailure &&
        (failure.statusCode == 429 || failure.code == 'RATE_LIMITED')) {
      final previous = _lastComplete;
      return SizedBox(
        height: widget.availableHeight,
        child: Stack(
          children: [
            if (previous != null)
              Positioned.fill(child: render(previous, readOnly: true)),
            Align(
              alignment: previous == null
                  ? Alignment.center
                  : Alignment.topCenter,
              child: CalendarReadStatus(
                failure: failure,
                onRetry: () => ref.invalidate(
                  calendarMonthTasksProvider((ownerId, _monthIndex(month))),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (state.hasError) _lastComplete = null;
    return state.when(
      loading: () => SizedBox(
        height: widget.availableHeight,
        child: const Center(child: SunnyLoadingIndicator()),
      ),
      error: (error, _) => SizedBox(
        height: widget.availableHeight,
        child: Center(
          child: _MonthRetry(
            message: '$error',
            onPressed: () => ref.invalidate(
              calendarMonthTasksProvider((ownerId, _monthIndex(month))),
            ),
          ),
        ),
      ),
      data: render,
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
              !dateLabel(day).isBefore(e.firstDay) &&
              !dateLabel(day).isAfter(e.lastDay),
        )
        .toList()
      ..sort((a, b) {
        int minute(CalendarEvent e) =>
            e.start ?? e.day.hour * 60 + e.day.minute;
        final result = minute(a).compareTo(minute(b));
        return result == 0 ? a.record.id.compareTo(b.record.id) : result;
      });

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.date,
    required this.events,
    this.onMove,
    this.onCreate,
  });
  final ValueChanged<Record>? onMove;
  final VoidCallback? onCreate;
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
      if (onCreate != null)
        TextButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('在所选日期创建任务'),
        ),
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('暂无记录，可选择其他日期'),
        ),
      for (final event in events)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _EventRow(event, onMove: onMove),
        ),
    ],
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event, {this.onMove});
  final ValueChanged<Record>? onMove;
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
        if (onMove != null &&
            event.record.fields['capabilities'] is Map &&
            event.record.fields['capabilities']['reschedule'] == true)
          IconButton(
            tooltip: '移动到日期',
            onPressed: () => onMove!(event.record),
            icon: const Icon(Icons.event_available),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    this.constraints,
    this.holidays,
    this.onRefreshHolidays,
  });
  final HolidayCalendar? holidays;
  final VoidCallback? onRefreshHolidays;
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onChanged;
  final double availableHeight;
  final CalendarConstraints? constraints;
  @override
  Widget build(BuildContext context) {
    final drag = CalendarInteraction.of(context)?.drag;
    return drag == null
        ? _buildGrid(context)
        : ValueListenableBuilder(
            valueListenable: drag.targetFeedback,
            builder: (context, _, _) => _buildGrid(context),
          );
  }

  Widget _buildGrid(BuildContext context) {
    final drag = CalendarInteraction.of(context)?.drag;
    final candidate = drag?.preview;
    final source = drag?.intent?.record;
    final moving = candidate == null || source == null
        ? null
        : CalendarEvent(
            source,
            scheduleWallTime(candidate.end),
            null,
            null,
            spanStart: candidate.firstDay,
            spanEnd: scheduleWallTime(candidate.end),
          );
    final first = DateTime.utc(date.year, date.month);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks =
        ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
            .ceil();
    final last = DateTime.utc(date.year, date.month + 1, 0);
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
          final recordTop =
              math.max(
                24.0,
                MediaQuery.textScalerOf(context).scale(13) * 1.15 + 6,
              ) +
              MediaQuery.textScalerOf(context).scale(10) * 1.3;
          final barHeight =
              MediaQuery.textScalerOf(context).scale(_monthRecordFontSize) *
                  1.15 +
              3;
          final gridLast = start.add(Duration(days: weeks * 7 - 1));
          final holidayWarning =
              holidays?.warningForRange(start, gridLast) ?? '';
          final lanes = _monthLanes(events, start, gridLast);
          final folded = calendarMonthPreview(
            first: start,
            last: gridLast,
            intervals: events
                .where((e) => lanes.containsKey(e.record.id))
                .map(
                  (event) => CalendarLaneInterval(
                    event.record.id,
                    event.firstDay,
                    event.lastDay,
                    lanes[event.record.id]!,
                  ),
                ),
          );
          final weekRows = List.filled(weeks, 0);
          for (var week = 0; week < weeks; week++) {
            for (var col = 0; col < 7; col++) {
              final day = start.add(Duration(days: week * 7 + col));
              weekRows[week] = math.max(weekRows[week], folded[day]!.rows);
            }
          }
          final previewLanes = <int, int>{};
          if (moving != null && this.constraints != null) {
            for (var week = 0; week < weeks; week++) {
              final weekStart = start.add(Duration(days: week * 7));
              final weekEnd = weekStart.add(const Duration(days: 6));
              final from = [
                moving.firstDay,
                weekStart,
                first,
              ].reduce((a, b) => a.isAfter(b) ? a : b);
              final to = [
                moving.lastDay,
                weekEnd,
                last,
              ].reduce((a, b) => a.isBefore(b) ? a : b);
              if (from.isAfter(to)) continue;
              previewLanes[week] = calendarPreviewLane(
                taskId: moving.record.id,
                first: from,
                last: to,
                occupied: [
                  for (
                    var day = from;
                    !day.isAfter(to);
                    day = day.add(const Duration(days: 1))
                  ) ...[
                    for (final entry in folded[day]!.lanes.entries)
                      CalendarLaneInterval(entry.key, day, day, entry.value),
                    // The fifth row is the complete-list entry on crowded
                    // dates. A candidate must not cover it or count as a task.
                    if (folded[day]!.remaining > 0)
                      CalendarLaneInterval('', day, day, 4),
                  ],
                ],
              );
            }
          }
          double overflowSpace(int week) =>
              [
                for (var col = 0; col < 7; col++)
                  folded[start.add(Duration(days: week * 7 + col))]!.remaining,
              ].any((remaining) => remaining > 0)
              ? math.max(0.0, 48 - barHeight)
              : 0.0;

          double weekHeight(int week) {
            final rows = math.max(
              weekRows[week],
              previewLanes.containsKey(week) ? previewLanes[week]! + 1 : 0,
            );
            return math.max(
              cellHeight,
              recordTop + rows * (barHeight + 1) + 2 + overflowSpace(week),
            );
          }

          return Column(
            children: [
              SizedBox(
                height: weekdayHeight,
                child: Stack(
                  children: [
                    Row(
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
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SunshineMascot(size: 14),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            _weekdays[i],
                                            key: ValueKey(
                                              'month-weekday:${_weekdays[i]}',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (holidayWarning.isNotEmpty)
                      Positioned(
                        left: 4,
                        right: 4,
                        top: 0,
                        height: 18,
                        child: Tooltip(
                          message: holidayWarning,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: onRefreshHolidays,
                            child: Text(
                              '调休数据待更新 · 刷新',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (var week = 0; week < weeks; week++)
                SizedBox(
                  width: double.infinity,
                  height: weekHeight(week),
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
                            final holiday = holidays?.days[holidayDateKey(day)];
                            final currentMonth = day.month == date.month;
                            return Positioned(
                              left: col * cellWidth,
                              top: 0,
                              width: cellWidth,
                              height: weekHeight(week),
                              child: CalendarDayTarget(
                                day: day,
                                constraints: currentMonth
                                    ? this.constraints
                                    : null,
                                child: Semantics(
                                  label: currentMonth
                                      ? '${dayHeading(day)}${today ? '，今天' : ''}，查看当天全部记录'
                                      : null,
                                  selected: selected,
                                  child: InkWell(
                                    key: ValueKey(
                                      'month-day:${day.year}-${day.month}-${day.day}',
                                    ),
                                    onTap: () => onChanged(day),
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
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            left: 3,
                                            right: holiday?.off == null
                                                ? 3
                                                : MediaQuery.textScalerOf(
                                                        context,
                                                      ).scale(10) +
                                                      6,
                                            top: 3,
                                            child: Row(
                                              children: [
                                                Text(
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
                                                if (holiday?.label.isNotEmpty ??
                                                    false) ...[
                                                  const SizedBox(width: 3),
                                                  Expanded(
                                                    child: Tooltip(
                                                      message: holiday!.label,
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          holiday.label,
                                                          maxLines: 1,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                height: 1.15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (holiday?.off != null)
                                            Positioned(
                                              top: 3,
                                              right: 3,
                                              child: Tooltip(
                                                message:
                                                    '${holiday!.off! ? '放假休息' : '调休上班'} · ${holiday.arrangementSource}',
                                                child: Text(
                                                  holiday.arrangementLabel,
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.15,
                                                    color: holiday.off!
                                                        ? Colors.red.shade700
                                                        : Colors.blue.shade700,
                                                  ),
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
                      ..._monthWeekBars(
                        context,
                        events,
                        start.add(Duration(days: week * 7)),
                        first,
                        last,
                        cellWidth,
                        lanes,
                        this.constraints,
                        onChanged,
                        foldedDays: folded,
                      ),
                      for (var col = 0; col < 7; col++)
                        if (folded[start.add(Duration(days: week * 7 + col))]!
                                .remaining >
                            0)
                          Positioned(
                            left: col * cellWidth + 2,
                            top: recordTop + 4 * (barHeight + 1),
                            width: cellWidth - 4,
                            height: math.max(48, barHeight),
                            child: Semantics(
                              label:
                                  '${dayHeading(start.add(Duration(days: week * 7 + col)))}，另有${folded[start.add(Duration(days: week * 7 + col))]!.remaining}项任务，查看当天全部任务',
                              button: true,
                              child: GestureDetector(
                                key: ValueKey(
                                  'month-overflow:${businessDateText(start.add(Duration(days: week * 7 + col)))}',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onChanged(
                                  start.add(Duration(days: week * 7 + col)),
                                ),
                                // This entry is not an empty date cell.
                                onLongPress: () {},
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '+${folded[start.add(Duration(days: week * 7 + col))]!.remaining}',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: _monthRecordFontSize,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      color: SunnyPalette.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      if (moving != null && previewLanes.containsKey(week))
                        ..._monthWeekBars(
                          context,
                          [moving],
                          start.add(Duration(days: week * 7)),
                          first,
                          last,
                          cellWidth,
                          {moving.record.id: previewLanes[week]!},
                          this.constraints,
                          onChanged,
                          previewDay: drag!.target!.day,
                          extraAfterFifthRow: overflowSpace(week),
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
  DateTime monthStart,
  DateTime monthEnd,
  double cellWidth,
  Map<String, int> lanes,
  CalendarConstraints? constraints,
  ValueChanged<DateTime> onChanged, {
  DateTime? previewDay,
  Map<DateTime, CalendarFoldedDay>? foldedDays,
  double extraAfterFifthRow = 0,
}) {
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
    // Neighbouring dates can preview and open records, but never gain write
    // capabilities from the current month's loaded schedule constraints.
    final visibleStart = previewDay == null || !weekStart.isBefore(monthStart)
        ? weekStart
        : monthStart;
    final visibleEnd = previewDay == null || !weekEnd.isAfter(monthEnd)
        ? weekEnd
        : monthEnd;
    final first = event.firstDay.isBefore(visibleStart)
        ? visibleStart
        : event.firstDay;
    final last = event.lastDay.isAfter(visibleEnd) ? visibleEnd : event.lastDay;
    if (first.isAfter(last)) continue;
    final visible = foldedDays == null
        ? [CalendarLaneInterval(event.record.id, first, last, lane)]
        : calendarVisibleSegments(
            taskId: event.record.id,
            first: first,
            last: last,
            days: foldedDays,
          );
    final segments = <CalendarLaneInterval>[];
    for (final interval in visible) {
      var beginning = interval.first;
      for (final boundary in [
        monthStart,
        monthEnd.add(const Duration(days: 1)),
      ]) {
        if (boundary.isAfter(beginning) && !boundary.isAfter(interval.last)) {
          segments.add(
            CalendarLaneInterval(
              event.record.id,
              beginning,
              boundary.subtract(const Duration(days: 1)),
              interval.lane,
            ),
          );
          beginning = boundary;
        }
      }
      segments.add(
        CalendarLaneInterval(
          event.record.id,
          beginning,
          interval.last,
          interval.lane,
        ),
      );
    }
    var mainIndex = 0, adjacentIndex = 0;
    for (final segment in segments) {
      final from = segment.first, to = segment.last;
      final currentMonth = !from.isBefore(monthStart) && !to.isAfter(monthEnd);
      final index = currentMonth ? mainIndex++ : adjacentIndex++;
      final keyDate =
          '${weekStart.toIso8601String().replaceFirst('Z', '')}'
          '${index == 0 ? '' : ':${businessDateText(from)}'}';
      final keyPrefix = previewDay != null
          ? 'drag-span'
          : currentMonth
          ? 'month-span'
          : 'adjacent-month-span';
      final col = from.difference(weekStart).inDays,
          days = to.difference(from).inDays + 1;
      final starts = sameDay(from, event.firstDay),
          continuesAtWeekStart =
              !starts &&
              (col == 0 ||
                  sameDay(from, monthStart) ||
                  index > 0 ||
                  !sameDay(from, first)),
          ends = sameDay(to, event.lastDay);
      final recordTop = math.max(
        24.0,
        MediaQuery.textScalerOf(context).scale(13) * 1.15 + 6,
      );
      final fontSize = _monthRecordFontSize;
      final barHeight =
          MediaQuery.textScalerOf(context).scale(fontSize) * 1.15 + 3;
      final top =
          recordTop +
          MediaQuery.textScalerOf(context).scale(10) * 1.3 +
          segment.lane * (barHeight + 1) +
          (segment.lane >= 5 ? extraAfterFifthRow : 0);
      final content = Material(
        key:
            previewDay != null &&
                !previewDay.isBefore(from) &&
                !previewDay.isAfter(to)
            ? const ValueKey('calendar-drag-bar')
            : null,
        elevation: previewDay == null ? 0 : 4,
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
                      event.record.title,
                      key: ValueKey(
                        '$keyPrefix-label:tasks:${event.record.id}:$keyDate',
                      ),
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
      );
      bars.add(
        Positioned(
          key: ValueKey('$keyPrefix:tasks:${event.record.id}:$keyDate'),
          left: col * cellWidth + (col == 0 ? 2 : 0),
          top: top,
          width:
              days * cellWidth -
              (col == 0 ? 2 : 0) -
              (sameDay(to, weekEnd) ? 2 : 0),
          height: barHeight,
          child: previewDay != null
              ? IgnorePointer(child: ExcludeSemantics(child: content))
              : Builder(
                  builder: (handleContext) => CalendarTaskHandle(
                    record: event.record,
                    constraints: currentMonth ? constraints : null,
                    onTap: (point) {
                      final box = handleContext.findRenderObject();
                      final offset = box is RenderBox
                          ? box.globalToLocal(point).dx
                          : 0.0;
                      final dayOffset = (offset / cellWidth).floor().clamp(
                        0,
                        days - 1,
                      );
                      onChanged(from.add(Duration(days: dayOffset)));
                    },
                    child: content,
                  ),
                ),
        ),
      );
    }
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
  final laneEvents = <List<CalendarEvent>>[];
  final result = <String, int>{};
  for (final event in candidates) {
    final from = event.firstDay.isBefore(gridStart)
        ? gridStart
        : event.firstDay;
    final to = event.lastDay.isAfter(gridEnd) ? gridEnd : event.lastDay;
    var lane = laneEvents.indexWhere(
      (items) => items.every(
        (other) => other.lastDay.isBefore(from) || other.firstDay.isAfter(to),
      ),
    );
    if (lane < 0) {
      lane = laneEvents.length;
      laneEvents.add(<CalendarEvent>[]);
    }
    laneEvents[lane].add(event);
    result[_calendarEventKey(event)] = lane;
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
