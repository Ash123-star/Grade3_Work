import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/config.dart';
import '../core/providers.dart';
import '../data/mock_repository.dart';
import '../shared/widgets.dart';

const _green = Color(0xFF185D4E);
const _mint = Color(0xFFE7F3EC);
const _amber = Color(0xFF916021);
const _cream = Color(0xFFFFF3DE);

class AiActionDraft {
  const AiActionDraft(
    this.id,
    this.title,
    this.detail,
    this.origin, {
    this.done = false,
  });
  final String id, title, detail, origin;
  final bool done;
}

// Personal, session-only drafts. No formal task is published from this page.
final aiActionDraftsProvider =
    StateProvider.family<List<AiActionDraft>, String>(
      (ref, user) => [
        const AiActionDraft(
          'dependency',
          '确认交互稿中的关键依赖',
          '交付物：依赖清单与待确认问题。先与相关同事核对，再推进联调。',
          '解决堵点',
        ),
        const AiActionDraft(
          'growth',
          '独立推进一次小型需求评审',
          '交付物：评审纪要、责任分工与验收标准，积累完整的项目推进经验。',
          '个人发展',
        ),
      ],
    );

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});
  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  int tab = 0;
  bool company = false;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void changeTab(int value) {
    setState(() => tab = value);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void addAction(AiActionDraft draft) {
    final provider = aiActionDraftsProvider(ref.read(sessionProvider).id);
    final items = ref.read(provider);
    if (!items.any((e) => e.id == draft.id)) {
      ref.read(provider.notifier).state = [...items, draft];
    }
    changeTab(2);
    notice(context, '已放入行动草稿，可编辑后再执行');
  }

  Future<void> editAction(AiActionDraft? item) async {
    final title = TextEditingController(text: item?.title);
    final detail = TextEditingController(text: item?.detail);
    final form = GlobalKey<FormState>();
    final userId = ref.read(sessionProvider).id;
    final result = await showDialog<AiActionDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item == null ? '添加行动' : '编辑行动'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: '要做的事'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请填写行动名称' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: detail,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: '步骤与交付物'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  AiActionDraft(
                    item?.id ??
                        'custom-${DateTime.now().microsecondsSinceEpoch}',
                    title.text.trim(),
                    detail.text.trim(),
                    item?.origin ?? '自主规划',
                    done: item?.done ?? false,
                  ),
                );
              }
            },
            child: const Text('保存草稿'),
          ),
        ],
      ),
    );
    // Controllers live through the dialog's closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    detail.dispose();
    if (!mounted || result == null || ref.read(sessionProvider).id != userId) {
      return;
    }
    final provider = aiActionDraftsProvider(userId);
    final items = ref.read(provider);
    ref.read(provider.notifier).state = item == null
        ? [...items, result]
        : [
            for (final e in items)
              if (e.id == item.id) result else e,
          ];
  }

  void sources() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('分析依据', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              '当前为预设分析样例，用于体验发展路径和行动流程，并非对你的实际工作做出的评估。下方可查看当前账号有权访问的记录。',
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看工作日志'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.pop(sheetContext);
                openList(context, 'logs');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.task_alt),
              title: const Text('查看关联工作任务'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.pop(sheetContext);
                openList(context, 'tasks');
              },
            ),
            const Text(
              '正式分析将逐条展示来源记录、分析时间及数据范围。',
              style: TextStyle(color: CuteTokens.muted),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final scenario = ref.watch(scenarioProvider);
    final isCompany = company && user.manager;
    return PageFrame(
      title: 'AI 地图',
      actions: [
        IconButton(
          tooltip: '用量与来源',
          onPressed: () => context.push('/ai-usage'),
          icon: const Icon(Icons.info_outline),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                children: [
                  for (final (i, label, icon) in [
                    (0, '发展分析', Icons.explore_outlined),
                    (1, '堵点风险', Icons.radar),
                    (2, '行动规划', Icons.route_outlined),
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                        child: Semantics(
                          selected: tab == i,
                          child: Material(
                            color: tab == i ? _green : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => changeTab(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 3,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      icon,
                                      color: tab == i ? Colors.white : _green,
                                      size: 22,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: tab == i
                                            ? Colors.white
                                            : CuteTokens.ink,
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
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                  children: [
                    if (!AppConfig.mock)
                      const EmptyIllustration(
                        title: '发展分析服务待接入',
                        subtitle: '连接企业分析服务后，将在这里展示你的发展、风险与行动建议。',
                      )
                    else if (!user.active || scenario == DemoScenario.forbidden)
                      const EmptyIllustration(
                        title: '暂无分析访问权限',
                        subtitle: '请联系管理员确认可查看的数据范围。',
                      )
                    else if (scenario == DemoScenario.offline)
                      ErrorPanel(
                        '分析暂时无法加载，请恢复网络后重试。',
                        retry: () => setState(() {}),
                      )
                    else if (scenario == DemoScenario.empty)
                      EmptyIllustration(
                        title: '从第一份工作记录开始',
                        subtitle: '积累工作日志与任务成果后，再来看发展方向。',
                        action: FilledButton(
                          onPressed: () => context.go('/logs'),
                          child: const Text('去写日志'),
                        ),
                      )
                    else ...[
                      const DemoLabel(),
                      if (tab == 0) ...development(isCompany, user.manager),
                      if (tab == 1) ...risks(),
                      if (tab == 2) ...planning(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget hero(String eyebrow, String title, String subtitle, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFBDE8CA), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    eyebrow,
                    style: const TextStyle(
                      color: Color(0xFFBDE8CA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFFD9EAE3), height: 1.6),
            ),
          ],
        ),
      );

  Widget card(
    String title,
    String body, {
    String? badge,
    Color color = Colors.white,
    Widget? footer,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: CuteCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (badge != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                badge,
                color: color == _cream ? const Color(0xFFF7DFB6) : _mint,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: CuteTokens.muted, height: 1.65),
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer],
        ],
      ),
    ),
  );

  Widget path(List<(String, String)> nodes) => CuteCard(
    child: Column(
      children: [
        for (final (i, node) in nodes.indexed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: i == nodes.length - 1 ? _green : _mint,
                child: Text(
                  '0${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: i == nodes.length - 1 ? Colors.white : _green,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.$2,
                      style: const TextStyle(color: CuteTokens.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (i != nodes.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 7),
                  child: Icon(Icons.south, size: 20, color: Color(0xFF8DB3A2)),
                ),
              ),
            ),
        ],
      ],
    ),
  );

  List<Widget> development(bool isCompany, bool manager) => [
    if (manager) ...[
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('个人发展'),
            selected: !isCompany,
            onSelected: (_) => setState(() => company = false),
          ),
          ChoiceChip(
            label: const Text('公司走向'),
            selected: isCompany,
            onSelected: (_) => setState(() => company = true),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ],
    hero(
      isCompany ? 'ORGANIZATION / 组织方向' : 'GROWTH / 个人成长',
      isCompany ? '从做过的业务，\n看见公司的下一站。' : '你做过的事，\n正在成为你的能力。',
      isCompany
          ? '连接业务投入、能力沉淀与战略机会，找到值得继续投入的方向。'
          : '把零散的工作经历串起来，看清积累，也看见下一次成长的机会。',
      isCompany ? Icons.business_outlined : Icons.auto_awesome,
    ),
    const SizedBox(height: 16),
    card(
      isCompany ? '从项目交付，走向能力复用' : '从执行任务，走向独立推进',
      isCompany
          ? '示例中，体验升级与协作规范形成了共同主题。可以探索把交付经验沉淀为可复用的方法和组件。'
          : '示例中，你的经历覆盖交互梳理、客户访谈和接口协作，可以尝试承担一项小需求的完整推进。',
      badge: '方向推测 · 待验证',
      color: _mint,
      footer: TextButton.icon(
        onPressed: sources,
        icon: const Icon(Icons.link),
        label: const Text('查看分析依据'),
      ),
    ),
    SectionHeader(isCompany ? '业务如何走向下一步' : '你的成长路径'),
    path(
      isCompany
          ? [
              ('已做的事 · 示例', '体验升级、客户需求整理、跨部门协作'),
              ('正在沉淀的能力', '需求识别、交付协同与标准化经验'),
              ('可以验证的方向', '将重复交付内容整理为可复用方案'),
            ]
          : [
              ('已做的事 · 示例', '梳理交互流程、整理访谈、推进接口联调'),
              ('正在积累的能力', '需求理解、问题拆解与协作推进'),
              ('可以尝试的方向', '独立负责一个小型项目或需求'),
            ],
    ),
    const SizedBox(height: 18),
    card(
      isCompany ? '值得投入：让成果复用起来' : '已经积累：把问题说清楚',
      isCompany
          ? '从相似项目中提取共性流程和交付模板，先用一个项目验证复用价值。'
          : '把用户反馈转成需求，再与设计和开发对齐，这是独立推进工作的基础。',
      badge: '能力观察 · 示例',
    ),
    card(
      isCompany ? '仍需验证：是否存在稳定需求' : '下一块拼图：完整闭环经验',
      isCompany
          ? '现有工作记录不足以判断市场规模与营收前景，还需要客户验证和经营数据。'
          : '参与协作与独立负责不同。建议补充从排期、协调到验收复盘的一次完整实践。',
      badge: '信息缺口',
      color: _cream,
    ),
    card(
      '把方向变成一次实践',
      isCompany
          ? '选择一个重复交付场景，整理共性需求、形成模板，再收集试用反馈。'
          : '选择一项范围清楚的小需求，主持评审，确认验收标准，并在结束后复盘。',
      footer: FilledButton.icon(
        onPressed: () => addAction(
          isCompany
              ? const AiActionDraft(
                  'reuse',
                  '梳理一套可复用的交付模板',
                  '整理相似需求，形成模板，并用一个实际项目验证复用价值。',
                  '公司走向',
                )
              : const AiActionDraft(
                  'growth',
                  '独立推进一次小型需求评审',
                  '交付物：评审纪要、责任分工与验收标准，积累完整的项目推进经验。',
                  '个人发展',
                ),
        ),
        icon: const Icon(Icons.add_road),
        label: const Text('加入行动规划'),
      ),
    ),
    const Text(
      '分析样例仅用于体验，不代表能力评分或经营预测。',
      style: TextStyle(fontSize: 12, color: CuteTokens.muted),
    ),
  ];

  List<Widget> risks() => [
    hero(
      'RADAR / 工作雷达',
      '先疏通堵点，\n再让工作向前。',
      '把问题、依赖与影响串起来，找到最值得先处理的一件事。',
      Icons.radar,
    ),
    const SizedBox(height: 16),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        StatusPill('2 个风险示例', color: _cream),
        StatusPill('先处理前置依赖', color: _mint),
      ],
    ),
    const SizedBox(height: 16),
    card(
      '交互规则待确认，联调可能受影响',
      '关键交互没有对齐时，接口实现和验收容易反复。先明确问题清单，再确认后续安排。',
      badge: '优先协调 · 示例',
      color: _cream,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '可能的影响链',
            style: TextStyle(fontWeight: FontWeight.w700, color: _amber),
          ),
          const SizedBox(height: 12),
          path([
            ('交互规则待确认', '先确认页面状态与异常分支'),
            ('接口联调', '依赖字段与交互规则对齐'),
            ('验收与交付', '联调推迟可能压缩验收空间'),
          ]),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('建议怎么处理'),
            children: const [
              Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '1. 列出尚未确认的规则。\n2. 与相关同事逐项核对。\n3. 更新联调清单，确认是否需要调整排期。',
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: sources,
            icon: const Icon(Icons.link),
            label: const Text('查看依据与相关任务'),
          ),
          FilledButton.icon(
            onPressed: () => addAction(
              const AiActionDraft(
                'dependency',
                '确认交互稿中的关键依赖',
                '交付物：依赖清单与待确认问题。先与相关同事核对，再推进联调。',
                '解决堵点',
              ),
            ),
            icon: const Icon(Icons.playlist_add),
            label: const Text('安排解决行动'),
          ),
        ],
      ),
    ),
    card(
      '客户反馈需要形成统一结论',
      '访谈结论如果没有转成可确认的需求，后续评审可能重复讨论。建议整理共识与分歧，明确需要谁来决策。',
      badge: '建议关注 · 示例',
      footer: OutlinedButton.icon(
        onPressed: () => addAction(
          const AiActionDraft(
            'feedback',
            '整理客户反馈与待决策问题',
            '交付物：需求共识、分歧清单和待确认人，作为下一次评审输入。',
            '解决堵点',
          ),
        ),
        icon: const Icon(Icons.playlist_add),
        label: const Text('加入行动规划'),
      ),
    ),
    const Text(
      '以上为风险场景演示。实际逾期由业务数据判断；影响关系需核实后使用。',
      style: TextStyle(fontSize: 12, color: CuteTokens.muted),
    ),
  ];

  List<Widget> planning() {
    final provider = aiActionDraftsProvider(ref.watch(sessionProvider).id);
    final items = ref.watch(provider);
    final done = items.where((e) => e.done).length;
    return [
      hero(
        'NEXT / 下一步行动',
        '把看见的方向，\n变成真正的行动。',
        '先解决眼前的阻碍，再留一件事给长期成长。行动清单由你来决定。',
        Icons.route_outlined,
      ),
      const SizedBox(height: 16),
      CuteCard(
        color: _mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '已完成 $done / ${items.length} 项行动',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: items.isEmpty ? 0 : done / items.length,
              minHeight: 6,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            const Text(
              '个人演示清单 · 本次运行内保留，不会自动派发任务',
              style: TextStyle(fontSize: 12, color: CuteTokens.muted),
            ),
          ],
        ),
      ),
      SectionHeader('我的行动清单', action: '添加行动', onAction: () => editAction(null)),
      if (items.isEmpty)
        const EmptyIllustration(
          title: '还没有行动',
          subtitle: '从发展分析或风险建议中加入，也可以自行添加。',
        ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CuteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: item.done,
                      semanticLabel: '完成：${item.title}',
                      onChanged: (v) {
                        ref.read(provider.notifier).state = [
                          for (final e in items)
                            if (e.id == item.id)
                              AiActionDraft(
                                e.id,
                                e.title,
                                e.detail,
                                e.origin,
                                done: v ?? false,
                              )
                            else
                              e,
                        ];
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: item.done
                                ? CuteTokens.muted
                                : CuteTokens.ink,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.detail,
                  style: const TextStyle(color: CuteTokens.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(item.origin, color: _mint),
                    TextButton.icon(
                      onPressed: () => editAction(item),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('编辑'),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(provider.notifier).state = items
                            .where((e) => e.id != item.id)
                            .toList();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('已移除行动'),
                            action: SnackBarAction(
                              label: '撤销',
                              onPressed: () {
                                final current = ref.read(provider);
                                if (!current.any((e) => e.id == item.id)) {
                                  ref.read(provider.notifier).state = [
                                    ...current,
                                    item,
                                  ];
                                }
                              },
                            ),
                          ),
                        );
                      },
                      child: const Text('移除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      card(
        '下一步，从一件小事开始',
        '完成后把过程和成果记入日志，让下一次发展分析更了解你。',
        footer: OutlinedButton.icon(
          onPressed: () => context.go('/logs'),
          icon: const Icon(Icons.edit_note),
          label: const Text('去记录工作成果'),
        ),
      ),
    ];
  }
}
