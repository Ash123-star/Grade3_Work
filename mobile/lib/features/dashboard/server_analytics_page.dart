import 'dart:typed_data';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

typedef CsvSaver = Future<String?> Function(String name, Uint8List bytes);
final csvSaverProvider = Provider<CsvSaver>(
  (ref) =>
      (name, bytes) => FilePicker.platform.saveFile(
        dialogTitle: '保存统计报表',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      ),
);

class ServerAnalyticsPage extends ConsumerWidget {
  const ServerAnalyticsPage({super.key});

  Future<void> _showPoint(
    BuildContext context,
    String title,
    List<String> lines, {
    VoidCallback? onDetails,
  }) async {
    await showTuantuanBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => TuantuanSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line),
                  ),
                if (onDetails != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: onDetails,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          '查看同范围明细',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAnalyticsDetails(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String metric,
    String? groupId,
    String? bucket,
  }) {
    final accountId = ref.read(sessionProvider).id;
    final filters = ref.read(analyticsFiltersProvider(accountId));
    final query = AnalyticsDetailsQuery(
      date: ref.read(selectedDateProvider),
      period: switch (ref.read(periodProvider)) {
        '日' => 'day',
        '周' => 'week',
        _ => 'month',
      },
      groupBy: filters.groupBy,
      departmentId: filters.departmentId.isEmpty ? null : filters.departmentId,
      teamId: filters.teamId.isEmpty ? null : filters.teamId,
      ownerId: filters.ownerId.isEmpty ? null : filters.ownerId,
      metric: metric,
      groupId: groupId,
      bucket: bucket,
    );
    return showTuantuanBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AnalyticsDetailsSheet(title: title, query: query),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (!user.manager) {
      return const PageFrame(
        title: '工作统计',
        child: EmptyIllustration(showCharacter: false, title: '暂无查看权限'),
      );
    }
    final tree = ref.watch(organizationTreeProvider).valueOrNull;
    final filters = ref.watch(analyticsFiltersProvider(user.id));
    final people = (tree?.fields['people'] as List? ?? []).whereType<Record>();
    final availableDepartments = <String, String>{};
    for (final person in people) {
      final id = '${person.fields['department_id'] ?? ''}';
      if (id.isNotEmpty) {
        availableDepartments[id] =
            '${person.fields['departmentName'] ?? person.fields['部门'] ?? id}';
      }
    }
    final availableTeams = <String, String>{};
    for (final person in people) {
      if (filters.departmentId.isNotEmpty &&
          '${person.fields['department_id'] ?? ''}' != filters.departmentId) {
        continue;
      }
      final id = '${person.fields['team_id'] ?? ''}';
      if (id.isNotEmpty) {
        availableTeams[id] =
            '${person.fields['teamName'] ?? person.fields['team_name'] ?? id}';
      }
    }
    final availableOwners = people.where((person) {
      return (filters.departmentId.isEmpty ||
              '${person.fields['department_id'] ?? ''}' ==
                  filters.departmentId) &&
          (filters.teamId.isEmpty ||
              '${person.fields['team_id'] ?? ''}' == filters.teamId);
    }).toList();
    final result = ref.watch(analyticsSummaryProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final seriesColors = [
      colorScheme.primary,
      colorScheme.tertiary,
      colorScheme.secondary,
      colorScheme.error,
      colorScheme.onSurfaceVariant,
      colorScheme.outline,
    ];
    const metricLabels = {
      'dispatched': '派发',
      'received': '接收',
      'feedback': '反馈',
      'accepted': '验收',
      'overdue': '逾期',
      'diarySubmitted': '日志提交',
    };
    List<Color> colorsFor(Iterable<String> metrics) => [
      for (final metric in metrics)
        seriesColors[metricLabels.keys.toList().indexOf(metric)],
    ];

    Widget filterField(
      String label,
      String value,
      List<(String, String)> options,
      ValueChanged<String?> changed,
    ) => SizedBox(
      width: 168,
      child: PremiumDropdownField<String>(
        key: ValueKey('$label:$value:${options.length}'),
        initialValue: options.any((option) => option.$1 == value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: '', child: Text('全部')),
          for (final option in options)
            DropdownMenuItem(value: option.$1, child: Text(option.$2)),
        ],
        onChanged: changed,
      ),
    );

    return PageFrame(
      title: '工作统计',
      child: PageBody(
        children: [
          const DateControls(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              filterField(
                '部门',
                filters.departmentId,
                availableDepartments.entries
                    .map((entry) => (entry.key, entry.value))
                    .toList(),
                (value) =>
                    ref
                        .read(analyticsFiltersProvider(user.id).notifier)
                        .state = filters.copyWith(
                      departmentId: value ?? '',
                      teamId: '',
                      ownerId: '',
                    ),
              ),
              filterField(
                '团队',
                filters.teamId,
                availableTeams.entries
                    .map((entry) => (entry.key, entry.value))
                    .toList(),
                (value) =>
                    ref.read(analyticsFiltersProvider(user.id).notifier).state =
                        filters.copyWith(teamId: value ?? '', ownerId: ''),
              ),
              filterField(
                '员工',
                filters.ownerId,
                availableOwners
                    .map((person) => (person.id, person.title))
                    .toList(),
                (value) =>
                    ref.read(analyticsFiltersProvider(user.id).notifier).state =
                        filters.copyWith(ownerId: value ?? ''),
              ),
              SizedBox(
                width: 168,
                child: PremiumDropdownField<String>(
                  key: ValueKey('分组:${filters.groupBy}'),
                  initialValue: filters.groupBy,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '图表分组',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'department', child: Text('按部门')),
                    DropdownMenuItem(value: 'team', child: Text('按团队')),
                    DropdownMenuItem(value: 'person', child: Text('按员工')),
                  ],
                  onChanged: (value) =>
                      ref
                          .read(analyticsFiltersProvider(user.id).notifier)
                          .state = filters.copyWith(
                        groupBy: value ?? 'department',
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          result.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(analyticsSummaryProvider),
            ),
            data: (record) {
              final fields = record.fields;
              final range = fields['range'] is Map
                  ? Map<String, dynamic>.from(fields['range'] as Map)
                  : const <String, dynamic>{};
              final rows =
                  (fields['groupedComparison'] as List? ??
                          fields['departmentComparison'] as List? ??
                          [])
                      .whereType<Map>()
                      .map((row) => Map<String, dynamic>.from(row))
                      .toList();
              final phaseRows = (fields['taskPhaseDistribution'] as List? ?? [])
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList();
              final trend =
                  (fields['trend'] as List? ??
                          fields['dailyTrend'] as List? ??
                          [])
                      .whereType<Map>()
                      .map((row) => Map<String, dynamic>.from(row))
                      .toList();
              final onTime = fields['onTimeAcceptance'] is Map
                  ? Map<String, dynamic>.from(fields['onTimeAcceptance'] as Map)
                  : const <String, dynamic>{};
              final diaryRate = fields['dailySubmission'] is Map
                  ? Map<String, dynamic>.from(fields['dailySubmission'] as Map)
                  : const <String, dynamic>{};
              String rate(Map<String, dynamic> value) {
                final denominator = value['denominator'];
                final ratio = value['rate'];
                if (denominator is! num || denominator == 0 || ratio is! num) {
                  return '暂无';
                }
                return '${(ratio * 100).toStringAsFixed(1)}%';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader('工作总览'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Metric(
                        title: '派发任务',
                        value: '${fields['dispatched'] ?? '暂无'}',
                        explain: '数量：${fields['dispatched'] ?? '未返回'} 项',
                      ),
                      _Metric(
                        title: '逾期任务',
                        value: '${fields['overdue'] ?? '暂无'}',
                        explain: '数量：${fields['overdue'] ?? '未返回'} 项',
                      ),
                      _Metric(
                        title: '按期验收率',
                        value: rate(onTime),
                        explain:
                            '按期 ${onTime['numerator'] ?? '未返回'} / 已验收 ${onTime['denominator'] ?? '未返回'}',
                      ),
                      _Metric(
                        title: '日报提交率',
                        value: rate(diaryRate),
                        explain: diaryRate['denominatorKnown'] == false
                            ? '入职或历史在职资料不完整，暂无法计算提交率'
                            : '提交 ${diaryRate['numerator'] ?? '未返回'} / 应提交 ${diaryRate['denominator'] ?? '未返回'}',
                      ),
                    ],
                  ),
                  const SectionHeader('综合对比'),
                  _ChartLegend(
                    labels: metricLabels,
                    colors: seriesColors,
                    active: filters.visibleMetrics.toSet(),
                    onToggle: (metric) {
                      final next = filters.visibleMetrics.toSet();
                      if (!next.add(metric)) next.remove(metric);
                      if (next.isEmpty) next.add(metric);
                      ref
                          .read(analyticsFiltersProvider(user.id).notifier)
                          .state = filters.copyWith(
                        visibleMetrics: next.toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Text('所选范围暂无可展示数据')
                  else
                    _GroupedBars(
                      rows: rows,
                      metricKeys: filters.visibleMetrics,
                      colors: colorsFor(filters.visibleMetrics),
                      metricLabels: metricLabels,
                      onSelect: (row, metric, value) => _showPoint(
                        context,
                        '${row['groupName'] ?? row['departmentName'] ?? '统计范围'} · ${metricLabels[metric] ?? metric}',
                        [
                          '数量：$value 项',
                          '业务区间：${range['first'] ?? '未返回'} 至 ${range['end'] ?? '未返回'}',
                        ],
                        onDetails: () => _showAnalyticsDetails(
                          context,
                          ref,
                          title:
                              '${row['groupName'] ?? '统计范围'} · ${metricLabels[metric] ?? metric}',
                          metric: metric,
                          groupId: '${row['groupId'] ?? ''}'.isEmpty
                              ? null
                              : '${row['groupId']}',
                        ),
                      ),
                    ),
                  const SectionHeader('工作趋势'),
                  _ChartLegend(
                    labels: metricLabels,
                    colors: seriesColors,
                    active: filters.visibleMetrics.toSet(),
                    onToggle: (metric) {
                      final next = filters.visibleMetrics.toSet();
                      if (!next.add(metric)) next.remove(metric);
                      if (next.isEmpty) next.add(metric);
                      ref
                          .read(analyticsFiltersProvider(user.id).notifier)
                          .state = filters.copyWith(
                        visibleMetrics: next.toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  if (trend.isEmpty)
                    const Text('所选范围暂无趋势数据')
                  else
                    SizedBox(
                      height: 190,
                      child: _TrendChart(
                        points: trend,
                        metricKeys: filters.visibleMetrics,
                        colors: colorsFor(filters.visibleMetrics),
                        onSelect: (point, metric) => _showPoint(
                          context,
                          '${point['date'] ?? '所选日期'} · ${metricLabels[metric] ?? metric}',
                          [
                            '${metricLabels[metric] ?? metric}：${point[metric] ?? '暂无'}',
                            if (metric == 'diarySubmitted')
                              '应提交：${point['diaryDenominator'] ?? '未返回'}',
                          ],
                          onDetails: () => _showAnalyticsDetails(
                            context,
                            ref,
                            title:
                                '${point['date'] ?? '所选日期'} · ${metricLabels[metric] ?? metric}',
                            metric: metric,
                            bucket: '${point['date'] ?? ''}',
                          ),
                        ),
                      ),
                    ),
                  if (trend.isNotEmpty)
                    SizedBox(
                      height: 86,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final point in trend)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Semantics(
                                  button: true,
                                  label:
                                      '${point['date'] ?? '日期'}，${filters.visibleMetrics.map((metric) => '${metricLabels[metric] ?? metric} ${point[metric] ?? '未返回'}').join('，')}',
                                  child: InkWell(
                                    onTap: () => _showPoint(
                                      context,
                                      '${point['date'] ?? '所选日期'} 工作数据',
                                      [
                                        for (final metric
                                            in filters.visibleMetrics)
                                          '${metricLabels[metric] ?? metric}：${point[metric] ?? '未返回'}',
                                        if (point['diaryDenominator'] != null)
                                          '日报应提交人数：${point['diaryDenominator']}',
                                      ],
                                      onDetails: () => _showAnalyticsDetails(
                                        context,
                                        ref,
                                        title:
                                            '${point['date'] ?? '所选日期'} 工作数据',
                                        metric: filters.visibleMetrics.first,
                                        bucket: '${point['date'] ?? ''}',
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 132,
                                      height: 72,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${point['date'] ?? '日期'}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: Text(
                                              filters.visibleMetrics
                                                  .map(
                                                    (metric) =>
                                                        '${metricLabels[metric] ?? metric} ${point[metric] ?? '—'}',
                                                  )
                                                  .join(' · '),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SectionHeader('任务阶段分布'),
                  if (phaseRows.isEmpty)
                    const Text('所选范围暂无任务阶段数据')
                  else
                    _PhaseDonut(
                      rows: phaseRows,
                      colors: seriesColors,
                      onSelect: (row) {
                        final total = phaseRows.fold<int>(
                          0,
                          (sum, item) =>
                              sum + ((item['count'] as num?)?.toInt() ?? 0),
                        );
                        final count = (row['count'] as num?)?.toInt() ?? 0;
                        _showPoint(
                          context,
                          '${row['phase'] ?? '任务阶段'}',
                          [
                            '数量：$count 项',
                            '占比：${total == 0 ? '暂无' : '${(count * 100 / total).toStringAsFixed(1)}%'}',
                          ],
                          onDetails: () => _showAnalyticsDetails(
                            context,
                            ref,
                            title: '${row['phase'] ?? '任务阶段'}',
                            metric: 'phase:${row['phase']}',
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 14),
                  Text('更新时间：${fields['updatedAt'] ?? '未返回'}'),
                  if (range.isNotEmpty)
                    Text('业务区间：${range['first']} 至 ${range['end']}（结束日不含）'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnalyticsDetailsSheet extends ConsumerStatefulWidget {
  const _AnalyticsDetailsSheet({required this.title, required this.query});
  final String title;
  final AnalyticsDetailsQuery query;

  @override
  ConsumerState<_AnalyticsDetailsSheet> createState() =>
      _AnalyticsDetailsSheetState();
}

class _AnalyticsDetailsSheetState
    extends ConsumerState<_AnalyticsDetailsSheet> {
  final items = <Record>[];
  String? cursor, error;
  var total = 0, loading = false;

  Future<void> load({bool next = false}) async {
    if (loading) return;
    final accountId = ref.read(sessionProvider).id;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await ref
          .read(repositoryProvider)
          .analyticsDetails(
            AnalyticsDetailsQuery(
              date: widget.query.date,
              period: widget.query.period,
              groupBy: widget.query.groupBy,
              departmentId: widget.query.departmentId,
              teamId: widget.query.teamId,
              ownerId: widget.query.ownerId,
              metric: widget.query.metric,
              groupId: widget.query.groupId,
              bucket: widget.query.bucket,
              cursor: next ? cursor : null,
              limit: widget.query.limit,
            ),
          );
      if (!mounted ||
          ref.read(sessionProvider).id != accountId ||
          !ref.read(sessionProvider).canReadBusiness) {
        return;
      }
      setState(() {
        if (!next) items.clear();
        items.addAll(page.items);
        total = page.total;
        cursor = page.nextCursor;
      });
    } catch (exception) {
      if (mounted && ref.read(sessionProvider).id == accountId) {
        setState(() => error = '$exception');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.canReadBusiness || !session.manager) {
      return const SafeArea(child: Center(child: Text('无权查看统计明细')));
    }
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .68,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('$total 条记录', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (loading && items.isEmpty)
                const Expanded(child: Center(child: LoadingSkeleton()))
              else if (error != null && items.isEmpty)
                Expanded(
                  child: Center(
                    child: RecordFailure(
                      error ?? '统计明细读取失败',
                      retry: () => load(),
                    ),
                  ),
                )
              else if (items.isEmpty)
                const Expanded(child: Center(child: Text('所选范围暂无明细')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length + (cursor == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return InkWell(
                          onTap: loading ? null : () => load(next: true),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                loading ? '正在加载' : '加载更多',
                                style: TextStyle(color: scheme.primary),
                              ),
                            ),
                          ),
                        );
                      }
                      final item = items[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            if (item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                item.subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
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

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.labels,
    required this.colors,
    required this.active,
    required this.onToggle,
  });
  final Map<String, String> labels;
  final List<Color> colors;
  final Set<String> active;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (var i = 0; i < labels.length; i++)
        InkWell(
          onTap: () => onToggle(labels.keys.elementAt(i)),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors[i].withValues(
                      alpha: active.contains(labels.keys.elementAt(i))
                          ? 1
                          : .25,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  labels.values.elementAt(i),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: active.contains(labels.keys.elementAt(i))
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _GroupedBars extends StatelessWidget {
  const _GroupedBars({
    required this.rows,
    required this.colors,
    required this.metricKeys,
    required this.metricLabels,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> rows;
  final List<Color> colors;
  final List<String> metricKeys;
  final Map<String, String> metricLabels;
  final void Function(Map<String, dynamic>, String, int) onSelect;

  @override
  Widget build(BuildContext context) {
    final keys = metricKeys;
    final maximum = rows.fold<int>(0, (maxValue, row) {
      for (final key in keys) {
        final value = (row[key] as num?)?.toInt();
        if (value == null) continue;
        if (value > maxValue) maxValue = value;
      }
      return maxValue;
    });
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${row['groupName'] ?? row['departmentName'] ?? row['teamName'] ?? row['ownerName'] ?? '统计范围'}',
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < keys.length; i++)
                  InkWell(
                    onTap: row[keys[i]] is num
                        ? () => onSelect(
                            row,
                            keys[i],
                            (row[keys[i]] as num).toInt(),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(
                              metricLabels[keys[i]] ?? keys[i],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final count = (row[keys[i]] as num?)?.toInt();
                                if (count == null) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '未返回',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  );
                                }
                                final fraction = maximum == 0
                                    ? 0.0
                                    : count / maximum;
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 8,
                                    child: ColoredBox(
                                      color: scheme.surfaceContainerHighest,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ColoredBox(
                                          color: colors[i],
                                          child: SizedBox(
                                            width:
                                                constraints.maxWidth * fraction,
                                            height: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${row[keys[i]] ?? '—'}',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.points,
    required this.colors,
    required this.metricKeys,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> points;
  final List<Color> colors;
  final List<String> metricKeys;
  final void Function(Map<String, dynamic>, String) onSelect;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '工作趋势折线图，${points.length}个日期数据点',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (event) {
        if (points.isEmpty || metricKeys.isEmpty) return;
        final width = context.size?.width ?? 1;
        final index = (event.localPosition.dx / width * points.length)
            .floor()
            .clamp(0, points.length - 1);
        final height = context.size?.height ?? 1;
        final maximum = points.fold<double>(1, (maxValue, point) {
          for (final key in metricKeys) {
            final value = (point[key] as num?)?.toDouble();
            if (value == null) continue;
            if (value > maxValue) maxValue = value;
          }
          return maxValue;
        });
        var selected = metricKeys.first;
        var distance = double.infinity;
        for (final key in metricKeys) {
          final value = (points[index][key] as num?)?.toDouble();
          if (value == null) continue;
          final y = height - 12 - (height - 24) * value / maximum;
          final candidate = (event.localPosition.dy - y).abs();
          if (candidate < distance) {
            distance = candidate;
            selected = key;
          }
        }
        onSelect(points[index], selected);
      },
      child: CustomPaint(
        painter: _TrendPainter(
          points: points,
          colors: colors,
          metricKeys: metricKeys,
          grid: Theme.of(context).colorScheme.outlineVariant,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.colors,
    required this.metricKeys,
    required this.grid,
  });
  final List<Map<String, dynamic>> points;
  final List<Color> colors;
  final List<String> metricKeys;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0;
    final rect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
    if (points.isEmpty) return;
    final maximum = points.fold<double>(1, (maxValue, point) {
      for (final key in metricKeys) {
        final value = (point[key] as num?)?.toDouble();
        if (value == null) continue;
        if (value > maxValue) maxValue = value;
      }
      return maxValue;
    });
    for (var s = 0; s < metricKeys.length; s++) {
      final path = Path();
      var connected = false;
      for (var i = 0; i < points.length; i++) {
        final value = (points[i][metricKeys[s]] as num?)?.toDouble();
        if (value == null) {
          connected = false;
          continue;
        }
        final x = points.length == 1
            ? rect.center.dx
            : rect.left + rect.width * i / (points.length - 1);
        final y = rect.bottom - rect.height * value / maximum;
        if (!connected) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        connected = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[s]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.colors != colors ||
      oldDelegate.metricKeys != metricKeys ||
      oldDelegate.grid != grid;
}

class _PhaseDonut extends StatelessWidget {
  const _PhaseDonut({
    required this.rows,
    required this.colors,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> rows;
  final List<Color> colors;
  final ValueChanged<Map<String, dynamic>> onSelect;

  int _hitTest(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = position - center;
    if (delta.distance > math.min(size.width, size.height) / 2 ||
        delta.distance < size.width * .18) {
      return -1;
    }
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['count'] as num?)?.toDouble() ?? 0),
    );
    if (total <= 0) return -1;
    var cursor = 0.0;
    for (var i = 0; i < rows.length; i++) {
      cursor +=
          ((rows[i]['count'] as num?)?.toDouble() ?? 0) / total * math.pi * 2;
      if (angle <= cursor) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<int>(
      0,
      (sum, row) => sum + ((row['count'] as num?)?.toInt() ?? 0),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 164,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onTapDown: (event) {
                final index = _hitTest(
                  event.localPosition,
                  constraints.biggest,
                );
                if (index >= 0) onSelect(rows[index]);
              },
              child: Semantics(
                label: '任务阶段环形图，共$total项',
                child: CustomPaint(
                  painter: _DonutPainter(
                    rows: rows,
                    colors: colors,
                    empty: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++)
                InkWell(
                  onTap: () => onSelect(rows[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          color: colors[i % colors.length],
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${rows[i]['phase'] ?? '其他'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('${rows[i]['count'] ?? 0}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.rows,
    required this.colors,
    required this.empty,
  });
  final List<Map<String, dynamic>> rows;
  final List<Color> colors;
  final Color empty;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['count'] as num?)?.toDouble() ?? 0),
    );
    if (total <= 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = empty
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < rows.length; i++) {
      final count = (rows[i]['count'] as num?)?.toDouble() ?? 0;
      final sweep = count / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.colors != colors ||
      oldDelegate.empty != empty;
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.explain,
  });
  final String title, value, explain;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width.clamp(0, 760) - 44) / 2,
    child: PaperSurface(
      skin: TuantuanAssets.metric,
      onTap: () => showTuantuanBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => TuantuanSheet(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(explain),
                ],
              ),
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class AnalyticsExportPage extends ConsumerStatefulWidget {
  const AnalyticsExportPage({super.key});
  @override
  ConsumerState<AnalyticsExportPage> createState() =>
      _AnalyticsExportPageState();
}

class _AnalyticsExportPageState extends ConsumerState<AnalyticsExportPage> {
  String resource = 'logs';
  bool busy = false;
  String? result;
  Future<void> export() async {
    final account = ref.read(sessionProvider).id;
    final date = ref
        .read(selectedDateProvider)
        .toIso8601String()
        .split('T')
        .first;
    final period = switch (ref.read(periodProvider)) {
      '日' => 'day',
      '周' => 'week',
      _ => 'month',
    };
    final filters = ref.read(analyticsFiltersProvider(account));
    final saver = ref.read(csvSaverProvider);
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final record = await ref
          .read(repositoryProvider)
          .execute(
            'analytics/export',
            Command('export', {
              'date': date,
              'period': period,
              'resource': resource,
              'groupBy': filters.groupBy,
              if (filters.departmentId.isNotEmpty)
                'departmentId': filters.departmentId,
              if (filters.teamId.isNotEmpty) 'teamId': filters.teamId,
              if (filters.ownerId.isNotEmpty) 'ownerId': filters.ownerId,
            }),
          );
      if (!mounted ||
          ref.read(sessionProvider).id != account ||
          !ref.read(sessionProvider).canReadBusiness) {
        return;
      }
      final raw = record.fields['bytes'];
      if (raw is! List<int>) throw StateError('服务器未返回CSV文件内容');
      final path = await saver(
        '$resource-$date-$period.csv',
        Uint8List.fromList(raw),
      );
      if (mounted && ref.read(sessionProvider).id == account) {
        setState(() => result = path == null ? '已取消保存，文件未写入' : '报表已保存：$path');
      }
    } catch (error) {
      if (mounted && ref.read(sessionProvider).id == account) {
        setState(() => result = '导出未完成：$error');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(sessionProvider).manager) {
      return const PageFrame(
        title: '统计导出',
        child: EmptyIllustration(showCharacter: false, title: '无权访问'),
      );
    }
    return PageFrame(
      title: '统计导出',
      bottom: BottomActions(
        primary: SunnyPrimaryButton.icon(
          loading: busy,
          onPressed: busy ? null : export,
          icon: const Icon(Icons.download_outlined),
          label: const Text('导出并保存CSV'),
        ),
      ),
      child: PageBody(
        children: [
          const DateControls(),
          const Text('导出沿用工作统计的日期、周期及组织筛选范围。'),
          const SizedBox(height: 20),
          PremiumDropdownField<String>(
            initialValue: resource,
            decoration: const InputDecoration(labelText: '导出内容'),
            items: const [
              DropdownMenuItem(value: 'logs', child: Text('工作日志')),
              DropdownMenuItem(value: 'tasks', child: Text('工作任务')),
            ],
            onChanged: busy ? null : (v) => setState(() => resource = v!),
          ),
          const SizedBox(height: 20),
          const Text('选择系统保存位置后才算导出完成。取消保存不会创建文件。'),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(result!),
            ),
        ],
      ),
    );
  }
}
