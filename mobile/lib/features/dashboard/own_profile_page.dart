import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart' show SectionHeader;
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class OwnProfilePage extends ConsumerWidget {
  const OwnProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final profile = ref.watch(itemProvider(('organization/profile', user.id)));
    final timeline = ref.watch(memberRecordsProvider(('logs', user.id)));
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
          profile.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(
                itemProvider(('organization/profile', user.id)),
              ),
            ),
            data: (value) => PaperSurface(
              color: DogBrandPalette.surface,
              borderColor: DogBrandPalette.line,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProtectedAvatar(
                        name: user.name,
                        attachmentId: value.fields['avatarAttachmentId'] as String?,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                            Text(value.subtitle),
                            Text('${user.role.label} · 组织与角色只读'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('${value.fields['个人介绍'] ?? value.fields['body'] ?? '暂无个人介绍'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('个人公开重点'),
          MemberRecords(
            ownerId: user.id,
            resource: 'dashboard/personal',
            title: '个人公开重点',
          ),
          const SizedBox(height: 16),
          const SectionHeader('日志时间线'),
          timeline.when(
            loading: () => const LoadingSkeleton(),
            error: (error, _) => RecordFailure(
              error,
              retry: () => ref.invalidate(
                memberRecordsProvider(('logs', user.id)),
              ),
            ),
            data: (page) {
              final items = page.items.where(isSubmittedDiary).toList()
                ..sort((a, b) => '${b.fields['businessDate']}'.compareTo(
                  '${a.fields['businessDate']}',
                ));
              if (items.isEmpty) {
                return const EmptyIllustration(
                  title: '暂无已提交日志',
                  subtitle: '提交后的工作记录会出现在这里',
                );
              }
              return PaperSurface(
                color: DogBrandPalette.surface,
                borderColor: DogBrandPalette.line,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.article_outlined),
                        title: Text(items[i].title),
                        subtitle: Text(
                          '${items[i].fields['businessDate'] ?? '未标记业务日期'} · 已提交',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openItem(context, 'logs', items[i].id),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const DemoLabel(),
        ],
      ),
    );
  }
}
