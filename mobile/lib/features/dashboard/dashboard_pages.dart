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
import 'package:pandora_mobile/shared/sunny_widgets.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
export 'package:pandora_mobile/features/ai_map/ai_map_page.dart';

String dayLabel(DateTime d) =>
    '${d.month}月${d.day}日 周${['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]}';
String savedTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final draftState = ref.watch(todayDraftProvider(user.id));
    final draft = draftState.valueOrNull;
    final unread = ref
        .watch(recordsProvider('notifications'))
        .valueOrNull
        ?.items
        .where((r) => r.fields['read'] != true)
        .length;
    final specs = [
      ('公司重点', SunnyPalette.blue, 'dashboard/company'),
      ('公司任务', SunnyPalette.orange, 'tasks'),
      ('个人重点', SunnyPalette.purple, 'dashboard/personal'),
      ('个人日志', SunnyPalette.mint, 'logs'),
    ];
    Widget tile(int index) {
      final spec = specs[index];
      final provider = index >= 2
          ? memberRecordsProvider((spec.$3, user.id))
          : recordsProvider(spec.$3);
      return PaperSurface(
        color: spec.$2,
        onTap: () =>
            index == 3 ? context.go('/logs') : openList(context, spec.$3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFD6E9DE)),
                  ),
                  child: TuantuanIcon(
                    ['mindmap', 'task', 'ai', 'log'][index],
                    size: 46,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  spec.$1,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (index == 3 && draftState.hasError)
              TextButton(
                onPressed: () => ref.invalidate(todayDraftProvider(user.id)),
                child: const Text('本机草稿读取失败，重试'),
              ),
            if (index == 3 && draft != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今天草稿',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '保存于 ${savedTime(draft)} · 继续写',
                      style: const TextStyle(
                        fontSize: 12,
                        color: CuteTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ref
                .watch(provider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('暂时不可用'),
                  data: (page) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (page.items.isEmpty && !(index == 3 && draft != null))
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('暂无记录'),
                        ),
                      for (final item in page.items.take(
                        index == 3 && draft != null ? 1 : 2,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                index == 1
                                    ? '截止 ${_shortDeadline(item.fields['deadline'])}'
                                    : index == 3
                                    ? '${item.fields['businessDate'] ?? ''} · 已提交'
                                    : item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CuteTokens.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            const Row(
              children: [
                TuantuanStatusPill('查看全部', color: SunnyPalette.surface),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: SunnyPalette.muted,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return PageFrame(
      title: '导图',
      actions: [
        TextButton(
          onPressed: () => openList(context, 'notifications'),
          child: Text('消息 ${unread ?? '—'}'),
        ),
      ],
      fab: user.manager && user.dispatch
          ? FloatingActionButton(
              heroTag: 'dashboard-dispatch',
              tooltip: '派发任务',
              onPressed: () => openForm(context, 'dispatch'),
              child: const Icon(Icons.add),
            )
          : null,
      child: PageBody(
        bottomPadding: 88,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const TuantuanDecoration('sparkle_pair', size: 42),
              const SizedBox(width: 4),
              Expanded(
                child: SunnyWelcome(
                  title: '你好，${user.name}',
                  subtitle: '${dayLabel(DateTime.now())} · 从重要的事开始',
                  mascotAsset: 'welcome',
                ),
              ),
              const SizedBox(width: 4),
              const TuantuanDecoration('leaf_cluster', size: 42),
            ],
          ),
          const SizedBox(height: 20),
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tile(row * 2)),
                    const SizedBox(width: 12),
                    Expanded(child: tile(row * 2 + 1)),
                  ],
                ),
              ),
            ),
          PaperSurface(
            onTap: () {
              ref.read(selectedDateProvider.notifier).state = DateTime.now();
              context.go('/view');
            },
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '打开今天的时间视图',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '查看任务期限与工作记录',
                  style: TextStyle(color: CuteTokens.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const DemoLabel(),
        ],
      ),
    );
  }
}

