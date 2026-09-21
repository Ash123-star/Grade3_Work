import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/config.dart';
import '../core/providers.dart';
import '../data/models.dart';
import '../data/mock_repository.dart';
import '../shared/widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: '设置',
    child: PageBody(
      children: [
        const SectionHeader('阅读偏好'),
        Text('文字大小 ${(ref.watch(fontScaleProvider) * 100).round()}%'),
        Slider(
          value: ref.watch(fontScaleProvider),
          min: 1,
          max: 1.5,
          divisions: 5,
          onChanged: (v) => ref.read(fontScaleProvider.notifier).state = v,
        ),
        ListTile(
          title: const Text('修改密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => openForm(context, 'password'),
        ),
        ListTile(
          title: const Text('隐私与数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/privacy'),
        ),
        ListTile(
          title: const Text('开源素材许可'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/licenses'),
        ),
        if (AppConfig.mock) ...[
          const SectionHeader('演示环境'),
          DropdownButtonFormField<UserRole>(
            initialValue: ref.watch(sessionProvider).role,
            decoration: const InputDecoration(labelText: '预览角色'),
            items: UserRole.values
                .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                .toList(),
            onChanged: (r) {
              if (r != null) {
                ref.read(sessionProvider.notifier).state = Session(
                  role: r,
                  dispatch: r != UserRole.employee,
                );
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DemoScenario>(
            initialValue: ref.watch(scenarioProvider),
            decoration: const InputDecoration(labelText: '数据场景'),
            items: DemoScenario.values
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(['正常', '空数据', '网络超时', '权限拒绝'][s.index]),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) ref.read(scenarioProvider.notifier).state = v;
            },
          ),
          SwitchListTile(
            title: const Text('派发任务资格'),
            value: ref.watch(sessionProvider).dispatch,
            onChanged: (v) {
              final u = ref.read(sessionProvider);
              ref.read(sessionProvider.notifier).state = Session(
                role: u.role,
                dispatch: v,
              );
            },
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            ref.read(sessionProvider.notifier).state = const Session(
              active: false,
              role: UserRole.employee,
              dispatch: false,
            );
            context.go('/form/login');
          },
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
      ],
    ),
  );
}

class UtilityPage extends ConsumerStatefulWidget {
  const UtilityPage(this.kind, {super.key});
  final String kind;
  @override
  ConsumerState<UtilityPage> createState() => _UtilityPageState();
}

class _UtilityPageState extends ConsumerState<UtilityPage> {
  String result = '';
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (widget.kind) {
      'pending' => ('等待归属确认', '你的员工申请已登记。管理员确认部门后，才能查看公司内部内容。'),
      'disabled' => ('账号已停用', '当前会话已撤销，请联系公司管理员确认账号状态。'),
      'expired' => ('登录已失效', '请重新登录后继续。未提交的本地日志草稿会保留。'),
      'privacy' => (
        '隐私与数据',
        '私人备注和未提交草稿仅本人可见。AI 只处理授权业务文本，不接收手机号、密码和私人备注。账号权限以服务端校验为准。',
      ),
      'licenses' => (
        '素材与开源许可',
        'OpenMoji，作者：HfG Schwäbisch Gmünd 及 OpenMoji contributors。来源：https://openmoji.org/ 。许可：CC BY-SA 4.0（https://creativecommons.org/licenses/by-sa/4.0/）。本项目原样使用六份 SVG，未修改图形。Flutter 组件许可可在下方查看。',
      ),
      'history' => ('历史修订与已读', '演示：v1 为当前生效版本；v2 为待审候选版本。上级已读记录与正文独立保存。'),
      'conflict' => (
        '草稿与同步',
        '本地草稿独立保存。接入服务后，服务器版本发生变化时，选择保留本地内容或重新读取服务器版本，不自动覆盖。',
      ),
      'report' => ('周报与月报', '按所选业务日期区间聚合已提交日报。AI 摘要为建议草稿，发布前请核对来源。'),
      'ai-usage' => (
        'AI 用量与来源',
        '演示：今日 0 次真实调用；本地示例不消耗模型额度。预算达到上限时停止生成，任务和日志继续可用。',
      ),
      'export' => ('统计导出', '导出仅包含当前授权范围和所选日期内的数据。'),
      'admin' => ('组织与权限设置', '关键修改进入审核，审批通过前原配置继续生效。'),
      _ => ('内容不存在', '请返回工作空间重新进入。'),
    };
    return PageFrame(
      title: title,
      child: PageBody(
        children: [
          const DemoLabel(),
          if (['pending', 'disabled', 'expired'].contains(widget.kind))
            const CuteArt('1F331', size: 88),
          Text(body),
          const SizedBox(height: 20),
          if (['pending', 'disabled', 'expired'].contains(widget.kind))
            OutlinedButton(
              onPressed: () => context.go('/form/login'),
              child: const Text('返回登录'),
            ),
          if (widget.kind == 'licenses')
            TextButton(
              onPressed: () =>
                  showLicensePage(context: context, applicationName: '潘多拉工作台'),
              child: const Text('组件许可证'),
            ),
          if (widget.kind == 'history') ...[
            const SectionHeader('候选版本 v2 · 待审'),
            const Text('补充访谈记录，原版保持生效。'),
            const SectionHeader('生效版本 v1'),
            const Text('完成初步需求梳理。'),
            const SectionHeader('阅读记录'),
            const Text('团队长已阅读 · 演示记录'),
          ],
          if (widget.kind == 'conflict') ...[
            OutlinedButton.icon(
              onPressed: () => openForm(context, 'log-edit'),
              icon: const Icon(Icons.edit_note),
              label: const Text('继续编辑本地草稿'),
            ),
            TextButton(
              onPressed: () => notice(context, '尚未连接服务端，本地内容未被覆盖'),
              child: const Text('检查服务器版本'),
            ),
          ],
          if (widget.kind == 'report') ...[
            const DateControls(),
            const RecordList('logs', dated: true),
            OutlinedButton.icon(
              onPressed: () => context.go('/ai'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成总结建议'),
            ),
          ],
          if (widget.kind == 'export') ...[
            const DateControls(),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await ref
                            .read(repositoryProvider)
                            .execute(
                              'analytics/export',
                              const Command('export', {}),
                            );
                        if (mounted) {
                          setState(
                            () => result = AppConfig.mock
                                ? '演示模式未生成真实下载文件，导出接口已预留。'
                                : '导出请求已提交，请查看任务结果',
                          );
                        }
                      } catch (e) {
                        if (mounted) setState(() => result = '$e');
                      }
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.download),
              label: const Text('申请导出'),
            ),
            Text(result),
          ],
          if (widget.kind == 'admin') ...[
            if (!ref.watch(sessionProvider).administrator)
              const Text('仅管理员可访问')
            else ...[
              for (final entry in {
                'department': '部门与团队',
                'membership': '确认员工归属',
                'role': '角色与派发资格',
                'reporting': '直属汇报关系',
                'disable': '停用账号',
                'policy': '审核策略',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openForm(context, entry.key),
                ),
              ListTile(
                title: const Text('审计记录'),
                onTap: () => openList(context, 'audit'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
