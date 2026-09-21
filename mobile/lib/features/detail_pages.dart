import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../core/config.dart';
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
  final Set<String> readIds = {};
  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final async = ref.watch(recordsProvider(resource));
    return PageFrame(
      title: resourceTitles[resource] ?? '记录',
      actions: [
        if (resource == 'dashboard/personal')
          IconButton(
            tooltip: '新增重点',
            onPressed: () => openForm(context, 'focus-edit'),
            icon: const Icon(Icons.add),
          ),
        if (resource == 'notifications')
          IconButton(
            tooltip: '全部已读',
            onPressed: () async {
              try {
                await ref
                    .read(repositoryProvider)
                    .execute('notifications', const Command('read-all', {}));
                setState(
                  () => readIds.addAll(
                    async.valueOrNull?.items.map((e) => e.id) ?? [],
                  ),
                );
              } catch (e) {
                if (context.mounted) notice(context, '$e');
              }
            },
            icon: const Icon(Icons.done_all),
          ),
        if (resource == 'analytics')
          IconButton(
            tooltip: '导出报表',
            onPressed: () => context.push('/export'),
            icon: const Icon(Icons.download_outlined),
          ),
      ],
      child: PageBody(
        children: [
          const DemoLabel(),
          if (resource == 'logs/subordinates')
            OutlinedButton.icon(
              onPressed: () async {
                final person = await showModalBottomSheet<Record>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const PersonPicker(),
                );
                if (person != null && context.mounted) {
                  openItem(context, 'organization', person.id);
                }
              },
              icon: const Icon(Icons.person_search),
              label: const Text('选择下属成员'),
            ),
          if (resource == 'analytics') ...[
            const DateControls(),
            const Text('演示口径：当前管理范围内的业务事件。比例同时显示分子、分母；不按日报字数评分。'),
            const SizedBox(height: 16),
          ],
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索记录',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          if (resource == 'notifications' || resource == 'reviews')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                spacing: 8,
                children:
                    (resource == 'notifications'
                            ? ['全部', '任务', '审批', '日志']
                            : ['全部', '待审', '已处理', '我的申请'])
                        .map(
                          (v) => ChoiceChip(
                            label: Text(v),
                            selected: filter == v,
                            onSelected: (_) => setState(() => filter = v),
                          ),
                        )
                        .toList(),
              ),
            ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const LoadingSkeleton(),
            error: (e, s) => ErrorPanel(
              '$e',
              retry: () => ref.invalidate(recordsProvider(resource)),
            ),
            data: (page) {
              final records = page.items
                  .where(
                    (r) =>
                        r.title.contains(search) &&
                        (filter == '全部' ||
                            (resource == 'notifications' &&
                                r.fields['type'] == filter) ||
                            (resource == 'reviews' &&
                                (filter == '我的申请'
                                    ? r.ownerId == ref.read(sessionProvider).id
                                    : filter == '待审'
                                    ? r.fields['reviewState'] == '待审'
                                    : r.fields['reviewState'] != '待审'))),
                  )
                  .toList();
              if (records.isEmpty) return const EmptyIllustration();
              return Column(
                children: records
                    .map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CuteCard(
                          onTap: () {
                            if (resource == 'notifications') {
                              setState(() => readIds.add(r.id));
                              openItem(
                                context,
                                r.fields['type'] == '审批'
                                    ? 'reviews'
                                    : r.fields['type'] == '日志'
                                    ? 'logs'
                                    : 'tasks',
                                '1',
                              );
                            } else {
                              openItem(context, resource, r.id);
                            }
                          },
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(r.subtitle),
                                    if (resource == 'notifications')
                                      Text(
                                        readIds.contains(r.id) ? '已读' : '未读',
                                        style: const TextStyle(
                                          color: CuteTokens.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
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
      ref.invalidate(itemProvider((widget.resource, widget.id)));
      ref.invalidate(recordsProvider(widget.resource));
      if (mounted) notice(context, AppConfig.mock ? '演示操作已记录' : '操作已提交');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final key = (widget.resource, widget.id), user = ref.watch(sessionProvider);
    return PageFrame(
      title: '${resourceTitles[widget.resource] ?? '记录'}详情',
      child: ref
          .watch(itemProvider(key))
          .when(
            loading: () => const LoadingSkeleton(),
            error: (e, s) => ErrorPanel(
              '$e',
              retry: () => ref.invalidate(itemProvider(key)),
            ),
            data: (item) {
              Widget form(String label, String kind, IconData icon) =>
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => openForm(
                            context,
                            kind,
                            id: item.id,
                            version: item.version,
                          ),
                    icon: Icon(icon),
                    label: Text(label),
                  );
              return PageBody(
                children: [
                  const DemoLabel(),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('${item.subtitle} · 版本 ${item.version}'),
                  const SizedBox(height: 20),
                  Text('${item.fields['body'] ?? ''}'),
                  if (widget.resource == 'tasks') ...[
                    const SectionHeader('任务信息'),
                    Text('主负责人：${user.name}'),
                    Text('截止：${item.fields['deadline'] ?? '尚未指定'}'),
                    const SectionHeader('操作时间线'),
                    ...List<String>.from(
                      item.fields['events'] as List? ?? [],
                    ).map(
                      (s) => ListTile(
                        leading: const Icon(
                          Icons.radio_button_checked,
                          size: 16,
                        ),
                        title: Text(s),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: busy ? null : () => action(item, 'receive'),
                      icon: const Icon(Icons.check),
                      label: const Text('接收任务'),
                    ),
                    form('提交成果反馈', 'feedback', Icons.edit_note),
                    if (user.manager) ...[
                      form('验收', 'acceptance', Icons.fact_check_outlined),
                      form('转派', 'transfer', Icons.person_add_alt),
                      form('改期', 'reschedule', Icons.event),
                      form('撤回', 'withdraw', Icons.undo),
                    ],
                  ],
                  if (widget.resource.startsWith('logs')) ...[
                    const SectionHeader('今日工作'),
                    const Text('完成需求梳理，记录待确认问题。'),
                    const SectionHeader('明日计划'),
                    const Text('补充交互稿并与协作成员确认。'),
                    if (item.ownerId == user.id)
                      form('提交修订', 'log-revise', Icons.edit_outlined),
                    TextButton.icon(
                      onPressed: () => context.push('/history?id=${item.id}'),
                      icon: const Icon(Icons.history),
                      label: const Text('历史修订与已读记录'),
                    ),
                    if (user.manager)
                      form('添加评语', 'comment', Icons.comment_outlined),
                  ],
                  if (widget.resource == 'reviews') ...[
                    const SectionHeader('版本对比'),
                    const Text('当前生效版本'),
                    Text('${item.fields['before']}'),
                    const SizedBox(height: 16),
                    const Text('候选版本'),
                    Text('${item.fields['after']}'),
                    const SectionHeader('审核链'),
                    const Text('团队长 → 部门老总 → 公司复核人'),
                    const Text('无独立复核人时保持待审；新版本通过前，旧版本继续生效。'),
                    const SizedBox(height: 16),
                    if (item.ownerId == user.id)
                      const Text('这是你发起的申请，不能自审。')
                    else ...[
                      FilledButton.icon(
                        onPressed: busy ? null : () => action(item, 'approve'),
                        icon: const Icon(Icons.check),
                        label: const Text('通过'),
                      ),
                      form('驳回并填写原因', 'reject', Icons.close),
                    ],
                    if (item.ownerId == user.id)
                      form('修订并重新提交', 'log-revise', Icons.edit_outlined),
                  ],
                  if (widget.resource == 'organization') ...[
                    const SectionHeader('正在查看下属面板'),
                    const Text('只读查看，不包含私人备注和未提交草稿。'),
                    const SectionHeader('已提交日志'),
                    const RecordList('logs/subordinates', limit: 2),
                    TextButton(
                      onPressed: () => context.go('/profile'),
                      child: const Text('返回本人面板'),
                    ),
                  ],
                  if (widget.resource == 'ai-maps') ...[
                    const SectionHeader('建议草稿'),
                    const Text('先确认关键依赖，再安排具体执行时间。请结合原始记录核对。'),
                    Text('生成时间：${item.fields['createdAt']}'),
                    const SectionHeader('来源'),
                    TextButton.icon(
                      onPressed: () => openItem(context, 'logs', '1'),
                      icon: const Icon(Icons.link),
                      label: const Text('工作日报'),
                    ),
                    TextButton.icon(
                      onPressed: () => openItem(context, 'tasks', '1'),
                      icon: const Icon(Icons.link),
                      label: const Text('关联任务'),
                    ),
                    form('编辑并确认任务草稿', 'ai-draft', Icons.edit_outlined),
                  ],
                  if (widget.resource == 'dashboard/company' ||
                      widget.resource == 'tasks')
                    form('我的私人备注', 'note', Icons.lock_outline),
                  if (widget.resource == 'dashboard/personal') ...[
                    form('编辑与排序', 'focus-edit', Icons.edit_outlined),
                    TextButton.icon(
                      onPressed: () => action(item, 'archive'),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('归档'),
                    ),
                  ],
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              );
            },
          ),
    );
  }
}
