import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart' show SectionHeader;
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';

class OwnProfilePage extends ConsumerWidget {
  const OwnProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    return PageFrame(
      title: '我的个人主页',
      actions: [
        TextButton(
          onPressed: () => openForm(context, 'profile-edit'),
          child: const Text('编辑资料'),
        ),
      ],
      child: PageBody(
        children: [
          ref
              .watch(itemProvider(('organization/profile', user.id)))
              .when(
                loading: () => const LoadingSkeleton(),
                error: (e, _) => RecordFailure(
                  e,
                  retry: () => ref.invalidate(
                    itemProvider(('organization/profile', user.id)),
                  ),
                ),
                data: (p) => PaperSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ProtectedAvatar(
                            name: user.name,
                            attachmentId:
                                p.fields['avatarAttachmentId'] as String?,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(p.subtitle),
                                Text('${user.role.label} · 组织与角色只读'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${p.fields['个人介绍'] ?? p.fields['body'] ?? '暂无个人介绍'}',
                      ),
                    ],
                  ),
                ),
              ),
          MemberRecords(
            ownerId: user.id,
            resource: 'dashboard/personal',
            title: '个人公开重点',
          ),
          const SectionHeader('日志时间线'),
          ref
              .watch(memberRecordsProvider(('logs', user.id)))
              .when(
                loading: () => const LoadingSkeleton(),
                error: (e, _) => RecordFailure(
                  e,
                  retry: () =>
                      ref.invalidate(memberRecordsProvider(('logs', user.id))),
                ),
                data: (page) {
                  final items = page.items.where(isSubmittedDiary).toList()
                    ..sort(
                      (a, b) => '${b.fields['businessDate']}'.compareTo(
                        '${a.fields['businessDate']}',
                      ),
                    );
                  if (items.isEmpty) {
                    return const EmptyIllustration(
                      title: '暂无已提交日志',
                      subtitle: '提交后的工作记录会出现在这里',
                    );
                  }
                  return Column(
                    children: [
                      for (final r in items) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.article_outlined),
                          title: Text(r.title),
                          subtitle: Text(
                            '${r.fields['businessDate'] ?? '未标记业务日期'} · 正式版本 v${r.version}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openItem(context, 'logs', r.id),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  );
                },
              ),
          const DemoLabel(),
        ],
      ),
    );
  }
}
