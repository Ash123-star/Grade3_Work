import 'dart:math' as math;

import 'package:cute_ui/cute_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../core/providers.dart';
import '../shared/widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final canDispatch = user.manager && user.dispatch;
    const panels = [
      (
        '公司重点',
        '1F31F',
        CuteTokens.yellow,
        'dashboard/company',
        Color(0xFF845600),
        Color(0xFF66562F),
      ),
      (
        '公司任务',
        '1F680',
        CuteTokens.blue,
        'tasks',
        Color(0xFF205D9A),
        Color(0xFF455F78),
      ),
      (
        '个人重点',
        '1F331',
        Color(0xFFE2F4EC),
        'dashboard/personal',
        Color(0xFF176A50),
        Color(0xFF456859),
      ),
      (
        '个人日志',
        '1F4D2',
        Color(0xFFFFE8E1),
        'logs',
        Color(0xFFA34535),
        Color(0xFF78534B),
      ),
    ];

    return PageFrame(
      title: '工作导图',
      actions: [
        if (user.manager)
          IconButton(
            tooltip: '管理公司展示项',
            onPressed: () => openForm(context, 'publish'),
            icon: const Icon(Icons.campaign_outlined),
          ),
        IconButton(
          tooltip: '消息中心',
          onPressed: () => openList(context, 'notifications'),
          icon: Badge(
            label: Text(
              '${ref.watch(recordsProvider('notifications')).valueOrNull?.items.where((r) => r.fields['read'] != true).length ?? 0}',
            ),
            isLabelVisible:
                (ref
                        .watch(recordsProvider('notifications'))
                        .valueOrNull
                        ?.items
                        .where((r) => r.fields['read'] != true)
                        .length ??
                    0) >
                0,
            child: const Icon(Icons.notifications_none),
          ),
        ),
      ],
      fab: canDispatch
          ? FloatingActionButton(
              heroTag: 'dashboard-dispatch',
              tooltip: '派发任务',
              onPressed: () => openForm(context, 'dispatch'),
              child: const Icon(Icons.add),
            )
          : null,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final bottom = canDispatch ? 72.0 : 12.0;
              // Keep headers and at least one content row usable on short screens.
              final minimumHeight =
                  (AppConfig.mock ? 38 : 0) +
                  76 * scale +
                  2 * (112 + 32 * scale) +
                  12 +
                  bottom +
                  8;
              final content = SizedBox(
                height: math.max(constraints.maxHeight, minimumHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '把今天的事情，一件件做好。',
                                  style: TextStyle(color: CuteTokens.muted),
                                ),
                              ],
                            ),
                          ),
                          const CuteArt('1F680', size: 56),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var row = 0; row < 2; row++) ...[
                        if (row > 0) const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var col = 0; col < 2; col++) ...[
                                if (col > 0) const SizedBox(width: 12),
                                Expanded(
                                  child: _DashboardPanel(
                                    title: panels[row * 2 + col].$1,
                                    art: panels[row * 2 + col].$2,
                                    color: panels[row * 2 + col].$3,
                                    resource: panels[row * 2 + col].$4,
                                    titleColor: panels[row * 2 + col].$5,
                                    textColor: panels[row * 2 + col].$6,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
              return constraints.maxHeight < minimumHeight
                  ? SingleChildScrollView(child: content)
                  : content;
            },
          ),
        ),
      ),
    );
  }
}

class _DashboardPanel extends ConsumerWidget {
  const _DashboardPanel({
    required this.title,
    required this.art,
    required this.color,
    required this.resource,
    required this.titleColor,
    required this.textColor,
  });

  final String title, art, resource;
  final Color color, titleColor, textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CuteCard(
    color: color,
    onTap: () => openList(context, resource),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CuteArt(art, size: 28),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: titleColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ref
              .watch(recordsProvider(resource))
              .when(
                data: (page) => page.items.isEmpty
                    ? const Text('暂无记录')
                    : ListView.separated(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: page.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) => Text(
                          page.items[index].title,
                          style: TextStyle(color: textColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                error: (e, s) => const Text('暂时不可用'),
                loading: () => const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
              ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Expanded(child: Text('查看全部', style: TextStyle(fontSize: 12))),
            Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ],
    ),
  );
}
