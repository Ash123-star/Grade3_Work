import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/task_display.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

class _TaskColumn {
  const _TaskColumn(
    this.label,
    this.width,
    this.value, {
    this.options,
    this.dateValue,
  });
  final String label;
  final double width;
  final String Function(Record record) value;
  final Iterable<String> Function(Record record)? options;
  final DateTime? Function(Record record)? dateValue;
}

final _taskColumns = <_TaskColumn>[
  _TaskColumn('任务名称', 188, (record) => record.title),
  _TaskColumn('标签', 112, (record) => taskTagLabel(record.fields)),
  _TaskColumn(
    '参与人',
    180,
    (record) => taskParticipantNames(record.fields).join('、'),
    options: (record) => taskParticipantNames(record.fields),
  ),
  _TaskColumn(
    '开始时间',
    128,
    (record) =>
        _taskDateText(record.fields['startAt'] ?? record.fields['start_at']),
    dateValue: (record) => businessEventTime(
      record.fields['startAt'] ?? record.fields['start_at'],
    ),
  ),
  _TaskColumn(
    '截止时间',
    128,
    (record) => _taskDateText(record.fields['deadline']),
    dateValue: (record) => businessEventTime(record.fields['deadline']),
  ),
  _TaskColumn(
    '派发时间',
    128,
    (record) => _taskDateText(
      record.fields['createdAt'] ?? record.fields['created_at'],
    ),
    dateValue: (record) => businessEventTime(
      record.fields['createdAt'] ?? record.fields['created_at'],
    ),
  ),
];

const _emptyFilterValue = '\u0000';

String _filterOptionLabel(String value) =>
    value == _emptyFilterValue ? '未设置' : value;

