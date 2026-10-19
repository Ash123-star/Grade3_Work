import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

bool isReceivedTask(Record item, String id) {
  final ids = (item.fields['participantIds'] as List?)?.map(
    (value) => '$value',
  );
  return (ids?.contains(id) ?? (item.ownerId == id)) &&
      '${item.fields['dispatcherId'] ?? ''}' != id;
}

/// Dashboard company-task records have no management toolbar.
class ReceivedTasksPage extends ConsumerWidget {
  const ReceivedTasksPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final state = ref.watch(recordsProvider('tasks'));
    return PageFrame(
      title: '公司任务',
      child: PageBody(
        children: [
          state.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(recordsProvider('tasks')),
            ),
            data: (page) {
              final rows = page.items
                  .where((r) => isReceivedTask(r, user.id))
                  .toList();
              if (rows.isEmpty) return const EmptyIllustration(title: '暂无接收任务');
              return Column(
                children: [
                  for (final item in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TaskRecordCard(
                        item: item,
                        compact: false,
                        received: true,
                        onTap: () => openItem(context, 'tasks', item.id),
                      ),
                    ),
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

/// A mobile record workspace for tasks received from leaders and tasks
/// published to participants. The page intentionally keeps the dashboard
/// summary separate from the full management view.
class TaskManagementPage extends ConsumerStatefulWidget {
  const TaskManagementPage({super.key});

  @override
  ConsumerState<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends ConsumerState<TaskManagementPage> {
  final searchController = TextEditingController();
  int segment = 0;
  bool compact = false;
  String tag = '全部标签';
  String participant = '全部参与人';
  DateTime? deadline;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  bool _isParticipant(Record item, String id) {
    final ids = (item.fields['participantIds'] as List?)
        ?.map((value) => '$value')
        .toSet();
    return ids?.contains(id) == true;
  }

  bool _isPublished(Record item, String id) =>
      '${item.fields['dispatcherId'] ?? ''}' == id;

  bool _isReceived(Record item, String id) =>
      (_isParticipant(item, id) ||
          (item.fields['participantIds'] == null && item.ownerId == id)) &&
      !_isPublished(item, id);

  List<Record> _filtered(PageResult page, Session user) {
    final query = searchController.text.trim().toLowerCase();
    return page.items.where((item) {
      final received = _isReceived(item, user.id);
      final published = _isPublished(item, user.id);
      if (segment == 1 && !received || segment == 2 && !published) {
        return false;
      }
      final fields = item.fields;
      final haystack = [
        item.title,
        '${fields['body'] ?? ''}',
        '${fields['tagName'] ?? ''}',
        '${fields['participantNames'] ?? ''}',
      ].join(' ').toLowerCase();
      if (query.isNotEmpty && !haystack.contains(query)) return false;
      if (tag != '全部标签' && '${fields['tagName'] ?? ''}' != tag) {
        return false;
      }
      if (participant != '全部参与人') {
        final names = (fields['participantNames'] as List?)
            ?.map((value) => '$value')
            .toSet();
        if (names?.contains(participant) != true) return false;
      }
      final due = DateTime.tryParse('${fields['deadline'] ?? ''}')?.toLocal();
      if (deadline != null &&
          (due == null ||
              due.year != deadline!.year ||
              due.month != deadline!.month ||
              due.day != deadline!.day)) {
        return false;
      }
      return segment == 0 || received || published;
    }).toList();
  }

  Future<void> _showFilters(List<Record> rows) async {
    final tags = <String>{
      '全部标签',
      ...rows.map((r) => '${r.fields['tagName'] ?? ''}'),
    }..remove('');
    final participants = <String>{'全部参与人'};
    for (final row in rows) {
      participants.addAll(
        (row.fields['participantNames'] as List?)?.map((value) => '$value') ??
            const <String>[],
      );
    }
    var nextTag = tag;
    var nextParticipant = participant;
    var nextDeadline = deadline;
    final tagColors = {
      for (final row in rows)
        '${row.fields['tagName'] ?? ''}': _tagColor(row.fields['tagColor']),
    };
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('筛选任务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _FilterChoice(
                label: '标签',
                value: nextTag,
                color: tagColors[nextTag],
                onTap: () async {
                  final value = await showPremiumTagPicker(
                    context,
                    options: [
                      for (final value in tags)
                        PremiumTagOption(
                          value,
                          value,
                          value == '全部标签'
                              ? const Color(0xFFE9EEF5)
                              : tagColors[value] ?? const Color(0xFFDDF1FA),
                        ),
                    ],
                    selected: nextTag,
                  );
                  if (value != null) setSheetState(() => nextTag = value);
                },
              ),
              _FilterChoice(
                label: '参与人',
                value: nextParticipant,
                onTap: () async {
                  final value = await showPremiumOptionPicker(
                    context,
                    title: '选择参与人',
                    options: participants.toList(),
                    selected: nextParticipant,
                  );
                  if (value != null) {
                    setSheetState(() => nextParticipant = value);
                  }
                },
              ),
              _FilterChoice(
                label: '截止日期',
                value: nextDeadline == null ? '不限' : _dayLabel(nextDeadline!),
                onTap: () async {
                  final value = await showPremiumDatePicker(
                    context,
                    initial: nextDeadline ?? DateTime.now(),
                    title: '选择截止日期',
                  );
                  if (value != null) setSheetState(() => nextDeadline = value);
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setSheetState(() => nextDeadline = null),
                  icon: const Icon(Icons.clear),
                  label: const Text('清除截止日期'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          tag = '全部标签';
                          participant = '全部参与人';
                          deadline = null;
                        });
                        Navigator.pop(sheetContext, true);
                      },
                      child: const Text('清空筛选'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          tag = nextTag;
                          participant = nextParticipant;
                          deadline = nextDeadline;
                        });
                        Navigator.pop(sheetContext, true);
                      },
                      child: const Text('应用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
  }

  static Color _tagColor(Object? raw) {
    final value = '$raw';
    final hex = value.replaceFirst('#', '').replaceFirst('0x', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return const Color(0xFFDDF1FA);
    return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  static String _dayLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final state = ref.watch(recordsProvider('tasks'));
    return PageFrame(
      title: '任务管理',
      fab: user.dispatch
          ? FloatingActionButton(
              heroTag: 'task-management-add',
              tooltip: '新增任务',
              onPressed: () => openForm(context, 'dispatch'),
              child: const Icon(Icons.add),
            )
          : null,
      child: PageBody(
        children: [
          Text('任务管理', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            user.manager ? '本人及下属的全部任务' : '本人的全部任务',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索标题、内容或参与人',
              prefixIcon: Icon(Icons.search),
              suffixIcon: Icon(Icons.tune_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('全部任务')),
              ButtonSegment(value: 1, label: Text('我接收的')),
              ButtonSegment(value: 2, label: Text('我发布的')),
            ],
            selected: {segment},
            onSelectionChanged: (value) =>
                setState(() => segment = value.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () =>
                      state.whenData((page) => _showFilters(page.items)),
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: Text(
                    tag == '全部标签' && participant == '全部参与人' && deadline == null
                        ? '筛选字段'
                        : '已应用筛选',
                  ),
                ),
              ),
              IconButton(
                tooltip: compact ? '字段卡片视图' : '紧凑列表视图',
                onPressed: () => setState(() => compact = !compact),
                icon: Icon(
                  compact
                      ? Icons.view_agenda_outlined
                      : Icons.table_rows_outlined,
                ),
              ),
            ],
          ),
          state.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(recordsProvider('tasks')),
            ),
            data: (page) {
              final rows = _filtered(page, user);
              if (rows.isEmpty) {
                return const EmptyIllustration(
                  title: '暂无任务记录',
                  subtitle: '调整筛选条件或创建一条新任务',
                );
              }
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '共 ${rows.length} 条记录 · ${user.manager ? '本人及授权下属' : '本人'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TaskRecordCard(
                        item: item,
                        compact: compact,
                        received: _isReceived(item, user.id),
                        onTap: () => context.push('/item/tasks/${item.id}'),
                      ),
                    ),
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

class _TaskRecordCard extends StatelessWidget {
  const _TaskRecordCard({
    required this.item,
    required this.compact,
    required this.received,
    required this.onTap,
  });

  final Record item;
  final bool compact;
  final bool received;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = item.fields;
    final tagColor =
        _colorFromHex('${f['tagColor'] ?? ''}') ?? SunnyPalette.blue;
    final participants = (f['participantNames'] as List?)
        ?.map((value) => '$value')
        .join('、');
    final deadline = businessEventTime(f['deadline']);
    return PaperSurface(
      skin: TuantuanAssets.surfaces[received ? 'blue' : 'warm'],
      cornerDecoration: TuantuanAssets.cardCorners[received ? 'blue' : 'warm'],
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(
        16,
        compact ? 12 : 16,
        12,
        compact ? 12 : 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: compact ? 48 : 72,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    AppLabelBadge(
                      '${f['tagName'] ?? '未分类'}',
                      color: tagColor,
                      compact: true,
                    ),
                    AppLabelBadge(
                      '${f['status'] ?? '状态未提供'}',
                      color: SunnyPalette.mint,
                      compact: true,
                    ),
                    AppLabelBadge(
                      received
                          ? '我接收'
                          : '${f['dispatcherId'] ?? ''}' == ''
                          ? '任务记录'
                          : '发布记录',
                      color: SunnyPalette.purple,
                      compact: true,
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    '开始 ${_taskDate(f['startAt'])} · 截止 ${deadline == null ? '未设置' : '${deadline.month}月${deadline.day}日 ${_taskTime(deadline)}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (participants != null && participants.isNotEmpty)
                    Text(
                      '参与人 $participants',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.value,
    required this.onTap,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color:
                      color ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

String _taskDate(dynamic value) {
  final date = businessEventTime(value);
  return date == null ? '未设置' : '${date.month}月${date.day}日 ${_taskTime(date)}';
}

String _taskTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Color? _colorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  final number = int.tryParse('FF$normalized', radix: 16);
  return number == null ? null : Color(number);
}
