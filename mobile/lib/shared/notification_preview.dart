import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/notification_display.dart';

/// Resolve only through the existing authorized detail API. Shared object keys
/// reuse one provider request; identity/epoch changes discard the old result.
final notificationTargetProvider = FutureProvider.autoDispose
    .family<Record, (String, String)>((ref, key) {
      ref.watch(sessionEpochProvider);
      final session = ref.watch(sessionProvider);
      if (!session.canReadBusiness) throw StateError('No business access');
      return ref.watch(itemProvider(key).future);
    });

String notificationContent(Record message) {
  for (final value in [
    message.subtitle,
    message.fields['taskTitle'],
    message.fields['task_title'],
    message.fields['objectTitle'],
    message.fields['object_title'],
    message.fields['summary'],
    message.fields['content'],
  ]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

class NotificationPreview extends ConsumerWidget {
  const NotificationPreview(this.message, {super.key});
  final Record message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var content = notificationContent(message);
    final resource =
        message.fields['targetResource'] ??
        notificationResource(message.fields['notificationType']);
    final id = message.fields['targetId'];
    if (content.isEmpty &&
        resource is String &&
        id is String &&
        id.isNotEmpty) {
      final target = ref.watch(notificationTargetProvider((resource, id)));
      content = target.when(
        data: (record) {
          final title = record.title.trim();
          return title.isEmpty ? '暂无内容摘要' : title;
        },
        error: (_, _) => '关联内容已不可用或无权查看',
        loading: () => '正在读取具体内容…',
      );
    }
    return Text(
      content.isEmpty ? '暂无内容摘要' : content,
      key: ValueKey('notification-preview:${message.id}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
