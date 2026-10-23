import 'dart:async';
import 'package:pandora_mobile/data/models/task_display.dart';
import 'package:pandora_mobile/shared/public_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'catalog.dart';
import 'form_page.dart';
import '../../core/state/live_notifications.dart';
import '../../shared/diary_task_links.dart';
import '../../shared/diary_read_receipt.dart';
import '../../shared/generated_assets.dart';

class ListPage extends ConsumerStatefulWidget {
  const ListPage(this.resource, {super.key});
  final String resource;
  @override
  ConsumerState<ListPage> createState() => _ListPageState();
}

class _ListPageState extends ConsumerState<ListPage> {
  String search = '', filter = '全部', group = '全部标签', deadline = '全部期限';
  String? owner, ownerName;
  int inbox = 0;
  String auditActor = '';
  DateTime? auditDate;
  String? readingMessage;
  bool readingAll = false;
  Object? messageError;
  bool get messageBusy => readingMessage != null || readingAll;

  bool sameSession(Session captured) {
    if (!mounted) return false;
    final current = ref.read(sessionProvider);
    return current.id == captured.id &&
        current.token == captured.token &&
        current.canReadBusiness;
  }

  Future<void> readMessage(Record? message) async {
    if (messageBusy) return;
    final session = ref.read(sessionProvider);
    if (!session.canReadBusiness) return;
    final repository = ref.read(repositoryProvider);
    setState(() {
      readingMessage = message?.id;
      readingAll = message == null;
      messageError = null;
    });
    try {
      await repository.execute(
        'notifications',
        message == null
            ? const Command('read-all', {})
            : Command('read', {'id': message.id}),
      );
      if (!mounted) return;
      if (!sameSession(session)) return;
      ref.invalidate(recordsProvider('notifications'));
      if (message == null) return;
      final target = message.fields['targetResource'];
      final id = message.fields['targetId'];
      if (id is! String ||
          id.trim().isEmpty ||
          !['tasks', 'logs', 'reviews'].contains(target)) {
        notice(context, '消息已读，关联内容暂不可用，请返回工作台查看');
        return;
      }
      if (target == 'reviews') {
        context.push('/me/reviews/${encode(id)}');
      } else {
        openItem(context, target as String, id);
      }
    } catch (error) {
      if (sameSession(session)) setState(() => messageError = error);
    } finally {
      if (sameSession(session)) {
        setState(() {
          readingMessage = null;
          readingAll = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (before, after) {
      if (before?.id != after.id ||
          before?.token != after.token ||
          !after.canReadBusiness) {
        setState(() {
          readingMessage = null;
          readingAll = false;
          messageError = null;
          owner = null;
          ownerName = null;
        });
      }
    });
    final resource = widget.resource,
        user = ref.watch(sessionProvider),
        data = resource == 'audit'
            ? ref.watch(auditRecordsProvider)
            : ref.watch(recordsProvider(widget.resource));
    final deniedMessage =
        messageError is ApiFailure &&
        [
          FailureKind.forbidden,
          FailureKind.unauthorized,
        ].contains((messageError as ApiFailure).kind);
    Widget selector(
      String value,
      List<String> options,
      ValueChanged<String> onChanged,
    ) => PremiumDropdownField<String>(
      initialValue: value,
      decoration: const InputDecoration(border: InputBorder.none),
      isExpanded: false,
      items: options
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    Future<void> open(Record r) async {
      if (resource == 'notifications') {
        await readMessage(r);
      } else if (resource == 'organization') {
        context.push('/me/team/${encode(r.id)}');
      } else if (resource == 'reviews') {
        context.push('/me/reviews/${encode(r.id)}');
      } else {
        openItem(context, resource, r.id);
      }
    }

    return PageFrame(
      title: resourceTitles[resource] ?? '记录',
      actions: [
        if (resource == 'dashboard/personal')
          IconButton(
            tooltip: '新增重点',
            onPressed: () => openForm(context, 'focus-edit'),
            icon: const Icon(Icons.add),
          ),
        if (resource == 'tasks' && user.manager && user.dispatch)
          IconButton(
            tooltip: '派发任务',
            onPressed: () => openForm(context, 'dispatch'),
            icon: const Icon(Icons.add),
          ),
        if (resource == 'feedback')
          IconButton(
            tooltip: '提交反馈',
            onPressed: () => openForm(context, 'support'),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        if (resource == 'notifications')
          TextButton(
            onPressed: messageBusy || deniedMessage || !data.hasValue
                ? null
                : () => readMessage(null),
            child: Text(readingAll ? '正在标记…' : '全部已读'),
          ),
      ],
      child: PageBody(
        children: [
          if (resource == 'organization')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '组织成员 · 仅显示授权管理范围',
                style: TextStyle(color: CuteTokens.muted),
              ),
            ),
          TextField(
            decoration: InputDecoration(
              hintText: resource == 'organization' ? '搜索姓名、部门或团队' : '搜索标题或内容',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 12),
          if (resource == 'reviews')
            PillTabs(
              labels: const ['待处理', '我发起', '全部'],
              selected: inbox,
              onChanged: (v) => setState(() => inbox = v),
            ),
          if (resource == 'notifications')
            PillTabs(
              labels: const ['全部', '未读'],
              selected: inbox,
              onChanged: (v) => setState(() => inbox = v),
            ),
          if (resource == 'notifications') const NotificationConnectionStatus(),
          if (resource == 'tasks') ...[
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                selector(
                  group,
                  {
                    '全部标签',
                    group,
                    ...data.valueOrNull?.items.map(
                          (r) => taskTagLabel(r.fields),
                        ) ??
                        <String>[],
                  }.toList(),
                  (v) => setState(() => group = v),
                ),
                selector(deadline, const [
                  '全部期限',
                  '未来7天',
                  '已过期限',
                ], (v) => setState(() => deadline = v)),
                if (user.manager)
                  TextButton.icon(
                    onPressed: () async {
                      final p = await showTuantuanBottomSheet<Record>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const PersonPicker(),
                      );
                      if (p != null && mounted) {
                        setState(() {
                          owner = p.id;
                          ownerName = p.title;
                        });
                      }
                    },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(owner == null ? '参与人' : '参与人 $ownerName'),
                  ),
                if (owner != null)
                  TextButton(
                    onPressed: () => setState(() {
                      owner = null;
                      ownerName = null;
                    }),
                    child: const Text('清除人员'),
                  ),
              ],
            ),
          ],
          if (['notifications', 'reviews', 'audit'].contains(resource))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value
                      in resource == 'notifications'
                          ? ['全部', '任务', '审批', '评论', '待阅提醒', '截止提醒', '审核结果']
                          : resource == 'reviews'
                          ? ['全部', '待审', '已通过', '已驳回']
                          : ['全部', '日志', '任务', '组织'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TuantuanFilterChip(
                        label: Text(value),
                        selected: filter == value,
                        onSelected: (_) => setState(() => filter = value),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (resource == 'audit') ...[
            TextField(
              decoration: const InputDecoration(
                labelText: '操作者标识',
                hintText: '按服务返回的操作者匹配',
              ),
              onChanged: (v) => setState(() => auditActor = v.trim()),
            ),
            Wrap(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                    auditDate == null
                        ? '发生日期'
                        : auditDate!.toIso8601String().split('T').first,
                  ),
                  onPressed: () async {
                    final day = await showPremiumDatePicker(
                      context,
                      initial: auditDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (day != null && mounted) setState(() => auditDate = day);
                  },
                ),
                if (auditDate != null)
                  TextButton(
                    onPressed: () => setState(() => auditDate = null),
                    child: const Text('全部日期'),
                  ),
              ],
            ),
          ],
          if (messageError != null && !deniedMessage)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ErrorPanel('消息操作未完成：$messageError。请再次选择消息或全部已读重试。'),
            ),
          if (deniedMessage) ...[
            RecordFailure(messageError!),
            TextButton(
              onPressed: () {
                setState(() => messageError = null);
                ref.invalidate(recordsProvider('notifications'));
              },
              child: const Text('重新检查消息权限'),
            ),
          ] else
            data.when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const LoadingSkeleton(),
              error: (e, _) => RecordFailure(
                e,
                retry: () => resource == 'audit'
                    ? ref.invalidate(auditRecordsProvider)
                    : ref.invalidate(recordsProvider(resource)),
              ),
              data: (page) {
                final items = page.items.where((r) {
                  if (!'${r.title}${r.subtitle}${r.fields['body'] ?? ''}'
                      .contains(search)) {
                    return false;
                  }
                  if (resource == 'tasks') {
                    if (owner != null &&
                        !(r.fields['participantIds'] as List? ?? const [])
                            .map((value) => '$value')
                            .contains(owner)) {
                      return false;
                    }
                    if (group != '全部标签' && taskTagLabel(r.fields) != group) {
                      return false;
                    }
                    final due = DateTime.tryParse('${r.fields['deadline']}');
                    if (deadline == '未来7天' &&
                        (due == null ||
                            due.isBefore(DateTime.now()) ||
                            due.isAfter(
                              DateTime.now().add(const Duration(days: 7)),
                            ))) {
                      return false;
                    }
                    if (deadline == '已过期限' &&
                        (due == null || !due.isBefore(DateTime.now()))) {
                      return false;
                    }
                  }
                  if (resource == 'notifications' &&
                      (inbox == 1 && r.fields['read'] == true ||
                          filter != '全部' && r.fields['type'] != filter)) {
                    return false;
                  }
                  if (resource == 'reviews' &&
                      (inbox == 0 &&
                              (r.ownerId == user.id ||
                                  r.fields['reviewState'] != '待审') ||
                          inbox == 1 && r.ownerId != user.id ||
                          filter != '全部' &&
                              r.fields['reviewState'] != filter)) {
                    return false;
                  }
                  if (resource == 'audit' &&
                      filter != '全部' &&
                      r.fields['auditType'] != filter) {
                    return false;
                  }
                  if (resource == 'audit') {
                    if (!'${r.fields['actor_id'] ?? ''}'.contains(auditActor)) {
                      return false;
                    }
                    if (auditDate != null) {
                      final day = businessEventTime(r.fields['created_at']);
                      if (day == null ||
                          day.year != auditDate!.year ||
                          day.month != auditDate!.month ||
                          day.day != auditDate!.day) {
                        return false;
                      }
                    }
                  }
                  return true;
                }).toList();
                if (items.isEmpty) {
                  return const EmptyIllustration(
                    title: '暂无匹配记录',
                    subtitle: '可以调整筛选条件',
                  );
                }
                String? last;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in items) ...[
                      if (resource == 'notifications') ...[
                        if (last != _notificationGroup(r))
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Text(
                              last = _notificationGroup(r),
                              style: const TextStyle(
                                color: CuteTokens.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                      if (resource == 'tasks')
                        _taskCard(context, r, () => open(r))
                      else
                        InkWell(
                          onTap: resource == 'notifications' && messageBusy
                              ? null
                              : () => open(r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (resource == 'organization') ...[
                                  CircleAvatar(
                                    backgroundColor: CuteTokens.blue,
                                    child: Text(
                                      r.title.isEmpty
                                          ? '人'
                                          : r.title.substring(0, 1),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (resource == 'notifications') ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Icon(
                                      r.fields['read'] == true
                                          ? Icons.notifications_none
                                          : Icons.circle,
                                      size: r.fields['read'] == true ? 20 : 9,
                                      color: r.fields['read'] == true
                                          ? CuteTokens.muted
                                          : const Color(0xFFA7460E),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        r.subtitle,
                                        style: const TextStyle(
                                          color: CuteTokens.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (resource == 'reviews')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            '${r.fields['reviewState'] ?? ''} · 申请人 ${r.fields['applicantName'] ?? r.ownerId}',
                                            style: const TextStyle(
                                              color: CuteTokens.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      if (resource == 'notifications')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            '${r.fields['read'] == true ? '已读' : '未读'} · ${prettyDate(r.fields['createdAt'])}',
                                            style: const TextStyle(
                                              color: CuteTokens.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      if (resource == 'audit')
                                        Text(
                                          '${prettyDate(r.fields['createdAt'])} · 操作者 ${r.fields['actor_id'] ?? '未返回'}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (resource == 'notifications' &&
                                    readingMessage == r.id)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: SunnyLoadingIndicator(size: 18),
                                  )
                                else
                                  const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        ),
                      if (resource != 'tasks') const Divider(height: 1),
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

  Widget _taskCard(BuildContext context, Record record, VoidCallback onTap) {
    final f = record.fields;
    final participantNames = taskParticipantNames(f);
    final tagName = taskTagLabel(f);
    final tagCategory = '${f['tagCategory'] ?? ''}';
    final tagColor = _recordColor(f['tagColor'] ?? f['tag_color']);
    return PaperSurface(
      onTap: onTap,
      color: const Color(0xFFFFF5C8),
      texture: TuantuanAssets.textures['warmSparkle'],
      cornerDecoration: TuantuanAssets.cardCorners['warm'],
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TuantuanIconTile(
                icon: 'task',
                color: SunnyPalette.orange,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SunnyPalette.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TuantuanStatusPill(
                '${f['status'] ?? '待接收'}',
                color: SunnyPalette.mint,
                icon: Icons.flag_outlined,
              ),
              TuantuanStatusPill(
                '${tagCategory.isEmpty ? '' : '$tagCategory · '}$tagName',
                color: tagColor,
                icon: Icons.sell_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _taskSummaryLine(
            Icons.schedule_outlined,
            '截止 ${prettyDate(f['deadline'])}',
          ),
          const SizedBox(height: 6),
          _taskSummaryLine(
            Icons.group_outlined,
            participantNames.isEmpty
                ? '参与人待选择'
                : '参与人 ${participantNames.take(3).join('、')}${participantNames.length > 3 ? ' 等' : ''}',
          ),
        ],
      ),
    );
  }

  Widget _taskSummaryLine(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 17, color: CuteTokens.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: CuteTokens.muted, fontSize: 12),
        ),
      ),
    ],
  );

  Color _recordColor(dynamic value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return SunnyPalette.blue;
    final parsed = int.tryParse(text.replaceFirst('#', ''), radix: 16);
    return parsed == null
        ? SunnyPalette.blue
        : Color(
            text.replaceFirst('#', '').length <= 6
                ? 0xFF000000 | parsed
                : parsed,
          );
  }

  String _notificationGroup(Record r) {
    final d = businessEventTime(r.fields['createdAt']),
        now = shanghaiWallTime(DateTime.now());
    return d != null &&
            d.year == now.year &&
            d.month == now.month &&
            d.day == now.day
        ? '今天'
        : '更早';
  }
}

String prettyDate(dynamic value) {
  final date = businessEventTime(value);
  return date == null
      ? '未设置'
      : '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class NotificationConnectionStatus extends ConsumerWidget {
  const NotificationConnectionStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(liveNotificationsProvider);
    if (status.connection == NotificationConnection.disabled) {
      return const SizedBox.shrink();
    }
    final label = switch (status.connection) {
      NotificationConnection.live => '消息实时更新中',
      NotificationConnection.connecting => '正在连接消息更新',
      NotificationConnection.reconnecting => '消息连接中断，正在重连；可手动刷新列表',
      _ => '实时更新已暂停，列表仍可手动刷新',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          if (status.connection == NotificationConnection.stopped) ...[
            Text(
              '${status.error ?? "消息连接已关闭"}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: () =>
                  ref.read(liveNotificationsProvider.notifier).retry(),
              icon: const Icon(Icons.sync),
              label: const Text('重新连接消息'),
            ),
          ],
          if (status.connection != NotificationConnection.live)
            TextButton(
              onPressed: () => ref.invalidate(recordsProvider('notifications')),
              child: const Text('刷新消息列表'),
            ),
        ],
      ),
    );
  }
}

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage(this.resource, this.id, {super.key, this.ownerId});
  final String resource, id;
  final String? ownerId;
  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  Timer? logDeadlineTimer;
  DateTime? scheduledLogDeadline;
  void scheduleLogDeadline(Record item) {
    final deadline = LogEditWindow(item).until;
    if (deadline == scheduledLogDeadline) return;
    scheduledLogDeadline = deadline;
    logDeadlineTimer?.cancel();
    if (deadline != null && deadline.isAfter(DateTime.now())) {
      logDeadlineTimer = Timer(deadline.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    logDeadlineTimer?.cancel();
    super.dispose();
  }

  bool busy = false;
  String? error;
  late final Session initialLogIdentity = ref.read(sessionProvider);
  ApiFailure? logAccessError;
  Future<void> action(Record item, String action) async {
    if (action == 'archive') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => TuantuanDialog(
          title: const Text('确认归档？'),
          content: const Text('归档后将结束本次工作安排。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            SunnyPrimaryButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('归档'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .execute(
            widget.resource,
            Command(
              action,
              {
                'id': item.id,
                if (widget.resource == 'dashboard/personal') ...{
                  ...item.fields,
                  'title': item.title,
                  '内容': item.fields['内容'] ?? item.fields['text'] ?? '',
                  '排序位置': item.fields['排序位置'] ?? item.fields['position'] ?? 0,
                },
              },
              version: item.version,
              idempotencyKey: '${item.id}:${item.version}:$action',
            ),
          );
      refreshBusiness(ref);
      if (mounted) {
        notice(context, AppConfig.mock ? '演示操作已保存' : '操作已提交');
        if (action == 'archive' && widget.resource == 'dashboard/personal') {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> withdrawLog(Record item) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('撤回日志'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(labelText: '撤回原因'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialog, controller.text.trim());
              }
            },
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .execute(
            'logs',
            Command('withdraw', {
              'id': item.id,
              'reason': reason,
            }, version: item.version),
          );
      refreshBusiness(ref);
      if (mounted) notice(context, '日志已撤回，可以继续编辑');
    } catch (failure) {
      refreshBusiness(ref);
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void edit(Record item, String kind) {
    if (kind == 'log-revise') {
      ref.read(logDateProvider.notifier).state =
          DateTime.tryParse('${item.fields['businessDate']}') ?? DateTime.now();
    }
    openForm(
      context,
      kind,
      id: kind == 'note'
          ? '${widget.resource}:${item.id}:${ref.read(sessionProvider).id}'
          : item.id,
      version: item.version,
    );
  }

  Widget button(String label, VoidCallback callback) => SunnyPrimaryButton(
    loading: busy,
    onPressed: busy ? null : callback,
    child: Text(label),
  );
  Widget section(String title, dynamic value) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: PaperSurface(
      skin:
          TuantuanAssets.detailSections[title.contains('私人') ? 'warm' : 'blue'],
      color: title.contains('私人') ? SunnyPalette.orange : SunnyPalette.paper,
      texture: TuantuanAssets.textures['paper'],
      cornerDecoration: TuantuanAssets.cardCorners['mint'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            _value(value),
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ],
      ),
    ),
  );
  String _value(dynamic value) {
    if (value == null || '$value'.isEmpty) return '暂无内容';
    if (value is Map) {
      return value.entries.map((e) => '${e.key}：${_value(e.value)}').join('\n');
    }
    if (value is List) return value.map(_value).join('、');
    return '$value';
  }

  Widget timeline(List events) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('暂无流转记录', style: TextStyle(color: CuteTokens.muted)),
        ),
      for (final (i, event) in events.indexed)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == events.length - 1
                            ? const Color(0xFFFF8A24)
                            : CuteTokens.line,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (i < events.length - 1)
                      Expanded(
                        child: Container(width: 1, color: CuteTokens.line),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 20),
                  child: Text(
                    _value(event),
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final key = (widget.resource, widget.id), user = ref.watch(sessionProvider);
    if (widget.resource.startsWith('logs') &&
        (logAccessError != null ||
            user.id != initialLogIdentity.id ||
            user.token != initialLogIdentity.token ||
            !user.canReadBusiness)) {
      return PageFrame(
        title: '日志阅读',
        child: PageBody(
          children: [
            RecordFailure(
              logAccessError ??
                  const ApiFailure(
                    FailureKind.forbidden,
                    '阅读访问已停止，请返回后重新确认账号与权限',
                  ),
            ),
          ],
        ),
      );
    }
    final provider = widget.ownerId == null
        ? itemProvider(key)
        : scopedItemProvider((widget.resource, widget.id, widget.ownerId!));
    return ref
        .watch(provider)
        .when(
          loading: () => PageFrame(
            title: '${resourceTitles[widget.resource] ?? '记录'}详情',
            child: const LoadingSkeleton(),
          ),
          error: (e, _) => PageFrame(
            title: '${resourceTitles[widget.resource] ?? '记录'}详情',
            child: PageBody(
              children: [
                RecordFailure(e, retry: () => ref.invalidate(provider)),
              ],
            ),
          ),
          data: (item) {
            final f = item.fields,
                resource = widget.resource,
                status = '${item.fields['status'] ?? ''}';
            Widget? bottom;
            final actions = <Widget>[];
            final children = <Widget>[];
            if (resource == 'tasks') {
              final participantIds = (f['participantIds'] as List? ?? const [])
                  .map((value) => '$value')
                  .toSet();
              final participantNames = taskParticipantNames(f);
              final canActOnTask =
                  participantIds.contains(user.id) || item.ownerId == user.id;
              final dispatcher =
                  user.manager &&
                  (f['dispatcherId'] == user.id || user.administrator);
              if (canActOnTask && status == '待接收') {
                bottom = button('接收任务', () => action(item, 'receive'));
              }
              if (canActOnTask && ['进行中', '需补充'].contains(status)) {
                bottom = button('提交成果反馈', () => edit(item, 'feedback'));
              }
              if (dispatcher && status == '待验收') {
                bottom = button('查看成果并验收', () => edit(item, 'acceptance'));
              }
              if (dispatcher && status == '已验收') {
                bottom = button('归档任务', () => action(item, 'archive'));
              }
              children.addAll([
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TuantuanStatusPill(
                      '${f['status'] ?? '待接收'}',
                      color: SunnyPalette.mint,
                      icon: Icons.flag_outlined,
                    ),
                    TuantuanStatusPill(
                      '${f['tagCategory'] == null ? '' : '${f['tagCategory']} · '}${taskTagLabel(f)}',
                      color: _recordColor(f['tagColor'] ?? f['tag_color']),
                      icon: Icons.sell_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                PaperSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _attribute(
                        '开始时间',
                        prettyDate(f['startAt'] ?? f['start_at']),
                      ),
                      const SizedBox(height: 14),
                      _attribute('截止时间', prettyDate(f['deadline'])),
                      const SizedBox(height: 14),
                      _attribute(
                        '参与人',
                        participantNames.isEmpty
                            ? '尚未返回参与人'
                            : participantNames.join('、'),
                      ),
                      const SizedBox(height: 14),
                      _attribute(
                        '审核状态',
                        '${f['reviewState'] ?? f['approvalStatus'] ?? '无需审核'}',
                      ),
                    ],
                  ),
                ),
                section('任务说明', f['任务内容'] ?? f['content'] ?? f['body']),
                if (!AppConfig.mock && ['进行中', '需补充', '待验收'].contains(status))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/tasks/${encode(item.id)}/delivery-check?version=${item.version}',
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('检查交付材料'),
                    ),
                  ),
                if ((f['attachments'] as List? ?? []).isNotEmpty) ...[
                  const SectionHeader('任务附件'),
                  for (final id
                      in (f['attachments'] as List).whereType<String>())
                    PaperSurface(
                      color: CuteTokens.blue,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: const Text('任务附件'),
                        subtitle: const Text('查看并保存文件'),
                        trailing: const Icon(Icons.download_outlined),
                        onTap: () => context.push('/attachments/${encode(id)}'),
                      ),
                    ),
                ],
                if ((f['attachments'] as List? ?? []).isEmpty &&
                    '${f['附件'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: PaperSurface(
                      color: CuteTokens.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '附件：${f['附件']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '演示记录未提供文件内容',
                            style: TextStyle(
                              color: CuteTokens.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (['待验收', '需补充', '已验收', '已归档'].contains(status))
                  section('成果反馈', f['成果说明']),
                if (f['验收意见'] != null) section('验收意见', f['验收意见']),
                const SectionHeader('流转记录'),
                timeline(f['events'] as List? ?? []),
                PublicComments(resource: 'tasks', record: item),
              ]);
            } else if (resource == 'reviews') {
              final self = item.ownerId == user.id;
              final pending = f['reviewState'] == '待审';
              final steps = f['steps'] as List?;
              final assigned =
                  AppConfig.mock ||
                  (steps
                              ?.where(
                                (s) => s is Map && s['state'] == 'PENDING',
                              )
                              .firstOrNull
                          as Map?)?['reviewer_id'] ==
                      user.id;
              if (user.manager && !self && pending && assigned) {
                bottom = button('通过本级审核', () => action(item, 'approve'));
              }
              actions.add(
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      '${f['reviewState'] ?? '审核状态未提供'}',
                      style: const TextStyle(color: CuteTokens.muted),
                    ),
                  ),
                ),
              );
              children.addAll([
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '申请人 ${f['applicantName'] ?? item.ownerId} · ${prettyDate(f['createdAt'])}',
                  style: const TextStyle(fontSize: 12, color: CuteTokens.muted),
                ),
                const SizedBox(height: 20),
                PaperSurface(
                  color: const Color(0xFFFFF0DA),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '申请原因',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(_value(f['reason'])),
                    ],
                  ),
                ),
                const SectionHeader('修改内容'),
                PaperSurface(
                  outlined: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前生效 · v${f['effectiveVersion'] ?? f['baseVersion'] ?? 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: CuteTokens.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_value(f['before'])),
                      const SizedBox(height: 16),
                      const Text(
                        '全部审核通过前，继续使用此版本',
                        style: TextStyle(color: CuteTokens.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PaperSurface(
                  color: CuteTokens.mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '候选版本 · v${f['candidateVersion'] ?? ((f['baseVersion'] as int? ?? 1) + 1)} · ${pending ? '待审核' : f['reviewState']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF246447),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _value(f['after']),
                        style: const TextStyle(height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SectionHeader('审核链'),
                if (!AppConfig.mock && (steps == null || steps.isEmpty))
                  const Text(
                    '等待配置独立复核人',
                    style: TextStyle(color: CuteTokens.muted),
                  ),
                if (!AppConfig.mock && steps != null)
                  for (final node in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '复核人 ${node['reviewer_id']} · ${node['state']} ${node['reason'] ?? ''}',
                      ),
                    ),
                if (AppConfig.mock)
                  for (final (i, label) in ['团队复核', '部门复核', '公司复核'].indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${i < (f['step'] as int? ?? 0) ? '●' : '○'} $label · ${f['reviewState'] == '已驳回'
                            ? '申请已驳回'
                            : i < (f['step'] as int? ?? 0)
                            ? '已处理'
                            : i == (f['step'] as int? ?? 0)
                            ? '等待独立复核'
                            : '下一步'}',
                        style: TextStyle(
                          color: i == (f['step'] as int? ?? 0)
                              ? CuteTokens.ink
                              : CuteTokens.muted,
                        ),
                      ),
                    ),
                for (final event in (f['reviewEvents'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_value(event)),
                  ),
                const SizedBox(height: 20),
                Text(
                  self ? '这是你发起的申请，不能审核自己的修改' : '申请人不能审核自己的修改',
                  style: const TextStyle(color: CuteTokens.muted, fontSize: 12),
                ),
                if (self &&
                    f['reviewState'] == '已驳回' &&
                    f['targetId'] != null &&
                    ['logs', 'dashboard/company'].contains(f['targetResource']))
                  TextButton(
                    onPressed: () => openForm(
                      context,
                      f['targetResource'] == 'logs' ? 'log-revise' : 'publish',
                      id: '${f['targetId']}',
                    ),
                    child: const Text('修改后重新提交'),
                  ),
              ]);
            } else if (resource.startsWith('logs')) {
              scheduleLogDeadline(item);
              final window = LogEditWindow(item);
              if (item.ownerId == user.id &&
                  window.canWithdrawAt(DateTime.now())) {
                actions.add(
                  TextButton(
                    onPressed: busy ? null : () => edit(item, 'log-withdraw'),
                    child: const Text('撤回日志'),
                  ),
                );
              }
              if (item.ownerId == user.id) {
                final canEdit = window.canEditAt(DateTime.now());
                bottom = !window.submitted
                    ? SunnyPrimaryButton(
                        onPressed: busy || !canEdit
                            ? null
                            : () => action(item, 'submit'),
                        child: const Text('提交日志'),
                      )
                    : SunnyPrimaryButton(
                        onPressed: busy || !canEdit
                            ? null
                            : () => edit(item, 'log-revise'),
                        child: Text(canEdit ? '申请修订日志' : '已满24小时 · 日志已锁定'),
                      );
                if (!window.submitted) {
                  actions.add(
                    TextButton(
                      onPressed: canEdit ? () => edit(item, 'log-edit') : null,
                      child: const Text('编辑草稿'),
                    ),
                  );
                }
              }
              children.addAll([
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${f['businessDate'] ?? ''} · 作者 ${f['authorName'] ?? item.ownerId} · ${f['status'] ?? (isSubmittedDiary(item) ? '已提交' : '提交状态未确认')}',
                  style: const TextStyle(color: CuteTokens.muted, fontSize: 12),
                ),
                if (f['editableUntil'] != null)
                  Text('可申请修订至 ${prettyDate(f['editableUntil'])}'),
                if (isSubmittedDiary(item) &&
                    businessEventTime(f['submittedAt']) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '提交于 ${prettyDate(f['submittedAt'])}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                PaperSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final label in [
                        '今日工作',
                        '关联任务',
                        '遇到的阻碍',
                        '明日计划',
                        '工时',
                      ]) ...[
                        if (label != '工时' ||
                            '${f[label] ?? ''}'.isNotEmpty) ...[
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (label == '关联任务')
                            DiaryTaskLinksReader(f['taskIds'] ?? f[label])
                          else
                            Text(
                              _value(f[label]),
                              style: const TextStyle(fontSize: 15, height: 1.8),
                            ),
                          if (label != '工时') const Divider(height: 32),
                        ],
                      ],
                    ],
                  ),
                ),
                if (isSubmittedDiary(item)) ...[
                  const SizedBox(height: 20),
                  DiaryReadReceipt(
                    item,
                    key: ValueKey('diary-read:${item.id}'),
                    onAccessDenied: (failure) {
                      if (mounted) setState(() => logAccessError = failure);
                    },
                  ),
                ],
                if (isSubmittedDiary(item))
                  PublicComments(resource: 'logs', record: item),
              ]);
            } else if (resource == 'organization') {
              children.addAll([
                PaperSurface(
                  color: CuteTokens.blue,
                  child: Text(
                    '正在查看：${item.title} · 只读面板',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                section('个人介绍', f['个人介绍'] ?? f['body']),
                const Text('不展示私人备注或未提交草稿'),
                MemberRecords(
                  ownerId: item.id,
                  resource: 'dashboard/personal',
                  title: '个人重点',
                ),
                MemberRecords(
                  ownerId: item.id,
                  resource: 'logs/subordinates',
                  title: '已提交日志',
                ),
                TextButton(
                  onPressed: () => context.go('/me'),
                  child: const Text('返回本人面板'),
                ),
              ]);
            } else if (resource == 'audit') {
              children.addAll([
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                section('事件类型', f['type']),
                section('操作者', f['actor_id']),
                section('发生时间', f['created_at']),
                section('修改对象', f['object_id']),
                section('变更理由', f['reason']),
                section('修改前', f['before']),
                section('修改后', f['after']),
                if (f['trace_id'] != null) section('追踪信息', f['trace_id']),
                const Text('只读审计记录，不提供修改入口。'),
              ]);
            } else if (resource == 'ai-maps') {
              final sourcePaths = (f['sources'] as List? ?? [])
                  .map((e) => '$e')
                  .where(
                    (e) => RegExp(r'^/item/(tasks|logs)/[^/]+$').hasMatch(e),
                  )
                  .toList();
              children.addAll([
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                section('建议草稿', f['body']),
                section(
                  '依据与不确定性',
                  f['uncertainty'] ?? '当前记录不足以确认实际影响，请核对来源与责任人。',
                ),
                Text('生成时间：${prettyDate(f['createdAt'])}'),
                const SectionHeader('参考来源'),
                for (final path in sourcePaths)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(path.contains('/logs/') ? '工作日志' : '工作任务'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(path),
                  ),
                if (sourcePaths.isEmpty) const Text('来源缺失，不能确认创建任务'),
                const SizedBox(height: 16),
                const Text(
                  '建议需人工核实，不会自动派发任务。',
                  style: TextStyle(color: CuteTokens.muted),
                ),
              ]);
              if (sourcePaths.isNotEmpty && user.manager && user.dispatch) {
                bottom = button(
                  '编辑并确认任务草稿',
                  () => context.push('/form/ai-draft?source=${item.id}'),
                );
              }
            } else {
              children.addAll([
                Text(
                  item.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.subtitle,
                  style: const TextStyle(color: CuteTokens.muted),
                ),
                section(
                  resource == 'feedback' ? '问题描述' : '内容',
                  f['内容'] ?? f['body'],
                ),
              ]);
              if (resource == 'dashboard/company') {
                actions.add(
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (v) => edit(item, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'note', child: Text('我的私人备注')),
                      if (user.manager)
                        const PopupMenuItem(
                          value: 'publish',
                          child: Text('申请修改展示项'),
                        ),
                    ],
                  ),
                );
              }
              if (resource == 'dashboard/personal' && item.ownerId == user.id) {
                bottom = button('编辑与排序', () => edit(item, 'focus-edit'));
                actions.add(
                  PopupMenuButton<String>(
                    tooltip: '更多操作',
                    onSelected: (v) =>
                        v == 'archive' ? action(item, v) : edit(item, v),
                    itemBuilder: (_) => const [
                      if (AppConfig.mock)
                        PopupMenuItem(value: 'note', child: Text('我的私人备注')),
                      PopupMenuItem(value: 'archive', child: Text('归档重点')),
                    ],
                  ),
                );
              }
            }
            if (resource == 'dashboard/company' ||
                resource == 'dashboard/personal' && item.ownerId == user.id) {
              children.add(
                OwnPrivateNote(resource: resource, recordId: item.id),
              );
            }
            if (error != null && bottom == null) {
              children.add(
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ErrorPanel(
                    error!,
                    retry: () => ref.invalidate(itemProvider(key)),
                  ),
                ),
              );
            }
            children.add(const DemoLabel());
            final review = resource == 'reviews' && bottom != null;
            return PageFrame(
              title: resource == 'tasks'
                  ? '任务详情'
                  : resource == 'reviews'
                  ? '修订审批'
                  : resource.startsWith('logs')
                  ? '工作日志'
                  : '${resourceTitles[resource] ?? '记录'}详情',
              actions: actions,
              bottom: bottom == null
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 128),
                              child: SingleChildScrollView(
                                child: ErrorPanel(
                                  error!,
                                  retry: () {
                                    setState(() => error = null);
                                    ref.invalidate(itemProvider(key));
                                  },
                                ),
                              ),
                            ),
                          ),
                        BottomActions(
                          primary: bottom,
                          secondary: review
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => edit(item, 'reject'),
                                  child: const Text('驳回'),
                                )
                              : null,
                          note: review ? '驳回必须填写原因；冲突需重新读取' : null,
                        ),
                      ],
                    ),
              child: PageBody(children: children),
            );
          },
        );
  }

  Color _recordColor(dynamic value) {
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return SunnyPalette.blue;
    final normalized = text.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null
        ? SunnyPalette.blue
        : Color(normalized.length <= 6 ? 0xFF000000 | parsed : parsed);
  }

  Widget _attribute(String label, dynamic value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 84,
        child: Text(
          label,
          style: const TextStyle(color: CuteTokens.muted, fontSize: 13),
        ),
      ),
      Expanded(
        child: Text(
          _value(value),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    ],
  );
}

