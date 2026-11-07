import 'dart:typed_data';
import 'dart:math' as math;

import 'package:pandora_mobile/core/config.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/theme/sunshine_palette.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ServerAnalyticsPage extends ConsumerStatefulWidget {
  const ServerAnalyticsPage({super.key});
  @override
  ConsumerState<ServerAnalyticsPage> createState() =>
      _ServerAnalyticsPageState();
}

const _statMetrics = {
  'overdue': '逾期任务',
  'accepted': '验收任务',
  'dispatched': '派发任务',
  'diarySubmitted': '提交日报',
  'received': '接收任务',
  'feedback': '反馈任务',
};
const _statGroups = {'department': '部门', 'team': '团队', 'person': '员工'};
const _phaseColors = [
  Color(0xFFE8B436),
  Color(0xFFF6D65A),
  Color(0xFFEAA179),
  Color(0xFF8BAFA0),
  Color(0xFFA7A9C8),
  Color(0xFFC5B59C),
  Color(0xFFCD8B7A),
];
List<Map<String, dynamic>> _statRows(dynamic value) =>
    (value is List ? value : [])
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
Map<String, dynamic> _statMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

class _ServerAnalyticsPageState extends ConsumerState<ServerAnalyticsPage> {
  String metric = 'overdue', view = 'phase';
  Future<void> details(
    String title,
    String metric, {
    String? groupId,
    String? bucket,
  }) {
    final filters = ref.read(
      analyticsFiltersProvider(ref.read(sessionProvider).id),
    );
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
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AnalyticsDetailsSheet(title: title, query: query),
    );
  }

  Future<void> pickMetric() async {
    final next = await _statPick(context, '比较指标', metric, _statMetrics);
    if (next != null && mounted) setState(() => metric = next);
  }

  Future<void> filters() async {
    final user = ref.read(sessionProvider);
    final next = await showTuantuanBottomSheet<AnalyticsFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _StatisticsFilterSheet(
        initial: ref.read(analyticsFiltersProvider(user.id)),
      ),
    );
    if (next != null && mounted && ref.read(sessionProvider).id == user.id)
      ref.read(analyticsFiltersProvider(user.id).notifier).state = next;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (!user.manager || !user.canReadBusiness)
      return const PageFrame(
        title: '工作统计',
        child: EmptyIllustration(showCharacter: false, title: '暂无查看权限'),
      );
    final filter = ref.watch(analyticsFiltersProvider(user.id));
    return PageFrame(
      title: '工作统计',
      actions: [
        PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (v) {
            if (v == 'refresh') ref.invalidate(analyticsSummaryProvider);
            if (v == 'export') context.push('/export');
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'refresh', child: Text('刷新统计')),
            PopupMenuItem(value: 'export', child: Text('导出当前范围')),
          ],
        ),
      ],
      child: PageBody(
        children: [
          _StatisticsDateControls(
            onFilters: filters,
            filtered:
                filter.departmentId.isNotEmpty ||
                filter.teamId.isNotEmpty ||
                filter.ownerId.isNotEmpty,
          ),
          const SizedBox(height: 12),
          ref
              .watch(analyticsSummaryProvider)
              .when(
                loading: () => const LoadingSkeleton(),
                error: (e, _) => RecordFailure(
                  e,
                  retry: () => ref.invalidate(analyticsSummaryProvider),
                ),
                data: (record) {
                  final f = record.fields,
                      onTime = _statMap(record.fields['onTimeAcceptance']),
                      diary = _statMap(record.fields['dailySubmission']);
                  final phases = _statRows(f['taskPhaseDistribution']);
                  const order = [
                    '待接收',
                    '进行中',
                    '需补充',
                    '待验收',
                    '已验收',
                    '已归档',
                    '已撤回',
                  ];
                  phases.sort(
                    (a, b) => order
                        .indexOf('${a['phase']}')
                        .compareTo(order.indexOf('${b['phase']}')),
                  );
                  final groups = _statRows(
                    f['groupedComparison'] ?? f['departmentComparison'],
                  );
                  groups.sort(
                    (a, b) => ((b[metric] as num?) ?? -1).compareTo(
                      (a[metric] as num?) ?? -1,
                    ),
                  );
                  final trend = _statRows(f['trend'] ?? f['dailyTrend']);
                  final unit = metric == 'diarySubmitted' ? '篇' : '项';
                  void groupDetails(Map<String, dynamic> row) {
                    if (row['groupId'] != null)
                      details(
                        '${row['groupName'] ?? '分组'} · ${_statMetrics[metric]}',
                        metric,
                        groupId: '${row['groupId']}',
                      );
                  }

                  final cards = [
                    _StatisticsMetric(
                      title: '派发任务',
                      value: _statCount(f['dispatched']),
                      asset: 'task',
                      onTap: () => details('派发任务', 'dispatched'),
                    ),
                    _StatisticsMetric(
                      title: '逾期任务',
                      value: _statCount(f['overdue']),
                      asset: 'notification',
                      onTap: () => details('逾期任务', 'overdue'),
                    ),
                    _StatisticsMetric(
                      title: '按期验收率',
                      value: _statRate(onTime),
                      asset: 'success',
                      onTap: () => details('区间内验收任务', 'accepted'),
                    ),
                    _StatisticsMetric(
                      title: '日报提交率',
                      value: _statRate(diary),
                      asset: 'log',
                      onTap: () => details('已提交日报', 'diarySubmitted'),
                    ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _statRange(_statMap(f['range'])),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, c) {
                          final cols =
                              c.maxWidth < 290 ||
                                  MediaQuery.textScalerOf(context).scale(13) >
                                      20
                              ? 1
                              : 2;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final card in cards)
                                SizedBox(
                                  width: (c.maxWidth - 8 * (cols - 1)) / cols,
                                  child: card,
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      PaperSurface(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'phase',
                                  label: Text('任务进展'),
                                ),
                                ButtonSegment(
                                  value: 'compare',
                                  label: Text('分组比较'),
                                ),
                                ButtonSegment(
                                  value: 'trend',
                                  label: Text('每日趋势'),
                                ),
                              ],
                              selected: {view},
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                textStyle: WidgetStatePropertyAll(
                                  TextStyle(fontSize: 12),
                                ),
                              ),
                              onSelectionChanged: (v) =>
                                  setState(() => view = v.first),
                            ),
                            const SizedBox(height: 12),
                            if (view == 'phase')
                              _StatisticsPhases(
                                rows: phases,
                                onDetails: (row) => details(
                                  '${row['phase']}',
                                  'phase:${row['phaseCode'] ?? row['phase']}',
                                ),
                              ),
                            if (view != 'phase')
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: pickMetric,
                                    child: Text('${_statMetrics[metric]} ▾'),
                                  ),
                                  if (view == 'compare')
                                    TextButton(
                                      onPressed: () async {
                                        final next = await _statPick(
                                          context,
                                          '分组方式',
                                          filter.groupBy,
                                          _statGroups,
                                        );
                                        if (next != null && mounted)
                                          ref
                                              .read(
                                                analyticsFiltersProvider(
                                                  user.id,
                                                ).notifier,
                                              )
                                              .state = filter.copyWith(
                                            groupBy: next,
                                          );
                                      },
                                      child: Text(
                                        '${_statGroups[filter.groupBy] ?? '分组'} ▾',
                                      ),
                                    ),
                                ],
                              ),
                            if (view == 'compare') ...[
                              if (groups.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('所选范围暂无比较数据'),
                                ),
                              for (final row in groups.take(4))
                                _StatisticsBar(
                                  name:
                                      '${row['groupName'] ?? row['departmentName'] ?? '名称暂不可用'}',
                                  value: row[metric] as num?,
                                  maximum: groups.fold<num>(
                                    0,
                                    (m, r) =>
                                        math.max(m, (r[metric] as num?) ?? 0),
                                  ),
                                  unit: unit,
                                  onTap: row['groupId'] == null
                                      ? null
                                      : () => groupDetails(row),
                                ),
                              if (groups.length > 4)
                                TextButton(
                                  onPressed: () =>
                                      showTuantuanBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        showDragHandle: true,
                                        builder: (_) => _StatisticsGroupsSheet(
                                          rows: groups,
                                          metric: metric,
                                          unit: unit,
                                          onDetails: groupDetails,
                                        ),
                                      ),
                                  child: Text('搜索 / 查看全部 ${groups.length} 组 ›'),
                                ),
                            ],
                            if (view == 'trend')
                              _StatisticsTrend(
                                key: ValueKey(
                                  '$metric:${_statRange(_statMap(f['range']))}',
                                ),
                                rows: trend,
                                metric: metric,
                                unit: unit,
                                onDetails: (row) => details(
                                  '${row['date']} · ${_statMetrics[metric]}',
                                  metric,
                                  bucket: '${row['date']}',
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${AppConfig.mock ? '演示数据 · ' : ''}${_statUpdated(f['updatedAt'])} 更新',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => showTuantuanBottomSheet<void>(
                              context: context,
                              useSafeArea: true,
                              showDragHandle: true,
                              builder: (_) => Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  24,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '统计口径',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(_statRange(_statMap(f['range']))),
                                      const SizedBox(height: 12),
                                      Text(
                                        '按期验收：${_statCount(onTime['numerator'])} / 验收 ${_statCount(onTime['denominator'])}\n日报提交：${_statCount(diary['numerator'])} / 应提交 ${diary['denominatorKnown'] == false ? '暂无' : _statCount(diary['denominator'])}',
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        '任务进展仅统计本期派发的任务。逾期按区间内截止日期计数，包含延期验收；不同事件指标不能解释为同一批任务的转化率。',
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${f['definition'] ?? '分组按当前负责人归属。比例分母为零或资料不足时显示暂无。'}',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            child: const Text(
                              '统计口径 ⓘ',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _StatisticsDateControls extends ConsumerWidget {
  const _StatisticsDateControls({
    required this.onFilters,
    required this.filtered,
  });
  final VoidCallback onFilters;
  final bool filtered;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(periodProvider),
        date = ref.watch(selectedDateProvider);
    final label = period == '月'
        ? '${date.year}年${date.month}月'
        : '${date.month}月${date.day}日${period == '周' ? '所在周' : ''}';
    return Column(
      children: [
        Center(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '日', label: Text('日')),
              ButtonSegment(value: '周', label: Text('周')),
              ButtonSegment(value: '月', label: Text('月')),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (v) =>
                ref.read(periodProvider.notifier).state = v.first,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2007),
                    lastDate: DateTime(2100, 12, 31),
                    helpText: '选择统计日期',
                    initialEntryMode: DatePickerEntryMode.calendarOnly,
                  );
                  if (picked != null && context.mounted)
                    ref.read(selectedDateProvider.notifier).state = picked;
                },
                label: Text(
                  '$label ▾',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: onFilters,
              icon: const Icon(Icons.filter_list_rounded, size: 18),
              label: Text(
                filtered ? '筛选 · 已选' : '筛选',
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatisticsMetric extends StatelessWidget {
  const _StatisticsMetric({
    required this.title,
    required this.value,
    required this.asset,
    required this.onTap,
  });
  final String title, value, asset;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PaperSurface(
    padding: const EdgeInsets.all(12),
    onTap: onTap,
    child: Row(
      children: [
        Image.asset(
          TuantuanAssets.icons[asset]!,
          width: 26,
          height: 26,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({
    required this.name,
    required this.value,
    required this.maximum,
    required this.unit,
    this.onTap,
  });
  final String name, unit;
  final num? value;
  final num maximum;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value == null || maximum <= 0
                    ? 0
                    : (value! / maximum).clamp(0, 1).toDouble(),
                minHeight: 9,
                backgroundColor: SunshinePalette.line,
                color: const Color(0xFFE8B436),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_statCount(value)} $unit',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
}

class _StatisticsPhases extends StatelessWidget {
  const _StatisticsPhases({required this.rows, required this.onDetails});
  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onDetails;
  @override
  Widget build(BuildContext context) {
    final total = rows.fold<num>(0, (v, r) => v + ((r['count'] as num?) ?? 0));
    if (total <= 0)
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('所选范围暂无派发任务', textAlign: TextAlign.center),
      );
    final ring = SizedBox(
      width: 130,
      height: 130,
      child: CustomPaint(
        painter: _StatisticsRingPainter(rows),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text('本期派发', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _phaseColors[i % _phaseColors.length],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${rows[i]['phase'] ?? '阶段未知'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  _statCount(rows[i]['count']),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) =>
              c.maxWidth < 270 ||
                  MediaQuery.textScalerOf(context).scale(12) > 18
              ? Column(children: [ring, const SizedBox(height: 16), legend])
              : Row(
                  children: [
                    ring,
                    const SizedBox(width: 20),
                    Expanded(child: legend),
                  ],
                ),
        ),
        TextButton(
          onPressed: () => showTuantuanBottomSheet<void>(
            context: context,
            useSafeArea: true,
            showDragHandle: true,
            builder: (sheet) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final row in rows)
                      ListTile(
                        title: Text('${row['phase'] ?? '阶段未知'}'),
                        trailing: Text('${_statCount(row['count'])} 项 ›'),
                        onTap: () {
                          Navigator.pop(sheet);
                          onDetails(row);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('按阶段查看明细 ›'),
        ),
      ],
    );
  }
}

class _StatisticsRingPainter extends CustomPainter {
  _StatisticsRingPainter(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    final total = rows.fold<double>(
      0,
      (v, r) => v + ((r['count'] as num?)?.toDouble() ?? 0),
    );
    if (total <= 0) return;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - 18,
      height: size.height - 18,
    );
    var start = -math.pi / 2;
    for (var i = 0; i < rows.length; i++) {
      final sweep =
          ((rows[i]['count'] as num?)?.toDouble() ?? 0) / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = _phaseColors[i % _phaseColors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StatisticsRingPainter old) => true;
}

class _StatisticsTrend extends StatefulWidget {
  const _StatisticsTrend({
    super.key,
    required this.rows,
    required this.metric,
    required this.unit,
    required this.onDetails,
  });
  final List<Map<String, dynamic>> rows;
  final String metric, unit;
  final ValueChanged<Map<String, dynamic>> onDetails;
  @override
  State<_StatisticsTrend> createState() => _StatisticsTrendState();
}

class _StatisticsTrendState extends State<_StatisticsTrend> {
  int selected = 0;
  @override
  void initState() {
    super.initState();
    final today = holidayLikeDate(DateTime.now());
    final i = widget.rows.indexWhere((r) => r['date'] == today);
    selected = i < 0 ? 0 : i;
  }

  String holidayLikeDate(DateTime d) {
    final local = shanghaiWallTime(d.toUtc());
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty)
      return const Padding(padding: EdgeInsets.all(32), child: Text('暂无每日数据'));
    final index = selected.clamp(0, rows.length - 1), row = rows[index];
    final max = rows.fold<num>(
      0,
      (m, r) => math.max(m, (r[widget.metric] as num?) ?? 0),
    );
    String label(Map<String, dynamic> r) => '${r['date'] ?? ''}'
        .replaceFirst(RegExp(r'^\d{4}-'), '')
        .replaceAll('-', '/');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '每日${_statMetrics[widget.metric]} · 峰值 $max ${widget.unit}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 138,
          child: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => setState(
                () => selected = (e.localPosition.dx / c.maxWidth * rows.length)
                    .floor()
                    .clamp(0, rows.length - 1),
              ),
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: Size(c.maxWidth, 138),
                  painter: _StatisticsTrendPainter(rows, widget.metric, index),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label(rows.first), style: const TextStyle(fontSize: 11)),
            Text(
              label(rows[rows.length ~/ 2]),
              style: const TextStyle(fontSize: 11),
            ),
            Text(label(rows.last), style: const TextStyle(fontSize: 11)),
          ],
        ),
        if (rows.length > 1)
          Slider(
            value: index.toDouble(),
            min: 0,
            max: (rows.length - 1).toDouble(),
            divisions: rows.length - 1,
            label: label(row),
            semanticFormatterCallback: (v) {
              final r = rows[v.round()];
              return '${r['date']}，${_statCount(r[widget.metric])}${widget.unit}';
            },
            onChanged: (v) => setState(() => selected = v.round()),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('${row['date']}'),
          trailing: Text(
            '${_statCount(row[widget.metric])} ${widget.unit} ›',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: row['date'] == null ? null : () => widget.onDetails(row),
        ),
      ],
    );
  }
}

class _StatisticsTrendPainter extends CustomPainter {
  _StatisticsTrendPainter(this.rows, this.metric, this.selected);
  final List<Map<String, dynamic>> rows;
  final String metric;
  final int selected;
  @override
  void paint(Canvas canvas, Size size) {
    final max = math
        .max(
          1,
          rows.fold<num>(0, (m, r) => math.max(m, (r[metric] as num?) ?? 0)),
        )
        .toDouble();
    final p = Paint()
      ..color = SunshinePalette.line
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final slot = size.width / rows.length;
    for (var i = 0; i < rows.length; i++) {
      final v = (rows[i][metric] as num?)?.toDouble();
      if (v == null) continue;
      final h = v <= 0 ? 2.0 : v / max * (size.height - 8);
      final width = math.min(30.0, slot * .7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * slot + (slot - width) / 2,
            size.height - h,
            width,
            h,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = i == selected
              ? const Color(0xFF8C6819)
              : const Color(0xFFE8B436),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StatisticsTrendPainter old) => true;
}

Future<String?> _statPick(
  BuildContext context,
  String title,
  String current,
  Map<String, String> options,
) => showTuantuanBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      _StatisticsChoiceSheet(title: title, current: current, options: options),
);

class _StatisticsChoiceSheet extends StatefulWidget {
  const _StatisticsChoiceSheet({
    required this.title,
    required this.current,
    required this.options,
  });
  final String title, current;
  final Map<String, String> options;
  @override
  State<_StatisticsChoiceSheet> createState() => _StatisticsChoiceSheetState();
}

class _StatisticsChoiceSheetState extends State<_StatisticsChoiceSheet> {
  String query = '';
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final rows = widget.options.entries
        .where((r) => r.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final pages = math.max(1, (rows.length / 6).ceil());
    final index = page.clamp(0, pages - 1);
    return _StatisticsSheetFrame(
      title: widget.title,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: '输入名称搜索',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() {
            query = v;
            page = 0;
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('没有匹配结果'))
              : ListView(
                  children: [
                    for (final row in rows.skip(index * 6).take(6))
                      ListTile(
                        title: Text(row.value),
                        selected: row.key == widget.current,
                        trailing: row.key == widget.current
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, row.key),
                      ),
                  ],
                ),
        ),
        _StatisticsPager(
          index: index,
          pages: pages,
          onPage: (p) => setState(() => page = p),
        ),
      ],
    );
  }
}

class _StatisticsGroupsSheet extends StatefulWidget {
  const _StatisticsGroupsSheet({
    required this.rows,
    required this.metric,
    required this.unit,
    required this.onDetails,
  });
  final List<Map<String, dynamic>> rows;
  final String metric, unit;
  final ValueChanged<Map<String, dynamic>> onDetails;
  @override
  State<_StatisticsGroupsSheet> createState() => _StatisticsGroupsSheetState();
}

class _StatisticsGroupsSheetState extends State<_StatisticsGroupsSheet> {
  String query = '';
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows
        .where(
          (r) =>
              '${r['groupName'] ?? r['departmentName'] ?? ''}'.contains(query),
        )
        .toList();
    final pages = math.max(1, (rows.length / 6).ceil());
    final index = page.clamp(0, pages - 1);
    final max = widget.rows.fold<num>(
      0,
      (m, r) => math.max(m, (r[widget.metric] as num?) ?? 0),
    );
    return _StatisticsSheetFrame(
      title: '${_statMetrics[widget.metric]} · 全部分组',
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索姓名或分组',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() {
            query = v;
            page = 0;
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('没有匹配结果'))
              : ListView(
                  children: [
                    for (final row in rows.skip(index * 6).take(6))
                      _StatisticsBar(
                        name:
                            '${row['groupName'] ?? row['departmentName'] ?? '名称暂不可用'}',
                        value: row[widget.metric] as num?,
                        maximum: max,
                        unit: widget.unit,
                        onTap: row['groupId'] == null
                            ? null
                            : () {
                                Navigator.pop(context);
                                widget.onDetails(row);
                              },
                      ),
                  ],
                ),
        ),
        _StatisticsPager(
          index: index,
          pages: pages,
          onPage: (p) => setState(() => page = p),
        ),
      ],
    );
  }
}

