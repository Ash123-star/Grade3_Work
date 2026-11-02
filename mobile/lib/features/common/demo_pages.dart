import 'package:pandora_mobile/features/dashboard/server_analytics_page.dart';
export 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'package:pandora_mobile/shared/diary_task_links.dart';

class AiGraph extends ConsumerStatefulWidget {
  const AiGraph({super.key});
  @override
  ConsumerState<AiGraph> createState() => _AiGraphState();
}

class _AiGraphState extends ConsumerState<AiGraph> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    if (!AppConfig.mock) {
      return const EmptyIllustration(
        title: '关系分析服务待接入',
        subtitle: '关系图只展示服务端明确返回的来源和建议',
      );
    }
    return ref
        .watch(recordsProvider('ai-maps'))
        .when(
          loading: () => const LoadingSkeleton(),
          error: (e, _) => ErrorPanel(
            '$e',
            retry: () => ref.invalidate(recordsProvider('ai-maps')),
          ),
          data: (page) {
            final items = page.items
                .where((r) => r.title.contains(search))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索建议节点',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const EmptyIllustration(title: '暂无匹配关系', subtitle: '可以更换搜索条件')
                else
                  SizedBox(
                    height: 340,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: InteractiveViewer(
                        minScale: .5,
                        maxScale: 3,
                        constrained: false,
                        child: SizedBox(
                          width: 640,
                          height: 440,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: CustomPaint(painter: _GraphLines()),
                              ),
                              Positioned(
                                left: 200,
                                top: 150,
                                width: 240,
                                child: PaperSurface(
                                  color: const Color(0xFFF1E7FF),
                                  onTap: () => openItem(
                                    context,
                                    'ai-maps',
                                    items.first.id,
                                  ),
                                  child: Text(
                                    items.first.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              for (final (i, path)
                                  in (items.first.fields['sources'] as List? ??
                                          [])
                                      .map((e) => '$e')
                                      .where(
                                        (e) => RegExp(
                                          r'^/item/(tasks|logs)/[^/]+$',
                                        ).hasMatch(e),
                                      )
                                      .take(2)
                                      .indexed)
                                Positioned(
                                  left: i == 0 ? 20 : 440,
                                  top: 40,
                                  width: 180,
                                  child: PaperSurface(
                                    color: CuteTokens.blue,
                                    onTap: () => context.push(path),
                                    child: Text(
                                      path.contains('/logs/')
                                          ? '来源 · 工作日志'
                                          : '来源 · 工作任务',
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 210,
                                top: 320,
                                width: 220,
                                child: PaperSurface(
                                  color: const Color(0xFFFFE9D4),
                                  onTap: () => context.go('/ai'),
                                  child: const Text('人工核对后加入行动规划'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SectionHeader('可访问节点列表'),
                for (final item in items) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title),
                    subtitle: const Text('建议草稿 · 需人工确认'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openItem(context, 'ai-maps', item.id),
                  ),
                  for (final path
                      in (item.fields['sources'] as List? ?? [])
                          .map((e) => '$e')
                          .where(
                            (e) => RegExp(
                              r'^/item/(tasks|logs)/[^/]+$',
                            ).hasMatch(e),
                          ))
                    ListTile(
                      title: Text(
                        path.contains('/logs/') ? '来源工作日志' : '来源工作任务',
                      ),
                      leading: const Icon(Icons.link),
                      onTap: () => context.push(path),
                    ),
                  const Divider(),
                ],
                const DemoLabel(),
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
      ..color = const Color(0xFFB49AD4)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(110, 100), const Offset(320, 150), p);
    canvas.drawLine(const Offset(530, 100), const Offset(320, 150), p);
    canvas.drawLine(const Offset(320, 220), const Offset(320, 320), p);
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
        child: EmptyIllustration(
          showCharacter: false,
          title: '暂无查看权限',
          subtitle: '统计面向管理范围内的工作数据',
        ),
      );
    }
    if (!AppConfig.mock) return const ServerAnalyticsPage();
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
            ? '暂无'
            : '${(accepted.length / due.length * 100).round()}%（${accepted.length}/${due.length}）',
        accepted,
        'tasks',
      ),
      (
        '日报提交率',
        expected == 0
            ? '暂无'
            : '${(logItems.length / expected * 100).round()}%（${logItems.length}/$expected）',
        logItems,
        'logs/subordinates',
      ),
    ];
    return PageFrame(
      title: '工作统计',
      child: PageBody(
        children: [
          const DateControls(),
          PremiumDropdownField<String>(
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
          PremiumDropdownField<String>(
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
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col == 1) const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final metric = metrics[row * 2 + col];
                            return PaperSurface(
                              color: row == 0
                                  ? CuteTokens.blue
                                  : const Color(0xFFFFE9D4),
                              onTap: () => showTuantuanBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (sheet) => SafeArea(
                                  child: ListView(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      Text(
                                        metric.$1,
                                        style: const TextStyle(
                                          fontFamily:
                                              AppTypography.displayFamily,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (metric.$3.isEmpty) const Text('暂无明细'),
                                      for (final r in metric.$3)
                                        ListTile(
                                          title: Text(r.title),
                                          onTap: () {
                                            Navigator.pop(sheet);
                                            openItem(context, metric.$4, r.id);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(metric.$1),
                                  const SizedBox(height: 10),
                                  Text(
                                    metric.$2,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.displayFamily,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '查看明细 →',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: CuteTokens.muted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
                  SunnyProgressBar(
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
                    height: 14,
                  ),
                ],
              ),
            ),
          const SectionHeader('近 7 天任务派发'),
          SizedBox(
            height: 108 + MediaQuery.textScalerOf(context).scale(44),
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
                            Text('$n', maxLines: 1),
                            Container(
                              height: (n * 24.0).clamp(0, 100),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: CuteTokens.mint,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('${day.day}日', maxLines: 1),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const DemoLabel(),
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
  final searchController = TextEditingController();
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  final articles = const [
    ('员工 · 如何填写日志', '进入日志，选择日期，点击写日志。输入今日工作、问题与下一步计划，草稿自动保存，提交后可查看详情。'),
    (
      '员工 · 如何处理任务',
      '打开任务详情，按当前权限接收任务并提交成果反馈，由派发者查看成果后验收。需要补充信息时，可先在任务评论中沟通。',
    ),
    ('管理者 · 派发任务与查看下属', '在导图右下角派发任务，选择主负责人。进入日志 → 下属日志，选择成员查看已提交内容。'),
    ('管理者 · 审核规则', '在我的 → 审批中心查看修改前后内容，由组织中配置的直属上级单级审核；驳回时须填写理由。不能审核本人申请。'),
    ('管理员 · 组织与权限', '在我的 → 组织与权限设置维护部门、人员归属和角色。关键变更由配置的直属上级单级审核，审核通过前原配置继续生效。'),
    ('登录失败或权限不足', '检查账号与密码和企业服务连接。注册申请只能创建待确认员工；管理员确认部门前无法读取业务资料。权限由企业服务校验。'),
    ('日志保存失败与审核驳回', '保留本地草稿，恢复网络后重试。申请被驳回时查看审核意见，调整内容后重新提交。'),
    (
      'AI 请求超时',
      '系统保留输入和上次结果。先刷新或重新接收已有作业；需要新分析时再明确重新生成。AI建议可保存为草稿，有派发权限且来源有效时，经人工确认才能创建任务。',
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final matches = articles
        .where(
          (article) => '${article.$1}${article.$2}'.contains(search.trim()),
        )
        .toList();
    return PageFrame(
      title: '帮助与反馈',
      child: PageBody(
        children: [
          const SectionHeader('有什么可以帮你？'),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: '搜索使用说明',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 12),
          if (matches.isEmpty) ...[
            const EmptyIllustration(
              title: '没有找到相关说明',
              subtitle: '尝试日志、任务、审核或AI等关键词',
            ),
            TextButton(
              onPressed: () {
                searchController.clear();
                setState(() => search = '');
              },
              child: const Text('清除搜索'),
            ),
          ],
          for (final article in matches)
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
        ],
      ),
    );
  }
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
    bottom: BottomActions(
      primary: SunnyPrimaryButton(
        onPressed: () {
          if (step < pages.length - 1) {
            setState(() => step++);
          } else {
            context.go('/dashboard');
          }
        },
        child: Text(step == pages.length - 1 ? '开始使用' : '下一步'),
      ),
    ),
    child: PageBody(
      children: [
        const SizedBox(height: 32),
        DogPose(index: [0, 5, 10, 14][step], size: 120),
        const SizedBox(height: 24),
        Text(
          pages[step].$2,
          style: const TextStyle(
            fontFamily: AppTypography.displayFamily,
            fontSize: 27,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          pages[step].$3,
          style: const TextStyle(fontSize: 16, height: 1.8),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  width: i == step ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == step
                        ? const Color(0xFFFF8A24)
                        : CuteTokens.line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
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
            PaperSurface(
              onTap: () => context.push(
                '/history/${encode(logId)}/version/${r.version}',
              ),
              child: Text('${r.fields['今日工作'] ?? r.fields['body'] ?? ''}'),
            ),
            const SectionHeader('历史版本'),
            if (r.fields['versionsError'] != null)
              RecordFailure(
                r.fields['versionsError'] as Object,
                retry: () => ref.invalidate(itemProvider(('logs', logId))),
              ),
            if (r.fields['versionsError'] == null &&
                (r.fields['versions'] as List? ?? []).isEmpty)
              const Text('暂无历史修订'),
            for (final v in diaryVersions(r))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: Text(
                  'v${v['version']} · ${v['body'] ?? v['今日工作'] ?? '打开版本正文'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${v['time'] ?? '时间未提供'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/history/${encode(logId)}/version/${v['version']}',
                ),
              ),
            const SectionHeader('修改申请'),
            ref
                .watch(recordsProvider('reviews'))
                .when(
                  loading: () => const SunnyLoadingIndicator(),
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
          ],
        ),
      );
}

List<Map<String, dynamic>> diaryVersions(Record record) {
  final result = (record.fields['versions'] as List? ?? [])
      .whereType<Map>()
      .map((v) => Map<String, dynamic>.from(v))
      .toList();
  result.sort(
    (a, b) => (int.tryParse('${b['version']}') ?? 0).compareTo(
      int.tryParse('${a['version']}') ?? 0,
    ),
  );
  return result;
}

class DiaryVersionPage extends ConsumerWidget {
  const DiaryVersionPage({
    super.key,
    required this.logId,
    required this.version,
  });
  final String logId;
  final int version;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: '日志版本 v$version',
    child: ref
        .watch(itemProvider(('logs', logId)))
        .when(
          loading: () => const PageBody(children: [LoadingSkeleton()]),
          error: (e, _) => PageBody(
            children: [
              RecordFailure(
                e,
                retry: () => ref.invalidate(itemProvider(('logs', logId))),
              ),
            ],
          ),
          data: (r) {
            final history = diaryVersions(
              r,
            ).where((v) => '${v['version']}' == '$version').firstOrNull;
            final current = version == r.version;
            if (!current && r.fields['versionsError'] != null) {
              return PageBody(
                children: [
                  RecordFailure(
                    r.fields['versionsError'] as Object,
                    retry: () => ref.invalidate(itemProvider(('logs', logId))),
                  ),
                ],
              );
            }
            if (history == null && !current) {
              return const PageBody(
                children: [
                  EmptyIllustration(
                    title: '该版本正文不可用',
                    subtitle: '服务端尚未返回此版本，不能用当前内容替代历史正文',
                  ),
                ],
              );
            }
            final fields = current
                ? r.fields
                : Map<String, dynamic>.from(
                    history?['fields'] as Map? ?? history!,
                  );
            return PageBody(
              children: [
                Text(r.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${r.fields['businessDate'] ?? '未标记日期'} · ${current ? '当前生效' : '历史只读'} · v$version',
                ),
                const SizedBox(height: 16),
                PaperSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '今日工作',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${fields['今日工作'] ?? fields['body'] ?? '该版本未返回正文'}',
                        style: const TextStyle(height: 1.8),
                      ),
                      for (final label in ['关联任务', '遇到的阻碍', '明日计划', '工时'])
                        if (fields[label] != null) ...[
                          const Divider(height: 32),
                          Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (label == '关联任务')
                            DiaryTaskLinksReader(
                              fields['taskIds'] ?? fields[label],
                            )
                          else
                            Text('${fields[label]}'),
                        ],
                    ],
                  ),
                ),
                const SectionHeader('版本信息'),
                Text(
                  '记录时间：${history?['time'] ?? fields['submittedAt'] ?? '未返回'}',
                ),
                Text('变更理由：${history?['reason'] ?? history?['修改理由'] ?? '未返回'}'),
                const SizedBox(height: 16),
                const Text('历史版本只读；查看不会触发修订或覆盖正式日志。'),
                const DemoLabel(),
              ],
            );
          },
        ),
  );
}

class ReportSummary extends ConsumerWidget {
  const ReportSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(datedRecordsProvider('logs'))
      .when(
        loading: () => const SunnyLoadingIndicator(),
        error: (e, s) => Text('$e'),
        data: (page) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('工作回顾'),
            PaperSurface(
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

final reportPeriodProvider = StateProvider<String>((ref) => '周');
final reportDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final reportRecordsProvider = FutureProvider.autoDispose<PageResult>((ref) {
  var active = true;
  ref.onDispose(() => active = false);
  final range = BusinessRange(
    ref.watch(reportDateProvider),
    ref.watch(reportPeriodProvider),
  );
  return readCompleteList(
    ref.watch(repositoryProvider),
    'logs',
    Query(
      ownerId: ref.watch(sessionProvider).id,
      from: range.from,
      to: range.to,
    ),
    isActive: () => active,
  );
});

class PeriodReport extends ConsumerStatefulWidget {
  const PeriodReport({super.key, this.initialPeriod});
  final String? initialPeriod;
  @override
  ConsumerState<PeriodReport> createState() => _PeriodReportState();
}

class _PeriodReportState extends ConsumerState<PeriodReport> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(reportPeriodProvider.notifier).state =
          widget.initialPeriod ?? '周',
    );
  }

  @override
  void didUpdateWidget(covariant PeriodReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPeriod != oldWidget.initialPeriod) {
      Future.microtask(
        () => ref.read(reportPeriodProvider.notifier).state =
            widget.initialPeriod ?? '周',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(reportDateProvider),
        period = ref.watch(reportPeriodProvider),
        range = BusinessRange(
          ref.watch(reportDateProvider),
          ref.watch(reportPeriodProvider),
        );
    final from = shanghaiWallTime(range.from),
        to = shanghaiWallTime(range.to).subtract(const Duration(days: 1));
    void move(int by) =>
        ref.read(reportDateProvider.notifier).state = period == '月'
        ? DateTime(date.year, date.month + by, 1)
        : date.add(Duration(days: by * 7));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.initialPeriod == null)
          PillTabs(
            labels: const ['周报', '月报'],
            selected: period == '周' ? 0 : 1,
            onChanged: (i) => ref.read(reportPeriodProvider.notifier).state =
                i == 0 ? '周' : '月',
          ),
        Row(
          children: [
            IconButton(
              tooltip: '上一周期',
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${from.month}月${from.day}日 — ${to.month}月${to.day}日',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '下一周期',
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        ref
            .watch(reportRecordsProvider)
            .when(
              loading: () => const LoadingSkeleton(),
              error: (e, _) => ErrorPanel(
                '$e',
                retry: () => ref.invalidate(reportRecordsProvider),
              ),
              data: (page) {
                final sources = page.items.where(isSubmittedDiary).toList();
                final drafts = page.items
                    .where((r) => !isSubmittedDiary(r))
                    .length;
                final today = shanghaiWallTime(DateTime.now());
                final dates = sources
                    .map((r) => '${r.fields['businessDate']}')
                    .toSet();
                final missing = <String>[];
                for (
                  var d = from;
                  !d.isAfter(to);
                  d = d.add(const Duration(days: 1))
                ) {
                  if (d.isAfter(today)) continue;
                  if (!dates.contains(d.toIso8601String().split('T').first)) {
                    missing.add('${d.month}/${d.day}');
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PaperSurface(
                      color: CuteTokens.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '已收集 ${sources.length} 份源日报',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            missing.isEmpty
                                ? '区间内已过去日期均有正式日报'
                                : '尚无正式日报的日期：${missing.join('、')}',
                            style: const TextStyle(
                              color: CuteTokens.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (drafts > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('$drafts 份草稿未提交，未计入回顾与源日报'),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('按日历日期核对记录，包含周末；不作为考勤或工作评分。'),
                    ),
                    for (final (index, label) in [
                      '今日工作',
                      '遇到的阻碍',
                      '明日计划',
                    ].indexed)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: PaperSurface(
                          color: [
                            const Color(0xFFFFF0DA),
                            CuteTokens.blue,
                            CuteTokens.mint,
                          ][index],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    [
                                      Icons.edit_note,
                                      Icons.info_outline,
                                      Icons.event_outlined,
                                    ][index],
                                    size: 28,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      label == '今日工作' ? '工作回顾' : label,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(
                                height: 20,
                                color: Color(0xFFE4C6A5),
                              ),
                              if (sources.isEmpty) const Text('暂无正式记录'),
                              for (final item in sources)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '• ${item.fields[label] ?? '暂无记录'}',
                                    style: const TextStyle(height: 1.8),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SectionHeader('源日报'),
                    for (final item in sources)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: const Icon(Icons.edit_note, size: 28),
                        title: Text(item.title),
                        subtitle: Text('${item.fields['businessDate']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openItem(context, 'logs', item.id),
                      ),
                    const Text(
                      '本页回顾仅汇总本人正式日报。AI按账号授权范围分析，不能保证仅使用这些日报；不会自动发布总结。',
                      style: TextStyle(fontSize: 12, color: CuteTokens.muted),
                    ),
                  ],
                );
              },
            ),
      ],
    );
  }
}