class OwnPrivateNote extends ConsumerWidget {
  const OwnPrivateNote({
    super.key,
    required this.resource,
    required this.recordId,
  });
  final String resource, recordId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = PrivateNoteTarget(
      resource,
      recordId,
      ref.watch(sessionProvider).id,
    );
    final id = target.key;
    if (!AppConfig.mock && !target.supported) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader('我的私人备注'),
          Text('此类重点的私人备注尚未接入；公司重点和任务提供独立备注入口。'),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PaperSurface(
        color: SunnyPalette.orange,
        cornerDecoration: TuantuanAssets.cardCorners['warm'],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                TuantuanIconTile(
                  icon: 'log',
                  color: SunnyPalette.orange,
                  size: 36,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '我的私人备注',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                Icon(Icons.lock_outline_rounded, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '仅本人可见，不进入公开资料、下属工作台或 AI 来源。',
              style: TextStyle(fontSize: 12, color: CuteTokens.muted),
            ),
            const SizedBox(height: 12),
            ref
                .watch(itemProvider(('private-notes', id)))
                .when(
                  loading: () => const SunnyLoadingIndicator(),
                  error: (e, _) =>
                      e is ApiFailure && e.kind == FailureKind.notFound
                      ? const Text('暂无私人备注')
                      : RecordFailure(
                          e,
                          retry: () => ref.invalidate(
                            itemProvider(('private-notes', id)),
                          ),
                        ),
                  data: (note) => PaperSurface(
                    child: Text(
                      '${note.fields['备注'] ?? note.fields['body'] ?? ''}',
                    ),
                  ),
                ),
            OutlinedButton.icon(
              onPressed: () => openForm(context, 'note', id: id),
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text('编辑私人备注'),
            ),
          ],
        ),
      ),
    );
  }
}

