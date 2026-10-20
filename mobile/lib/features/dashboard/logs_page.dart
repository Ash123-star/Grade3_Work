import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart' show CuteTokens;
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

String _dateLabel(DateTime date) => '${date.month}月${date.day}日';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key, this.subordinates = false});
  final bool subordinates;
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String search = '';
  String department = '全部部门';

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
    final date = ref.watch(logFilterDateProvider);
    final resource = team ? 'logs/subordinates' : 'logs';
    final state = ref.watch(
      logDayRecordsProvider((resource, team ? null : user.id)),
    );
    final people = team ? ref.watch(recordsProvider('organization')) : null;
    final draft = ref.watch(todayDraftProvider(user.id));

    void edit(Record? record) {
      ref.read(logDateProvider.notifier).state = record == null
          ? date ?? DateTime.now()
          : DateTime.tryParse('${record.fields['businessDate']}') ??
                DateTime.now();
      openForm(
        context,
        record == null || !isSubmittedDiary(record) ? 'log-edit' : 'log-revise',
        id: record?.id,
        version: record?.version,
      );
    }

    void create() {
      ref.read(logDateProvider.notifier).state = date ?? DateTime.now();
      openForm(context, 'log-edit');
    }

    void restoreDraft() {
      ref.read(logDateProvider.notifier).state = date ?? DateTime.now();
      openForm(context, 'log-edit', restoreDiaryDraft: true);
    }

    Future<void> chooseDateFilter() async {
      final selectedDate = date;
      final choice = await showPremiumOptionPicker(
        context,
        title: '日志日期',
        options: [
          '全部日期',
          if (selectedDate != null) _dateLabel(selectedDate),
          '选择日期…',
        ],
        selected: selectedDate == null ? '全部日期' : _dateLabel(selectedDate),
      );
      if (!context.mounted || choice == null) return;
      if (choice == '全部日期') {
        ref.read(logFilterDateProvider.notifier).state = null;
      } else if (choice == '选择日期…') {
        final next = await showPremiumDatePicker(
          context,
          initial: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
        );
        if (!context.mounted || next == null) return;
        ref.read(logFilterDateProvider.notifier).state = next;
      }
      setState(() {});
    }

    Widget dateFilter() => OutlinedButton.icon(
      key: ValueKey('log-date:${date?.toIso8601String() ?? 'all'}'),
      onPressed: chooseDateFilter,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(date == null ? '全部日期' : _dateLabel(date)),
    );

    return PageFrame(
      title: team ? '下属日志' : '日志',
      showTitle: team,
      actions: [
        if (!team && user.manager)
          TextButton(
            onPressed: () => context.push('/logs/subordinates'),
            child: const Text('下属日志 ›'),
          ),
      ],
      fab: team
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
              onChanged: (value) =>
                  setState(() => search = value.trim().toLowerCase()),
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
                            setState(() => department = selected);
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
            if (draft.valueOrNull != null)
              TextButton.icon(
                onPressed: restoreDraft,
                icon: const Icon(Icons.edit_note),
                label: const Text('继续本机草稿'),
              ),
          ],
          const SizedBox(height: 16),
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
                    final author = authors[r.ownerId];
                    final group =
                        '${author?.fields['departmentName'] ?? '未分组'}';
                    if (department != '全部部门' && department != group) {
                      return false;
                    }
                    return '${author?.title ?? r.fields['authorName'] ?? r.ownerId} ${r.title} ${r.fields['今日工作'] ?? r.fields['body'] ?? ''}'
                        .toLowerCase()
                        .contains(search);
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
                    ? '${authors[r.ownerId]?.fields['departmentName'] ?? '未分组'}'
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
                                    title:
                                        '${r.fields['authorName'] ?? r.ownerId}',
                                  )
                            : null,
                        onTap: () =>
                            !team && LogEditWindow(r).canEditAt(DateTime.now())
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
