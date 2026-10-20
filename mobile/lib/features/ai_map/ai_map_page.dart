import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/sunny_widgets.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'server_ai_page.dart';

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
      builder: (dialogContext) => TuantuanDialog(
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
          SunnyPrimaryButton(
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

  void openSources(Record item) => showTuantuanBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => TuantuanSheet(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '建议依据',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(AppConfig.mock ? '预设建议与显式来源链接，用于流程演示。' : '请核对来源后再作决策。'),
                Text(
                  '生成时间：${_generated(item)}',
                  style: const TextStyle(color: CuteTokens.muted),
                ),
                for (final path in _sourcePaths(item))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      path.contains('/logs/') ? '来源 · 工作日志' : '来源 · 工作任务',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(sheet);
                      context.push(path);
                    },
                  ),
                if (_sourcePaths(item).isEmpty)
                  const Text('缺少来源，建议尚未证实，不能据此创建任务。'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  List<String> _sourcePaths(Record item) =>
      (item.fields['sources'] as List? ?? [])
          .map((e) => '$e')
          .where((e) => RegExp(r'^/item/(logs|tasks)/[^/]+$').hasMatch(e))
          .toList();
  String _generated(Record item) {
    final d = DateTime.tryParse('${item.fields['createdAt']}')?.toLocal();
    return d == null
        ? '未提供'
        : '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.mock) {
      final session = ref.watch(sessionProvider);
      return ServerAiPage(
        key: ValueKey(
          '${session.id}:${Object.hash(session.token, session.expiresAt)}',
        ),
      );
    }
    final user = ref.watch(sessionProvider),
        scenario = ref.watch(scenarioProvider);
    final items =
        AppConfig.mock && user.active && scenario == DemoScenario.normal
        ? ref.watch(recordsProvider('ai-maps'))
        : const AsyncValue<PageResult>.data(PageResult([]));
    final scope = !company
        ? '个人发展'
        : switch (user.role) {
            UserRole.admin || UserRole.founder => '公司走向',
            UserRole.director => '部门走向',
            _ => '团队走向',
          };
    Widget content;
    if (!AppConfig.mock) {
      content = const EmptyIllustration(
        title: '分析服务待接入',
        subtitle: '连接服务后展示带来源的建议，当前不生成实时建议。',
      );
    } else if (!user.active || scenario == DemoScenario.forbidden) {
      content = const EmptyIllustration(
        showCharacter: false,
        title: '暂无分析访问权限',
        subtitle: '请确认账号授权范围',
      );
    } else if (scenario == DemoScenario.offline) {
      content = ErrorPanel(
        '分析暂时无法加载，请恢复网络后重试',
        retry: () => ref.invalidate(recordsProvider('ai-maps')),
      );
    } else {
      content = items.when(
        loading: () => const LoadingSkeleton(),
        error: (e, _) => ErrorPanel(
          '$e',
          retry: () => ref.invalidate(recordsProvider('ai-maps')),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return EmptyIllustration(
              title: '从第一份工作记录开始',
              subtitle: '数据不足时不生成建议',
              action: TextButton(
                onPressed: () => context.go('/logs'),
                child: const Text('去写日志'),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SunnyWelcome(
                pose: BuddyPose.explaining,
                title: '把下一步想清楚',
                subtitle: '先看建议，再核对来源',
                color: Color(0xFFF1E7FF),
              ),
              const SizedBox(height: 12),
              Text(
                page.items.length >= 3 ? '今天优先处理的三件事' : '建议先处理',
                style: const TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${AppConfig.mock ? '预设演示 · ' : ''}${_generated(page.items.first)} · $scope',
                style: const TextStyle(fontSize: 12, color: CuteTokens.muted),
              ),
              const SizedBox(height: 12),
              for (final (i, item) in page.items.take(3).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PaperSurface(
                    skin: TuantuanAssets.surfaces[['warm', 'blue', 'warm'][i]],
                    color: [
                      SunnyPalette.orange,
                      SunnyPalette.blue,
                      SunnyPalette.primaryContainer,
                    ][i],
                    texture: TuantuanAssets
                        .textures[['warmSparkle', 'paper', 'warmSparkle'][i]],
                    cornerDecoration:
                        TuantuanAssets.cardCorners[['warm', 'blue', 'warm'][i]],
                    onTap: () => openSources(item),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              TuantuanArt(
                                TuantuanAssets.aiAssets[[
                                  'priority',
                                  'sources',
                                  'confirm',
                                ][i]]!,
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: CircleAvatar(
                                  radius: 9,
                                  backgroundColor: [
                                    const Color(0xFFFFE5D2),
                                    CuteTokens.blue,
                                    SunnyPalette.primaryContainer,
                                  ][i],
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: CuteTokens.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item.fields['body'] ?? item.subtitle}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CuteTokens.muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '来源 ${_sourcePaths(item).length} 条 · 点击查看',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7746A5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  for (final (i, label) in ['发展分析', '堵点风险', '行动规划'].indexed)
                    TextButton(
                      onPressed: () => setState(() => tab = i),
                      style: TextButton.styleFrom(
                        foregroundColor: tab == i
                            ? const Color(0xFFA7460E)
                            : CuteTokens.muted,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: tab == i
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                ],
              ),
              PaperSurface(
                skin: TuantuanAssets.metric,
                color: const Color(0xFFFFF0DA),
                onTap: () => context.push('/ai/graph'),
                child: const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '打开工作关系图',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '目标、来源与行动的连接',
                            style: TextStyle(
                              fontSize: 12,
                              color: CuteTokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TuantuanArt(
                      '${TuantuanAssets.newPack}/ai/relation_map.png',
                      width: 50,
                      height: 50,
                    ),
                    Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (tab == 0) ...[
                const Text(
                  '方向分析 · 待验证',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  company
                      ? '把相似交付整理为可复用方法，先以一个项目验证。经营方向仍需客户与业务数据支持。'
                      : '梳理已有工作中的能力积累，选择范围明确的小需求，实践从评审到验收的完整闭环。',
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => openSources(page.items.first),
                  child: const Text('查看分析依据'),
                ),
                OutlinedButton(
                  onPressed: () => addAction(
                    company
                        ? const AiActionDraft(
                            'reuse',
                            '梳理一套可复用的交付模板',
                            '先用一个项目验证复用价值。',
                            '管理范围',
                          )
                        : const AiActionDraft(
                            'growth',
                            '独立推进一次小型需求评审',
                            '确认分工、验收与复盘。',
                            '个人发展',
                          ),
                  ),
                  child: const Text('加入行动规划'),
                ),
              ],
              if (tab == 1) ...[
                const Text(
                  '规则风险与推测分开阅读',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ref
                    .watch(recordsProvider('tasks'))
                    .when(
                      loading: () => const SunnyLoadingIndicator(),
                      error: (e, _) => Text('$e'),
                      data: (p) {
                        final overdue = p.items.where((r) {
                          final d = DateTime.tryParse(
                            '${r.fields['deadline']}',
                          );
                          return d != null &&
                              d.isBefore(DateTime.now()) &&
                              ![
                                '已验收',
                                '已归档',
                                '已撤回',
                              ].contains(r.fields['status']);
                        }).toList();
                        return Text(
                          '按期限识别：${overdue.length} 项尚未结束的逾期任务；需结合实际情况确认。',
                        );
                      },
                    ),
                const Divider(height: 24),
                const Text('推测 · 前置依赖未确认可能影响联调，现有记录不足以判断实际影响。'),
                TextButton(
                  onPressed: () => openSources(page.items.first),
                  child: const Text('查看依据与相关任务'),
                ),
                OutlinedButton(
                  onPressed: () => addAction(
                    const AiActionDraft(
                      'dependency',
                      '确认交互稿中的关键依赖',
                      '核对接口、负责人和验收边界。',
                      '解决堵点',
                    ),
                  ),
                  child: const Text('安排解决行动'),
                ),
              ],
              if (tab == 2) ...planning(),
              const SizedBox(height: 16),
              const DemoLabel(),
            ],
          );
        },
      );
    }
    return PageFrame(
      title: 'AI地图',
      showTitle: false,
      child: PageBody(
        controller: scroll,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TuantuanFilterChip(
                      label: const Text('个人发展'),
                      selected: !company,
                      onSelected: (_) => setState(() => company = false),
                    ),
                    if (user.manager)
                      TuantuanFilterChip(
                        label: Text(switch (user.role) {
                          UserRole.admin || UserRole.founder => '公司走向',
                          UserRole.director => '部门走向',
                          _ => '团队走向',
                        }),
                        selected: company,
                        onSelected: (_) => setState(() => company = true),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => context.push('/ai-usage'),
                style: TextButton.styleFrom(
                  backgroundColor: SunnyPalette.orange,
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text(
                  '建议草稿',
                  style: TextStyle(color: SunnyPalette.ink, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  List<Widget> planning() {
    final provider = aiActionDraftsProvider(ref.watch(sessionProvider).id),
        items = ref.watch(
          aiActionDraftsProvider(ref.watch(sessionProvider).id),
        );
    return [
      Row(
        children: [
          const Expanded(
            child: Text(
              '个人行动草稿',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => editAction(null),
            child: const Text('添加行动'),
          ),
        ],
      ),
      const Text(
        '当前会话内保留，操作不会派发正式任务',
        style: TextStyle(fontSize: 12, color: CuteTokens.muted),
      ),
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无行动，可添加或从建议加入'),
        ),
      for (final item in items)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: item.done,
                  semanticLabel: '完成：${item.title}',
                  onChanged: (v) => ref.read(provider.notifier).state = [
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
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: item.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(
                item.detail,
                style: const TextStyle(color: CuteTokens.muted),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => editAction(item),
                  child: const Text('编辑'),
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
                          onPressed: () => ref.read(provider.notifier).state = [
                            ...ref.read(provider),
                            item,
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('移除'),
                ),
              ],
            ),
            const Divider(),
          ],
        ),
    ];
  }
}
