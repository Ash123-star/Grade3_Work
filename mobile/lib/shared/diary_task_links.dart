import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/state/providers.dart';
import '../data/models/models.dart';
import '../data/models/diary_task_links.dart';
import 'widgets.dart';
import 'paper_layout.dart';
import '../theme/app_theme.dart';

bool _sameAccount(Session original, Session current) =>
    original.id == current.id &&
    original.token == current.token &&
    current.canReadBusiness;

/// Inline chips keep the diary as a continuous document.
class DiaryTaskLinksEditor extends ConsumerWidget {
  const DiaryTaskLinksEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    List<String> ids;
    try {
      ids = DiaryTaskLinks.parse(value);
    } catch (error) {
      return ErrorPanel('$error');
    }
    final state = ref.watch(recordsProvider('tasks'));
    final records = state.isLoading || state.hasError
        ? <Record>[]
        : state.valueOrNull?.items ?? <Record>[];
    final titles = {for (final task in records) task.id: task.title};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '关联任务',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (state.isLoading) const LinearProgressIndicator(),
        if (state.hasError)
          RecordFailure(
            state.error!,
            retry: () => ref.invalidate(recordsProvider('tasks')),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, id) in ids.indexed)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 64,
                ),
                child: InputChip(
                  backgroundColor: SunnyPaperTokens.of(context).information,
                  label: Text(
                    titles[id] ?? '关联任务 ${index + 1} · 暂不可查看',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  tooltip: titles[id] ?? '保留原关联；授权列表未提供此任务',
                  deleteButtonTooltipMessage: '移除此关联任务',
                  onDeleted: enabled
                      ? () => onChanged(
                          DiaryTaskLinks.encode(
                            ids.where((item) => item != id).toList(),
                          ),
                        )
                      : null,
                ),
              ),
            TextButton.icon(
              onPressed: !enabled || !session.canReadBusiness
                  ? null
                  : () async {
                      final captured = ref.read(sessionProvider);
                      final selected = await showModalBottomSheet<List<String>>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) =>
                            DiaryTaskPicker(initial: ids, account: captured),
                      );
                      if (context.mounted &&
                          selected != null &&
                          _sameAccount(captured, ref.read(sessionProvider))) {
                        onChanged(DiaryTaskLinks.encode(selected));
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
          ],
        ),
        if (ids.any((id) => !titles.containsKey(id)) && !state.isLoading)
          const Text('未能读取的关联仍会保留；只有主动移除才会修改原记录。'),
      ],
    );
  }
}

class DiaryTaskPicker extends ConsumerStatefulWidget {
  const DiaryTaskPicker({
    super.key,
    required this.initial,
    required this.account,
  });
  final List<String> initial;
  final Session account;
  @override
  ConsumerState<DiaryTaskPicker> createState() => _DiaryTaskPickerState();
}

class _DiaryTaskPickerState extends ConsumerState<DiaryTaskPicker> {
  late final Set<String> selected = widget.initial.toSet();
  String search = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!_sameAccount(widget.account, session)) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('任务选择已停止，请重新确认账号与权限'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    }
    final data = ref.watch(recordsProvider('tasks'));
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: (media.size.height * .82 - media.viewInsets.bottom).clamp(
            160.0,
            media.size.height,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '选择授权任务',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text('可关联多个任务，仅显示当前账号有权访问的记录。'),
                            const SizedBox(height: 12),
                            TextField(
                              decoration: const InputDecoration(
                                labelText: '搜索任务名称或内容',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) => setState(
                                () => search = value.trim().toLowerCase(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('已选 ${selected.length} 项 · 筛选不会移除已有选择'),
                          ],
                        ),
                      ),
                    ),
                    data.when(
                      skipLoadingOnRefresh: false,
                      skipLoadingOnReload: false,
                      loading: () =>
                          const SliverToBoxAdapter(child: LoadingSkeleton()),
                      error: (error, _) => SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: RecordFailure(
                            error,
                            retry: () =>
                                ref.invalidate(recordsProvider('tasks')),
                          ),
                        ),
                      ),
                      data: (page) {
                        final visible = page.items
                            .where(
                              (item) =>
                                  '${item.title} ${item.subtitle} ${item.fields['任务内容'] ?? ''}'
                                      .toLowerCase()
                                      .contains(search),
                            )
                            .toList();
                        if (visible.isEmpty) {
                          return SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                page.items.isEmpty ? '暂无可关联任务' : '没有匹配的授权任务',
                              ),
                            ),
                          );
                        }
                        return SliverList.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            return CheckboxListTile(
                              key: ValueKey('diary-task-${item.id}'),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(item.title),
                              subtitle: item.subtitle.isEmpty
                                  ? null
                                  : Text(item.subtitle),
                              value: selected.contains(item.id),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  selected.add(item.id);
                                } else {
                                  selected.remove(item.id);
                                }
                              }),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              BottomActions(
                primary: SunnyPrimaryButton(
                  onPressed: data.isLoading || data.hasError || !data.hasValue
                      ? null
                      : () {
                          if (_sameAccount(
                            widget.account,
                            ref.read(sessionProvider),
                          )) {
                            Navigator.pop(context, selected.toList());
                          }
                        },
                  child: const Text('确认关联'),
                ),
                secondary: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DiaryTaskLinksReader extends ConsumerWidget {
  const DiaryTaskLinksReader(this.value, {super.key});
  final dynamic value;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<String> ids;
    try {
      ids = DiaryTaskLinks.parse(value);
    } catch (error) {
      return ErrorPanel('$error');
    }
    if (ids.isEmpty) return const Text('未关联任务');
    final session = ref.watch(sessionProvider);
    final data = ref.watch(recordsProvider('tasks'));
    return data.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => RecordFailure(
        error,
        retry: () => ref.invalidate(recordsProvider('tasks')),
      ),
      data: (page) {
        final accessible = {for (final task in page.items) task.id: task};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, id) in ids.indexed)
              if (accessible[id] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(accessible[id]!.title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (_sameAccount(session, ref.read(sessionProvider))) {
                      openItem(context, 'tasks', id);
                    }
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('关联任务 ${index + 1} 暂不可查看 · 已保留原关联'),
                ),
          ],
        );
      },
    );
  }
}