class MemberRecords extends ConsumerWidget {
  const MemberRecords({
    super.key,
    required this.ownerId,
    required this.resource,
    required this.title,
    this.previewLimit,
    this.onViewAll,
  });
  final String ownerId, resource, title;
  final int? previewLimit;
  final VoidCallback? onViewAll;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title),
      ref
          .watch(memberRecordsProvider((resource, ownerId)))
          .when(
            loading: () => const SunnyLoadingIndicator(),
            error: (e, s) => RecordFailure(
              e,
              retry: () =>
                  ref.invalidate(memberRecordsProvider((resource, ownerId))),
            ),
            data: (loaded) {
              final visible = loaded.items
                  .where(
                    (r) => !resource.startsWith('logs') || isSubmittedDiary(r),
                  )
                  .toList();
              return Column(
                children: [
                  if (visible.isEmpty) const Text('暂无记录'),
                  for (final r
                      in previewLimit == null
                          ? visible
                          : visible.take(previewLimit!))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.title),
                      subtitle: Text(
                        resource.startsWith('logs')
                            ? '${r.fields['businessDate'] ?? '未标记业务日期'} · 已提交'
                            : resource == 'tasks'
                            ? '截止 ${businessEventTime(r.fields['deadline']) ?? '未设置'}'
                            : r.subtitle,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openItem(
                        context,
                        resource,
                        r.id,
                        ownerId: resource == 'dashboard/personal'
                            ? ownerId
                            : null,
                      ),
                    ),
                  if (onViewAll != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: onViewAll,
                        child: Text('查看全部 ${visible.length} 条$title →'),
                      ),
                    ),
                ],
              );
            },
          ),
    ],
  );
}
