import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/sunshine_palette.dart';

/// One surface for direct date input, calendar selection and optional time.
class QuickDateTimePicker extends StatefulWidget {
  const QuickDateTimePicker({
    super.key,
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.includeDate = true,
    this.includeTime = false,
  });
  final DateTime initial, firstDate, lastDate;
  final String title;
  final bool includeDate, includeTime;
  @override
  State<QuickDateTimePicker> createState() => _QuickDateTimePickerState();
}

class _QuickDateTimePickerState extends State<QuickDateTimePicker> {
  late DateTime selected = widget.initial;
  late final year = TextEditingController(text: '${selected.year}');
  late final month = TextEditingController(text: '${selected.month}');
  late final day = TextEditingController(text: '${selected.day}');
  late final hour = TextEditingController(text: _two(selected.hour));
  late final minute = TextEditingController(text: _two(selected.minute));
  String? error;
  String _two(int n) => '$n'.padLeft(2, '0');
  bool allowed(DateTime value) =>
      !value.isBefore(widget.firstDate) && !value.isAfter(widget.lastDate);

  void select(DateTime value) {
    setState(() {
      selected = value;
      year.text = '${value.year}';
      month.text = '${value.month}';
      day.text = '${value.day}';
      error = null;
    });
  }

  DateTime? read() {
    final y = int.tryParse(year.text),
        m = int.tryParse(month.text),
        d = int.tryParse(day.text),
        h = int.tryParse(hour.text),
        n = int.tryParse(minute.text);
    if (y == null ||
        m == null ||
        d == null ||
        y < 1 ||
        y > 9999 ||
        m < 1 ||
        m > 12 ||
        d < 1 ||
        d > DateTime(y, m + 1, 0).day) {
      error = '请输入有效的年、月、日';
      return null;
    }
    final date = DateTime(y, m, d);
    if (widget.includeDate && !allowed(date)) {
      error = '请选择 ${_date(widget.firstDate)} 至 ${_date(widget.lastDate)}';
      return null;
    }
    if (widget.includeTime &&
        (h == null || n == null || h < 0 || h > 23 || n < 0 || n > 59)) {
      error = '小时范围 0–23，分钟范围 0–59';
      return null;
    }
    error = null;
    return DateTime(
      y,
      m,
      d,
      widget.includeTime ? h! : 0,
      widget.includeTime ? n! : 0,
    );
  }

  String _date(DateTime d) => '${d.year}/${d.month}/${d.day}';
  void changed(String _) => setState(() {
    final value = read();
    if (value != null) selected = value;
  });

  void shift(int delta) {
    final next = DateTime(selected.year, selected.month + delta);
    var value = DateTime(
      next.year,
      next.month,
      math.min(selected.day, DateTime(next.year, next.month + 1, 0).day),
    );
    if (value.isBefore(widget.firstDate)) value = widget.firstDate;
    if (value.isAfter(widget.lastDate)) value = widget.lastDate;
    select(value);
  }

  Widget number(String label, TextEditingController controller, int length) =>
      Expanded(
        flex: length == 4 ? 4 : 3,
        child: TextField(
          key: ValueKey('quick-date-$label'),
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(length),
          ],
          textAlign: TextAlign.center,
          onChanged: changed,
          onTap: () => controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          ),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 14,
            ),
            filled: true,
            fillColor: SunshinePalette.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final first = DateTime(selected.year, selected.month);
    final offset = first.weekday - 1;
    final count = DateTime(selected.year, selected.month + 1, 0).day;
    final today = DateUtils.dateOnly(DateTime.now());
    return Material(
      color: SunshinePalette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: SunshinePalette.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SunshinePalette.yellow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.includeDate
                          ? Icons.calendar_month_rounded
                          : Icons.schedule_rounded,
                      size: 22,
                      color: SunshinePalette.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '取消选择',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.includeDate) ...[
                Row(
                  children: [
                    number('年', year, 4),
                    const SizedBox(width: 10),
                    number('月', month, 2),
                    const SizedBox(width: 10),
                    number('日', day, 2),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上个月',
                      onPressed:
                          first.isAfter(
                            DateTime(
                              widget.firstDate.year,
                              widget.firstDate.month,
                            ),
                          )
                          ? () => shift(-1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${selected.year}年${selected.month}月',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (allowed(today))
                      TextButton(
                        onPressed: () => select(today),
                        child: const Text('今天'),
                      ),
                    IconButton(
                      tooltip: '下个月',
                      onPressed:
                          first.isBefore(
                            DateTime(
                              widget.lastDate.year,
                              widget.lastDate.month,
                            ),
                          )
                          ? () => shift(1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final text in ['一', '二', '三', '四', '五', '六', '日'])
                      Expanded(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SunshinePalette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ((offset + count + 6) ~/ 7) * 7,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 48,
                  ),
                  itemBuilder: (_, index) {
                    final n = index - offset + 1;
                    if (n < 1 || n > count) return const SizedBox.shrink();
                    final date = DateTime(selected.year, selected.month, n);
                    final active = n == selected.day;
                    return Semantics(
                      label: _date(date),
                      selected: active,
                      button: true,
                      child: InkWell(
                        key: ValueKey(
                          'quick-day:${date.year}-${date.month}-$n',
                        ),
                        borderRadius: BorderRadius.circular(12),
                        onTap: !allowed(date)
                            ? null
                            : () {
                                select(date);
                                if (!widget.includeTime) {
                                  Navigator.pop(context, date);
                                }
                              },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? SunshinePalette.yellow : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$n',
                            style: TextStyle(
                              color: allowed(date)
                                  ? SunshinePalette.ink
                                  : SunshinePalette.outline,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (widget.includeTime) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 20),
                    const SizedBox(width: 10),
                    number('时', hour, 2),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(':'),
                    ),
                    number('分', minute, 2),
                  ],
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: SunshinePalette.error),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('quick-date-confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SunshinePalette.yellow,
                    foregroundColor: SunshinePalette.ink,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () {
                    final value = read();
                    if (value != null) {
                      Navigator.pop(context, value);
                    } else {
                      setState(() {});
                    }
                  },
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [year, month, day, hour, minute]) {
      c.dispose();
    }
    super.dispose();
  }
}
