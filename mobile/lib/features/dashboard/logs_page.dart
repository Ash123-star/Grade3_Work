import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart' show CuteTokens;
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/record_display.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/features/dashboard/diary_composer_sheet.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

String _dateLabel(DateTime date) => '${date.month}月${date.day}日';

/// Injectable instant clock; business dates are always derived in Shanghai.
final recentDiaryClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key, this.subordinates = false});
  final bool subordinates;
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage>
    with WidgetsBindingObserver {
  String search = '';
  String department = '全部部门';
  bool _showRecent = true;
  late DateTime _today;
  Timer? _midnightTimer;

  DateTime _clock() => ref.read(recentDiaryClockProvider)();

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(shanghaiWallTime(_clock()));
    WidgetsBinding.instance.addObserver(this);
    if (!widget.subordinates) _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _clock();
    final wall = shanghaiWallTime(now);
    final next = DateTime.utc(
      wall.year,
      wall.month,
      wall.day + 1,
    ).subtract(const Duration(hours: 8));
    _midnightTimer = Timer(
      next.difference(now.toUtc()) + const Duration(milliseconds: 1),
      _refreshDate,
    );
  }

  void _refreshDate() {
    if (!mounted) return;
    final day = DateUtils.dateOnly(shanghaiWallTime(_clock()));
    ref.invalidate(recentDiaryRecordsProvider(day));
    ref.invalidate(todayDraftProvider(ref.read(sessionProvider).id));
    setState(() => _today = day);
    _scheduleMidnight();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.subordinates) return;
    if (state == AppLifecycleState.resumed) {
      _refreshDate();
    } else {
      _midnightTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final team = widget.subordinates;
    if (team && !user.manager) {
      return const PageFrame(
        title: '下属日志',
        child: EmptyIllustration(title: '无权访问', showCharacter: false),
      );
    }
    final recent = !team && _showRecent;
    final date = recent ? null : ref.watch(logFilterDateProvider);
    final canCreateForDate =
        date == null || canInitiallySubmitDiaryOn(date, now: _clock());
    final resource = team ? 'logs/subordinates' : 'logs';
    final state = recent
        ? ref.watch(recentDiaryRecordsProvider(_today))
        : ref.watch(logDayRecordsProvider((resource, team ? null : user.id)));
    final people = team ? ref.watch(recordsProvider('organization')) : null;
    final draft = ref.watch(todayDraftProvider(user.id));

    void compose(DateTime editDate, {Record? record}) {
      ref.read(logDateProvider.notifier).state = editDate;
      unawaited(
        showDiaryComposer(
          context,
          ref,
          date: editDate,
          recordId: record?.id,
          version: record?.version,
        ),
      );
    }

    void edit(Record record) => compose(
      DateTime.tryParse('${record.fields['businessDate']}') ?? _today,
      record: record,
    );

    void create() => compose(date ?? _today);

    Future<void> chooseDateFilter() async {
      final selectedDate = date;
      final choice = await showPremiumOptionPicker(
        context,
        title: '日志日期',
        options: [
          if (!team) '近三天',
          '全部日期',
          if (selectedDate != null) _dateLabel(selectedDate),
          '选择日期…',
        ],
        selected: recent
            ? '近三天'
            : selectedDate == null
            ? '全部日期'
            : _dateLabel(selectedDate),
      );
      if (!context.mounted || choice == null) return;
      if (choice == '近三天') {
        setState(() => _showRecent = true);
        _refreshDate();
      } else if (choice == '全部日期') {
        _showRecent = false;
        ref.read(logFilterDateProvider.notifier).state = null;
      } else if (choice == '选择日期…') {
        final next = await showPremiumDatePicker(
          context,
          initial: date ?? _today,
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
        );
        if (!context.mounted || next == null) return;
        _showRecent = false;
        ref.read(logFilterDateProvider.notifier).state = next;
      }
      setState(() {});
    }

    Widget dateFilter() => OutlinedButton.icon(
      key: ValueKey(
        'log-date:${recent ? 'recent' : date?.toIso8601String() ?? 'all'}',
      ),
      onPressed: chooseDateFilter,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        recent
            ? '近三天'
            : date == null
            ? '全部日期'
            : _dateLabel(date),
      ),
    );

    return PageFrame(
      title: team ? '下属日志' : '日志',
      showTitle: team,
      actions: [
        if (!team && user.manager)
          TextButton(
            onPressed: () => context.push('/logs/subordinates'),
            child: const Text('下属日志 ›', maxLines: 1, softWrap: false),
          ),
      ],
      fab: team || !canCreateForDate
          ? null
          : FloatingActionButton(
              heroTag: 'create-log',
              tooltip: '创建日志',
              onPressed: create,
              child: const Icon(Icons.add),
            ),
      child: PageBody(
        bottomPadding: team ? 24 : 88,
        children: [
          if (team) ...[
            const Text(
              '仅展示授权范围内已提交日志，不含草稿',
              style: TextStyle(color: CuteTokens.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('subordinate-log-search'),
              decoration: const InputDecoration(
                hintText: '搜索姓名或日志内容',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() {
                search = value.trim().toLowerCase();
                final filter = ref.read(subordinateLogFilterProvider);
                ref.read(subordinateLogFilterProvider.notifier).state = (
                  filter.$1,
                  search,
                );
              }),
            ),
            const SizedBox(height: 12),
            people!.when(
              loading: () => const SunnyLoadingIndicator(),
              error: (error, _) => RecordFailure(
                error,
                retry: () => ref.invalidate(recordsProvider('organization')),
              ),
              data: (page) {
                final departments = {
                  '全部部门',
                  ...page.items
                      .where((p) => p.id != user.id)
                      .map((p) => '${p.fields['departmentName'] ?? '未分组'}'),
                };
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: ValueKey('log-department:$department'),
                        onPressed: () async {
                          final selected = await showPremiumOptionPicker(
                            context,
                            title: '选择部门',
                            options: departments.toList(),
                            selected: department,
                          );
                          if (selected != null && mounted) {
                            setState(() {
                              department = selected;
                              final person = page.items
                                  .where(
                                    (p) =>
                                        p.fields['departmentName'] == selected,
                                  )
                                  .firstOrNull;
                              ref
                                  .read(subordinateLogFilterProvider.notifier)
                                  .state = (
                                selected == '全部部门'
                                    ? null
                                    : (person?.fields['department_id'] ??
                                              person?.fields['departmentId'])
                                          ?.toString(),
                                search,
                              );
                            });
                          }
                        },
                        icon: const Icon(Icons.apartment_outlined, size: 18),
                        label: Text(
                          department,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: dateFilter()),
                  ],
                );
              },
            ),
          ] else ...[
            dateFilter(),
            const SizedBox(height: 16),
            const Text(
              '今天，慢慢写也没关系',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (draft.hasError)
              RecordFailure(
                draft.error!,
                retry: () => ref.invalidate(todayDraftProvider(user.id)),
              ),
            if (draft.valueOrNull != null &&
                (date == null || DateUtils.isSameDay(date, _today)))
              TextButton.icon(
                onPressed: create,
                icon: const Icon(Icons.edit_note),
                label: const Text('继续本机草稿'),
              ),
          ],
          const SizedBox(height: 16),
          if (recent)
            _RecentDiarySections(
              today: _today,
              state: state,
              retry: () => ref.invalidate(recentDiaryRecordsProvider(_today)),
              onWrite: compose,
              row: (record) => _DiaryRow(
                record: record,
                onTap: () => LogEditWindow(record).canEditAt(_clock())
                    ? edit(record)
                    : openItem(context, resource, record.id),
                onDetails: () => openItem(context, resource, record.id),
              ),
            )
          else
            state.when(
              loading: () => const LoadingSkeleton(),
              error: (error, _) => RecordFailure(
                error,
                retry: () => ref.invalidate(logDayRecordsProvider),
              ),
              data: (page) {
                // The repository supplies authorized records; this is display filtering.
                if (team && (people!.isLoading || people.hasError)) {
                  return const SizedBox.shrink();
                }
                final authors = {
                  for (final p in people?.valueOrNull?.items ?? <Record>[])
                    p.id: p,
                };
                final items =
                    page.items.where((r) {
                      if (!team) return true;
                      if (r.ownerId == user.id || !isSubmittedDiary(r)) {
                        return false;
                      }
                      // Filtering belongs to the server: account matches need not
                      // appear in the displayed author name or diary body.
                      return true;
                    }).toList()..sort(
                      (a, b) => '${b.fields['businessDate']}'.compareTo(
                        '${a.fields['businessDate']}',
                      ),
                    );
                if (items.isEmpty) {
                  return const EmptyIllustration(
                    title: '暂无日志',
                    subtitle: '可以调整日期、部门或搜索条件',
                  );
                }
                final groups = <String, List<Record>>{};
                for (final r in items) {
                  final d = DateTime.tryParse('${r.fields['businessDate']}');
                  final group = team
                      ? '${r.fields['departmentName'] ?? authors[r.ownerId]?.fields['departmentName'] ?? '未分组'}'
                      : d == null
                      ? '未标记日期'
                      : '${d.year}年${d.month}月';
                  groups.putIfAbsent(group, () => []).add(r);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          group.key,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final r in group.value)
                        _DiaryRow(
                          record: r,
                          author: team
                              ? authors[r.ownerId] ??
                                    Record(
                                      id: r.ownerId,
                                      title: displayPersonName(
                                        r.fields['authorName'],
                                      ),
                                    )
                              : null,
                          onTap: () =>
                              !team && LogEditWindow(r).canEditAt(_clock())
                              ? edit(r)
                              : openItem(context, resource, r.id),
                          onDetails: !team
                              ? () => openItem(context, resource, r.id)
                              : null,
                          onMember: team
                              ? () => context.push(
                                  '/me/team/${encode(r.ownerId)}/logs${date == null ? '' : '?date=${date.toIso8601String().split('T').first}'}',
                                )
                              : null,
                        ),
                    ],
                  ],
                );
              },
            ),
          const DemoLabel(),
        ],
      ),
    );
  }
}