String _shortDeadline(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  return date == null ? '未设置' : '${date.month}月${date.day}日 ${savedTime(date)}';
}

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key, this.subordinates = false});
  final bool subordinates;
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String? member;
  int period = 0;
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final team = widget.subordinates;
    if (team && !user.manager) {
      return const PageFrame(
        title: '下属日志',
        child: EmptyIllustration(showCharacter: false, title: '无权访问'),
      );
    }
    final date = ref.watch(logFilterDateProvider);
    final editDate = date ?? DateTime.now();
    final resource = team ? 'logs/subordinates' : 'logs';
    final data = ref.watch(
      logDayRecordsProvider((resource, team ? member : user.id)),
    );
    final existing = data.valueOrNull?.items
        .where(
          (r) =>
              r.fields['businessDate'] ==
              editDate.toIso8601String().split('T').first,
        )
        .firstOrNull;
    final draftState = ref.watch(todayDraftProvider(user.id));
    final draft = draftState.valueOrNull;
    Future<void> edit({bool today = false}) async {
      final chosen = today ? DateTime.now() : editDate;
      ref.read(logDateProvider.notifier).state = chosen;
      final item = today
          ? data.valueOrNull?.items
                .where(
                  (r) =>
                      r.fields['businessDate'] ==
                      chosen.toIso8601String().split('T').first,
                )
                .firstOrNull
          : existing;
      await context.push(
        '/form/${item == null || item.fields['status'] == '草稿' ? 'log-edit' : 'log-revise'}${item == null ? '' : '?id=${encode(item.id)}&version=${item.version}'}',
      );
      ref.invalidate(todayDraftProvider(user.id));
    }

    return PageFrame(
      title: team ? '下属日志' : '日志',
      actions: [
        if (!team && user.manager)
          TextButton(
            onPressed: () => context.push('/logs/subordinates'),
            child: const Text('下属日志 ›'),
          ),
      ],
      bottom: team
          ? null
          : BottomActions(
              primary: SunnyPrimaryButton.icon(
                onPressed: data.isLoading || data.hasError
                    ? null
                    : () => edit(),
                icon: const Icon(Icons.add),
                label: Text(
                  existing != null
                      ? '${existing.fields['status'] == '草稿' ? '继续编辑' : '申请修订'}${date == null ? '今天' : dayLabel(editDate)}日志'
                      : date == null
                      ? '写今天日志'
                      : '写${editDate.month}月${editDate.day}日日志',
                ),
              ),
            ),
      child: PageBody(
        children: [
          if (!team)
            PillTabs(
              labels: const ['日报', '周报', '月报'],
              selected: period,
              onChanged: (v) => setState(() => period = v),
            ),
          if (team) ...[
            const Text(
              '仅展示授权范围内已提交日志，不含草稿',
              style: TextStyle(color: CuteTokens.muted),
            ),
            const SizedBox(height: 12),
            ref
                .watch(recordsProvider('organization'))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorPanel('$e'),
                  data: (page) => DropdownButtonFormField<String>(
                    initialValue: member,
                    decoration: const InputDecoration(labelText: '选择下属'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('全部下属')),
                      for (final person in page.items.where(
                        (p) => p.id != user.id,
                      ))
                        DropdownMenuItem(
                          value: person.id,
                          child: Text(person.title),
                        ),
                    ],
                    onChanged: (v) => setState(() => member = v),
                  ),
                ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(date == null ? '全部日期' : dayLabel(date)),
                onPressed: () async {
                  final next = await showDatePicker(
                    context: context,
                    initialDate: editDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (next != null) {
                    ref.read(logFilterDateProvider.notifier).state = next;
                  }
                },
              ),
              if (date != null)
                TextButton(
                  onPressed: () =>
                      ref.read(logFilterDateProvider.notifier).state = null,
                  child: const Text('全部日期'),
                ),
            ],
          ),
          if (!team) ...[
            if (draftState.hasError)
              ErrorPanel(
                '本机加密草稿暂时无法读取，请重试；不要清除设备数据。',
                retry: () => ref.invalidate(todayDraftProvider(user.id)),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '今天，慢慢写也没关系',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            if (date == null && (existing == null || draft != null))
              PaperSurface(
                color: const Color(0xFFFFF0DA),
                onTap: data.hasError || data.isLoading
                    ? null
                    : () => edit(today: true),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft == null ? '开始今天的日志' : '今天的日志草稿',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            draft == null
                                ? '记录工作与下一步 →'
                                : '${savedTime(draft)} 本机保存 · 继续写 →',
                            style: const TextStyle(
                              color: CuteTokens.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const TuantuanMascot('welcome', size: 62),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (!team && period > 0)
            PeriodReport(initialPeriod: period == 1 ? '周' : '月'),
          if (period == 0 || team)
            data.when(
              loading: () => const LoadingSkeleton(),
              error: (e, _) => ErrorPanel(
                '$e',
                retry: () => ref.invalidate(logDayRecordsProvider),
              ),
              data: (page) {
                final items =
                    page.items
                        .where(
                          (r) =>
                              !team ||
                              r.ownerId != user.id && isSubmittedDiary(r),
                        )
                        .toList()
                      ..sort(
                        (a, b) => '${b.fields['businessDate']}'.compareTo(
                          '${a.fields['businessDate']}',
                        ),
                      );
                if (items.isEmpty) {
                  return const EmptyIllustration(
                    title: '暂无日志',
                    subtitle: '可以更换日期或开始填写',
                  );
                }
                String group(Record r) {
                  final d = DateTime.tryParse('${r.fields['businessDate']}');
                  if (d == null) return '未标记日期';
                  if (period != 1) return '${d.year}年${d.month}月';
                  final mon = d.subtract(Duration(days: d.weekday - 1));
                  return '${mon.month}月${mon.day}日起一周';
                }

                String? last;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in items) ...[
                      if (group(r) != last)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 12),
                          child: Text(
                            last = group(r),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: CuteTokens.muted,
                            ),
                          ),
                        ),
                      _DiaryRow(
                        record: r,
                        onTap: () => openItem(context, resource, r.id),
                        onMember: team
                            ? () => context.push(
                                '/me/team/${encode(r.ownerId)}/logs${date == null ? '' : '?date=${date.toIso8601String().split('T').first}'}',
                              )
                            : null,
                      ),
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

class _DiaryRow extends StatelessWidget {
  const _DiaryRow({required this.record, required this.onTap, this.onMember});
  final Record record;
  final VoidCallback onTap;
  final VoidCallback? onMember;
  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse('${record.fields['businessDate']}');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d?.day ?? '—'}',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    d == null
                        ? '未知'
                        : '周${['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]}',
                    style: const TextStyle(
                      color: CuteTokens.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${record.fields['status'] ?? '已提交'} · v${record.version}',
                    style: const TextStyle(
                      color: Color(0xFF246447),
                      fontSize: 12,
                    ),
                  ),
                  if (onMember != null)
                    TextButton.icon(
                      onPressed: onMember,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: Text(
                        '查看 ${record.fields['authorName'] ?? record.ownerId} 的工作台',
                      ),
                    ),
                  const Divider(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) => PageFrame(
    title: '视图',
    actions: [
      TextButton(
        onPressed: () =>
            ref.read(selectedDateProvider.notifier).state = DateTime.now(),
        child: const Text('今天'),
      ),
    ],
    child: const PageBody(
      children: [DateControls(), CalendarContent(), DemoLabel()],
    ),
  );
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final profile = ref.watch(itemProvider(('organization/profile', user.id)));
    final unread = ref.watch(recordsProvider('notifications'));
    final reviews = ref.watch(recordsProvider('reviews'));
    Widget link(String title, VoidCallback tap) => Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: tap,
        ),
        const Divider(height: 1),
      ],
    );
    Widget metric(String title, String caption, VoidCallback tap) => Expanded(
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                caption,
                style: const TextStyle(fontSize: 12, color: CuteTokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
    return PageFrame(
      title: '我的',
      actions: [
        TextButton(
          onPressed: () => openForm(context, 'profile-edit'),
          child: const Text('编辑资料'),
        ),
      ],
      child: PageBody(
        children: [
          PaperSurface(
            onTap: () => context.push('/me/profile'),
            child: Column(
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (profile.valueOrNull?.subtitle.isNotEmpty == true)
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
                    const SizedBox(width: 8),
                    const TuantuanDecoration('flower_sticker', size: 42),
                  ],
                ),
                const SizedBox(height: 16),
                profile.when(
                  loading: () => const LinearProgressIndicator(),
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
          ),
          const SizedBox(height: 16),
          PaperSurface(
            color: const Color(0xFFFFF0DA),
            child: Row(
              children: [
                metric(
                  '${unread.valueOrNull?.items.where((r) => r.fields['read'] != true).length ?? '—'} 条未读消息',
                  '打开消息中心 →',
                  () => openList(context, 'notifications'),
                ),
                if (user.manager)
                  metric(
                    '${reviews.valueOrNull?.items.where((r) => r.ownerId != user.id && r.fields['reviewState'] == '待审').length ?? '—'} 项待审批',
                    '进入审批 →',
                    () => context.push('/me/reviews'),
                  ),
              ],
            ),
          ),
          const SectionHeader('工作'),
          link('消息中心', () => openList(context, 'notifications')),
          if (user.manager) link('工作统计', () => context.push('/me/statistics')),
          link(
            user.manager ? '审批中心' : '我的申请',
            () => context.push('/me/reviews'),
          ),
          if (user.manager) ...[
            const SectionHeader('管理'),
            link('下属工作台', () => context.push('/me/team')),
            link('组织与成员', () => context.push('/me/organization')),
          ],
          if (user.administrator) ...[
            link('组织与权限', () => context.push('/me/admin')),
            link('审计记录', () => openList(context, 'audit')),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => context.push('/me/settings'),
                child: const Text('设置'),
              ),
              TextButton(
                onPressed: () => context.push('/me/help'),
                child: const Text('帮助与反馈'),
              ),
            ],
          ),
          const DemoLabel(),
        ],
      ),
    );
  }
}
