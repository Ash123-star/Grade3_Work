import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../shared/widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    return PageFrame(
      title: '工作导图',
      actions: [
        IconButton(
          tooltip: '消息中心',
          onPressed: () => openList(context, 'notifications'),
          icon: const Icon(Icons.notifications_none),
        ),
      ],
      fab: user.manager && user.dispatch
          ? FloatingActionButton(
              heroTag: 'dashboard-dispatch',
              tooltip: '派发任务',
              onPressed: () => openForm(context, 'dispatch'),
              child: const Icon(Icons.add),
            )
          : null,
      child: PageBody(
        children: [
          const DemoLabel(),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '你好，${user.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '把今天的事情，一件件做好。',
                      style: TextStyle(color: CuteTokens.muted),
                    ),
                  ],
                ),
              ),
              const CuteArt('1F680', size: 76),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const StatusPill('产品部 · 体验团队'),
              StatusPill(user.role.label, color: CuteTokens.yellow),
            ],
          ),
          const SectionHeader('我的工作空间'),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              final specs = [
                ('公司重点', '1F31F', CuteTokens.yellow, 'dashboard/company'),
                ('公司任务', '1F680', CuteTokens.blue, 'tasks'),
                (
                  '个人重点',
                  '1F331',
                  const Color(0xFFE2F4EC),
                  'dashboard/personal',
                ),
                ('个人日志', '1F4D2', const Color(0xFFFFE8E1), 'logs'),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: specs
                    .map(
                      (spec) => SizedBox(
                        width: width,
                        child: CuteCard(
                          color: spec.$3,
                          onTap: () => openList(context, spec.$4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CuteArt(spec.$2, size: 44),
                              const SizedBox(height: 12),
                              Text(
                                spec.$1,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              ref
                                  .watch(recordsProvider(spec.$4))
                                  .when(
                                    data: (page) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: page.items.isEmpty
                                          ? [const Text('暂无记录')]
                                          : page.items
                                                .take(2)
                                                .map(
                                                  (e) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 6,
                                                        ),
                                                    child: Text(
                                                      e.title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                    ),
                                    error: (e, s) => const Text('暂时不可用'),
                                    loading: () =>
                                        const LinearProgressIndicator(),
                                  ),
                              const SizedBox(height: 8),
                              const Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '查看全部',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SectionHeader('今天的安排', action: '时间视图', onAction: null),
          const RecordList('tasks', limit: 2),
          if (user.manager)
            TextButton.icon(
              onPressed: () => openForm(context, 'publish'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('管理公司展示项'),
            ),
        ],
      ),
    );
  }
}

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: '工作日志',
    actions: [
      IconButton(
        tooltip: '周报与月报',
        onPressed: () => context.push('/report'),
        icon: const Icon(Icons.summarize_outlined),
      ),
    ],
    fab: FloatingActionButton(
      heroTag: 'logs-edit',
      tooltip: '写日志',
      onPressed: () => openForm(context, 'log-edit'),
      child: const Icon(Icons.edit_outlined),
    ),
    child: PageBody(
      children: [
        const DemoLabel(),
        const DateControls(),
        if (ref.watch(sessionProvider).manager)
          OutlinedButton.icon(
            onPressed: () => openList(context, 'logs/subordinates'),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('下属日志'),
          ),
        const SectionHeader('我的日志'),
        const RecordList('logs', dated: true),
        TextButton.icon(
          onPressed: () => context.push('/conflict'),
          icon: const Icon(Icons.history),
          label: const Text('草稿与同步记录'),
        ),
      ],
    ),
  );
}

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});
  @override
  Widget build(BuildContext context) => const PageFrame(
    title: '时间视图',
    child: PageBody(
      children: [
        DemoLabel(),
        DateControls(),
        SectionHeader('任务安排'),
        RecordList('tasks', dated: true),
        SectionHeader('工作日志'),
        RecordList('logs', dated: true),
      ],
    ),
  );
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    Widget link(String title, IconData icon, VoidCallback tap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: tap,
    );
    return PageFrame(
      title: '我的',
      actions: [
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      child: PageBody(
        children: [
          const DemoLabel(),
          const CuteArt('1F331', size: 80),
          const SizedBox(height: 16),
          Center(
            child: Text(
              user.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 6),
          Center(child: Text('产品部 · 体验团队 · ${user.role.label}')),
          const SizedBox(height: 8),
          const Center(child: Text('认真工作，也记得好好生活。')),
          TextButton(
            onPressed: () => openForm(context, 'profile-edit'),
            child: const Text('编辑个人资料'),
          ),
          const Divider(),
          link('我的任务', Icons.task_alt, () => openList(context, 'tasks')),
          link(
            '个人重点',
            Icons.star_border,
            () => openList(context, 'dashboard/personal'),
          ),
          link(
            '消息中心',
            Icons.notifications_none,
            () => openList(context, 'notifications'),
          ),
          if (user.manager) ...[
            const SectionHeader('团队管理'),
            link(
              '审批',
              Icons.fact_check_outlined,
              () => openList(context, 'reviews'),
            ),
            link(
              '组织与成员',
              Icons.account_tree_outlined,
              () => openList(context, 'organization'),
            ),
            link('经营分析', Icons.bar_chart, () => openList(context, 'analytics')),
          ],
          if (user.administrator) ...[
            link(
              '组织与权限设置',
              Icons.admin_panel_settings_outlined,
              () => context.push('/admin'),
            ),
            link('审计记录', Icons.manage_search, () => openList(context, 'audit')),
          ],
          const SectionHeader('工作动态'),
          const RecordList('logs', limit: 2),
        ],
      ),
    );
  }
}

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});
  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  bool graph = false, generating = false;
  int generation = 0;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'AI 地图',
    child: PageBody(
      children: [
        const DemoLabel(),
        const Row(
          children: [
            CuteArt('1F916', size: 72),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                '今天，先做好这三件事。',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.view_list_outlined),
              label: Text('行动'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.hub_outlined),
              label: Text('关系图'),
            ),
          ],
          selected: {graph},
          onSelectionChanged: (s) => setState(() => graph = s.first),
        ),
        const SizedBox(height: 20),
        if (graph)
          SizedBox(
            height: 320,
            child: InteractiveViewer(
              minScale: .6,
              maxScale: 2,
              child: Column(
                children: [
                  ActionChip(
                    label: const Text('本周目标'),
                    avatar: const Icon(Icons.flag_outlined),
                    onPressed: () => openItem(context, 'ai-maps', '1'),
                  ),
                  const Expanded(child: VerticalDivider()),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ActionChip(
                        label: const Text('任务'),
                        onPressed: () => openItem(context, 'tasks', '1'),
                      ),
                      ActionChip(
                        label: const Text('阻碍'),
                        onPressed: () => openItem(context, 'ai-maps', '2'),
                      ),
                    ],
                  ),
                  const Expanded(child: VerticalDivider()),
                  ActionChip(
                    label: const Text('工作日志'),
                    onPressed: () => openItem(context, 'logs', '1'),
                  ),
                ],
              ),
            ),
          )
        else
          const RecordList('ai-maps', limit: 3),
        if (generating) const LinearProgressIndicator(),
        FilledButton.icon(
          onPressed: () async {
            if (generating) {
              generation++;
              setState(() => generating = false);
              return;
            }
            final current = ++generation;
            setState(() => generating = true);
            try {
              await ref
                  .read(repositoryProvider)
                  .execute('ai', const Command('summarize', {}));
              if (!context.mounted || generation != current) return;
              ref.invalidate(recordsProvider('ai-maps'));
              notice(context, '演示建议已更新，发布前请确认来源与内容');
            } catch (e) {
              if (context.mounted && current == generation) {
                notice(context, e.toString());
              }
            }
            if (context.mounted && current == generation) {
              setState(() => generating = false);
            }
          },
          icon: Icon(generating ? Icons.stop : Icons.auto_awesome_outlined),
          label: Text(generating ? '取消生成' : '整理今日工作'),
        ),
        TextButton(
          onPressed: () => context.push('/ai-usage'),
          child: const Text('用量与来源'),
        ),
      ],
    ),
  );
}
