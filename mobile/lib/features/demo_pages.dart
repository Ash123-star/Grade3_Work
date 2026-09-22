export 'calendar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../shared/widgets.dart';

class AiGraph extends ConsumerWidget {
  const AiGraph({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(recordsProvider('ai-maps'));
    final task = ref
        .watch(recordsProvider('tasks'))
        .valueOrNull
        ?.items
        .firstOrNull;
    final log = ref
        .watch(recordsProvider('logs'))
        .valueOrNull
        ?.items
        .firstOrNull;
    return suggestions.when(
      loading: () => const LoadingSkeleton(),
      error: (e, s) => ErrorPanel(
        '$e',
        retry: () => ref.invalidate(recordsProvider('ai-maps')),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const EmptyIllustration(
            title: '暂无关系图',
            subtitle: '选择有记录的日期后生成建议',
          );
        }
        final first = page.items.first;
        return Column(
          children: [
            const Text('双指缩放查看关系，点击节点打开详情'),
            const SizedBox(height: 8),
            SizedBox(
              height: 340,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: CuteTokens.cream,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 2.5,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 500,
                        height: 340,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: CustomPaint(painter: _GraphLines()),
                            ),
                            for (final node in [
                              (
                                170.0,
                                12.0,
                                '本期目标',
                                '明确优先工作',
                                'ai-maps',
                                first.id,
                              ),
                              (
                                10.0,
                                135.0,
                                '关键任务',
                                task?.title ?? '暂无任务',
                                'tasks',
                                task?.id,
                              ),
                              (
                                330.0,
                                135.0,
                                '风险与阻碍',
                                '确认关键依赖',
                                'ai-maps',
                                first.id,
                              ),
                              (
                                170.0,
                                255.0,
                                '工作依据',
                                log?.title ?? '暂无日报',
                                'logs',
                                log?.id,
                              ),
                            ])
                              Positioned(
                                left: node.$1,
                                top: node.$2,
                                width: 160,
                                child: CuteCard(
                                  color: node.$3 == '风险与阻碍'
                                      ? CuteTokens.yellow
                                      : CuteTokens.blue,
                                  onTap: node.$6 == null
                                      ? null
                                      : () => openItem(
                                          context,
                                          node.$5,
                                          node.$6!,
                                        ),
                                  child: Column(
                                    children: [
                                      Text(
                                        node.$3,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        node.$4,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
            ),
          ],
        );
      },
    );
  }
}

class _GraphLines extends CustomPainter {
  const _GraphLines();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = CuteTokens.mint
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final end in [const Offset(90, 135), const Offset(410, 135)]) {
      canvas.drawLine(const Offset(250, 88), end, p);
      canvas.drawLine(Offset(end.dx, 210), const Offset(250, 255), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});
  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  String department = '全部部门', owner = '全部人员';
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(sessionProvider).manager) {
      return const PageFrame(
        title: '工作统计',
        child: EmptyIllustration(title: '暂无查看权限', subtitle: '统计面向管理范围内的工作数据'),
      );
    }
    final tasks = ref.watch(recordsProvider('tasks')),
        logs = ref.watch(recordsProvider('logs/subordinates'));
    final date = ref.watch(selectedDateProvider),
        period = ref.watch(periodProvider),
        range = BusinessRange(date, period);
    bool inRange(dynamic value) {
      final d = DateTime.tryParse('$value');
      return d != null && !d.isBefore(range.from) && d.isBefore(range.to);
    }

    bool member(Record r) =>
        (owner == '全部人员' || r.ownerId == owner) &&
        (department == '全部部门' ||
            (department == '技术部' ? r.ownerId == 'u3' : r.ownerId != 'u3'));
    final all = (tasks.valueOrNull?.items ?? <Record>[]).where(member).toList();
    final dispatched = all
        .where((r) => inRange(r.fields['createdAt']))
        .toList();
    final due = all.where((r) => inRange(r.fields['deadline'])).toList();
    final overdue = due
        .where(
          (r) =>
              !['已验收', '已归档', '已撤回'].contains(r.fields['status']) &&
              (DateTime.tryParse(
                    '${r.fields['deadline']}',
                  )?.isBefore(DateTime.now()) ??
                  false),
        )
        .toList();
    final accepted = due
        .where(
          (r) =>
              ['已验收', '已归档'].contains(r.fields['status']) &&
              (DateTime.tryParse('${r.fields['acceptedAt']}')?.isAfter(
                    DateTime.tryParse('${r.fields['deadline']}') ??
                        DateTime(2000),
                  ) ==
                  false),
        )
        .toList();
    final logItems = (logs.valueOrNull?.items ?? <Record>[])
        .where(
          (r) =>
              member(r) &&
              inRange('${r.fields['businessDate']}T00:00:00+08:00'),
        )
        .toList();
    final people = ['u1', 'u2', 'u3']
        .where(
          (id) =>
              (owner == '全部人员' || owner == id) &&
              (department == '全部部门' ||
                  (department == '技术部' ? id == 'u3' : id != 'u3')),
        )
        .length;
    final expected = range.to.difference(range.from).inDays * people;
    final metrics = [
      ('派发任务', '${dispatched.length} 项', dispatched, 'tasks'),
      ('逾期任务', '${overdue.length} 项', overdue, 'tasks'),
      (
        '按期验收率',
        due.isEmpty
            ? '不适用'
            : '${(accepted.length / due.length * 100).round()}%（${accepted.length}/${due.length}）',
        accepted,
        'tasks',
      ),
      (
        '日报提交率',
        expected == 0
            ? '不适用'
            : '${(logItems.length / expected * 100).round()}%（${logItems.length}/$expected）',
        logItems,
        'logs/subordinates',
      ),
    ];
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
          const DemoLabel(),
          const DateControls(),
          DropdownButtonFormField<String>(
            initialValue: department,
            decoration: const InputDecoration(labelText: '部门'),
            items: [
              '全部部门',
              '产品部',
              '技术部',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => department = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: owner,
            decoration: const InputDecoration(labelText: '人员'),
            items: [
              const DropdownMenuItem(value: '全部人员', child: Text('全部人员')),
              for (final (i, name) in ['林小满', '陈一诺', '许知远'].indexed)
                DropdownMenuItem(value: 'u${i + 1}', child: Text(name)),
            ],
            onChanged: (v) => setState(() => owner = v!),
          ),
          if (tasks.isLoading || logs.isLoading) const LoadingSkeleton(),
          if (tasks.hasError || logs.hasError)
            ErrorPanel(
              '${tasks.error ?? logs.error}',
              retry: () => ref.invalidate(recordsProvider),
            ),
          const SectionHeader('工作概览'),
          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CuteCard(
                color: CuteTokens.blue,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (c) => SafeArea(
                    child: SizedBox(
                      height: MediaQuery.sizeOf(c).height * .65,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            metric.$1,
                            style: Theme.of(c).textTheme.titleLarge,
                          ),
                          if (metric.$3.isEmpty) const EmptyIllustration(),
                          for (final r in metric.$3)
                            ListTile(
                              title: Text(r.title),
                              subtitle: Text(r.subtitle),
                              onTap: () {
                                Navigator.pop(c);
                                openItem(context, metric.$4, r.id);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.$1),
                    Text(
                      metric.$2,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      '点击查看明细',
                      style: TextStyle(color: CuteTokens.muted),
                    ),
                  ],
                ),
              ),
            ),
          const SectionHeader('部门任务分布'),
          for (final dept in ['产品部', '技术部'])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dept · ${dispatched.where((r) => dept == '技术部' ? r.ownerId == 'u3' : r.ownerId != 'u3').length} 项',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: dispatched.isEmpty
                        ? 0
                        : dispatched
                                  .where(
                                    (r) => dept == '技术部'
                                        ? r.ownerId == 'u3'
                                        : r.ownerId != 'u3',
                                  )
                                  .length /
                              dispatched.length,
                    minHeight: 14,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ],
              ),
            ),
          const SectionHeader('近 7 天任务派发'),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 6; i >= 0; i--)
                  Expanded(
                    child: Builder(
                      builder: (c) {
                        final day = date.subtract(Duration(days: i));
                        final n = all.where((r) {
                          final d = DateTime.tryParse(
                            '${r.fields['createdAt']}',
                          )?.toLocal();
                          return d != null &&
                              d.year == day.year &&
                              d.month == day.month &&
                              d.day == day.day;
                        }).length;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('$n'),
                            Container(
                              height: (12 + n * 24.0).clamp(12, 100),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: CuteTokens.mint,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('${day.day}日'),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader('统计说明'),
          const Text(
            '派发数量按创建日期；逾期与验收按截止日期筛选。日报分母按所选天数 × 人员数计算（演示包含周末）。按期验收率 = 截止日处于所选周期且按期验收的任务 / 该周期到期任务。',
          ),
          Text('更新时间：${DateTime.now().toString().substring(0, 16)}'),
        ],
      ),
    );
  }
}

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});
  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String search = '';
  final articles = const [
    ('员工 · 如何填写日志', '进入日志，选择日期，点击写日志。输入今日工作、问题与下一步计划，草稿自动保存，提交后可查看详情。'),
    ('员工 · 如何处理任务', '打开任务详情，点击接收任务。完成工作后提交成果反馈；退回补充时修改成果，再次提交。'),
    ('管理者 · 派发任务与查看下属', '在导图右下角派发任务，选择主负责人。进入日志 → 下属日志，选择成员查看已提交内容。'),
    ('管理者 · 审核规则', '在我的 → 审批中心查看修改前后内容，逐级通过或填写驳回理由。不能审核本人申请。'),
    ('管理员 · 组织与权限', '在我的 → 组织与权限设置维护部门、人员归属和角色。演示角色可在设置中切换。'),
    ('登录失败或权限不足', '检查账号与密码。组织归属尚未确认时请联系管理员。演示时可在设置检查当前角色和数据场景。'),
    ('日志保存失败与审核驳回', '保留本地草稿，恢复网络后重试。申请被驳回时查看审核意见，调整内容后重新提交。'),
    ('AI 请求超时', '系统保留输入，点击重新生成。AI 建议需要人工确认；不会影响任务和日志。'),
  ];
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '帮助与反馈',
    child: PageBody(
      children: [
        const CuteArt('1F331', size: 72),
        const SectionHeader('有什么可以帮你？'),
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索使用说明',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 12),
        for (final article in articles)
          if ('${article.$1}${article.$2}'.contains(search))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(article.$1),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(article.$2),
                ),
              ],
            ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.push('/guide'),
          icon: const Icon(Icons.explore_outlined),
          label: const Text('查看新手引导'),
        ),
        FilledButton.icon(
          onPressed: () => openForm(context, 'support'),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('提交问题反馈'),
        ),
        TextButton(
          onPressed: () => openList(context, 'feedback'),
          child: const Text('我的反馈与处理进度'),
        ),
      ],
    ),
  );
}

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});
  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  int step = 0;
  final pages = const [
    ('1F680', '从导图开始', '公司重点、公司任务、个人重点、个人日志，四个板块集中查看。'),
    ('1F4D2', '记录每一天', '在日志填写今日工作与下一步计划，草稿会自动保存在设备上。'),
    ('1F31F', '让协作有回应', '接收任务、提交成果、等待验收。管理者可以查看下属日志与审批。'),
    ('1F916', '安排下一步', '在时间视图回顾日、周、月安排，通过 AI 地图梳理重点与依赖。'),
  ];
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '欢迎使用潘多拉',
    actions: [
      TextButton(
        onPressed: () => context.go('/dashboard'),
        child: const Text('跳过'),
      ),
    ],
    child: PageBody(
      children: [
        const SizedBox(height: 40),
        CuteArt(pages[step].$1, size: 120),
        const SizedBox(height: 32),
        Text(
          pages[step].$2,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(pages[step].$3, textAlign: TextAlign.center),
        const SizedBox(height: 32),
        Center(child: Text('${step + 1} / ${pages.length}')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (step < pages.length - 1) {
              setState(() => step++);
            } else {
              context.go('/dashboard');
            }
          },
          child: Text(step == pages.length - 1 ? '开始使用' : '下一步'),
        ),
      ],
    ),
  );
}