class _RecentDiarySections extends StatelessWidget {
  const _RecentDiarySections({
    required this.today,
    required this.state,
    required this.retry,
    required this.onWrite,
    required this.row,
  });

  final DateTime today;
  final AsyncValue<PageResult> state;
  final VoidCallback retry;
  final void Function(DateTime day) onWrite;
  final Widget Function(Record) row;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (offset, title) in [(2, '前天'), (1, '昨天'), (0, '今天')])
        _daySection(context, offset, title),
    ],
  );

  Widget _daySection(BuildContext context, int offset, String title) {
    final date = DateTime.utc(today.year, today.month, today.day - offset);
    final dateKey = date.toIso8601String().split('T').first;
    return Column(
      key: ValueKey('recent-diary-day:$dateKey'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 12),
              Text(_dateLabel(date)),
            ],
          ),
        ),
        state.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SunnyLoadingIndicator(),
          ),
          error: (error, _) => RecordFailure(error, retry: retry),
          data: (page) {
            final items = page.items.where(
              (record) => '${record.fields['businessDate']}' == dateKey,
            );
            return items.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$title暂无日志'),
                      TextButton.icon(
                        key: ValueKey('recent-diary-write:$dateKey'),
                        onPressed: () => onWrite(date),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('写这天的日志'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: items.map(row).toList(),
                  );
          },
        ),
      ],
    );
  }
}

