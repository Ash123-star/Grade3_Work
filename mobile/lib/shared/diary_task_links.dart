import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/state/providers.dart';
import '../data/models/models.dart';
import '../data/models/diary_task_links.dart';
import 'widgets.dart';
import '../theme/sunshine_palette.dart';

bool diaryTaskIsPending(Record record) => record.fields['phase'] == 'RECEIVED';

final diaryAvailableTasksProvider = FutureProvider.autoDispose<List<Record>>((
  ref,
) async {
  final page = await ref.watch(receivedTaskCardProvider.future);
  return page.items.where(diaryTaskIsPending).toList();
});

Color diaryTaskColor(Map<String, dynamic> fields) {
  final labels = fields['labels'];
  final label = labels is List ? labels.whereType<Map>().firstOrNull : null;
  final raw = label?['color'] ?? fields['tagColor'] ?? fields['tag_color'];
  if (raw is Color) return raw;
  final hex = '$raw'.replaceFirst('#', '').replaceFirst('0x', '');
  final value = int.tryParse(hex, radix: 16);
  return value == null
      ? const Color(0xFFDDF1FA)
      : Color(hex.length <= 6 ? 0xFF000000 | value : value);
}

class DiaryTaskPill extends StatelessWidget {
  const DiaryTaskPill({
    super.key,
    required this.title,
    required this.color,
    this.selected,
    this.onTap,
  });
  final String title;
  final Color color;
  final bool? selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF352B24);
    return Semantics(
      label: title,
      checked: selected,
      button: true,
      child: Material(
        color: color,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected == true ? ink : color,
            width: selected == true ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected != null) ...[
                    Icon(
                      selected!
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: ink,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: ink,
                        fontWeight: selected == true
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// All received participant tasks are loaded, independent of the diary date.
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
    List<String> ids;
    try {
      ids = DiaryTaskLinks.parse(value);
    } catch (error) {
      return ErrorPanel('$error');
    }
    final state = ref.watch(diaryAvailableTasksProvider);
    final tasks = state.isLoading || state.hasError
        ? <Record>[]
        : state.valueOrNull ?? <Record>[];
    void toggle(String id) {
      final next = [...ids];
      next.contains(id) ? next.remove(id) : next.add(id);
      onChanged(DiaryTaskLinks.encode(next));
    }

    return LayoutBuilder(
      builder: (context, layout) => MenuAnchor(
        style: MenuStyle(
          side: const WidgetStatePropertyAll(
            BorderSide(color: SunshinePalette.outline),
          ),
          elevation: const WidgetStatePropertyAll(3),
          shadowColor: const WidgetStatePropertyAll(Color(0x335F471B)),
          backgroundColor: WidgetStatePropertyAll(SunshinePalette.canvas),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: SunshinePalette.outline),
            ),
          ),
        ),
        menuChildren: [
          SizedBox(
            width: (layout.maxWidth - 16).clamp(180.0, 480.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .36,
              ),
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.isLoading) const SunnyLoadingIndicator(),
                    if (state.hasError)
                      RecordFailure(
                        state.error!,
                        retry: () => ref.invalidate(receivedTaskCardProvider),
                      ),
                    if (!state.isLoading && !state.hasError && tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('暂无已接收的任务'),
                      ),
                    for (final task in tasks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: DiaryTaskPill(
                          key: ValueKey('diary-task-${task.id}'),
                          title: task.title,
                          color: diaryTaskColor(task.fields),
                          selected: ids.contains(task.id),
                          onTap: enabled ? () => toggle(task.id) : null,
                        ),
                      ),
                    for (final id in ids.where(
                      (id) => !tasks.any((t) => t.id == id),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SavedTaskPill(
                          id: id,
                          selected: true,
                          onTap: enabled ? () => toggle(id) : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        builder: (context, controller, _) => OutlinedButton(
          key: const ValueKey('diary-task-dropdown'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            foregroundColor: SunshinePalette.ink,
            backgroundColor: SunshinePalette.butter,
            side: BorderSide(color: SunshinePalette.outline),
          ),
          onPressed: !enabled
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  controller.isOpen ? controller.close() : controller.open();
                },
          child: Row(
            children: [
              const Icon(Icons.checklist_rounded, size: 19),
              const SizedBox(width: 8),
              const Text('关联任务', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ids.isEmpty ? '请选择' : '已选 ${ids.length} 项',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                controller.isOpen ? Icons.expand_less : Icons.expand_more,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolve saved links individually: completed tasks stay visible and a link
/// outside the first task page never appears missing merely due to pagination.
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
    if (ids.isEmpty) return const Text('未选择关联任务');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final id in ids) _SavedTaskPill(id: id)],
    );
  }
}

class _SavedTaskPill extends ConsumerWidget {
  const _SavedTaskPill({required this.id, this.selected, this.onTap});
  final String id;
  final bool? selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(itemProvider(('tasks', id)));
    final task = state.isLoading || state.hasError ? null : state.valueOrNull;
    return DiaryTaskPill(
      title: state.isLoading ? '正在读取任务…' : task?.title ?? '任务暂不可查看 · 已保留关联',
      color: diaryTaskColor(task?.fields ?? {}),
      selected: selected,
      onTap:
          onTap ??
          (task != null
              ? () => openItem(context, 'tasks', id)
              : () => ref.invalidate(itemProvider(('tasks', id)))),
    );
  }
}
