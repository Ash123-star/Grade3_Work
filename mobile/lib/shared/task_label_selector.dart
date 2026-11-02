import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'premium_pickers.dart';

/// Uses the same server label records projected into task-management rows.
/// The controller stores only the label ID; names are never submitted as IDs.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(recordsProvider('task-labels'));
    // Do not offer stale cached values while refreshing or after a failed fetch.
    final labels = catalog.isLoading || catalog.hasError
        ? <Record>[]
        : (catalog.valueOrNull?.items ?? <Record>[])
              .where((label) => label.fields['status'] == 'ACTIVE')
              .toList();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final selected = labels
            .where((label) => label.id == value.text)
            .firstOrNull;
        return FormField<String>(
          initialValue: value.text,
          validator: (_) {
            if (catalog.isLoading) return '标签正在加载，请稍后提交';
            if (catalog.hasError) return '请重新加载标签后再提交';
            if (labels.isEmpty) return '当前没有可用标签';
            if (controller.text.isEmpty) return '请选择标签';
            if (!labels.any((label) => label.id == controller.text)) {
              return '原标签已停用或不可选，请重新选择';
            }
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
                  onTap: !enabled || labels.isEmpty
                      ? null
                      : () async {
                          final session = ref.read(sessionProvider);
                          final choice = await showPremiumTagPicker(
                            context,
                            options: [
                              for (final label in labels)
                                PremiumTagOption(
                                  label.id,
                                  label.title,
                                  _color(label.fields['color']),
                                ),
                            ],
                            selected: controller.text,
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
                          if (current.isLoading ||
                              current.hasError ||
                              !(current.valueOrNull?.items.any(
                                    (label) =>
                                        label.id == choice &&
                                        label.fields['status'] == 'ACTIVE',
                                  ) ??
                                  false)) {
                            state.validate();
                            return;
                          }
                          controller.text = choice;
                          state.didChange(choice);
                          state.validate();
                          onChanged?.call();
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: selected == null
                              ? Text(labels.isEmpty ? '当前没有可用标签' : '选择标签')
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    key: const ValueKey('task-label-selected'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _color(selected.fields['color']),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      selected.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
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
                if (value.text.isNotEmpty && selected == null)
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

  static Color _color(dynamic raw) {
    final hex = '$raw'.replaceFirst('#', '');
    final value = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
        ? int.tryParse(hex, radix: 16)
        : null;
    return value == null ? Colors.grey.shade200 : Color(0xFF000000 | value);
  }
}
