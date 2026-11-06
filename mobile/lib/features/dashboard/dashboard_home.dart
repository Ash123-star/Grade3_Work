import 'dart:math' as math;
import '../home/home_summary_card.dart';
import '../../theme/home_paper_theme.dart';
import '../../shared/calendar/civil_date.dart';
import '../personal_todos/presentation/daily_todos_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Theme(data: homePaperTheme(context), child: const _HomeContent());
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final paper = HomePaperTokens.of(context);
    final date = shanghaiToday();
    final unread = user.canReadBusiness
        ? ref
                  .watch(recordsProvider('notifications'))
                  .valueOrNull
                  ?.items
                  .any((item) => item.fields['read'] != true) ==
              true
        : false;
    return Scaffold(
      backgroundColor: paper.canvas,
      body: SafeArea(
        bottom: false,
        child: TuantuanPaperBackdrop(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: LayoutBuilder(
                builder: (context, viewport) {
                  final narrow = viewport.maxWidth < 375;
                  final compact = viewport.maxWidth < 340;
                  final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
                  final cards = [
                    HomeSummaryCard(
                      title: '事件纪',
                      resource: 'dashboard/company',
                      onAll: () => _showFocusCollection(
                        context,
                        ref,
                        title: '事件纪',
                        resource: 'dashboard/company',
                      ),
                      onItem: (item) => _showCompanyItem(context, ref, item),
                    ),
                    HomeSummaryCard(
                      title: '任务看板',
                      resource: 'tasks/received-card',
                      onAll: () => context.push('/tasks/received'),
                      onItem: (item) => openItem(context, 'tasks', item.id),
                    ),
                  ];
                  return ListView(
                    key: const PageStorageKey('home-scroll'),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          narrow ? 12 : 16,
                          24,
                          narrow ? 12 : 16,
                          18,
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: SunnyPalette.primaryContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: SunshineMascot(size: compact ? 44 : 52),
                            ),
                            SizedBox(width: compact ? 8 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '你好，${user.name}',
                                    style: paper.heading(
                                      compact ? 23 : 25,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${date.month}月${date.day}日 · 星期${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}',
                                    style: paper.body(12, color: paper.muted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: HomePaperTokens.messageSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                                side: const BorderSide(
                                  color: HomePaperTokens.messageEdge,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: IconButton(
                                        tooltip: unread ? '消息，有未读消息' : '消息',
                                        onPressed: () =>
                                            openList(context, 'notifications'),
                                        icon: const TuantuanIcon(
                                          'notification',
                                          size: 25,
                                        ),
                                      ),
                                    ),
                                    if (unread)
                                      Positioned(
                                        right: 10,
                                        top: 9,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: HomePaperTokens.unread,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: HomePaperTokens
                                                    .messageSurface,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user.canReadBusiness)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: narrow ? 10 : 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (compact || large)
                                Column(
                                  children: [
                                    cards[0],
                                    const SizedBox(height: 10),
                                    cards[1],
                                  ],
                                )
                              else
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: cards[0]),
                                      SizedBox(width: narrow ? 8 : 10),
                                      Expanded(child: cards[1]),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 24),
                              DailyTodosSection(key: ObjectKey(user)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showCompanyItem(
  BuildContext context,
  WidgetRef ref,
  Record item,
) async {
  final openedSession = ref.read(sessionProvider);
  final colors = Theme.of(context).colorScheme;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭公司重点详情',
    barrierColor: colors.scrim.withValues(alpha: .72),
    transitionDuration: reduceMotion ? Duration.zero : WorkMotion.overlay,
    pageBuilder: (dialogContext, _, _) => Consumer(
      builder: (dialogContext, dialogRef, _) {
        final session = dialogRef.watch(sessionProvider);
        final accessChanged =
            session.id != openedSession.id ||
            session.token != openedSession.token ||
            !session.canReadBusiness;
        final records = accessChanged
            ? null
            : dialogRef.watch(recordsProvider('dashboard/company'));
        final current = records != null && !records.isLoading
            ? records.valueOrNull?.items
                  .where((record) => record.id == item.id)
                  .firstOrNull
            : null;
        final Widget body;
        if (accessChanged) {
          body = const Center(child: Text('账号权限已变化，详情已清除'));
        } else {
          body = records!.when(
            loading: () => const Center(child: SunnyLoadingIndicator()),
            error: (error, _) => RecordFailure(
              error,
              retry: () =>
                  dialogRef.invalidate(recordsProvider('dashboard/company')),
            ),
            data: (_) {
              if (current == null) {
                return const Center(child: Text('该内容已不可用'));
              }
              final rawBody =
                  current.fields['text'] ??
                  current.fields['body'] ??
                  current.fields['content'];
              final content = rawBody is Map
                  ? '${rawBody['text'] ?? rawBody['content'] ?? rawBody['正文'] ?? ''}'
                  : '${rawBody ?? ''}';
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  content.trim().isEmpty ? '暂无可展示内容' : content,
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodyLarge?.copyWith(height: 1.65),
                ),
              );
            },
          );
        }
        return Center(
          child: SafeArea(
            child: SizedBox(
              width: math.min(
                MediaQuery.sizeOf(dialogContext).width - 32,
                560.0,
              ),
              height: math.min(
                MediaQuery.sizeOf(dialogContext).height * .72,
                640.0,
              ),
              child: PaperSurface(
                color: colors.surface,
                borderColor: colors.outlineVariant,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              current?.title ?? '',
                              style: Theme.of(
                                dialogContext,
                              ).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

Future<void> _showFocusCollection(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String resource,
  String? ownerId,
}) async {
  await showTuantuanFocusSheet<void>(
    context: context,
    title: title,
    floatingActionButton: ownerId == null
        ? null
        : FloatingActionButton.small(
            tooltip: '新增个人重点',
            onPressed: () async {
              await _showPersonalItem(context, ref);
              if (context.mounted) {
                ref.invalidate(memberRecordsProvider((resource, ownerId)));
              }
            },
            child: const Icon(Icons.add_rounded),
          ),
    child: Consumer(
      builder: (context, dialogRef, _) {
        final state = ownerId == null
            ? dialogRef.watch(recordsProvider(resource))
            : dialogRef.watch(memberRecordsProvider((resource, ownerId)));
        return state.when(
          loading: () => const Center(child: SunnyLoadingIndicator()),
          error: (error, _) => Center(
            child: RecordFailure(
              error,
              retry: () => ownerId == null
                  ? dialogRef.invalidate(recordsProvider(resource))
                  : dialogRef.invalidate(
                      memberRecordsProvider((resource, ownerId)),
                    ),
            ),
          ),
          data: (page) => page.items.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = page.items[index];
                    final body =
                        '${item.fields['内容'] ?? item.fields['text'] ?? item.fields['body'] ?? ''}'
                            .trim();
                    return InkWell(
                      onTap: () => _showFocusDetail(context, item),
                      onLongPress: ownerId == null
                          ? null
                          : () => _showPersonalItemActions(
                              context,
                              ref,
                              item,
                              collectionResource: resource,
                              ownerId: ownerId,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Icon(
                                resource == 'dashboard/company'
                                    ? Icons.circle
                                    : Icons.radio_button_unchecked_rounded,
                                size: resource == 'dashboard/company' ? 10 : 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      body,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}

Future<void> _showFocusDetail(BuildContext context, Record item) async {
  final rawBody =
      item.fields['内容'] ??
      item.fields['text'] ??
      item.fields['body'] ??
      item.fields['content'];
  final body = rawBody is Map
      ? '${rawBody['text'] ?? rawBody['content'] ?? rawBody['正文'] ?? ''}'.trim()
      : '${rawBody ?? ''}'.trim();
  await showTuantuanFocusSheet<void>(
    context: context,
    title: item.title,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      child: Text(
        body.isEmpty ? '暂无正文' : body,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
      ),
    ),
  );
}

Future<void> _showPersonalItemActions(
  BuildContext context,
  WidgetRef ref,
  Record item, {
  String collectionResource = 'dashboard/personal',
  String? ownerId,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑'),
            onTap: () => Navigator.pop(sheetContext, 'edit'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(sheetContext).colorScheme.error,
            ),
            title: Text(
              '删除',
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  if (action == 'edit') {
    await _showPersonalItem(context, ref, item);
    if (!context.mounted) return;
    ref.invalidate(
      memberRecordsProvider((collectionResource, ownerId ?? item.ownerId)),
    );
    ref.invalidate(recordsProvider(collectionResource));
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => TuantuanDialog(
      title: const Text('删除这条个人重点？'),
      content: const Text('删除后会从个人重点列表中移除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref
        .read(repositoryProvider)
        .execute(
          collectionResource,
          Command(
            'archive',
            {
              'id': item.id,
              'title': item.title,
              '内容':
                  item.fields['内容'] ??
                  item.fields['text'] ??
                  item.fields['body'] ??
                  '',
              '排序位置': item.fields['排序位置'] ?? item.fields['position'] ?? 0,
              'pinned': item.fields['pinned'] ?? false,
            },
            version: item.version,
            idempotencyKey: '${item.id}:${item.version}:archive',
          ),
        );
    refreshBusiness(ref);
    ref.invalidate(
      memberRecordsProvider((collectionResource, ownerId ?? item.ownerId)),
    );
    ref.invalidate(recordsProvider(collectionResource));
  } catch (error) {
    if (context.mounted) {
      notice(context, '删除失败：$error', tone: NoticeTone.error);
    }
  }
}

Future<void> _showPersonalItem(
  BuildContext context,
  WidgetRef ref, [
  Record? item,
]) async {
  final title = TextEditingController(text: item?.title ?? '');
  final content = TextEditingController(
    text:
        '${item?.fields['内容'] ?? item?.fields['text'] ?? item?.fields['body'] ?? ''}',
  );
  final colors = Theme.of(context).colorScheme;
  var saving = false;
  var pinned = item?.fields['pinned'] == true;
  String? error;
  final saved = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭个人重点编辑',
    barrierColor: colors.scrim.withValues(alpha: .72),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : WorkMotion.overlay,
    pageBuilder: (dialogContext, _, _) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AnimatedPadding(
        duration: MediaQuery.disableAnimationsOf(dialogContext)
            ? Duration.zero
            : WorkMotion.overlay,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: Center(
          child: SafeArea(
            child: SizedBox(
              width: math.min(
                MediaQuery.sizeOf(dialogContext).width - 32,
                560.0,
              ),
              height: math.max(
                160.0,
                math.min(
                  (MediaQuery.sizeOf(dialogContext).height -
                          MediaQuery.viewInsetsOf(dialogContext).bottom -
                          32) *
                      .92,
                  640.0,
                ),
              ),
              child: PaperSurface(
                color: colors.surface,
                borderColor: colors.outlineVariant,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: title,
                              enabled: !saving,
                              maxLength: 80,
                              decoration: const InputDecoration(
                                hintText: '标题',
                                border: InputBorder.none,
                                counterText: '',
                              ),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (item != null)
                            IconButton(
                              tooltip: '归档个人重点',
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        saving = true;
                                        error = null;
                                      });
                                      try {
                                        await ref
                                            .read(repositoryProvider)
                                            .execute(
                                              'dashboard/personal',
                                              Command(
                                                'archive',
                                                {'id': item.id},
                                                version: item.version,
                                                idempotencyKey:
                                                    '${item.id}:${item.version}:archive',
                                              ),
                                            );
                                        refreshBusiness(ref);
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext, true);
                                        }
                                      } catch (failure) {
                                        if (dialogContext.mounted) {
                                          setDialogState(() {
                                            saving = false;
                                            error = '$failure';
                                          });
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(dialogContext, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    SwitchListTile.adaptive(
                      value: pinned,
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(() => pinned = value),
                      title: const Text('置顶'),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    Expanded(
                      child: TextField(
                        controller: content,
                        enabled: !saving,
                        maxLength: 10000,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: '写下备忘或工作感悟',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(20),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          error!,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(dialogContext, false),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (title.text.trim().isEmpty ||
                                        content.text.trim().isEmpty) {
                                      setDialogState(() => error = '标题和内容不能为空');
                                      return;
                                    }
                                    setDialogState(() {
                                      saving = true;
                                      error = null;
                                    });
                                    try {
                                      await ref
                                          .read(repositoryProvider)
                                          .execute(
                                            'dashboard/personal',
                                            Command(
                                              'save',
                                              {
                                                if (item != null) 'id': item.id,
                                                'title': title.text.trim(),
                                                '内容': content.text,
                                                '排序位置':
                                                    item?.fields['排序位置'] ??
                                                    item?.fields['position'] ??
                                                    0,
                                                'pinned': pinned,
                                              },
                                              version: item?.version ?? 0,
                                              idempotencyKey: item == null
                                                  ? 'personal-focus:${ref.read(sessionProvider).id}:${DateTime.now().microsecondsSinceEpoch}'
                                                  : '${item.id}:${item.version}:save',
                                            ),
                                          );
                                      refreshBusiness(ref);
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext, true);
                                      }
                                    } catch (failure) {
                                      if (dialogContext.mounted) {
                                        setDialogState(() {
                                          saving = false;
                                          error = '$failure';
                                        });
                                      }
                                    }
                                  },
                            child: Text(saving ? '保存中…' : '保存'),
                          ),
                        ],
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
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: .96, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
  if (saved == true) ref.invalidate(recordsProvider('dashboard/personal'));
  title.dispose();
  content.dispose();
}