class LogHistory extends ConsumerWidget {
  const LogHistory({super.key, required this.logId});
  final String logId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(itemProvider(('logs', logId)))
      .when(
        loading: () => const LoadingSkeleton(),
        error: (e, s) => ErrorPanel(
          '$e',
          retry: () => ref.invalidate(itemProvider(('logs', logId))),
        ),
        data: (r) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader('生效版本 v${r.version}'),
            CuteCard(
              child: Text('${r.fields['今日工作'] ?? r.fields['body'] ?? ''}'),
            ),
            const SectionHeader('历史版本'),
            if ((r.fields['versions'] as List? ?? []).isEmpty)
              const Text('暂无历史修订'),
            for (final v in (r.fields['versions'] as List? ?? []))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text('v${v['version']} · ${v['body']}'),
                subtitle: Text('${v['time']}'),
              ),
            const SectionHeader('修改申请'),
            ref
                .watch(recordsProvider('reviews'))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, s) => Text('$e'),
                  data: (page) {
                    final requests = page.items
                        .where(
                          (v) =>
                              v.fields['targetResource'] == 'logs' &&
                              v.fields['targetId'] == logId,
                        )
                        .toList();
                    return Column(
                      children: [
                        if (requests.isEmpty) const Text('暂无修改申请'),
                        for (final v in requests)
                          ListTile(
                            title: Text('${v.fields['after']}'),
                            subtitle: Text('${v.fields['reviewState']}'),
                            onTap: () => openItem(context, 'reviews', v.id),
                          ),
                      ],
                    );
                  },
                ),
            const SectionHeader('阅读记录'),
            Text('${r.fields['readBy'] ?? '暂无上级阅读记录'}'),
          ],
        ),
      );
}

class ReportSummary extends ConsumerWidget {
  const ReportSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(datedRecordsProvider('logs'))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, s) => Text('$e'),
        data: (page) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('工作回顾'),
            CuteCard(
              color: CuteTokens.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本期提交 ${page.items.length} 份日报',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final r in page.items)
                    Text('• ${r.fields['今日工作'] ?? r.title}'),
                  if (page.items.isEmpty) const Text('切换日期范围查看历史工作。'),
                ],
              ),
            ),
            const SectionHeader('关注的问题'),
            for (final r in page.items)
              if ('${r.fields['遇到的阻碍'] ?? ''}'.isNotEmpty)
                Text('• ${r.fields['遇到的阻碍']}'),
            const SectionHeader('日报来源'),
          ],
        ),
      );
}
