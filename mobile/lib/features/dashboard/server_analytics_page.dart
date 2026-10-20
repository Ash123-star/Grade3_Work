import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/features/dashboard/management_page.dart';

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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sessionProvider).manager) {
      return const PageFrame(
        title: '工作统计',
        child: EmptyIllustration(showCharacter: false, title: '暂无查看权限'),
      );
    }
    final tree = ref.watch(organizationTreeProvider).valueOrNull;
    return PageFrame(
      title: '工作统计',
      actions: [
        IconButton(
          tooltip: '导出报表',
          onPressed: () => context.push('/export'),
          icon: const Icon(Icons.download_outlined),
        ),
      ],
      child: PageBody(
        children: [
          const DateControls(),
          const Text('范围：当前服务端授权范围。汇总按该范围计算，不支持部门或人员二次筛选。'),
          const SizedBox(height: 20),
          ref
              .watch(analyticsSummaryProvider)
              .when(
                loading: () => const LoadingSkeleton(),
                error: (error, _) => RecordFailure(
                  error,
                  retry: () => ref.invalidate(analyticsSummaryProvider),
                ),
                data: (record) {
                  final f = record.fields;
                  final rateMetrics = [
                    ('按期验收率', f['onTimeAcceptance']),
                    ('日报提交率', f['dailySubmission']),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('工作概览'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final metric in [
                            ('派发任务', f['dispatched']),
                            ('逾期任务', f['overdue']),
                          ])
                            _Metric(
                              title: metric.$1,
                              value: '${metric.$2 ?? '未返回'}',
                              explain: metric.$1 == '派发任务'
                                  ? '所选区间创建的授权任务'
                                  : '所选区间到期且未按期验收的授权任务',
                            ),
                          for (final (title, raw) in rateMetrics)
                            Builder(
                              builder: (context) {
                                final m = raw is Map
                                    ? raw
                                    : <String, dynamic>{};
                                final denominator =
                                    (m['denominator'] as num?) ?? 0;
                                return _Metric(
                                  title: title,
                                  value: denominator == 0
                                      ? '暂无'
                                      : '${(((m['rate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
                                  explain:
                                      '分子 ${m['numerator'] ?? '未返回'} / 分母 ${m['denominator'] ?? '未返回'}\n${m['definition'] ?? '口径未返回'}',
                                );
                              },
                            ),
                        ],
                      ),
                      const SectionHeader('部门分布 · 派发任务'),
                      if ((f['departmentDistribution'] as List? ?? []).isEmpty)
                        const Text('所选区间没有部门分布记录'),
                      for (final row
                          in (f['departmentDistribution'] as List? ?? [])
                              .whereType<Map>())
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            organizationName(
                              tree,
                              'departments',
                              row['department_id'],
                            ),
                          ),
                          trailing: Text('${row['dispatched']} 项'),
                        ),
                      const SectionHeader('统计口径'),
                      Text('未读日志：${f['unreadLogs'] ?? '未返回'}'),
                      Text('更新时间：${f['updatedAt'] ?? '未返回'}'),
                      if (f['range'] is Map)
                        Text(
                          '业务区间：${f['range']['first']} 至 ${f['range']['end']}（结束日不含）',
                        ),
                      const SizedBox(height: 12),
                      const Text('点击指标查看分母与口径。当前汇总接口未返回指标明细或趋势，不用部分列表推算。'),
                    ],
                  );
                },
              ),
        ],
      ),
    );
  }
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
          const Text('查看口径 ›'),
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
    final saver = ref.read(csvSaverProvider);
    setState(() {
      busy = true;
      result = null;
    });
    try {
      if (AppConfig.mock && ref.read(sessionProvider).token == null) {
        setState(() => result = '演示模式不导出真实企业数据');
        return;
      }
      final record = await ref
          .read(repositoryProvider)
          .execute(
            'analytics/export',
            Command('export', {
              'date': date,
              'period': period,
              'resource': resource,
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
          const Text('范围与工作统计相同，服务端再次校验每条记录权限。'),
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
