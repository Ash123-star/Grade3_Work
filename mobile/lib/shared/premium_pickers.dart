import 'package:flutter/cupertino.dart';
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
    this.icon = const Icon(Icons.expand_more_rounded),
    this.isExpanded = true,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final Widget icon;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) => FormField<T>(
    initialValue: initialValue,
    validator: validator,
    builder: (field) {
      final item = items.where((e) => e.value == field.value).firstOrNull;
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onChanged == null
            ? null
            : () async {
                final value = await showModalBottomSheet<T>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (sheet) => _PremiumShell(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PremiumHeading(decoration.labelText ?? '请选择'),
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
                if (value == null || !context.mounted) return;
                field.didChange(value);
                onChanged?.call(value);
              },
        child: InputDecorator(
          isEmpty: item == null,
          decoration: decoration.copyWith(
            enabled: onChanged != null,
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
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(child: child),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<DateTime?> showPremiumDateTimePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择时间',
}) async {
  final now = DateTime.now();
  final seed = initial ?? now;
  final date = await showPremiumDatePicker(
    context,
    initial: seed,
    firstDate: firstDate ?? DateTime(now.year - 2),
    lastDate: lastDate ?? DateTime(now.year + 8),
    title: title,
  );
  if (date == null || !context.mounted) return null;
  final time = await showPremiumTimePicker(
    context,
    initial: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<DateTime?> showPremiumDatePicker(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期',
}) async {
  final today = DateTime.now();
  final min = DateUtils.dateOnly(firstDate ?? DateTime(today.year - 2));
  final max = DateUtils.dateOnly(lastDate ?? DateTime(today.year + 8));
  if (min.isAfter(max)) throw ArgumentError('开始日期不能晚于截止日期');
  final candidate = DateUtils.dateOnly(initial ?? today);
  final picked = candidate.isBefore(min)
      ? min
      : candidate.isAfter(max)
      ? max
      : candidate;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PremiumDateSheet(
      initial: picked,
      firstDate: min,
      lastDate: max,
      title: title,
    ),
  );
}

Future<TimeOfDay?> showPremiumTimePicker(
  BuildContext context, {
  TimeOfDay? initial,
}) async {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumTimeSheet(initial: initial ?? TimeOfDay.now()),
  );
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
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
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

class _PremiumDateSheet extends StatefulWidget {
  const _PremiumDateSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });
  final DateTime initial, firstDate, lastDate;
  final String title;
  @override
  State<_PremiumDateSheet> createState() => _PremiumDateSheetState();
}

class _PremiumDateSheetState extends State<_PremiumDateSheet> {
  late DateTime selected = DateTime(
    widget.initial.year,
    widget.initial.month,
    widget.initial.day,
  );
  late DateTime month = DateTime(widget.initial.year, widget.initial.month);
  int get days => DateTime(month.year, month.month + 1, 0).day;
  int get offset => DateTime(month.year, month.month, 1).weekday - 1;
  bool allowed(DateTime value) =>
      !value.isBefore(widget.firstDate) && !value.isAfter(widget.lastDate);
  @override
  Widget build(BuildContext context) => _PremiumShell(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('确定'),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed:
                  month.month == widget.firstDate.month &&
                      month.year == widget.firstDate.year
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${month.year}年${month.month}月',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed:
                  month.year == widget.lastDate.year &&
                      month.month == widget.lastDate.month
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ((offset + days + 6) ~/ 7) * 7,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 44,
          ),
          itemBuilder: (_, index) {
            final day = index - offset + 1;
            if (day < 1 || day > days) return const SizedBox.shrink();
            final value = DateTime(month.year, month.month, day);
            final isSelected =
                value.year == selected.year &&
                value.month == selected.month &&
                value.day == selected.day;
            return Padding(
              padding: const EdgeInsets.all(3),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: allowed(value)
                    ? () => setState(() => selected = value)
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                        fontWeight: isSelected ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _PremiumTimeSheet extends StatefulWidget {
  const _PremiumTimeSheet({required this.initial});
  final TimeOfDay initial;
  @override
  State<_PremiumTimeSheet> createState() => _PremiumTimeSheetState();
}

class _PremiumTimeSheetState extends State<_PremiumTimeSheet> {
  late int hour = widget.initial.hour;
  late int minute = widget.initial.minute - widget.initial.minute % 5;
  @override
  Widget build(BuildContext context) => _PremiumShell(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '选择时间',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, TimeOfDay(hour: hour, minute: minute)),
              child: const Text('确定'),
            ),
          ],
        ),
        SizedBox(
          height: 170,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wheel(24, hour, (v) => setState(() => hour = v)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  ':',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
              _wheel(
                12,
                minute ~/ 5,
                (v) => setState(() => minute = v * 5),
                minuteLabel: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _wheel(
    int count,
    int value,
    ValueChanged<int> onChanged, {
    bool minuteLabel = false,
  }) => SizedBox(
    width: 82,
    child: CupertinoPicker(
      itemExtent: 42,
      scrollController: FixedExtentScrollController(initialItem: value),
      onSelectedItemChanged: onChanged,
      children: [
        for (var i = 0; i < count; i++)
          Center(
            child: Text(
              '${minuteLabel ? i * 5 : i}'.padLeft(2, '0'),
              style: const TextStyle(fontSize: 22),
            ),
          ),
      ],
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
