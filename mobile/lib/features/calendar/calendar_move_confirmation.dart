import 'package:flutter/material.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'calendar_schedule.dart';

/// Owns form state until the dialog route (including its exit animation) is
/// disposed. A cancelled route must never use an already-disposed controller.
class CalendarMoveConfirmation extends StatefulWidget {
  const CalendarMoveConfirmation({
    super.key,
    required this.before,
    required this.after,
    this.anchor,
    this.target,
  });
  final CalendarSchedule before, after;
  final DateTime? anchor, target;
  @override
  State<CalendarMoveConfirmation> createState() =>
      _CalendarMoveConfirmationState();
}

class _CalendarMoveConfirmationState extends State<CalendarMoveConfirmation> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TuantuanDialog(
    title: const Text('确认移动排期'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('原排期', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    widget.before.description,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Text('调整后', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    widget.after.description,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('审核通过后生效'),
            const SizedBox(height: 20),
            TextFormField(
              controller: reason,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '移动原因（1–1000 字）'),
              validator: (value) {
                final text = (value ?? '').trim();
                return text.isEmpty || text.runes.length > 1000
                    ? '请填写 1–1000 字原因'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: const Text('提交审核'),
      ),
    ],
  );
}
