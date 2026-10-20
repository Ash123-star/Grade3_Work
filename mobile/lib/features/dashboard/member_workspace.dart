import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';

String memberDayLabel(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日';

const memberCategories = [
  'overview',
  'profile',
  'focus',
  'logs',
  'tasks',
  'ai',
];

final memberWorkspaceProvider = FutureProvider.autoDispose
    .family<Record, (String, String)>((ref, key) async {
      final session = ref.watch(sessionProvider);
      if (!session.manager || !session.canReadBusiness) {
        throw const ApiFailure(FailureKind.forbidden, '无权查看成员工作台');
      }
      var active = true;
      ref.onDispose(() => active = false);
      // Identity and body are gated together; a failed section cannot leave stale identity.
      final member = await ref.watch(
        itemProvider(('organization', key.$1)).future,
      );
      if (!active) throw const ApiFailure(FailureKind.unavailable, '读取已停止');
      final resources = switch (key.$2) {
        'overview' => ['dashboard/personal', 'logs/subordinates', 'tasks'],
        'focus' => ['dashboard/personal'],
        'logs' => ['logs/subordinates'],
        'tasks' => ['tasks'],
        _ => <String>[],
      };
      await Future.wait([
        for (final resource in resources)
          ref.watch(memberRecordsProvider((resource, key.$1)).future),
      ]);
      return member;
    });

class MemberWorkspace extends ConsumerStatefulWidget {
  const MemberWorkspace(
    this.memberId, {
    super.key,
    this.category = 'overview',
    this.businessDate,
  });
  final String memberId, category;
  final String? businessDate;
  @override
  ConsumerState<MemberWorkspace> createState() => _MemberWorkspaceState();
}

class _MemberWorkspaceState extends ConsumerState<MemberWorkspace> {
  bool ready = false;
  late final DateTime? incomingDate = DateTime.tryParse(
    widget.businessDate ?? '',
  );
  bool get valid =>
      memberCategories.contains(widget.category) &&
      (widget.businessDate == null ||
          incomingDate != null &&
              RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.businessDate!) &&
              incomingDate!.toIso8601String().split('T').first ==
                  widget.businessDate);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (valid && widget.businessDate != null) {
        ref.read(memberLogDateProvider(widget.memberId).notifier).state =
            incomingDate;
      }
      setState(() => ready = true);
    });
  }

  String route(String category) {
    final date = ref.read(memberLogDateProvider(widget.memberId));
    return '/me/team/${encode(widget.memberId)}/$category${date == null ? '' : '?date=${date.toIso8601String().split('T').first}'}';
  }

  void retry() {
    ref.invalidate(itemProvider(('organization', widget.memberId)));
    for (final resource in [
      'dashboard/personal',
      'logs/subordinates',
      'tasks',
    ]) {
      ref.invalidate(memberRecordsProvider((resource, widget.memberId)));
    }
    ref.invalidate(memberWorkspaceProvider((widget.memberId, widget.category)));
  }

  @override
  Widget build(BuildContext context) {
    final memberId = widget.memberId, category = widget.category;
    if (!valid) {
      return PageFrame(
        title: '下属工作台',
        child: PageBody(
          children: [
            const EmptyIllustration(
              showCharacter: false,
              title: '工作台链接无效',
              subtitle: '日期或分类无效，请从成员列表重新进入',
            ),
            OutlinedButton(
              onPressed: () => context.go('/me/people'),
              child: const Text('返回成员列表'),
            ),
          ],
        ),
      );
    }
    if (!ref.watch(sessionProvider).manager) {
      return const PageFrame(
        title: '下属工作台',
        child: EmptyIllustration(
          showCharacter: false,
          title: '无权访问',
          subtitle: '仅可查看服务端授权的成员范围',
        ),
      );
    }
    return PageFrame(
      title: '下属工作台',
      child: !ready
          ? const LoadingSkeleton()
          : ref
                .watch(memberWorkspaceProvider((memberId, category)))
                .when(
                  skipLoadingOnRefresh: false,
                  skipLoadingOnReload: false,
                  loading: () => const LoadingSkeleton(),
                  error: (e, _) => PageBody(
                    children: [
                      RecordFailure(e, retry: retry),
                      if (e is ApiFailure &&
                          e.kind == FailureKind.forbidden) ...[
                        const Text('成员范围已不可访问，受保护资料与记录已清除。'),
                        OutlinedButton(
                          onPressed: retry,
                          child: const Text('重新检查访问权限'),
                        ),
                      ],
                      OutlinedButton(
                        onPressed: () => context.go('/me'),
                        child: const Text('返回本人面板'),
                      ),
                    ],
                  ),
                  data: (member) => PageBody(
                    children: [
                      PaperSurface(
                        color: const Color(0xFFFFFCF7),
                        borderColor: const Color(0xFFEEDCCB),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProtectedAvatar(
                                  name: member.title,
                                  attachmentId:
                                      member.fields['avatarAttachmentId']
                                          as String?,
                                  radius: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '正在查看：${member.title}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                  color: DogBrandPalette.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('${member.subtitle} · 只读'),
                            TextButton(
                              onPressed: () => context.go('/me'),
                              child: const Text('返回本人面板'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final c in const [
                              ('overview', '概览'),
                              ('profile', '资料'),
                              ('focus', '重点'),
                              ('logs', '日志'),
                              ('tasks', '任务'),
                              ('ai', 'AI摘要'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(c.$2),
                                  selected: category == c.$1,
                                  onSelected: (_) =>
                                      context.replace(route(c.$1)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '只读工作台 · 私人备注和未提交草稿不展示',
                        style: TextStyle(color: CuteTokens.muted),
                      ),
                      if (category == 'profile') ...[
                        const SectionHeader('公开介绍'),
                        Text(
                          '${member.fields['个人介绍'] ?? member.fields['body'] ?? '暂无介绍'}',
                        ),
                      ],
                      if (category == 'logs') ...[
                        const SectionHeader('业务日期'),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              label: Text(
                                ref.watch(memberLogDateProvider(memberId)) ==
                                        null
                                    ? '全部日期'
                                    : memberDayLabel(
                                        ref.watch(
                                          memberLogDateProvider(memberId),
                                        )!,
                                      ),
                              ),
                              onPressed: () async {
                                final next = await showPremiumDatePicker(
                                  context,
                                  initial:
                                      ref.read(
                                        memberLogDateProvider(memberId),
                                      ) ??
                                      shanghaiWallTime(DateTime.now()),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2040),
                                );
                                if (next != null && mounted) {
                                  ref
                                          .read(
                                            memberLogDateProvider(
                                              memberId,
                                            ).notifier,
                                          )
                                          .state =
                                      next;
                                }
                              },
                            ),
                            if (ref.watch(memberLogDateProvider(memberId)) !=
                                null)
                              TextButton(
                                onPressed: () =>
                                    ref
                                            .read(
                                              memberLogDateProvider(
                                                memberId,
                                              ).notifier,
                                            )
                                            .state =
                                        null,
                                child: const Text('清除日期'),
                              ),
                          ],
                        ),
                      ],
                      if (category == 'overview' || category == 'focus')
                        MemberRecords(
                          ownerId: memberId,
                          resource: 'dashboard/personal',
                          title: '公开个人重点',
                          previewLimit: category == 'overview' ? 3 : null,
                          onViewAll: category == 'overview'
                              ? () => context.replace(route('focus'))
                              : null,
                        ),
                      if (category == 'overview' || category == 'logs')
                        MemberRecords(
                          ownerId: memberId,
                          resource: 'logs/subordinates',
                          title: '已提交日志',
                          previewLimit: category == 'overview' ? 3 : null,
                          onViewAll: category == 'overview'
                              ? () => context.replace(route('logs'))
                              : null,
                        ),
                      if (category == 'overview' || category == 'tasks')
                        MemberRecords(
                          ownerId: memberId,
                          resource: 'tasks',
                          title: '授权工作任务',
                          previewLimit: category == 'overview' ? 3 : null,
                          onViewAll: category == 'overview'
                              ? () => context.replace(route('tasks'))
                              : null,
                        ),
                      if (category == 'ai')
                        const EmptyIllustration(
                          title: '成员 AI 摘要待接入',
                          subtitle: '真实服务按成员和授权范围生成，当前不以本人样例替代',
                        ),
                    ],
                  ),
                ),
    );
  }
}