class _DiaryRow extends StatelessWidget {
  const _DiaryRow({
    required this.record,
    required this.onTap,
    this.author,
    this.onMember,
    this.onDetails,
  });
  final Record record;
  final VoidCallback onTap;
  final Record? author;
  final VoidCallback? onMember;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${record.fields['businessDate']}');
    return InkWell(
      key: ValueKey('diary-row:${record.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${date?.day ?? '—'}',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    date == null
                        ? ''
                        : '周${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (author != null) ...[
                    Row(
                      children: [
                        ProtectedAvatar(
                          name: author!.title,
                          attachmentId:
                              author!.fields['avatarAttachmentId'] as String?,
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            author!.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    record.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${record.fields['status'] ?? '草稿'}',
                    style: const TextStyle(
                      color: Color(0xFF246447),
                      fontSize: 12,
                    ),
                  ),
                  if (onMember != null)
                    TextButton.icon(
                      onPressed: onMember,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: Text('查看 ${author!.title} 的日志'),
                    ),
                  const Divider(height: 24),
                ],
              ),
            ),
            if (onDetails != null)
              IconButton(
                tooltip: '查看日志详情',
                onPressed: onDetails,
                icon: const Icon(Icons.chevron_right),
              ),
          ],
        ),
      ),
    );
  }
}
