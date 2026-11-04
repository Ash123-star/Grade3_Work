import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认移动排期'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.anchor != null && widget.target != null) ...[
              Text(
                '抓取处：${businessDateText(widget.anchor!)} → ${businessDateText(widget.target!)}',
              ),
              const SizedBox(height: 12),
            ],
            Text('原排期：${widget.before.description}'),
            const SizedBox(height: 12),
            Text('新排期：${widget.after.description}'),
            const SizedBox(height: 12),
            const Text('按现有审核规则处理；需要审核时，生效前任务留在原日期。'),
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
