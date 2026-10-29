import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'task_management_page.dart';
import 'diary_composer_sheet.dart';

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
            final resource = index == 1 ? 'tasks/received-card' : spec.$2;
            final state = index >= 2
                ? ref.watch(memberRecordsProvider((spec.$2, user.id)))
                : index == 1
                ? ref.watch(receivedTaskCardProvider)
                : ref.watch(recordsProvider(resource));
            void open() => index == 3
                ? context.go('/logs')
                : index == 1
                ? context.push('/tasks/received')
                : openList(context, spec.$2);
            void continueDiary() => unawaited(
              showDiaryComposer(context, ref, date: DateTime.now()),
            );
            return SizedBox(
              height: tileHeight,
              child: PaperSurface(
                key: ValueKey('dashboard-tile:$index'),
                skin: TuantuanAssets.surfaces[spec.$4],
                decorated: true,
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                onTap: index == 0 || index == 2
                    ? () => _showFocusCollection(
                        context,
                        ref,
                        title: spec.$1,
                        resource: spec.$2,
                        ownerId: index == 2 ? user.id : null,
                      )
                    : index == 3 && draft.valueOrNull != null
                    ? continueDiary
                    : open,
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
                          onPressed: () => index == 1
                              ? ref.invalidate(receivedTaskCardProvider)
                              : ref.invalidate(recordsProvider(resource)),
                          child: const Text('加载失败，重试'),
                        ),
                        data: (page) {
                          final items = (index == 1
                              ? page.items.where(
                                  (r) => isReceivedTask(r, user.id),
                                )
                              : page.items).toList();
                          if (index == 1) {
                            items.sort((a, b) {
                              final aTime = DateTime.tryParse(
                                '${a.fields['dispatchAt'] ?? ''}',
                              );
                              final bTime = DateTime.tryParse(
                                '${b.fields['dispatchAt'] ?? ''}',
                              );
                              if (aTime == null || bTime == null) {
                                if (aTime == null && bTime != null) return 1;
                                if (bTime == null && aTime != null) return -1;
                                return a.id.compareTo(b.id);
                              }
                              final byDispatch = bTime.compareTo(aTime);
                              return byDispatch != 0
                                  ? byDispatch
                                  : a.id.compareTo(b.id);
                            });
                            if (items.length > 10) {
                              items.removeRange(10, items.length);
                            }
                          }
                          final titles = [
                            if (index == 3 && draft.valueOrNull != null)
                              '本机草稿 · 继续写',
                            ...items.map((r) => r.title),
                          ];
                          if (titles.isEmpty) {
                            return Text(
                              draft.hasError && index == 3
                                  ? '草稿暂不可用，请重试'
                                  : index == 1
                                  ? '暂无任务记录'
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
                                      child: index == 0 || index == 2
                                          ? InkWell(
                                              borderRadius: BorderRadius.circular(12),
                                              onTap: () => index == 0
                                                  ? _showCompanyItem(context, ref, items[i])
                                                  : _showFocusDetail(context, items[i]),
                                              onLongPress: index == 2
                                                  ? () => _showPersonalItemActions(
                                                      context,
                                                      ref,
                                                      items[i],
                                                    )
                                                  : null,
                                              child: _FocusPreviewRow(
                                                title: visibleTitles[i],
                                                scale: scale,
                                              ),
                                            )
                                          : _FocusPreviewRow(
                                              title: visibleTitles[i],
                                              scale: scale,
                                                  completed: index == 1 &&
                                                      _isCompletedTask(items[i]),
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
                              onPressed: index == 0 || index == 2
                                  ? () => _showFocusCollection(
                                      context,
                                      ref,
                                      title: spec.$1,
                                      resource: spec.$2,
                                      ownerId: index == 2 ? user.id : null,
                                    )
                                  : open,
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

class _FocusPreviewRow extends StatelessWidget {
  const _FocusPreviewRow({
    required this.title,
    required this.scale,
    this.completed = false,
  });
  final String title;
  final double scale;
  final bool completed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: completed
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: completed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
              decoration: completed ? TextDecoration.lineThrough : null,
              decorationColor: completed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

bool _isCompletedTask(Record item) {
  const completed = {'已验收', '已归档', 'ACCEPTED', 'ARCHIVED'};
  return completed.contains('${item.fields['status']}'.toUpperCase()) ||
      completed.contains('${item.fields['phase']}'.toUpperCase());
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
              retry: () => dialogRef.invalidate(
                recordsProvider('dashboard/company'),
              ),
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
                  style: Theme.of(dialogContext)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.65),
                ),
              );
            },
          );
        }
        return Center(
          child: SafeArea(
            child: SizedBox(
              width: math.min(MediaQuery.sizeOf(dialogContext).width - 32, 560.0),
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
                              style: Theme.of(dialogContext).textTheme.titleLarge,
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
          error: (error, _) => Center(child: RecordFailure(
            error,
            retry: () => ownerId == null
                ? dialogRef.invalidate(recordsProvider(resource))
                : dialogRef.invalidate(memberRecordsProvider((resource, ownerId))),
          )),
          data: (page) => page.items.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = page.items[index];
                    final body = '${item.fields['内容'] ?? item.fields['text'] ?? item.fields['body'] ?? ''}'.trim();
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
                                Icons.radio_button_unchecked_rounded,
                                size: 18,
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
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      body,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final rawBody = item.fields['内容'] ??
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
    ref.invalidate(memberRecordsProvider((collectionResource, ownerId ?? item.ownerId)));
    ref.invalidate(recordsProvider(collectionResource));
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
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
    await ref.read(repositoryProvider).execute(
      collectionResource,
      Command(
        'archive',
        {
          'id': item.id,
          'title': item.title,
          '内容': item.fields['内容'] ?? item.fields['text'] ?? item.fields['body'] ?? '',
          '排序位置': item.fields['排序位置'] ?? item.fields['position'] ?? 0,
          'pinned': item.fields['pinned'] ?? false,
        },
        version: item.version,
        idempotencyKey: '${item.id}:${item.version}:archive',
      ),
    );
    refreshBusiness(ref);
    ref.invalidate(memberRecordsProvider((collectionResource, ownerId ?? item.ownerId)));
    ref.invalidate(recordsProvider(collectionResource));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
    text: '${item?.fields['内容'] ?? item?.fields['text'] ?? item?.fields['body'] ?? ''}',
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
            width: math.min(MediaQuery.sizeOf(dialogContext).width - 32, 560.0),
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item != null)
                          IconButton(
                            tooltip: '归档个人重点',
                            onPressed: saving
                                ? null
                                : () async {
                                    setDialogState(() { saving = true; error = null; });
                                    try {
                                      await ref.read(repositoryProvider).execute(
                                        'dashboard/personal',
                                        Command(
                                          'archive',
                                          {'id': item.id},
                                          version: item.version,
                                          idempotencyKey: '${item.id}:${item.version}:archive',
                                        ),
                                      );
                                      refreshBusiness(ref);
                                      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                                    } catch (failure) {
                                      if (dialogContext.mounted) {
                                        setDialogState(() { saving = false; error = '$failure'; });
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.archive_outlined),
                          ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  SwitchListTile.adaptive(
                    value: pinned,
                    onChanged: saving ? null : (value) => setDialogState(() => pinned = value),
                    title: const Text('置顶'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
                      child: Text(error!, style: TextStyle(color: colors.error)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
                                    setDialogState(() => error = '标题和内容不能为空');
                                    return;
                                  }
                                  setDialogState(() { saving = true; error = null; });
                                  try {
                                    await ref.read(repositoryProvider).execute(
                                      'dashboard/personal',
                                      Command(
                                        'save',
                                        {
                                          if (item != null) 'id': item.id,
                                          'title': title.text.trim(),
                                          '内容': content.text,
                                          '排序位置': item?.fields['排序位置'] ?? item?.fields['position'] ?? 0,
                                          'pinned': pinned,
                                        },
                                        version: item?.version ?? 0,
                                        idempotencyKey: item == null
                                            ? 'personal-focus:${ref.read(sessionProvider).id}:${DateTime.now().microsecondsSinceEpoch}'
                                            : '${item.id}:${item.version}:save',
                                      ),
                                    );
                                    refreshBusiness(ref);
                                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                                  } catch (failure) {
                                    if (dialogContext.mounted) {
                                      setDialogState(() { saving = false; error = '$failure'; });
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
