import 'package:flutter/material.dart';
import 'package:pandora_mobile/data/models/models.dart';

String notificationContent(Record message) {
  for (final value in [
    message.fields['summary'],
    message.subtitle,
    message.fields['taskTitle'],
    message.fields['task_title'],
    message.fields['objectTitle'],
    message.fields['object_title'],
    message.fields['content'],
  ]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

class NotificationPreview extends StatelessWidget {
  const NotificationPreview(this.message, {super.key});
  final Record message;

  @override
  Widget build(BuildContext context) {
    final content = notificationContent(message);
    return Text(
      content.isEmpty ? '打开查看具体内容' : content,
      key: ValueKey('notification-preview:${message.id}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
