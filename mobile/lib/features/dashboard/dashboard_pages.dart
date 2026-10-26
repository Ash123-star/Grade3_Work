import 'package:pandora_mobile/shared/sibling_swipe.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
export 'dashboard_home.dart';
export 'logs_page.dart';
export 'package:pandora_mobile/features/ai_map/ai_map_page.dart';

String dayLabel(DateTime d) =>
    '${d.month}月${d.day}日 周${['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]}';
String savedTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, this.initialPeriod});
  final String? initialPeriod;
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  @override
  void initState() {
    super.initState();
    if (widget.initialPeriod != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(periodProvider.notifier).state = widget.initialPeriod!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final period = ref.watch(periodProvider);
    final page = PageFrame(
      title: '视图',
      showTitle: false,
      fab: user.manager && user.dispatch
          ? FloatingActionButton(
              heroTag: 'view-dispatch',
              tooltip: '新增任务',
              onPressed: () => openForm(context, 'dispatch'),
              child: const Icon(Icons.add),
            )
          : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: period == '月' ? 0 : 16),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: period == '月' ? 12 : 0),
              child: const DateControls(showTaskManagement: true),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) => period == '月'
                    ? Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, monthViewport) =>
                                  CalendarContent(
                                    availableHeight: monthViewport.maxHeight,
                                  ),
                            ),
                          ),
                          SizedBox(
                            height: user.manager && user.dispatch ? 72 : null,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: 16,
                                right: user.manager && user.dispatch ? 88 : 16,
                              ),
                              child: const Align(
                                alignment: Alignment.centerLeft,
                                child: DemoLabel(),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: EdgeInsets.only(
                          bottom: user.manager && user.dispatch ? 80 : 16,
                        ),
                        children: [
                          CalendarContent(
                            availableHeight:
                                viewport.maxHeight -
                                (user.manager && user.dispatch ? 104 : 40),
                          ),
                          const DemoLabel(),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    return SiblingSwipe(
      index: ['日', '周', '月'].indexOf(period),
      itemCount: 3,
      onStep: (step) {
        const periods = ['日', '周', '月'];
        final next = periods.indexOf(period) + step;
        if (next < 0 || next >= periods.length) return false;
        ref.read(periodProvider.notifier).state = periods[next];
        return true;
      },
      child: page,
    );
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final profile = ref.watch(itemProvider(('organization/profile', user.id)));
    final unread = ref.watch(recordsProvider('notifications'));
    final reviews = ref.watch(recordsProvider('reviews'));
    Widget link(String title, VoidCallback tap, {String? badge}) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: TuantuanIcon(switch (title) {
                    '消息中心' => 'notification',
                    '工作统计' || '审计记录' => 'report',
                    '审批中心' || '我的申请' => 'approval',
                    '组织与权限' || '人员展示' => 'members',
                    '设置' => 'settings',
                    '帮助与反馈' => 'help',
                    _ => 'members',
                  }, size: 27),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      switch (title) {
                        '消息中心' => '任务、审批与工作提醒',
                        '工作统计' => '查看授权范围内的工作数据',
                        '审批中心' || '我的申请' => '核对审核进度',
                        '人员展示' => '按部门查看授权范围内的成员',
                        '组织与权限' => '组织配置与权限申请',
                        '设置' => '偏好与隐私',
                        '帮助与反馈' => '使用指南',
                        _ => '查看变更与操作记录',
                      },
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF82796F),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                SunnyStatusBadge(
                  label: badge,
                  icon: Icons.circle,
                  color: const Color(0xFFB76B4D),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF9A9186),
              ),
            ],
          ),
        ),
      ),
    );
    Widget sectionTitle(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    Widget group(List<Widget> rows) => PaperSurface(
      color: DogBrandPalette.surface,
      borderColor: DogBrandPalette.line,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: 56),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFEDE8E0),
                ),
              ),
            rows[i],
          ],
        ],
      ),
    );
    return PageFrame(
      title: '我的',
      showTitle: false,
      child: PageBody(
        children: [
          PaperSurface(
            onTap: () => context.push('/me/profile'),
            color: DogBrandPalette.surface,
            borderColor: DogBrandPalette.line,
            padding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProtectedAvatar(
                          name: user.name,
                          attachmentId:
                              profile.valueOrNull?.fields['avatarAttachmentId']
                                  as String?,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontFamily: AppTypography.displayFamily,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (profile.valueOrNull?.subtitle.isNotEmpty ==
                                  true)
                                Text(
                                  profile.valueOrNull!.subtitle,
                                  style: const TextStyle(
                                    color: CuteTokens.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              AppLabelBadge(user.role.label),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: DogBrandPalette.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    profile.when(
                      loading: () => const SunnyStatusBadge(
                        label: '正在加载资料',
                        icon: Icons.sync_rounded,
                      ),
                      error: (_, _) => const Text('资料暂不可用'),
                      data: (p) => Text(
                        '${p.fields['个人介绍'] ?? p.fields['body'] ?? '暂无个人介绍'}',
                        style: const TextStyle(
                          color: CuteTokens.muted,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          sectionTitle('工作'),
          group([
            link(
              '消息中心',
              () => openList(context, 'notifications'),
              badge:
                  '${unread.valueOrNull?.items.where((r) => r.fields['read'] != true).length ?? '—'}',
            ),
            if (user.manager)
              link('工作统计', () => context.push('/me/statistics')),
            link(
              user.manager ? '审批中心' : '我的申请',
              () => context.push('/me/reviews'),
              badge: user.manager
                  ? '${reviews.valueOrNull?.items.where((r) => r.ownerId != user.id && r.fields['reviewState'] == '待审').length ?? '—'}'
                  : null,
            ),
          ]),
          if (user.administrator) ...[
            sectionTitle('管理'),
            group([
              link('组织与权限', () => context.push('/me/admin')),
              link('审计记录', () => openList(context, 'audit')),
            ]),
          ],
          sectionTitle('人员'),
          group([link('人员展示', () => context.push('/me/people'))]),
          sectionTitle('其他'),
          group([
            link('设置', () => context.push('/me/settings')),
            link('帮助与反馈', () => context.push('/me/help')),
          ]),
          const DemoLabel(),
        ],
      ),
    );
  }
}