String _taskDateText(Object? value) {
  final date = businessEventTime(value);
  if (date == null) return '';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

Color _taskTagColor(Map<String, dynamic> fields) {
  final raw = fields['tagColor'] ?? fields['tag_color'];
  final text = '$raw'.trim();
  if (text.isNotEmpty && text != 'null') {
    final hex = text.replaceFirst('#', '').replaceFirst('0x', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) {
      return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
    }
  }
  return const Color(0xFFDDF1FA);
}

class TaskManagementPage extends ConsumerStatefulWidget {
  const TaskManagementPage({super.key});

  @override
  ConsumerState<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends ConsumerState<TaskManagementPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _horizontalController = ScrollController();
  final Map<String, Set<String>> _filters = {};
  final Map<String, DateTime> _dateFilters = {};

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  List<Record> _filtered(List<Record> records) {
    final search = _searchController.text.trim().toLowerCase();
    return records.where((record) {
      if (search.isNotEmpty &&
          !_taskColumns.any(
            (column) => column.value(record).toLowerCase().contains(search),
          )) {
        return false;
      }
      return _taskColumns.every((column) {
        final selectedDate = _dateFilters[column.label];
        if (selectedDate != null) {
          final value = column.dateValue?.call(record);
          if (value == null ||
              !_matchesDateFilter(column, value, selectedDate)) {
            return false;
          }
        }
        final filter = _filters[column.label];
        if (filter == null || filter.isEmpty) return true;
        final values = _columnValues(column, record);
        return values.any((value) => filter.contains(value));
      });
    }).toList();
  }

  static bool _matchesDateFilter(
    _TaskColumn column,
    DateTime value,
    DateTime selected,
  ) {
    final recordDate = DateUtils.dateOnly(value);
    final filterDate = DateUtils.dateOnly(selected);
    if (column.label == '开始时间') {
      return !recordDate.isBefore(filterDate);
    }
    if (column.label == '截止时间') {
      return !recordDate.isAfter(filterDate);
    }
    return DateUtils.isSameDay(recordDate, filterDate);
  }

  Future<void> _editFilter(_TaskColumn column, List<Record> records) async {
    if (column.dateValue != null) {
      final choice = await showTuantuanBottomSheet<_TaskDateFilterResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TaskDateFilterSheet(
          column: column,
          initialDate: _dateFilters[column.label],
        ),
      );
      if (choice == null || !mounted) return;
      setState(() {
        if (choice.clear) {
          _dateFilters.remove(column.label);
        } else if (choice.date != null) {
          _dateFilters[column.label] = choice.date!;
        }
      });
      return;
    }
    final options =
        records
            .expand((record) => _columnValues(column, record))
            .toSet()
            .toList()
          ..sort((a, b) {
            if (a == _emptyFilterValue) return -1;
            if (b == _emptyFilterValue) return 1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    final value = await showTuantuanBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskFilterSheet(
        column: column,
        options: options,
        initialValues: _filters[column.label] ?? const {},
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (value.isEmpty) {
        _filters.remove(column.label);
      } else {
        _filters[column.label] = value;
      }
    });
  }

  static Iterable<String> _columnValues(_TaskColumn column, Record record) {
    final values = (column.options?.call(record) ?? [column.value(record)])
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    return values.isEmpty ? const [_emptyFilterValue] : values;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordsProvider('tasks'));
    final colors = Theme.of(context).colorScheme;
    final tableWidth = _taskColumns.fold<double>(
      0,
      (sum, column) => sum + column.width,
    );
    return Scaffold(
      body: TuantuanPaperBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TaskIconAction(
                        tooltip: '返回',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => context.pop(),
                      ),
                    ),
                    Text(
                      '任务管理',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '搜索任务名称、标签、参与人或日期',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : _TaskIconAction(
                            tooltip: '清空搜索',
                            icon: Icons.close_rounded,
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: state.when(
                  loading: () => const LoadingSkeleton(),
                  error: (error, _) => RecordFailure(
                    error,
                    retry: () => ref.invalidate(recordsProvider('tasks')),
                  ),
                  data: (page) {
                    final rows = _filtered(page.items);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Material(
                        color: colors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: colors.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Scrollbar(
                            controller: _horizontalController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              key: const ValueKey(
                                'task-table-horizontal-scroll',
                              ),
                              controller: _horizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                height: constraints.maxHeight,
                                child: CustomScrollView(
                                  slivers: [
                                    SliverPersistentHeader(
                                      pinned: true,
                                      delegate: _TaskHeaderDelegate(
                                        height: 48,
                                        child: Row(
                                          children: [
                                            for (final column in _taskColumns)
                                              _TaskHeaderCell(
                                                column: column,
                                                selectedCount:
                                                    _filters[column.label]
                                                        ?.length ??
                                                    (_dateFilters.containsKey(
                                                          column.label,
                                                        )
                                                        ? 1
                                                        : 0),
                                                onTap: () => _editFilter(
                                                  column,
                                                  page.items,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (rows.isEmpty)
                                      SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: Center(
                                          child: Text(
                                            page.items.isEmpty
                                                ? '暂无任务记录'
                                                : '没有符合条件的任务',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      )
                                    else
                                      SliverList.builder(
                                        itemCount: rows.length,
                                        itemBuilder: (context, index) =>
                                            _TaskRow(
                                              record: rows[index],
                                              onTap: () => context.push(
                                                '/item/tasks/${rows[index].id}',
                                              ),
                                            ),
                                      ),
                                  ],
                                ),
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
        ),
      ),
    );
  }
}

class _TaskFilterSheet extends StatefulWidget {
  const _TaskFilterSheet({
    required this.column,
    required this.options,
    required this.initialValues,
  });
  final _TaskColumn column;
  final List<String> options;
  final Set<String> initialValues;

  @override
  State<_TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<_TaskFilterSheet> {
  late final TextEditingController _controller = TextEditingController();
  late final Set<String> _selected = {...widget.initialValues};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(Set<String> value) {
    FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final visible = widget.options
        .where(
          (option) => _filterOptionLabel(option).toLowerCase().contains(query),
        )
        .toList();
    final colors = Theme.of(context).colorScheme;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = math.min(
      560.0,
      math.max(180.0, (availableHeight - 24) * .84),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '筛选${widget.column.label}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索候选值',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的候选值',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: colors.outlineVariant.withValues(alpha: .55),
                      ),
                      itemBuilder: (context, index) {
                        final option = visible[index];
                        final selected = _selected.contains(option);
                        return InkWell(
                          key: ValueKey(
                            'task-filter-option:${_filterOptionLabel(option)}',
                          ),
                          onTap: () => setState(() {
                            if (selected) {
                              _selected.remove(option);
                            } else {
                              _selected.add(option);
                            }
                          }),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: selected
                                        ? colors.primary
                                        : colors.outline,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _filterOptionLabel(option),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TaskFilterAction(
                    label: '取消',
                    onPressed: () {
                      FocusScope.of(
                        context,
                      ).unfocus(disposition: UnfocusDisposition.scope);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TaskFilterAction(
                    key: const ValueKey('task-filter-apply'),
                    label: _selected.isEmpty ? '应用' : '应用（${_selected.length}）',
                    emphasized: true,
                    onPressed: () => _close({..._selected}),
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

class _TaskDateFilterResult {
  const _TaskDateFilterResult({this.date, this.clear = false});

  final DateTime? date;
  final bool clear;
}

class _TaskDateFilterSheet extends StatefulWidget {
  const _TaskDateFilterSheet({required this.column, this.initialDate});

  final _TaskColumn column;
  final DateTime? initialDate;

  @override
  State<_TaskDateFilterSheet> createState() => _TaskDateFilterSheetState();
}

class _TaskDateFilterSheetState extends State<_TaskDateFilterSheet> {
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
  }

  Future<void> _selectDate() async {
    final value = await showPremiumDatePicker(
      context,
      initial: _selected ?? DateTime.now(),
      title: '选择${widget.column.label}日期',
    );
    if (value != null && mounted) setState(() => _selected = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '筛选${widget.column.label}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Material(
            color: colors.surfaceContainerHighest.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: const ValueKey('task-date-filter-picker'),
              borderRadius: BorderRadius.circular(12),
              onTap: _selectDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selected == null
                            ? '选择日期'
                            : '${_selected!.year}年${_selected!.month}月${_selected!.day}日',
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TaskFilterAction(
                  label: '清除此筛选',
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _TaskDateFilterResult(clear: true)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TaskFilterAction(
                  key: const ValueKey('task-date-filter-apply'),
                  label: '应用',
                  emphasized: true,
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(_TaskDateFilterResult(date: _selected)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskFilterAction extends StatelessWidget {
  const _TaskFilterAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: emphasized ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: emphasized
                      ? colors.onPrimaryContainer
                      : colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskIconAction extends StatelessWidget {
  const _TaskIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TaskHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(_TaskHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}

class _TaskHeaderCell extends StatelessWidget {
  const _TaskHeaderCell({
    required this.column,
    required this.selectedCount,
    required this.onTap,
  });
  final _TaskColumn column;
  final int selectedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: column.width,
    height: 48,
    child: Material(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .42),
      child: InkWell(
        key: ValueKey('task-filter-header:${column.label}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selectedCount > 0
                        ? SunnyPalette.primaryStrong
                        : SunnyPalette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selectedCount > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: SunnyPalette.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$selectedCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: SunnyPalette.primaryStrong,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: SunnyPalette.muted,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.record, required this.onTap});
  final Record record;
  final VoidCallback onTap;

  Future<void> _showValue(BuildContext context, int index, String value) async {
    await showTuantuanBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _taskColumns[index].label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            SelectableText(value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            for (var index = 0; index < _taskColumns.length; index++)
              SizedBox(
                width: _taskColumns[index].width,
                child: index == 0
                    ? InkWell(
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 14,
                            top: 8,
                            bottom: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _valueText(context, index)),
                              SizedBox(
                                width: 40,
                                child: Center(
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: () => _showValue(
                          context,
                          index,
                          _taskColumns[index].value(record),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: _valueText(context, index),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _valueText(BuildContext context, int index) {
    final value = _taskColumns[index].value(record);
    if (index == 1) {
      return AppLabelBadge(
        value.isEmpty ? '—' : value,
        color: _taskTagColor(record.fields),
        compact: true,
      );
    }
    return Text(
      value.isEmpty ? '—' : value,
      maxLines: index == 0 ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: SunnyPalette.ink,
        fontWeight: index == 0 ? FontWeight.w600 : FontWeight.w400,
        height: 1.35,
      ),
    );
  }
}