class _StatisticsPager extends StatelessWidget {
  const _StatisticsPager({
    required this.index,
    required this.pages,
    required this.onPage,
  });
  final int index, pages;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '上一页',
        onPressed: index > 0 ? () => onPage(index - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Text('${index + 1} / $pages 页'),
      IconButton(
        tooltip: '下一页',
        onPressed: index + 1 < pages ? () => onPage(index + 1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _StatisticsSheetFrame extends StatelessWidget {
  const _StatisticsSheetFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: math.min(
        MediaQuery.sizeOf(context).height * .72,
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            MediaQuery.paddingOf(context).top -
            50,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _StatisticsFilterSheet extends ConsumerStatefulWidget {
  const _StatisticsFilterSheet({required this.initial});
  final AnalyticsFilters initial;
  @override
  ConsumerState<_StatisticsFilterSheet> createState() =>
      _StatisticsFilterSheetState();
}

class _StatisticsFilterSheetState
    extends ConsumerState<_StatisticsFilterSheet> {
  late AnalyticsFilters draft = widget.initial;
  @override
  Widget build(BuildContext context) {
    final org = ref.watch(organizationTreeProvider);
    final tree = org.valueOrNull;
    final people = (tree?.fields['people'] as List? ?? [])
        .whereType<Record>()
        .toList();
    String department(Record p) =>
        '${p.fields['department_id'] ?? p.fields['departmentId'] ?? ''}';
    String team(Record p) =>
        '${p.fields['team_id'] ?? p.fields['teamId'] ?? ''}';
    final departments = <String, String>{};
    final teams = <String, String>{};
    for (final p in people) {
      final d = department(p), t = team(p);
      if (d.isNotEmpty)
        departments[d] =
            '${p.fields['departmentName'] ?? p.fields['部门'] ?? '部门名称暂不可用'}';
      if (t.isNotEmpty &&
          (draft.departmentId.isEmpty || draft.departmentId == d)) {
        final data = (tree?.fields['teams'] as List? ?? [])
            .whereType<Map>()
            .where((v) => v['id'] == t)
            .firstOrNull;
        teams[t] =
            '${data?['name'] ?? p.fields['teamName'] ?? p.fields['team_name'] ?? '团队名称暂不可用'}';
      }
    }
    final owners = {
      for (final p in people.where(
        (p) =>
            (draft.departmentId.isEmpty ||
                department(p) == draft.departmentId) &&
            (draft.teamId.isEmpty || team(p) == draft.teamId),
      ))
        p.id: p.title,
    };
    Widget selector(
      String title,
      String selected,
      Map<String, String> options,
      ValueChanged<String> change,
    ) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(
        selected.isEmpty ? '全部' : options[selected] ?? '已选范围（名称暂不可用）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: tree == null
          ? null
          : () async {
              final value = await _statPick(context, title, selected, {
                '': '全部',
                ...options,
              });
              if (value != null && mounted) setState(() => change(value));
            },
    );
    return _StatisticsSheetFrame(
      title: '筛选统计范围',
      children: [
        if (org.isLoading) const LinearProgressIndicator(),
        if (org.hasError)
          TextButton(
            onPressed: () => ref.invalidate(organizationTreeProvider),
            child: const Text('加载失败，点击重试'),
          ),
        Expanded(
          child: ListView(
            children: [
              selector(
                '部门',
                draft.departmentId,
                departments,
                (v) => draft = draft.copyWith(
                  departmentId: v,
                  teamId: '',
                  ownerId: '',
                ),
              ),
              selector(
                '团队',
                draft.teamId,
                teams,
                (v) => draft = draft.copyWith(teamId: v, ownerId: ''),
              ),
              selector(
                '员工',
                draft.ownerId,
                owners,
                (v) => draft = draft.copyWith(ownerId: v),
              ),
            ],
          ),
        ),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(
                () => draft = draft.copyWith(
                  departmentId: '',
                  teamId: '',
                  ownerId: '',
                ),
              ),
              child: const Text('重置'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft),
              child: const Text('应用筛选'),
            ),
          ],
        ),
      ],
    );
  }
}

String _statCount(dynamic value) => value is num ? value.toString() : '—';
String _statRate(Map<String, dynamic> value) {
  if (value['denominatorKnown'] == false ||
      value['denominator'] is! num ||
      value['denominator'] <= 0 ||
      value['rate'] is! num)
    return '暂无';
  return '${((value['rate'] as num) * 100).toStringAsFixed(1)}%';
}

String _statRange(Map<String, dynamic> range) {
  final first = DateTime.tryParse('${range['first']}');
  final end = DateTime.tryParse('${range['end']}');
  if (first == null || end == null) return '统计区间暂不可用';
  final last = end.subtract(const Duration(days: 1));
  return '${first.year}.${first.month}.${first.day} — ${last.year}.${last.month}.${last.day}';
}

String _statUpdated(dynamic value) {
  final instant = DateTime.tryParse('$value');
  if (instant == null) return '暂不可用';
  final date = shanghaiWallTime(instant);
  return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
                                loading
                                    ? '正在加载'
                                    : error != null
                                    ? '加载失败，点击重试'
                                    : '加载更多',
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
