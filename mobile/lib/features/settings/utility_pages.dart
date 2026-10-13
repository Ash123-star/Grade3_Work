import 'package:flutter/material.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'diary_sync_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool exiting = false;
  String? exitError;
  @override
  Widget build(BuildContext context) => PageFrame(
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
          title: const Text('帮助与新手引导'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/me/help'),
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
          title: const Text('草稿与同步'),
          subtitle: const Text('查看本机草稿与服务器日志版本'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/conflict'),
        ),
        ListTile(
          title: const Text('开源素材许可'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/licenses'),
        ),
        if (AppConfig.mock &&
            ref.watch(sessionProvider).token == null &&
            ref.watch(sessionProvider).canReadBusiness) ...[
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
                  id: r == UserRole.employee ? 'u2' : 'u1',
                  name: r == UserRole.employee ? '陈一诺' : '林小满',
                  role: r,
                  dispatch: r != UserRole.employee,
                );
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(ref.watch(sessionProvider).id),
            initialValue: ref.watch(sessionProvider).id,
            decoration: const InputDecoration(labelText: '演示账号'),
            items: const [
              DropdownMenuItem(value: 'u1', child: Text('林小满')),
              DropdownMenuItem(value: 'u2', child: Text('陈一诺')),
              DropdownMenuItem(value: 'u3', child: Text('许知远')),
            ],
            onChanged: (id) {
              if (id == null) return;
              final old = ref.read(sessionProvider);
              ref.read(sessionProvider.notifier).state = Session(
                id: id,
                name: {'u1': '林小满', 'u2': '陈一诺', 'u3': '许知远'}[id]!,
                role: old.role,
                dispatch: old.dispatch,
              );
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
                id: u.id,
                name: u.name,
                role: u.role,
                dispatch: v,
              );
            },
          ),
        ],
        const SizedBox(height: 24),
        if (ref.watch(sessionStorageErrorProvider) != null)
          ErrorPanel(ref.watch(sessionStorageErrorProvider)!),
        if (exitError != null) ErrorPanel(exitError!),
        OutlinedButton.icon(
          onPressed: exiting
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('退出登录？'),
                      content: const Text('本机草稿将按账号保留。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('取消'),
                        ),
                        SunnyPrimaryButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('退出'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  setState(() {
                    exiting = true;
                    exitError = null;
                  });
                  try {
                    await logoutCurrentSession(ref);
                    if (context.mounted) context.go('/auth/login');
                  } catch (error) {
                    if (mounted) setState(() => exitError = '退出未完成：$error');
                  } finally {
                    if (mounted) setState(() => exiting = false);
                  }
                },
          icon: const Icon(Icons.logout),
          label: Text(exiting ? '正在退出…' : '退出登录'),
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
  Future<void> refreshAccount() async {
    setState(() {
      busy = true;
      result = '';
    });
    try {
      await refreshCurrentSession(ref);
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session.canReadBusiness) {
        context.go('/dashboard');
      } else {
        setState(() => result = '归属尚未确认，请稍后刷新。');
      }
    } catch (error) {
      if (mounted) setState(() => result = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leaveAccount() async {
    setState(() {
      busy = true;
      result = '';
    });
    try {
      await logoutCurrentSession(ref);
      if (mounted) context.go('/auth/login');
    } catch (error) {
      if (mounted) setState(() => result = '退出未完成：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == 'conflict') return const DiarySyncPage();
    final user = ref.watch(sessionProvider);
    final department = widget.kind == 'pending' && user.departmentId != null
        ? ref
              .watch(registrationDepartmentsProvider)
              .valueOrNull
              ?.items
              .where((record) => record.id == user.departmentId)
              .firstOrNull
              ?.title
        : null;
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
        'Phosphor Icons：官方 phosphor-icons/core，MIT，导航与工作入口使用本地SVG。Forui 0.17.0：MIT，日历和角色标签沿用动漫橙主题。欢迎与个人页使用项目原创猫狗。用户已拒绝网络角色方案，当前界面不使用宝可梦角色图片。Untitled UI仅设计参考。\n\nOpenMoji，作者：HfG Schwäbisch Gmünd 及 OpenMoji contributors。来源：https://openmoji.org/ 。许可：CC BY-SA 4.0。原样使用六份SVG，未修改图形。',
      ),
      'history' => ('历史修订与已读', '已提交版本与待审候选内容分别展示，审核通过后更新正式记录。'),
      'report' => ('周报与月报', '按所选业务日期区间聚合已提交日报。AI 摘要为建议草稿，发布前请核对来源。'),
      'ai-usage' => ('AI 用量与来源', '分析建议需要人工确认。'),
      'export' => ('统计导出', '导出仅包含当前授权范围和所选日期内的数据。'),
      'admin' => ('组织与权限设置', '关键修改进入审核，审批通过前原配置继续生效。'),
      _ => ('内容不存在', '请返回工作空间重新进入。'),
    };
    return PageFrame(
      title: title,
      child: PageBody(
        children: [
          if (['pending', 'disabled', 'expired'].contains(widget.kind))
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.lock_clock_outlined, size: 48),
            ),
          PaperSurface(
            child: Text(
              body,
              style: const TextStyle(fontSize: 15, height: 1.8),
            ),
          ),
          const SizedBox(height: 20),
          if (widget.kind == 'pending') ...[
            if (user.name.isNotEmpty) Text('申请账号：${user.name}'),
            if (user.departmentId != null) Text('申请部门：${department ?? '等待确认'}'),
            const SizedBox(height: 12),
            Text(user.status == 'UNKNOWN' ? '账号状态未确认，请重新登录核对。' : '状态：等待归属确认'),
            if (user.authenticated) ...[
              const SizedBox(height: 16),
              SunnyPrimaryButton(
                loading: busy,
                onPressed: busy ? null : refreshAccount,
                child: const Text('刷新申请状态'),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('申请已提交。登录后可刷新归属确认状态。'),
              ),
          ],
          if (result.isNotEmpty &&
              ['pending', 'disabled', 'expired'].contains(widget.kind))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ErrorPanel(result),
            ),
          if (['pending', 'disabled', 'expired'].contains(widget.kind))
            OutlinedButton(
              onPressed: busy ? null : leaveAccount,
              child: Text(user.authenticated ? '退出登录' : '返回登录'),
            ),
          if (widget.kind == 'licenses')
            TextButton(
              onPressed: () {
                registerCuratedAssetLicenses();
                showLicensePage(context: context, applicationName: '潘多拉工作台');
              },
              child: const Text('组件许可证'),
            ),
          if (widget.kind == 'ai-usage') ...[
            const SectionHeader('服务状态'),
            PaperSurface(
              color: const Color(0xFFF1E7FF),
              child: Text(
                AppConfig.mock
                    ? '本地预设样例不调用模型，也不消耗额度。'
                    : '用量查询服务待接入，当前不能显示调用次数或预算。',
              ),
            ),
            const SectionHeader('来源规则'),
            const Text('每条建议需提供可访问来源、生成时间和数据范围。信息不足时仅作提示，不自动创建任务。'),
          ],
          if (widget.kind == 'history')
            LogHistory(
              logId: GoRouterState.of(context).uri.queryParameters['id'] ?? '1',
            ),
          if (widget.kind == 'report') ...[
            const PeriodReport(),
            OutlinedButton.icon(
              onPressed: () => context.go('/ai'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成总结建议'),
            ),
          ],
          if (widget.kind == 'admin') ...[
            if (!ref.watch(sessionProvider).administrator)
              const Text('仅管理员可访问')
            else ...[
              const SectionHeader('组织与人员'),
              ListTile(
                title: const Text('浏览组织与成员'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/me/organization'),
              ),
              for (final entry in {
                'department': '部门与团队',
                'membership': '确认员工归属',
                'role': '角色与权限（含公司复核资格）',
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
          const DemoLabel(),
        ],
      ),
    );
  }
}
