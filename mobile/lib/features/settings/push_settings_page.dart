import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/push/push_controller.dart';
import '../../core/state/providers.dart';
import '../../shared/widgets.dart';

class PushSettingsPage extends ConsumerWidget {
  const PushSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pushControllerProvider),
        controller = ref.read(pushControllerProvider.notifier);
    final p = state.preferences;
    final ready = p.configured && state.clientConfigured;
    return PageFrame(
      title: '通知设置',
      child: PageBody(
        children: [
          if (state.loading) const LinearProgressIndicator(),
          if (!ready)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('移动推送尚未配置，站内消息仍可正常使用。'),
            ),
          SwitchListTile(
            title: const Text('手机通知'),
            subtitle: const Text('任务动态、截止提醒、审批与入职结果'),
            value: p.enabled,
            onChanged: state.loading || (!ready && !p.enabled)
                ? null
                : (v) => controller.update({'enabled': v}),
          ),
          ListTile(
            title: const Text('系统通知权限'),
            subtitle: Text(state.permitted ? '已允许' : '未允许'),
            trailing: TextButton(
              onPressed: () => controller.platform.settings(),
              child: const Text('系统设置'),
            ),
          ),
          for (final row in [
            ('tasks', '任务动态', p.tasks),
            ('deadlines', '截止提醒', p.deadlines),
            ('reviews', '审批与入职结果', p.reviews),
          ])
            SwitchListTile(
              title: Text(row.$2),
              value: row.$3,
              onChanged: state.loading || !p.enabled
                  ? null
                  : (v) => controller.update({row.$1: v}),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('免打扰'),
            subtitle: const Text('按北京时间，时段内的有效提醒延后发送'),
            value: p.quietEnabled,
            onChanged: state.loading || !p.enabled
                ? null
                : (v) => controller.update({'quietEnabled': v}),
          ),
          if (p.quietEnabled)
            Wrap(
              spacing: 20,
              children: [
                for (final row in [
                  ('quietStart', '开始', p.quietStart),
                  ('quietEnd', '结束', p.quietEnd),
                ])
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey('${row.$1}:${row.$3}'),
                      initialValue: row.$3,
                      decoration: InputDecoration(labelText: row.$2),
                      items: List.generate(
                        24,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text('${i.toString().padLeft(2, '0')}:00'),
                        ),
                      ),
                      onChanged: state.loading || !p.enabled
                          ? null
                          : (v) {
                              if (v != null) controller.update({row.$1: v});
                            },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 20),
          const Text('锁屏仅显示提醒摘要。系统通知关闭、厂商后台限制或网络异常可能影响送达；完整消息可在 App 内查看。'),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: state.loading
                ? null
                : () => controller.sync(ref.read(sessionProvider)),
            child: const Text('刷新通知状态'),
          ),
        ],
      ),
    );
  }
}

final membershipResultProvider = FutureProvider.autoDispose.family<Map, String>(
  (ref, id) async {
    final session = ref.watch(sessionProvider);
    if (session.token == null) throw StateError('请登录后查看');
    final api = ref.watch(pushApiFactoryProvider)(session.token!);
    ref.onDispose(api.close);
    return api.membership(id);
  },
);

class MembershipResultPage extends ConsumerWidget {
  const MembershipResultPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: '入职申请结果',
    child: PageBody(
      children: [
        ref
            .watch(membershipResultProvider(id))
            .when(
              loading: () => const CircularProgressIndicator(),
              error: (_, _) => Column(
                children: [
                  const Text('暂时无法查看该申请，请重试或核对当前账号。'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(membershipResultProvider(id)),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (r['status']) {
                    'APPROVED' => '入职申请已通过',
                    'REJECTED' => '入职申请已驳回',
                    _ => '入职申请待审核',
                  }, style: Theme.of(context).textTheme.titleLarge),
                  for (final step in r['steps'] as List? ?? [])
                    if (step is Map &&
                        step['reason'] is String &&
                        (step['reason'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('审核说明：${step['reason']}'),
                      ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await refreshCurrentSession(ref);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('账号状态刷新失败，请重试')),
                          );
                        }
                      }
                    },
                    child: const Text('刷新账号状态'),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}
