import 'quick_date_time_picker.dart';
import '../theme/sunshine_palette.dart';
import 'package:flutter/material.dart';

class PremiumTagOption {
  const PremiumTagOption(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

/// Shared custom dropdown surface. Menu-item widgets supply labels only;
/// selection is rendered in a rounded bottom sheet instead of a platform menu.
class PremiumDropdownField<T> extends StatelessWidget {
  const PremiumDropdownField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.validator,
    this.sheetTitle,
    this.icon = const Icon(Icons.expand_more_rounded),
    this.isExpanded = true,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final String? sheetTitle;
  final Widget icon;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) => FormField<T>(
    initialValue: initialValue,
    validator: validator,
    builder: (field) {
      final item = items.where((e) => e.value == field.value).firstOrNull;
      final enabled =
          onChanged != null &&
          decoration.enabled &&
          items.any((item) => item.enabled);
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: !enabled
            ? null
            : () async {
                final value = await showModalBottomSheet<T>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: false,
                  backgroundColor: Colors.transparent,
                  builder: (sheet) => _PremiumShell(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PremiumHeading(
                          sheetTitle ?? decoration.labelText ?? '请选择',
                        ),
                        for (final option in items)
                          _PremiumOptionRow(
                            selected: option.value == field.value,
                            enabled: option.enabled,
                            onTap: () => Navigator.pop(sheet, option.value),
                            child: option.child,
                          ),
                      ],
                    ),
                  ),
                );
                if (value == null || !field.mounted) return;
                field.didChange(value);
                onChanged?.call(value);
              },
        child: InputDecorator(
          isEmpty: item == null,
          decoration: decoration.copyWith(
            enabled: enabled,
            errorText: field.errorText,
          ),
          child: Row(
            mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (isExpanded)
                Expanded(child: item?.child ?? const SizedBox.shrink())
              else
                item?.child ?? const SizedBox.shrink(),
              const SizedBox(width: 8),
              icon,
            ],
          ),
        ),
      );
    },
  );
}

class _PremiumHeading extends StatelessWidget {
  const _PremiumHeading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

class _PremiumOptionRow extends StatelessWidget {
  const _PremiumOptionRow({
    required this.selected,
    required this.child,
    required this.onTap,
    this.enabled = true,
  });
  final bool selected;
  final bool enabled;
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? SunshinePalette.butter : SunshinePalette.surface,
            border: Border.all(
              color: selected ? SunshinePalette.outline : SunshinePalette.line,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(child: child),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: SunshinePalette.accentInk,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<DateTime?> _quickPicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  required String title,
  bool includeDate = true,
  bool includeTime = false,
}) {
  final now = DateTime.now();
  final min = DateUtils.dateOnly(firstDate ?? DateTime(now.year - 2));
  final max = DateUtils.dateOnly(lastDate ?? DateTime(now.year + 8));
  if (min.isAfter(max)) throw ArgumentError('开始日期不能晚于截止日期');
  final seed = initial ?? now;
  final date = DateUtils.dateOnly(seed);
  final picked = date.isBefore(min)
      ? min
      : date.isAfter(max)
      ? max
      : date;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => QuickDateTimePicker(
      initial: DateTime(
        picked.year,
        picked.month,
        picked.day,
        seed.hour,
        seed.minute,
      ),
      firstDate: min,
      lastDate: max,
      title: title,
      includeDate: includeDate,
      includeTime: includeTime,
    ),
  );
}

Future<DateTime?> showPremiumDateTimePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期与时间',
}) => _quickPicker(
  context,
  initial: initial,
  firstDate: firstDate,
  lastDate: lastDate,
  title: title,
  includeTime: true,
);

Future<DateTime?> showPremiumDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期',
}) => _quickPicker(
  context,
  initial: initial,
  firstDate: firstDate,
  lastDate: lastDate,
  title: title,
);

Future<TimeOfDay?> showPremiumTimePicker(
  BuildContext context, {
  TimeOfDay? initial,
}) async {
  final time = initial ?? TimeOfDay.now();
  final now = DateTime.now();
  final value = await _quickPicker(
    context,
    initial: DateTime(now.year, now.month, now.day, time.hour, time.minute),
    title: '选择时间',
    includeDate: false,
    includeTime: true,
  );
  return value == null ? null : TimeOfDay.fromDateTime(value);
}

Future<String?> showPremiumTagPicker(
  BuildContext context, {
  required List<PremiumTagOption> options,
  String? selected,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumTagSheet(options: options, selected: selected),
  );
}

Future<String?> showPremiumOptionPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
}) async {
  final result = await showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _PremiumOptionSheet(title: title, options: options, selected: selected),
  );
  return result is String ? result : null;
}

const _premiumOptionCancel = Object();

class _PremiumOptionSheet extends StatelessWidget {
  const _PremiumOptionSheet({
    required this.title,
    required this.options,
    this.selected,
  });
  final String title;
  final List<String> options;
  final String? selected;
  @override
  Widget build(BuildContext context) => _PremiumShell(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _premiumOptionCancel),
              child: const Text('取消'),
            ),
          ],
        ),
        for (final option in options)
          _PremiumOptionRow(
            selected: option == selected,
            onTap: () => Navigator.pop(context, option),
            child: Text(option),
          ),
      ],
    ),
  );
}

class _PremiumShell extends StatelessWidget {
  const _PremiumShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: SunshinePalette.canvas,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child,
          ],
        ),
      ),
    ),
  );
}

class _PremiumTagSheet extends StatelessWidget {
  const _PremiumTagSheet({required this.options, this.selected});
  final List<PremiumTagOption> options;
  final String? selected;
  @override
  Widget build(BuildContext context) => _PremiumShell(
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
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in options)
              Semantics(
                button: true,
                selected: option.id == selected,
                label: option.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(context, option.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: option.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: option.id == selected
                            ? Colors.black54
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      option.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
