import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../shared/widgets.dart';
import 'catalog.dart';
import 'form_page.dart';

class ListPage extends ConsumerStatefulWidget {
  const ListPage(this.resource, {super.key});
  final String resource;
  @override
  ConsumerState<ListPage> createState() => _ListPageState();
}

class _ListPageState extends ConsumerState<ListPage> {
  String search = '', filter = '全部';
  Record? person;
  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final data = ref.watch(recordsProvider(resource));
    return PageFrame(
      title: resourceTitles[resource] ?? '记录',
      actions: [
        if (resource == 'dashboard/personal')
          IconButton(
            tooltip: '新增重点',
            onPressed: () => openForm(context, 'focus-edit'),
            icon: const Icon(Icons.add),
          ),
        if (resource == 'tasks' && ref.watch(sessionProvider).dispatch)
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
          IconButton(
            tooltip: '全部已读',
            onPressed: () async {
              try {
                await ref
                    .read(repositoryProvider)
                    .execute(resource, const Command('read-all', {}));
                refreshBusiness(ref);
              } catch (e) {
                if (context.mounted) notice(context, '$e');
              }
            },
            icon: const Icon(Icons.done_all),
          ),
      ],
      child: PageBody(
        children: [
          const DemoLabel(),
          if (resource == 'logs/subordinates')
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showModalBottomSheet<Record>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const PersonPicker(),
                );
                if (selected != null) setState(() => person = selected);
              },
              icon: const Icon(Icons.person_search),
              label: Text(person == null ? '选择下属成员' : '正在查看：${person!.title}'),
            ),
          if (person != null)
            TextButton(
              onPressed: () => openItem(context, 'organization', person!.id),
              child: const Text('查看成员个人面板'),
            ),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索标题或内容',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 12),
          if (['notifications', 'reviews', 'tasks'].contains(resource))
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  (resource == 'notifications'
                          ? ['全部', '未读', '任务', '审批', '日志', '截止提醒', '审核结果']
                          : resource == 'reviews'
                          ? ['全部', '待审', '已通过', '已驳回', '我的申请']
                          : [
                              '全部',
                              '待接收',
                              '进行中',
                              '待验收',
                              '需补充',
                              '已验收',
                              '已归档',
                              '已撤回',
                            ])
                      .map(
                        (v) => ChoiceChip(
                          label: Text(v),
                          selected: filter == v,
                          onSelected: (_) => setState(() => filter = v),
                        ),
                      )
                      .toList(),
            ),
          const SizedBox(height: 16),
          data.when(
            loading: () => const LoadingSkeleton(),
            error: (e, s) => ErrorPanel(
              '$e',
              retry: () => ref.invalidate(recordsProvider(resource)),
            ),
            data: (page) {
              final items = page.items
                  .where(
                    (r) =>
                        '${r.title}${r.subtitle}${r.fields['body']}'.contains(
                          search,
                        ) &&
                        (person == null || r.ownerId == person!.id) &&
                        (filter == '全部' ||
                            filter == r.fields['status'] ||
                            filter == r.fields['reviewState'] ||
                            filter == r.fields['type'] ||
                            (filter == '未读' && r.fields['read'] != true) ||
                            (filter == '我的申请' &&
                                r.ownerId == ref.read(sessionProvider).id)),
                  )
                  .toList();
              if (items.isEmpty) return const EmptyIllustration();
              return Column(
                children: items
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CuteCard(
                          onTap: () async {
                            if (resource == 'notifications') {
                              try {
                                await ref
                                    .read(repositoryProvider)
                                    .execute(
                                      resource,
                                      Command('read', {'id': r.id}),
                                    );
                                refreshBusiness(ref);
                                if (context.mounted) {
                                  openItem(
                                    context,
                                    '${r.fields['targetResource']}',
                                    '${r.fields['targetId']}',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) notice(context, '$e');
                              }
                            } else {
                              openItem(context, resource, r.id);
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(r.subtitle),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (resource == 'notifications')
                                    StatusPill(
                                      r.fields['read'] == true ? '已读' : '未读',
                                      color: r.fields['read'] == true
                                          ? CuteTokens.blue
                                          : CuteTokens.yellow,
                                    ),
                                  if (resource == 'tasks') ...[
                                    StatusPill(
                                      '${r.fields['status'] ?? '待接收'}',
                                    ),
                                    StatusPill(
                                      '${r.fields['紧急程度'] ?? '普通'}',
                                      color: CuteTokens.yellow,
                                    ),
                                  ],
                                  if (resource == 'reviews')
                                    StatusPill('${r.fields['reviewState']}'),
                                  if (resource.startsWith('logs') ||
                                      resource == 'feedback')
                                    StatusPill(
                                      '${r.fields['status'] ?? '已提交'}',
                                    ),
                                ],
                              ),
                              if (resource == 'tasks')
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '${r.fields['主负责人'] ?? '待分配'} · 截止 ${prettyDate(r.fields['deadline'])}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

String prettyDate(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  return date == null
      ? '未设置'
      : '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage(this.resource, this.id, {super.key});
  final String resource, id;
  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  bool busy = false;
  String? error;
  Future<void> action(Record item, String action) async {
    if (action == 'archive') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('确认归档？'),
          content: const Text('归档后将结束本次工作安排。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
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
              {'id': item.id},
              version: item.version,
              idempotencyKey: '${item.id}:${item.version}:$action',
            ),
          );
      refreshBusiness(ref);
      if (mounted) {
        notice(context, '演示操作已保存');
        if (action == 'archive' && widget.resource == 'dashboard/personal') {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.resource, widget.id),
        user = ref.watch(sessionProvider),
        resource = widget.resource;
    return PageFrame(
      title: '${resourceTitles[resource] ?? '记录'}详情',
      child: ref
          .watch(itemProvider(key))
          .when(
            loading: () => const LoadingSkeleton(),
            error: (e, s) => ErrorPanel(
              '$e',
              retry: () => ref.invalidate(itemProvider(key)),
            ),
            data: (item) {
              Widget form(String label, String kind) => OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => openForm(
                        context,
                        kind,
                        id: kind == 'note' ? '$resource:${item.id}:${user.id}' : item.id,
                        version: item.version,
                      ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(label),
              );
              Widget section(String title, dynamic value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title),
                  Text('$value'.isEmpty ? '暂无内容' : '$value'),
                ],
              );
              final f = item.fields, status = '${item.fields['status'] ?? ''}';
              return PageBody(
                children: [
                  const DemoLabel(),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('${item.subtitle} · 版本 ${item.version}'),
                  const SizedBox(height: 16),
                  if (status.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(status),
                    ),
                  if (resource == 'tasks') ...[
                    section('工作要求', f['任务内容'] ?? f['body'] ?? ''),
                    const SectionHeader('任务信息'),
                    CuteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('主负责人：${f['主负责人'] ?? '未指定'}'),
                          Text('协作人：${f['协作人'] ?? '无'}'),
                          Text('分组：${f['所属分组'] ?? '日常工作'}'),
                          Text('紧急程度：${f['紧急程度'] ?? '普通'}'),
                          Text('截止：${prettyDate(f['deadline'])}'),
                        ],
                      ),
                    ),
                    if ('${f['附件'] ?? ''}'.isNotEmpty)
                      section('附件（本地演示）', f['附件']),
                    if (['待验收', '需补充', '已验收', '已归档'].contains(status))
                      section('成果反馈', f['成果说明'] ?? '暂无成果'),
                    if (f['验收意见'] != null) section('验收意见', f['验收意见']),
                    const SectionHeader('操作时间线'),
                    for (final event in (f['events'] as List? ?? []))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text('$event'),
                      ),
                    if (item.ownerId == user.id && status == '待接收')
                      FilledButton(
                        onPressed: busy ? null : () => action(item, 'receive'),
                        child: const Text('接收任务'),
                      ),
                    if (item.ownerId == user.id &&
                        ['进行中', '需补充'].contains(status))
                      form('提交成果反馈', 'feedback'),
                    if (user.manager && status == '待验收') ...[
                      form('验收通过', 'acceptance'),
                      form('退回补充', 'return'),
                    ],
                    if (user.manager &&
                        !['已归档', '已撤回', '已验收'].contains(status)) ...[
                      form('转派任务', 'transfer'),
                      form('调整截止时间', 'reschedule'),
                      form('撤回任务', 'withdraw'),
                    ],
                    if (user.manager && status == '已验收')
                      OutlinedButton(
                        onPressed: busy ? null : () => action(item, 'archive'),
                        child: const Text('归档任务'),
                      ),
                  ] else if (resource.startsWith('logs')) ...[
                    for (final label in ['今日工作', '遇到的阻碍', '明日计划', '工时'])
                      section(label, f[label] ?? '暂无记录'),
                    if ('${f['关联任务'] ?? ''}'.isNotEmpty)
                      TextButton.icon(
                        onPressed: () =>
                            openItem(context, 'tasks', '${f['关联任务']}'),
                        icon: const Icon(Icons.link),
                        label: const Text('查看关联任务'),
                      ),
                    const SectionHeader('上级评语'),
                    if ((f['comments'] as List? ?? []).isEmpty)
                      const Text('暂无评语'),
                    for (final c in (f['comments'] as List? ?? []))
                      ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text('$c'),
                      ),
                    if (item.ownerId == user.id) form('提交修订', 'log-revise'),
                    if (user.manager) form('添加评语', 'comment'),
                    TextButton.icon(
                      onPressed: () => context.push('/history?id=${item.id}'),
                      icon: const Icon(Icons.history),
                      label: const Text('历史修订与已读记录'),
                    ),
                  ] else if (resource == 'reviews') ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill('${f['reviewState']}'),
                    ),
                    section('申请理由', f['reason'] ?? '补充业务内容'),
                    const SectionHeader('版本对比'),
                    CuteCard(
                      color: CuteTokens.cream,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('当前生效版本'),
                          const SizedBox(height: 8),
                          Text('${f['before']}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CuteCard(
                      color: CuteTokens.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('候选版本'),
                          const SizedBox(height: 8),
                          Text('${f['after']}'),
                        ],
                      ),
                    ),
                    const SectionHeader('审核进度'),
                    for (final (i, label) in ['团队复核', '部门复核', '公司复核'].indexed)
                      ListTile(
                        leading: Icon(
                          i < (f['step'] as int? ?? 0)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: i < (f['step'] as int? ?? 0)
                              ? Colors.teal
                              : CuteTokens.muted,
                        ),
                        title: Text(label),
                        subtitle: Text(
                          f['reviewState'] == '已驳回'
                              ? '申请已驳回'
                              : i < (f['step'] as int? ?? 0)
                              ? '已处理'
                              : i == (f['step'] as int? ?? 0)
                              ? '当前待处理'
                              : '等待前级审核',
                        ),
                      ),
                    for (final event in (f['reviewEvents'] as List? ?? []))
                      Text('$event'),
                    const SizedBox(height: 12),
                    const Text('演示中切换管理角色可查看各级复核；通过全部步骤后正式内容更新。'),
                    if (item.ownerId == user.id) const Text('这是你发起的申请，不能自审。'),
                    if (user.manager &&
                        item.ownerId != user.id &&
                        f['reviewState'] == '待审') ...[
                      FilledButton(
                        onPressed: busy ? null : () => action(item, 'approve'),
                        child: const Text('通过当前审核'),
                      ),
                      form('驳回并填写原因', 'reject'),
                    ],
                    if (item.ownerId == user.id &&
                        f['reviewState'] == '已驳回' &&
                        f['targetId'] != null)
                      TextButton(
                        onPressed: () => openForm(
                          context,
                          f['targetResource'] == 'logs'
                              ? 'log-revise'
                              : 'publish',
                          id: '${f['targetId']}',
                        ),
                        child: const Text('修改后重新提交'),
                      ),
                  ] else if (resource == 'organization') ...[
                    CuteCard(
                      color: CuteTokens.blue,
                      child: Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('正在查看：${item.title}\n${item.subtitle}'),
                          ),
                        ],
                      ),
                    ),
                    section('个人介绍', f['body'] ?? ''),
                    const Text('只读面板 · 不展示私人备注和未提交草稿'),
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
                      onPressed: () => context.go('/profile'),
                      child: const Text('返回本人面板'),
                    ),
                  ] else if (resource == 'ai-maps') ...[
                    section('建议草稿', f['body'] ?? ''),
                    section(
                      '推荐步骤',
                      '1. 确认关键依赖与负责人\n2. 拆分交付内容并明确时间\n3. 组织评审，记录反馈',
                    ),
                    section('风险解释', '依赖事项尚未确认，可能影响后续评审。建议先与相关成员同步。'),
                    Text('生成时间：${prettyDate(f['createdAt'])}'),
                    const SectionHeader('参考来源'),
                    if(f['sourceResource'] != null) TextButton.icon(onPressed:()=>openItem(context,'${f['sourceResource']}','${f['sourceId']}'),icon:const Icon(Icons.link),label:const Text('查看生成依据'))
                    else ...[
                      if(ref.watch(recordsProvider('logs')).valueOrNull?.items.isNotEmpty ?? false) TextButton.icon(onPressed:()=>openItem(context,'logs',ref.read(recordsProvider('logs')).valueOrNull!.items.first.id),icon:const Icon(Icons.link),label:const Text('工作日报')),
                      if(ref.watch(recordsProvider('tasks')).valueOrNull?.items.isNotEmpty ?? false) TextButton.icon(onPressed:()=>openItem(context,'tasks',ref.read(recordsProvider('tasks')).valueOrNull!.items.first.id),icon:const Icon(Icons.link),label:const Text('关联任务')),
                    ],
                    if (user.manager && user.dispatch)
                      FilledButton(
                        onPressed: () =>
                            context.push('/form/ai-draft?source=${item.id}'),
                        child: const Text('编辑并确认任务草稿'),
                      ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('暂不采用'),
                    ),
                  ] else ...[
                    section(
                      resource == 'feedback' ? '问题描述' : '内容',
                      f['body'] ?? '',
                    ),
                    if (resource == 'feedback') ...[
                      section('处理进度', '已收到反馈 · 等待处理'),
                      section('处理意见', '暂未收到处理回复'),
                    ],
                  ],
                  if (resource == 'dashboard/company' || resource == 'tasks')
                    form('我的私人备注', 'note'),
                  if (resource == 'dashboard/company' && user.manager)
                    form('修改公司展示项', 'publish'),
                  if (resource == 'dashboard/personal' && item.ownerId == user.id) ...[
                    form('编辑与排序', 'focus-edit'),
                    TextButton(
                      onPressed: busy ? null : () => action(item, 'archive'),
                      child: const Text('归档重点'),
                    ),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (busy) const LinearProgressIndicator(),
                ],
              );
            },
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
  });
  final String ownerId, resource, title;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title),
      ref
          .watch(memberRecordsProvider((resource, ownerId)))
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (e, s) => Text('$e'),
            data: (page) => Column(
              children: [
                if (page.items.isEmpty) const Text('暂无记录'),
                for (final r in page.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.title),
                    subtitle: Text(r.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openItem(context, resource, r.id),
                  ),
              ],
            ),
          ),
    ],
  );
}
