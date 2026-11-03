import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';

/// Existing task-form label surface with optional, zero-or-more selection.
/// IDs are kept in the controller as a comma-separated transport value; names
/// and colours always come from the server catalogue.
class TaskLabelSelector extends ConsumerWidget {
  const TaskLabelSelector({
    super.key,
    required this.controller,
    this.enabled = true,
    this.historicalName,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? historicalName;
  final VoidCallback? onChanged;

  Set<String> _ids(String value) => value
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(recordsProvider('task-labels'));
    final labels = catalog.isLoading || catalog.hasError
        ? <Record>[]
        : (catalog.valueOrNull?.items ?? <Record>[])
              .where((label) => label.fields['status'] == 'ACTIVE')
              .toList();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final selectedIds = _ids(value.text);
        final selected = labels
            .where((label) => selectedIds.contains(label.id))
            .toList();
        final unavailable = selectedIds.difference(
          labels.map((e) => e.id).toSet(),
        );
        return FormField<String>(
          initialValue: value.text,
          validator: (_) {
            // 标签本身是可选项；没有选择任何标签时，目录加载/刷新不应阻止派发。
            if (selectedIds.isEmpty) return null;
            if (catalog.isLoading) return '标签正在加载，请稍后提交';
            if (catalog.hasError) return '请重新加载标签后再提交';
            if (unavailable.isNotEmpty) return '原标签已停用或不可选，请重新选择';
            return null;
          },
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (catalog.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('正在加载标签…'),
                )
              else if (catalog.hasError) ...[
                const Text('标签加载失败，请重试'),
                TextButton(
                  onPressed: enabled
                      ? () => ref.invalidate(recordsProvider('task-labels'))
                      : null,
                  child: const Text('重新加载标签'),
                ),
              ] else ...[
                InkWell(
                  key: const ValueKey('task-label-select'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: !enabled
                      ? null
                      : () async {
                          final session = ref.read(sessionProvider);
                          final choice = await _showLabelSheet(
                            context,
                            labels,
                            selectedIds,
                          );
                          if (choice == null || !context.mounted) return;
                          final currentSession = ref.read(sessionProvider);
                          if (currentSession.id != session.id ||
                              currentSession.token != session.token) {
                            return;
                          }
                          final current = ref.read(
                            recordsProvider('task-labels'),
                          );
                          final active =
                              current.valueOrNull?.items
                                  .where(
                                    (label) =>
                                        label.fields['status'] == 'ACTIVE',
                                  )
                                  .map((label) => label.id)
                                  .toSet() ??
                              <String>{};
                          if (current.isLoading ||
                              current.hasError ||
                              !active.containsAll(choice)) {
                            state.validate();
                            return;
                          }
                          final ordered = choice.toList()..sort();
                          controller.text = ordered.join(',');
                          state.didChange(controller.text);
                          state.validate();
                          onChanged?.call();
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: selected.isEmpty
                              ? const Text('可不选，点击选择标签')
                              : Wrap(
                                  key: const ValueKey('task-label-selected'),
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final label in selected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _color(label.fields['color']),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Text(
                                          label.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        const Icon(Icons.expand_more_rounded),
                      ],
                    ),
                  ),
                ),
                if (labels.isEmpty)
                  TextButton(
                    onPressed: enabled
                        ? () => ref.invalidate(recordsProvider('task-labels'))
                        : null,
                    child: const Text('刷新标签'),
                  ),
                if (unavailable.isNotEmpty)
                  Text(
                    '原标签：${historicalName?.trim().isNotEmpty == true ? historicalName : '名称未提供'}（已停用或不可选，请重新选择）',
                  ),
              ],
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Set<String>?> _showLabelSheet(
    BuildContext context,
    List<Record> labels,
    Set<String> selected,
  ) => showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _TaskLabelSheet(labels: labels, selected: selected),
  );

  static Color _color(dynamic raw) {
    final hex = '$raw'.replaceFirst('#', '');
    final value = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
        ? int.tryParse(hex, radix: 16)
        : null;
    return value == null ? Colors.grey.shade200 : Color(0xFF000000 | value);
  }
}

class _TaskLabelSheet extends StatefulWidget {
  const _TaskLabelSheet({required this.labels, required this.selected});
  final List<Record> labels;
  final Set<String> selected;
  @override
  State<_TaskLabelSheet> createState() => _TaskLabelSheetState();
}

class _TaskLabelSheetState extends State<_TaskLabelSheet> {
  late final Set<String> selected = {...widget.selected};
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选择标签',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final label in widget.labels)
                FilterChip(
                  label: Text(label.title),
                  selected: selected.contains(label.id),
                  selectedColor: TaskLabelSelector._color(
                    label.fields['color'],
                  ),
                  onSelected: (value) => setState(() {
                    if (value) {
                      selected.add(label.id);
                    } else {
                      selected.remove(label.id);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
