import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart' show SectionHeader;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'attachment_widgets.dart';
import 'widgets.dart';

class PublicComments extends ConsumerStatefulWidget {
  const PublicComments({
    super.key,
    required this.resource,
    required this.record,
  });
  final String resource;
  final Record record;
  @override
  ConsumerState<PublicComments> createState() => _PublicCommentsState();
}

class _PublicCommentsState extends ConsumerState<PublicComments> {
  final input = TextEditingController();
  Map? reply;
  Object? error;
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> post() async {
    if (busy) return;
    final text = input.text.trim();
    if (text.isEmpty) {
      setState(() => error = '评论不能为空');
      return;
    }
    final identity = ref.read(sessionProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .execute(
            '${widget.resource}/comments',
            Command(
              'comment',
              {
                'id': widget.record.id,
                'text': text,
                if (reply != null) 'parentCommentId': reply!['id'],
              },
              idempotencyKey:
                  'comment:${identity.id}:${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
      if (!mounted ||
          ref.read(sessionProvider).id != identity.id ||
          ref.read(sessionProvider).token != identity.token) {
        return;
      }
      input.clear();
      setState(() => reply = null);
      refreshBusiness(ref);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.record.fields['comments'] as List? ?? const [];
    final byId = {
      for (final comment in comments.whereType<Map>())
        '${comment['id']}': comment,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('评论'),
        if (comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无评论，来交流一下吧'),
          ),
        if (comments.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final (i, value) in comments.indexed)
                  Builder(
                    builder: (context) {
                      final comment = value is Map ? value : {'text': '$value'};
                      final parent = byId['${comment['parentCommentId']}'];
                      final name =
                          '${comment['actorName'] ?? comment['actorId'] ?? '成员'}';
                      final date = businessEventTime(
                        '${comment['createdAt'] ?? comment['time']}',
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 5 : 10,
                          bottom: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProtectedAvatar(
                              name: name,
                              attachmentId:
                                  comment['avatarAttachmentId'] as String?,
                              radius: 17,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        date == null
                                            ? '时间未提供'
                                            : '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  RichText(
                                    text: TextSpan(
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                      children: [
                                        if (parent != null) ...[
                                          const TextSpan(
                                            text: '回复 ',
                                            style: TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                '${parent['actorName'] ?? '成员'}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: '：',
                                            style: TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                        TextSpan(
                                          text:
                                              '${comment['text'] ?? comment['body'] ?? ''}',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (comment['id'] != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        key: ValueKey('reply-comment:$i'),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 32),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                        onPressed: busy
                                            ? null
                                            : () => setState(
                                                () => reply = comment,
                                              ),
                                        child: const Text('回复'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        if (widget.record.fields['commentsError'] != null)
          RecordFailure(widget.record.fields['commentsError'] as Object),
        if (reply != null)
          Row(
            children: [
              Expanded(child: Text('回复 ${reply!['actorName'] ?? '成员'}')),
              IconButton(
                tooltip: '取消回复',
                onPressed: () => setState(() => reply = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        TextField(
          key: const ValueKey('public-comment-input'),
          controller: input,
          enabled: !busy,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '写下评论，或回复已有评论'),
        ),
        const SizedBox(height: 8),
        if (error != null)
          Text(
            '$error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        SunnyPrimaryButton(
          onPressed: busy ? null : post,
          child: Text(busy ? '发布中…' : '发布评论'),
        ),
        const SizedBox(height: 8),
        Text(
          '对有权查看本记录的成员公开，发布后不可编辑或删除。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
