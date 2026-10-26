import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

const managementKinds = {
  'department',
  'membership',
  'role',
  'reporting',
  'disable',
  'policy',
};
const managementTitles = {
  'department': '部门与团队',
  'membership': '确认员工归属',
  'role': '角色与权限',
  'reporting': '直属汇报关系',
  'disable': '停用账号',
  'policy': '审核策略',
};

List<Map<String, dynamic>> organizationUnits(Record? tree, String key) =>
    (tree?.fields[key] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
String organizationName(Record? tree, String key, dynamic id) =>
    organizationUnits(
      tree,
      key,
    ).where((r) => r['id'] == id).firstOrNull?['name']?.toString() ??
    '未分配或不在可见范围';

/// Reads effective values first; every write creates an independently reviewed candidate.
class ManagementPage extends ConsumerStatefulWidget {
  const ManagementPage(this.kind, {super.key, this.memberId});
  final String kind;
  final String? memberId;
  @override
  ConsumerState<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends ConsumerState<ManagementPage> {
  final name = TextEditingController(), reason = TextEditingController();
  final form = GlobalKey<FormState>();
  Record? tree, current;
  String unitKind = 'departments',
      unitId = '',
      memberId = '',
      departmentId = '',
      teamId = '',
      managerId = '';
  String role = 'EMPLOYEE';
  bool dispatch = false;
  bool loading = true,
      busy = false,
      denied = false,
      conflict = false,
      submitted = false;
  Object? error;
  int generation = 0;
  List<Record> get people =>
      (tree?.fields['people'] as List? ?? []).whereType<Record>().toList();
  bool get unit => widget.kind == 'department';
  bool get policy => widget.kind == 'policy';
  @override
  void initState() {
    super.initState();
    memberId = widget.memberId ?? '';
    load();
  }

  @override
  void dispose() {
    generation++;
    name.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation, account = ref.read(sessionProvider).id;
    if (!ref.read(sessionProvider).administrator ||
        !ref.read(sessionProvider).canReadBusiness) {
      loading = false;
      denied = true;
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repository = ref.read(repositoryProvider);
      final organization = policy
          ? null
          : await repository.detail('organization/tree', 'tree');
      Record? value;
      if (!policy && !unit && memberId.isNotEmpty) {
        value = await repository.detail('organization/profile', memberId);
      }
      if (value != null &&
          (value.version < 1 ||
              !policy &&
                  widget.kind == 'role' &&
                  value.fields['dispatch_enabled'] is! bool)) {
        throw const ApiFailure(FailureKind.unavailable, '当前版本或权限未完整返回，请重新读取');
      }
      if (!mounted ||
          ticket != generation ||
          account != ref.read(sessionProvider).id) {
        return;
      }
      setState(() {
        tree = organization;
        current = value;
        loading = false;
        denied = false;
        conflict = false;
        submitted = false;
        reason.clear();
        if (unit) {
          final selected = organizationUnits(
            tree,
            unitKind,
          ).where((u) => u['id'] == unitId).firstOrNull;
          name.text = '${selected?['name'] ?? ''}';
          departmentId = '${selected?['department_id'] ?? ''}';
        } else if (value != null) {
          final f = value.fields;
          departmentId = '${f['department_id'] ?? ''}';
          teamId = '${f['team_id'] ?? ''}';
          role = '${f['role'] ?? 'UNKNOWN'}';
          dispatch = f['dispatch_enabled'] == true;
          managerId = '${f['manager_id'] ?? ''}';
        }
      });
    } catch (e) {
      if (mounted &&
          ticket == generation &&
          account == ref.read(sessionProvider).id) {
        failure(e);
      }
    }
  }

  void failure(Object e) {
    setState(() {
      error = e;
      loading = false;
      conflict = e is ApiFailure && e.kind == FailureKind.conflict;
      if (e is ApiFailure &&
          [FailureKind.forbidden, FailureKind.unauthorized].contains(e.kind)) {
        denied = true;
        current = null;
        tree = null;
        name.clear();
        reason.clear();
      }
    });
  }

  Future<void> reload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => TuantuanDialog(
        title: const Text('重新读取当前配置？'),
        content: const Text('会清除本页未提交的修改与理由。取消可继续保留输入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留输入'),
          ),
          SunnyPrimaryButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('重新读取'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await load();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy || denied || submitted) return;
    final account = ref.read(sessionProvider).id;
    final values = <String, dynamic>{'reason': reason.text.trim()};
    int version;
    String action;
    if (unit) {
      final selected = organizationUnits(
        tree,
        unitKind,
      ).where((u) => u['id'] == unitId).firstOrNull;
      version = unitId.isEmpty
          ? 0
          : (selected?['version'] as num?)?.toInt() ?? -1;
      action = 'unit';
      values.addAll({
        'kind': unitKind,
        'id': unitId,
        'name': name.text.trim(),
        if (unitKind == 'teams') 'departmentId': departmentId,
      });
    } else {
      if (current == null) return;
      version = current!.version;
      if (policy) return;
      action = 'user';
      values['id'] = memberId;
      switch (widget.kind) {
          case 'membership':
            values.addAll({
              'departmentId': departmentId,
              'teamId': teamId.isEmpty ? null : teamId,
              if (current!.fields['status'] == 'PENDING') 'status': 'ACTIVE',
            });
          case 'role':
            values.addAll({
              'role': role,
              'dispatchEnabled': dispatch,
            });
          case 'reporting':
            values['managerId'] = managerId.isEmpty ? null : managerId;
          case 'disable':
            values['status'] = 'DISABLED';
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .execute(
            'organization/admin',
            Command(action, values, version: version),
          );
      if (!mounted || ref.read(sessionProvider).id != account) return;
      setState(() {
        submitted = true;
        conflict = false;
      });
      ref.invalidate(recordsProvider('reviews'));
    } catch (e) {
      if (mounted && ref.read(sessionProvider).id == account) failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget select(
    String label,
    String value,
    List<(String, String)> options,
    ValueChanged<String> change, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: PremiumDropdownField<String>(
      key: ValueKey('$label:$value:${options.map((e) => e.$1).join(',')}'),
      initialValue: options.any((e) => e.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o.$1, child: Text(o.$2)),
      ],
      validator: required
          ? (v) => v == null || v.isEmpty ? '请选择$label' : null
          : null,
      onChanged: busy || submitted
          ? null
          : (v) {
              if (v != null) change(v);
            },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.administrator || !session.canReadBusiness || denied) {
      return const PageFrame(
        title: '组织管理',
        child: EmptyIllustration(
          showCharacter: false,
          title: '暂无管理权限',
          subtitle: '请返回本人面板',
        ),
      );
    }
    final departments = organizationUnits(tree, 'departments');
    final teams = organizationUnits(
      tree,
      'teams',
    ).where((t) => t['department_id'] == departmentId).toList();
    final units = organizationUnits(tree, unitKind);
    final canSubmit =
        !policy &&
        !loading &&
        tree != null &&
        (unit || current != null) &&
        !submitted &&
        !conflict;
    return PageFrame(
      title: managementTitles[widget.kind]!,
      bottom: policy
          ? null
          : BottomActions(
        primary: SunnyPrimaryButton(
          loading: busy,
          onPressed: busy || !canSubmit ? null : submit,
          child: Text(submitted ? '候选已提交' : '提交候选修改'),
        ),
        note: '直属上级单级审核通过后生效；当前配置继续使用。',
      ),
      child: PageBody(
        children: [
          if (loading)
            const LoadingSkeleton()
          else if (tree == null && error != null)
            RecordFailure(error!, retry: load)
          else
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!policy)
                    PaperSurface(
                      color: const Color(0xFFFFF0DA),
                      child: const Text('修改申请与当前配置分开展示。提交不会立即更改组织或成员权限。'),
                    ),
                  if (!policy) const SectionHeader('选择修改对象'),
                  if (unit) ...[
                    select(
                      '组织类型',
                      unitKind,
                      const [('departments', '部门'), ('teams', '团队')],
                      (v) {
                        setState(() {
                          unitKind = v;
                          unitId = '';
                          departmentId = '';
                          name.clear();
                        });
                      },
                    ),
                    select(
                      '当前组织',
                      unitId,
                      [
                        ('', '新增组织'),
                        for (final u in units) ('${u['id']}', '${u['name']}'),
                      ],
                      (v) {
                        final selected = units
                            .where((u) => u['id'] == v)
                            .firstOrNull;
                        setState(() {
                          unitId = v;
                          name.text = '${selected?['name'] ?? ''}';
                          departmentId = '${selected?['department_id'] ?? ''}';
                        });
                      },
                    ),
                    Text(
                      unitId.isEmpty
                          ? '当前：尚未创建；候选审核通过后新增'
                          : '当前：${units.where((u) => u['id'] == unitId).firstOrNull?['name']}',
                    ),
                    const SectionHeader('候选配置'),
                    TextFormField(
                      controller: name,
                      enabled: !busy && !submitted,
                      decoration: const InputDecoration(labelText: '名称'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请输入组织名称' : null,
                    ),
                    const SizedBox(height: 16),
                    if (unitKind == 'teams')
                      select(
                        '上级部门',
                        departmentId,
                        [
                          for (final d in departments)
                            ('${d['id']}', '${d['name']}'),
                        ],
                        (v) => setState(() => departmentId = v),
                        required: true,
                      ),
                  ] else if (policy) ...[
                    const SectionHeader('关键修改审核规则'),
                    const PaperSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '非创始人的关键修改由组织中配置的直属上级单级审核，通过后生效，不再逐级转审。直属上级未配置或关系失效时，申请保持待审，不自动批准。',
                          ),
                          SizedBox(height: 12),
                          Text(
                            '创始人已获授权的操作自动批准；管理员身份本身不构成免审。',
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    select(
                      '员工',
                      memberId,
                      [for (final p in people) (p.id, p.title)],
                      (v) {
                        setState(() => memberId = v);
                        load();
                      },
                      required: true,
                    ),
                    if (current != null) ...[
                      const SectionHeader('当前生效配置'),
                      PaperSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${current!.title} · v${current!.version}'),
                            Text(
                              '角色：${UserRole.values.where((r) => r.name.toUpperCase() == current!.fields['role']).firstOrNull?.label ?? '未返回'}',
                            ),
                            Text(
                              '状态：${switch (current!.fields['status']) {
                                'PENDING' => '待确认',
                                'ACTIVE' => '已启用',
                                'DISABLED' => '已停用',
                                _ => '未返回',
                              }}',
                            ),
                            Text(
                              '部门：${organizationName(tree, 'departments', current!.fields['department_id'])}',
                            ),
                            Text(
                              '团队：${organizationName(tree, 'teams', current!.fields['team_id'])}',
                            ),
                            if (widget.kind == 'role')
                              Text(
                                '派发资格：${current!.fields['dispatch_enabled'] == true ? '允许' : '不允许'}',
                              ),
                            if (widget.kind == 'reporting')
                              Text(
                                current!.fields.containsKey('manager_id')
                                    ? '直属上级：${people.where((p) => p.id == current!.fields['manager_id']).firstOrNull?.title ?? '未设置或不可见'}'
                                    : '直属上级：当前资料接口未返回；下方仅修改新的候选关系',
                              ),
                          ],
                        ),
                      ),
                      const SectionHeader('候选修改'),
                      if (widget.kind == 'membership') ...[
                        select(
                          '部门',
                          departmentId,
                          [
                            for (final d in departments)
                              ('${d['id']}', '${d['name']}'),
                          ],
                          (v) => setState(() {
                            departmentId = v;
                            teamId = '';
                          }),
                          required: true,
                        ),
                        select('团队', teamId, [
                          ('', '暂不分配团队'),
                          for (final t in teams) ('${t['id']}', '${t['name']}'),
                        ], (v) => setState(() => teamId = v)),
                        if (current!.fields['status'] == 'PENDING')
                          const Text('归属确认候选包含账号启用，审核通过前仍为待确认。'),
                      ],
                      if (widget.kind == 'role') ...[
                        select(
                          '角色',
                          role,
                          [
                            for (final r in UserRole.values)
                              (r.name.toUpperCase(), r.label),
                          ],
                          (v) => setState(() => role = v),
                          required: true,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('允许派发任务'),
                          value: dispatch,
                          onChanged: busy || submitted
                              ? null
                              : (v) => setState(() => dispatch = v),
                        ),
                      ],
                      if (widget.kind == 'reporting')
                        select('候选直属上级', managerId, [
                          ('', '移除直属上级'),
                          for (final p in people.where((p) => p.id != memberId))
                            (p.id, p.title),
                        ], (v) => setState(() => managerId = v)),
                      if (widget.kind == 'disable')
                        const Text('审核通过后停用该账号。提交前请确认工作交接；最后一位管理员等限制由服务端校验。'),
                    ] else
                      const Text('选择员工后读取当前资料与版本，再填写候选修改。'),
                  ],
                  if (!policy) ...[
                    const SectionHeader('变更理由'),
                    TextFormField(
                      controller: reason,
                      enabled: !busy && !submitted,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: '说明原因与影响'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请填写变更理由' : null,
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ErrorPanel(
                        '$error',
                        retry: conflict ? reload : load,
                      ),
                    ),
                  if (conflict)
                    TextButton(
                      onPressed: busy ? null : reload,
                      child: const Text('重新读取当前配置'),
                    ),
                  if (submitted) ...[
                    const SectionHeader('已提交待审'),
                    const Text('原配置保持生效。到“我的审批”查看申请进展。'),
                    TextButton(
                      onPressed: () => context.push('/me/reviews'),
                      child: const Text('查看审批'),
                    ),
                  ],
                  const DemoLabel(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
