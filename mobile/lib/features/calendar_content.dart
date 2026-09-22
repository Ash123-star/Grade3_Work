import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../shared/widgets.dart';

class CalendarEvent {
  CalendarEvent(this.record, this.resource, this.day, this.start, this.end);
  final Record record;
  final String resource;
  final DateTime day;
  final int? start, end;
  bool get timed => start != null && end != null;
  Color get color => resource == 'tasks' ? CuteTokens.blue : CuteTokens.cream;
  String get time => timed ? '${clock(start!)} — ${clock(end!)}' : '未设置时段';
  static String clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String get description => [
    if (record.fields['body'] != null) '${record.fields['body']}',
    for (final field in [
      '任务内容',
      '今日工作',
      '遇到的阻碍',
      '明日计划',
      '主负责人',
      '协作人',
      '紧急程度',
      'status',
    ])
      if ('${record.fields[field] ?? ''}'.isNotEmpty)
        '${field == 'status' ? '状态' : field}：${record.fields[field]}',
  ].join('\n');
}

class CalendarContent extends ConsumerWidget {
  const CalendarContent({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider),
        period = ref.watch(periodProvider);
    final tasks = ref.watch(datedRecordsProvider('tasks')),
        logs = ref.watch(datedRecordsProvider('logs'));
    if (tasks.hasError || logs.hasError) {
      return ErrorPanel(
        '${tasks.error ?? logs.error}',
        retry: () => ref.invalidate(datedRecordsProvider),
      );
    }
    if (tasks.isLoading || logs.isLoading) return const LoadingSkeleton();
    final events = <CalendarEvent>[];
    for (final pair in [
      (tasks.valueOrNull?.items ?? <Record>[], 'tasks'),
      (logs.valueOrNull?.items ?? <Record>[], 'logs'),
    ]) {
      for (final r in pair.$1) {
        final day = DateTime.tryParse(
          '${pair.$2 == 'tasks' ? r.fields['deadline'] : r.fields['businessDate']}',
        )?.toLocal();
        if (day == null) continue;
        final start = DateTime.tryParse('${r.fields['startAt']}')?.toLocal();
        final end = DateTime.tryParse('${r.fields['endAt']}')?.toLocal();
        final valid =
            start != null &&
            end != null &&
            end.isAfter(start) &&
            start.year == day.year &&
            start.month == day.month &&
            start.day == day.day;
        events.add(
          CalendarEvent(
            r,
            pair.$2,
            day,
            valid ? start.hour * 60 + start.minute : null,
            valid
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
        events
            .where(
              (e) =>
                  e.day.year == d.year &&
                  e.day.month == d.month &&
                  e.day.day == d.day,
            )
            .toList()
          ..sort((a, b) => (a.start ?? 0).compareTo(b.start ?? 0));
    Widget card(CalendarEvent e, {bool compact = false}) => Material(
      color: e.color,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openItem(context, e.resource, e.record.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.record.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF245C66),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                e.time,
                style: const TextStyle(fontSize: 11, color: CuteTokens.muted),
              ),
              if (!compact) ...[
                const SizedBox(height: 6),
                Text(
                  e.description,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final first = DateTime(date.year, date.month, 1);
    final monday = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period == '月'
              ? '左右滑动查看整月 · 点击事件标签查看详情'
              : period == '周'
              ? '左右滑动查看周一至周日 · 上下滑动查看完整内容'
              : '按小时等比例排列 · 事件框内可滚动查看完整内容',
          style: const TextStyle(color: CuteTokens.muted),
        ),
        const SizedBox(height: 12),
        if (period == '月')
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1120,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final d in [
                        '周一',
                        '周二',
                        '周三',
                        '周四',
                        '周五',
                        '周六',
                        '周日',
                      ])
                        SizedBox(
                          width: 160,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              d,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (
                    var week = 0;
                    week <
                        ((first.weekday -
                                    1 +
                                    DateTime(
                                      date.year,
                                      date.month + 1,
                                      0,
                                    ).day) /
                                7)
                            .ceil();
                    week++
                  )
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var dow = 0; dow < 7; dow++)
                            Builder(
                              builder: (context) {
                                final d = first
                                    .subtract(Duration(days: first.weekday - 1))
                                    .add(Duration(days: week * 7 + dow));
                                return Container(
                                  width: 160,
                                  constraints: const BoxConstraints(
                                    minHeight: 155,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: d.month != date.month
                                        ? const Color(0xFFF0F2F1)
                                        : d.day == date.day
                                        ? const Color(0xFFE9F5EF)
                                        : Colors.white,
                                    border: Border.all(color: CuteTokens.line),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${d.month}/${d.day}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: d.month == date.month
                                              ? CuteTokens.ink
                                              : CuteTokens.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      for (final e in onDay(d))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Material(
                                            color: e.color,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: InkWell(
                                              onTap: () => openItem(
                                                context,
                                                e.resource,
                                                e.record.id,
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: Text(
                                                  e.record.title,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF245C66),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          )
        else if (period == '周')
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 7; i++)
                    Container(
                      width: 270,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: CuteTokens.line),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: CuteTokens.mint,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 12,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '周${['一', '二', '三', '四', '五', '六', '日'][i]} · ${monday.add(Duration(days: i)).month}/${monday.add(Duration(days: i)).day}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (onDay(monday.add(Duration(days: i))).isEmpty)
                            const Text(
                              '暂无事件',
                              style: TextStyle(color: CuteTokens.muted),
                            ),
                          for (final e in onDay(monday.add(Duration(days: i))))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: card(e),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          )
        else ...[
          for (final e in onDay(date).where((e) => !e.timed))
            Padding(padding: const EdgeInsets.only(bottom: 12), child: card(e)),
          LayoutBuilder(
            builder: (context, c) {
              final timed = onDay(date).where((e) => e.timed).toList();
              final lanes = <List<CalendarEvent>>[];
              final assigned = <int>[];
              for (final e in timed) {
                var lane = lanes.indexWhere((l) => l.last.end! <= e.start!);
                if (lane < 0) {
                  lane = lanes.length;
                  lanes.add([]);
                }
                lanes[lane].add(e);
                assigned.add(lane);
              }
              final columns = math.max(1, lanes.length);
              final width = math.max(c.maxWidth, 64 + columns * 240.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: 24 * 120 + 28,
                  child: Stack(
                    children: [
                      for (var hour = 0; hour <= 24; hour++)
                        Positioned(
                          top: hour * 120,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 56,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CuteTokens.muted,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(
                                  height: 1,
                                  color: CuteTokens.line,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final (i, e) in timed.indexed)
                        Positioned(
                          top: e.start! * 2.0,
                          left: 64 + assigned[i] * (width - 64) / columns,
                          width: (width - 64) / columns - 8,
                          height: (e.end! - e.start!) * 2.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: e.color,
                              border: Border(
                                left: BorderSide(
                                  color: e.resource == 'tasks'
                                      ? Colors.blue
                                      : Colors.orange,
                                  width: 3,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(child: card(e)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
