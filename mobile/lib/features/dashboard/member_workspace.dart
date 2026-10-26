import 'dart:async';
import 'package:pandora_mobile/shared/sibling_pager.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';

String memberDayLabel(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日';

const memberCategories = ['logs', 'tasks'];

final memberWorkspaceProvider = FutureProvider.autoDispose
    .family<Record, (String, String)>((ref, key) async {
      final session = ref.watch(sessionProvider);
      if (!session.manager || !session.canReadBusiness) {
        throw const ApiFailure(FailureKind.forbidden, '无权查看成员工作台');
      }
      var active = true;
      ref.onDispose(() => active = false);
      // Identity and body are gated together; a failed section cannot leave stale identity.
      final member = await ref.watch(
        itemProvider(('organization', key.$1)).future,
      );
      if (!active) throw const ApiFailure(FailureKind.unavailable, '读取已停止');
      final profile = await ref.watch(
        itemProvider(('organization/profile', key.$1)).future,
      );
      if (!active) throw const ApiFailure(FailureKind.unavailable, '读取已停止');
      final identity = member.title.trim().isEmpty ? profile : member;
      final fields = {...identity.fields, ...profile.fields};
      fields['position'] ??= fields['position_name'] ?? fields['职位'];
      fields['departmentName'] ??= fields['department_name'] ?? fields['部门'];
      return Record(
        id: identity.id,
        title: identity.title,
        subtitle: identity.subtitle,
        ownerId: identity.ownerId,
        version: identity.version,
        fields: fields,
      );
    });

class MemberWorkspace extends ConsumerStatefulWidget {
  const MemberWorkspace(
    this.memberId, {
    super.key,
    this.category = 'logs',
    this.businessDate,
  });
  final String memberId, category;
  final String? businessDate;
  @override
  ConsumerState<MemberWorkspace> createState() => _MemberWorkspaceState();
}

class _MemberWorkspaceState extends ConsumerState<MemberWorkspace> {
  bool ready = false;
  late final DateTime? incomingDate = DateTime.tryParse(
    widget.businessDate ?? '',
  );
  String get selectedCategory =>
      memberCategories.contains(widget.category) ? widget.category : 'logs';

  bool get valid =>
      (widget.businessDate == null ||
      incomingDate != null &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.businessDate!) &&
          incomingDate!.toIso8601String().split('T').first ==
              widget.businessDate);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (valid && widget.businessDate != null) {
        ref.read(memberLogDateProvider(widget.memberId).notifier).state =
            incomingDate;
        ref.read(memberCalendarDateProvider(widget.memberId).notifier).state =
            incomingDate!;
      }
      // Warm the member task month before the task tab is selected so the
      // calendar opens with records already available from the provider cache.
      final taskMonth = ref.read(memberCalendarDateProvider(widget.memberId));
      unawaited(
        ref.read(
          calendarMonthTasksProvider((
            widget.memberId,
            taskMonth.year * 12 + taskMonth.month - 1,
          )).future,
        ),
      );
      setState(() => ready = true);
    });
  }

  String route(String category) {
    final selected = memberCategories.contains(category) ? category : 'logs';
    final date = ref.read(memberLogDateProvider(widget.memberId));
    return '/me/team/${encode(widget.memberId)}/$selected${date == null ? '' : '?date=${date.toIso8601String().split('T').first}'}';
  }

  void retry(String category) {
    ref.invalidate(itemProvider(('organization', widget.memberId)));
    ref.invalidate(itemProvider(('organization/profile', widget.memberId)));
    for (final resource in ['logs/subordinates', 'tasks']) {
      ref.invalidate(memberRecordsProvider((resource, widget.memberId)));
    }
    ref.invalidate(memberWorkspaceProvider((widget.memberId, category)));
  }

  @override
  Widget build(BuildContext context) {
    if (!valid) {
      return PageFrame(
        title: '下属工作台',
        child: PageBody(
          children: [
            const EmptyIllustration(
              showCharacter: false,
              title: '工作台链接无效',
              subtitle: '日期无效，请从成员列表重新进入',
            ),
            OutlinedButton(
              onPressed: () => context.go('/me/people'),
              child: const Text('返回成员列表'),
            ),
          ],
        ),
      );
    }
    final session = ref.watch(sessionProvider);
    if (!session.manager || !session.canReadBusiness) {
      return const PageFrame(
        title: '下属工作台',
        child: EmptyIllustration(
          showCharacter: false,
          title: '无权访问',
          subtitle: '仅可查看服务端授权的成员范围',
        ),
      );
    }
    if (ref.watch(memberWorkspaceRevokedProvider(widget.memberId))) {
      return PageFrame(
        title: '下属工作台',
        child: PageBody(
          children: [
            const EmptyIllustration(
              showCharacter: false,
              title: '成员范围已不可访问',
              subtitle: '请重新检查当前授权范围',
            ),
            OutlinedButton(
              onPressed: () {
                ref
                        .read(
                          memberWorkspaceRevokedProvider(
                            widget.memberId,
                          ).notifier,
                        )
                        .state =
                    false;
                retry(selectedCategory);
              },
              child: const Text('重新检查访问权限'),
            ),
          ],
        ),
      );
    }
    return SiblingPager(
      key: ValueKey(widget.memberId),
      index: memberCategories.indexOf(selectedCategory),
      itemCount: memberCategories.length,
      onSelected: (index) => context.replace(route(memberCategories[index])),
      itemBuilder: (context, index) => Consumer(
        builder: (context, ref, _) =>
            _categoryPage(context, ref, memberCategories[index]),
      ),
    );
  }

  Widget _categoryPage(BuildContext context, WidgetRef ref, String category) {
    final memberId = widget.memberId;
    return PageFrame(
      key: PageStorageKey('member:$memberId:$category'),
      title: '下属工作台',
      child: !ready
          ? const LoadingSkeleton()
          : ref
                .watch(memberWorkspaceProvider((memberId, category)))
                .when(
                  skipLoadingOnRefresh: false,
                  skipLoadingOnReload: false,
                  loading: () => const LoadingSkeleton(),
                  error: (e, _) => PageBody(
                    children: [
                      RecordFailure(e, retry: () => retry(category)),
                      if (e is ApiFailure &&
                          e.kind == FailureKind.forbidden) ...[
                        const Text('成员范围已不可访问，受保护资料与记录已清除。'),
                        OutlinedButton(
                          onPressed: () => retry(category),
                          child: const Text('重新检查访问权限'),
                        ),
                      ],
                    ],
                  ),
                  data: (member) => PageBody(
                    children: [
                      PaperSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProtectedAvatar(
                                  name: member.title,
                                  attachmentId:
                                      member.fields['avatarAttachmentId']
                                          as String?,
                                  radius: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    member.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _memberInfo(
                                  '职位',
                                  member.fields['position'] ??
                                      member.fields['position_name'] ??
                                      member.fields['职位'],
                                ),
                                _memberInfo(
                                  '部门',
                                  member.fields['departmentName'] ??
                                      member.fields['department_name'] ??
                                      member.fields['部门'],
                                ),
                                _memberInfo(
                                  '电话',
                                  member.fields['phone'] ??
                                      member.fields['手机号'],
                                ),
                                _memberInfo(
                                  '邮箱',
                                  member.fields['email'] ?? member.fields['邮箱'],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final c in const [
                              ('logs', '日志'),
                              ('tasks', '任务'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(c.$2),
                                  selected: category == c.$1,
                                  onSelected: (_) =>
                                      context.replace(route(c.$1)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (category == 'logs')
                        MemberLogCalendar(ownerId: memberId),
                      if (category == 'tasks')
                        Column(
                          children: [
                            _MemberTaskMonthPicker(ownerId: memberId),
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * .76,
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    CalendarContent(
                                      ownerId: memberId,
                                      monthOnly: true,
                                      availableHeight: constraints.maxHeight,
                                    ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _MemberTaskMonthPicker extends ConsumerWidget {
  const _MemberTaskMonthPicker({required this.ownerId});
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(memberCalendarDateProvider(ownerId));
    return Row(
      children: [
        IconButton(
          tooltip: '上个月',
          onPressed: () =>
              ref.read(memberCalendarDateProvider(ownerId).notifier).state =
                  DateTime(date.year, date.month - 1, 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final picked = await showCalendarDateWheel(
                context: context,
                initialDate: DateTime(date.year, date.month, 1),
              );
              if (picked != null) {
                ref.read(memberCalendarDateProvider(ownerId).notifier).state =
                    DateTime(picked.year, picked.month, 1);
              }
            },
            child: Text('${date.year}年${date.month}月'),
          ),
        ),
        IconButton(
          tooltip: '下个月',
          onPressed: () =>
              ref.read(memberCalendarDateProvider(ownerId).notifier).state =
                  DateTime(date.year, date.month + 1, 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class MemberLogCalendar extends ConsumerStatefulWidget {
  const MemberLogCalendar({required this.ownerId, super.key});
  final String ownerId;

  @override
  ConsumerState<MemberLogCalendar> createState() => _MemberLogCalendarState();
}

class _MemberLogCalendarState extends ConsumerState<MemberLogCalendar> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(memberCalendarDateProvider(widget.ownerId));
    final month = DateTime(selected.year, selected.month);
    final monthIndex = month.year * 12 + month.month - 1;
    final state = ref.watch(
      memberLogMonthProvider((widget.ownerId, monthIndex)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: () => _moveMonth(selected, -1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => _pickMonth(selected),
                child: Text(
                  '${month.year}年${month.month}月',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed: () => _moveMonth(selected, 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        const SizedBox(height: 6),
        state.when(
          loading: () => const SizedBox(
            height: 300,
            child: Center(child: SunnyLoadingIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 180,
            child: RecordFailure(
              error,
              retry: () => ref.invalidate(
                memberLogMonthProvider((widget.ownerId, monthIndex)),
              ),
            ),
          ),
          data: (statuses) {
            final first = month.subtract(Duration(days: month.weekday - 1));
            final today = shanghaiWallTime(DateTime.now());
            final todayDate = DateTime(today.year, today.month, today.day);
            final cells =
                ((month.weekday -
                            1 +
                            DateTime(month.year, month.month + 1, 0).day) /
                        7)
                    .ceil() *
                7;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (context, index) {
                final date = first.add(Duration(days: index));
                final currentMonth = date.month == month.month;
                final reportedStatus = currentMonth
                    ? statuses.days[date.day] ?? MemberLogDayStatus.unknown
                    : MemberLogDayStatus.unknown;
                var status = reportedStatus;
                final day = DateTime(date.year, date.month, date.day);
                if (!currentMonth) {
                  status = MemberLogDayStatus.unknown;
                } else if (reportedStatus == MemberLogDayStatus.submitted) {
                  status = MemberLogDayStatus.submitted;
                } else if (day.isAfter(todayDate)) {
                  status = MemberLogDayStatus.future;
                } else if (statuses.employmentStartDate == null ||
                    day.isBefore(
                      DateTime(
                        statuses.employmentStartDate!.year,
                        statuses.employmentStartDate!.month,
                        statuses.employmentStartDate!.day,
                      ),
                    )) {
                  status = MemberLogDayStatus.unknown;
                }
                final dotColor = switch (status) {
                  MemberLogDayStatus.submitted => SunnyPalette.successInk,
                  MemberLogDayStatus.missing => Theme.of(
                    context,
                  ).colorScheme.error,
                  _ => null,
                };
                final dayLabel = switch (status) {
                  MemberLogDayStatus.submitted => '已提交日志',
                  MemberLogDayStatus.missing => '未提交日志',
                  MemberLogDayStatus.future => '未来日期',
                  MemberLogDayStatus.unknown => '状态未知',
                };
                return Semantics(
                  button: currentMonth,
                  label: '${memberDayLabel(date)}，$dayLabel',
                  child: InkWell(
                    onTap: currentMonth ? () => _openDay(date, status) : null,
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: currentMonth
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: .45),
                            ),
                          ),
                        ),
                        if (dotColor != null)
                          Positioned(
                            top: 7,
                            right: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox(width: 7, height: 7),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _statusLegend(context, '已提交', SunnyPalette.successInk),
            _statusLegend(context, '未提交', Theme.of(context).colorScheme.error),
            const Text('未来及未知日期不标记'),
          ],
        ),
      ],
    );
  }

  void _moveMonth(DateTime current, int offset) {
    final next = DateTime(current.year, current.month + offset, 1);
    ref.read(memberCalendarDateProvider(widget.ownerId).notifier).state = next;
    ref.invalidate(
      memberLogMonthProvider((widget.ownerId, next.year * 12 + next.month - 1)),
    );
  }

  Future<void> _pickMonth(DateTime current) async {
    final picked = await showCalendarDateWheel(
      context: context,
      initialDate: DateTime(current.year, current.month, 1),
    );
    if (!mounted || picked == null) {
      return;
    }
    final next = DateTime(picked.year, picked.month, 1);
    ref.read(memberCalendarDateProvider(widget.ownerId).notifier).state = next;
    ref.invalidate(
      memberLogMonthProvider((widget.ownerId, next.year * 12 + next.month - 1)),
    );
  }

  Future<void> _openDay(DateTime day, MemberLogDayStatus status) async {
    if (_opening) return;
    if (status != MemberLogDayStatus.submitted) {
      await showDialog<void>(
        context: context,
        builder: (context) => TuantuanDialog(
          title: Text(memberDayLabel(day)),
          content: Text(switch (status) {
            MemberLogDayStatus.missing => '当日未提交日志',
            MemberLogDayStatus.future => '该日期尚未到来',
            MemberLogDayStatus.unknown => '无法确认该日期的日志状态',
            MemberLogDayStatus.submitted => '正在读取日志',
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _opening = true);
    try {
      ref.read(memberLogDateProvider(widget.ownerId).notifier).state = day;
      final range = BusinessRange(day, '日');
      final page = await readCompleteList(
        ref.read(repositoryProvider),
        'logs/subordinates',
        Query(ownerId: widget.ownerId, from: range.from, to: range.to),
      );
      if (!mounted) return;
      final targetDate = day.toIso8601String().split('T').first;
      final record = page.items
          .where((item) => item.fields['businessDate'] == targetDate)
          .firstOrNull;
      if (record == null) {
        await showDialog<void>(
          context: context,
          builder: (context) => TuantuanDialog(
            title: Text(memberDayLabel(day)),
            content: const Text('当日未提交日志'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        openItem(context, 'logs/subordinates', record.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取日志失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

Widget _statusLegend(BuildContext context, String label, Color color) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 5),
    Text(label, style: Theme.of(context).textTheme.bodySmall),
  ],
);

Widget _memberInfo(String label, dynamic value) => Text(
  '$label  ${value == null || '$value'.trim().isEmpty ? '未提供' : value}',
  style: const TextStyle(color: DogBrandPalette.muted, fontSize: 12),
);
