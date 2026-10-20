import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'task_management_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final draft = ref.watch(todayDraftProvider(user.id));
    final unread = ref
        .watch(recordsProvider('notifications'))
        .valueOrNull
        ?.items
        .where((r) => r.fields['read'] != true)
        .length;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    const specs = [
      ('公司重点', 'dashboard/company', 'mindmap', 'blue', SunnyPalette.blue),
      ('公司任务', 'tasks', 'task', 'warm', SunnyPalette.orange),
      ('个人重点', 'dashboard/personal', 'ai', 'lavender', SunnyPalette.purple),
      ('个人日志', 'logs', 'log', 'warm', SunnyPalette.primaryContainer),
    ];
    return PageFrame(
      title: '导图',
      showTitle: false,
      child: LayoutBuilder(
        builder: (context, viewport) {
          final tileHeight = math.max(
            240 * scale,
            (viewport.maxHeight - 134) / 2,
          );
          Widget tile(int index) {
            final spec = specs[index];
            final state = index >= 2
                ? ref.watch(memberRecordsProvider((spec.$2, user.id)))
                : ref.watch(recordsProvider(spec.$2));
            void open() => index == 3
                ? context.go('/logs')
                : index == 1
                ? context.push('/tasks/received')
                : openList(context, spec.$2);
            return SizedBox(
              height: tileHeight,
              child: PaperSurface(
                key: ValueKey('dashboard-tile:$index'),
                skin: TuantuanAssets.surfaces[spec.$4],
                decorated: true,
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                onTap: open,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DogBackground(
                      index: const [2, 3, 6, 7][index],
                      opacity: 1,
                      fit: BoxFit.contain,
                    ),
                    Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: spec.$5.withValues(alpha: .28),
                          ),
                          child: DogAvatar(
                            index: const [0, 7, 10, 15][index],
                            size: 37,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            spec.$1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: state.when(
                        loading: () =>
                            const Center(child: SunnyLoadingIndicator()),
                        error: (_, _) => TextButton(
                          onPressed: () =>
                              ref.invalidate(recordsProvider(spec.$2)),
                          child: const Text('加载失败，重试'),
                        ),
                        data: (page) {
                          final items =
                              (index == 1
                                      ? page.items
                                            .where(
                                              (r) => isReceivedTask(r, user.id),
                                            )
                                            .take(10)
                                      : page.items)
                                  .toList();
                          final titles = [
                            if (index == 3 && draft.valueOrNull != null)
                              '本机草稿 · 继续写',
                            ...items.map((r) => r.title),
                          ];
                          if (titles.isEmpty) {
                            return Text(
                              draft.hasError && index == 3
                                  ? '草稿暂不可用，请重试'
                                  : '暂无记录',
                            );
                          }
                          return LayoutBuilder(
                            builder: (context, space) {
                              final count = math.max(
                                1,
                                ((space.maxHeight + 8 * scale) /
                                        (50 * scale))
                                    .floor(),
                              );
                              final visibleTitles = titles.take(count).toList();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < visibleTitles.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 8),
                                    SizedBox(
                                      height: 42 * scale,
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFD98254),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              visibleTitles[i],
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: open,
                              child: const Text('查看全部 →'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                    ),
                  ],
                ),
              ),
            );
          }

          return PageBody(
            bottomPadding: 12,
            children: [
              PaperSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                color: DogBrandPalette.surface,
                borderColor: DogBrandPalette.line,
                child: Row(
                  children: [
                    const DogPose(index: DogAssets.sitting, size: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '你好，${user.name}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: DogBrandPalette.ink),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '把今天的事情，慢慢理清。',
                            style: TextStyle(
                              fontSize: 12,
                              color: DogBrandPalette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '消息 ${unread ?? '—'}',
                      onPressed: () => openList(context, 'notifications'),
                      icon: Badge(
                        isLabelVisible: unread != null && unread > 0,
                        label: Text('${unread ?? 0}'),
                        child: const Icon(Icons.notifications_none_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (var row = 0; row < 2; row++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tile(row * 2)),
                    const SizedBox(width: 12),
                    Expanded(child: tile(row * 2 + 1)),
                  ],
                ),
                if (row == 0) const SizedBox(height: 12),
              ],
              const DemoLabel(),
            ],
          );
        },
      ),
    );
  }
}
