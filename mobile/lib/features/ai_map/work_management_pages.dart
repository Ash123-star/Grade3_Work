import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/repositories/ai_work_repository.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class WorkTargetPicker extends ConsumerStatefulWidget {
  const WorkTargetPicker(this.action, {super.key});
  final String action;
  @override
  ConsumerState<WorkTargetPicker> createState() => WorkTargetPickerState();
}

class WorkTargetPickerState extends ConsumerState<WorkTargetPicker> {
  final search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool loading = true, more = false;
  Object? error;
  int generation = 0;
  late final account = ref.read(sessionProvider);
  bool get valid =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      account.id == ref.read(sessionProvider).id &&
      account.token == ref.read(sessionProvider).token;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await ref
          .read(workRepositoryProvider)
          .request(
            'GET',
            '/ai/work-authorization-options?action=${widget.action}&search=${Uri.encodeQueryComponent(search.text.trim())}&cursor=${append ? items.length : 0}',
          );
      if (!valid || ticket != generation) return;
      final next = workMaps(result['items']);
      setState(() {
        items = append ? [...items, ...next] : next;
        more = next.length == 30;
      });
    } catch (e) {
      if (valid && ticket == generation) setState(() => error = e);
    } finally {
      if (valid && ticket == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    return AlertDialog(
      title: Text(widget.action == 'CREATE_TASK' ? '选择人员' : '选择任务'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: !valid
            ? const Center(child: Text('账号已切换，请重新打开'))
            : Column(
                children: [
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      hintText: '搜索名称',
                      suffixIcon: IconButton(
                        tooltip: '搜索',
                        onPressed: () => load(),
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) => load(),
                  ),
                  if (error != null)
                    TextButton(
                      onPressed: () => load(),
                      child: Text(workError(error!)),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final item in items)
                          ListTile(
                            title: Text('${item['label']}'),
                            subtitle: widget.action == 'CREATE_TASK'
                                ? Text(
                                    [item['department'], item['team']]
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join(' · '),
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, item),
                          ),
                        if (!loading && items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('没有找到可选对象'),
                          ),
                        if (loading)
                          const Center(child: CircularProgressIndicator()),
                        if (more && !loading)
                          TextButton(
                            onPressed: () => load(append: true),
                            child: const Text('加载更多'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class WorkSettingsPage extends ConsumerStatefulWidget {
  const WorkSettingsPage({super.key});
  @override
  ConsumerState<WorkSettingsPage> createState() => _WorkSettingsPageState();
}

class _WorkSettingsPageState extends ConsumerState<WorkSettingsPage> {
  List<Map<String, dynamic>>? items;
  Map<String, dynamic>? policy;
  Object? error;
  bool busy = false;
  late final account = ref.read(sessionProvider);
  bool get valid =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      account.id == ref.read(sessionProvider).id &&
      account.token == ref.read(sessionProvider).token;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final repo = ref.read(workRepositoryProvider);
      final results = await Future.wait<Object>([
        repo.authorizations(),
        repo.request('GET', '/ai/work-authorization-policy'),
      ]);
      final result = results[0] as List<Map<String, dynamic>>;
      if (valid) {
        setState(() {
          items = result;
          policy = workMap(results[1]);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> create() async {
    if (policy == null) return;
    final allowCreate = policy!['canCreate'] == true;
    final allowSubmit = policy!['canSubmit'] == true;
    if (!allowCreate && !allowSubmit) return;
    final maxDays = (policy!['maxDays'] as num).toInt();
    final maxActions = (policy!['maxActions'] as num).toInt();
    var actions = maxActions;
    Map<String, dynamic>? target;
    var action = allowCreate ? 'CREATE_TASK' : 'SUBMIT_DELIVERY';
    var days = maxDays < 7 ? maxDays : 7;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => StatefulBuilder(
        builder: (context, state) => AlertDialog(
          title: const Text('添加自动授权'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: action,
                  isExpanded: true,
                  items: [
                    if (allowCreate)
                      const DropdownMenuItem(
                        value: 'CREATE_TASK',
                        child: Text('为指定人员创建任务'),
                      ),
                    if (allowSubmit)
                      const DropdownMenuItem(
                        value: 'SUBMIT_DELIVERY',
                        child: Text('为指定任务提交反馈'),
                      ),
                  ],
                  onChanged: (v) => state(() {
                    action = v!;
                    target = null;
                  }),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      animationStyle: WorkMotion.dialog(context),
                      builder: (_) => WorkTargetPicker(action),
                    );
                    if (context.mounted && result != null) {
                      state(() => target = result);
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: Text(
                    target?['label'] as String? ??
                        (action == 'CREATE_TASK' ? '选择人员' : '选择任务'),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: days,
                  decoration: const InputDecoration(labelText: '有效期'),
                  items: [
                    for (final d in {1, 7, maxDays}.where((d) => d <= maxDays))
                      DropdownMenuItem(value: d, child: Text('$d 天')),
                  ],
                  onChanged: (v) => state(() => days = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: actions,
                  decoration: const InputDecoration(labelText: '每批最多办理'),
                  items: [
                    for (var n = 1; n <= maxActions; n++)
                      DropdownMenuItem(value: n, child: Text('$n 项')),
                  ],
                  onChanged: (v) => state(() => actions = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (target == null) return;
                Navigator.pop(context, {
                  'action': action,
                  'scope': {
                    'maxActions': actions,
                    action == 'CREATE_TASK' ? 'ownerIds' : 'taskIds': [
                      target!['id'],
                    ],
                  },
                  'expiresAt': DateTime.now()
                      .add(Duration(days: days))
                      .toUtc()
                      .toIso8601String(),
                });
              },
              child: const Text('开启授权'),
            ),
          ],
        ),
      ),
    );
    if (body == null || !valid) return;
    setState(() => busy = true);
    try {
      await ref
          .read(workRepositoryProvider)
          .request(
            'POST',
            '/ai/work-authorizations',
            body: body,
            key: AiWorkRepository.key(),
          );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> companyPolicy() async {
    final values = workMap(policy!['values']);
    final reason = TextEditingController();
    final labels = {
      'aiWorkCreateAuthorization': '为指定人员创建任务',
      'aiWorkSubmitAuthorization': '检查通过后提交反馈',
    };
    final limits = {
      'aiWorkAuthorizationMaxDays': ('最长有效天数', 30),
      'aiWorkAuthorizationMaxObjects': ('最多授权对象', 100),
      'aiWorkAuthorizationMaxActions': ('每批最多办理', 5),
    };
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => StatefulBuilder(
        builder: (context, state) => AlertDialog(
          title: const Text('公司自动授权范围'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in labels.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    value: values[entry.key] == true,
                    onChanged: (v) => state(() => values[entry.key] = v),
                  ),
                for (final entry in limits.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DropdownButtonFormField<int>(
                      initialValue: (values[entry.key] as num).toInt(),
                      decoration: InputDecoration(labelText: entry.value.$1),
                      items: [
                        for (var n = 1; n <= entry.value.$2; n++)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: (v) => state(() => values[entry.key] = v),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('修改通过复核后生效，已有自动授权需要重新开启。'),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: '修改原因'),
                  maxLength: 500,
                  onChanged: (_) => state(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                      ...values,
                      'version': policy!['version'],
                      'reason': reason.text.trim(),
                    }),
              child: const Text('提交复核'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (body == null || !valid) return;
    setState(() => busy = true);
    try {
      await ref
          .read(workRepositoryProvider)
          .request('POST', '/organization/review-policy/revisions', body: body);
      if (mounted && valid) {
        notice(context, '已提交，等待复核', success: true);
      }
      await load();
    } catch (e) {
      if (valid) setState(() => error = e);
    } finally {
      if (valid) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SunnyPalette.paper,
    appBar: AppBar(title: const Text('办事设置')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PaperSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('自动授权', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('只办理你指定的人员或任务，到期自动停止，随时可以撤回。'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed:
                    busy ||
                        policy == null ||
                        (policy!['canCreate'] != true &&
                            policy!['canSubmit'] != true)
                    ? null
                    : create,
                icon: const Icon(Icons.add),
                label: const Text('添加授权'),
              ),
            ],
          ),
        ),
        if (policy != null &&
            policy!['canCreate'] != true &&
            policy!['canSubmit'] != true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('公司暂未开放自动授权，你仍可逐次交代办理。'),
          ),
        if (ref.watch(sessionProvider).administrator && policy != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PaperSurface(
              child: ListTile(
                title: const Text('公司自动授权范围'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : companyPolicy,
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(workError(error!)),
          ),
        if (items == null && error == null)
          const Center(child: CircularProgressIndicator()),
        if (items?.isEmpty == true)
          const Padding(padding: EdgeInsets.all(24), child: Text('尚未开启自动授权')),
        for (final item in items ?? <Map<String, dynamic>>[])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PaperSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['action'] == 'CREATE_TASK' ? '创建任务' : '检查通过后提交反馈',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('范围：${(item['scopeLabels'] as List? ?? []).join('、')}'),
                  Text('到期：${workDate(item['expires_at'])}'),
                  const SizedBox(height: 8),
                  if (item['effective'] == false && item['revoked_at'] == null)
                    const Text('已失效，需要重新开启授权'),
                  if (item['revoked_at'] != null)
                    const Text('已撤回')
                  else
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await ref
                                    .read(workRepositoryProvider)
                                    .request(
                                      'POST',
                                      '/ai/work-authorizations/${item['id']}/revoke',
                                      body: {'version': item['version']},
                                      key: AiWorkRepository.key(),
                                    );
                                await load();
                              } catch (e) {
                                if (mounted) setState(() => error = e);
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: const Text('撤回授权'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        ListTile(
          title: const Text('公司制度与模板'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/ai/procedures'),
        ),
      ],
    ),
  );
}

class ProcedurePage extends ConsumerStatefulWidget {
  const ProcedurePage({super.key, this.id});
  final String? id;
  @override
  ConsumerState<ProcedurePage> createState() => _ProcedurePageState();
}

class _ProcedureScopeEditor extends ConsumerStatefulWidget {
  const _ProcedureScopeEditor(this.initial, this.changed);
  final Map<String, dynamic> initial;
  final void Function(Map<String, dynamic>) changed;
  @override
  ConsumerState<_ProcedureScopeEditor> createState() =>
      _ProcedureScopeEditorState();
}

class _ProcedureScopeEditorState extends ConsumerState<_ProcedureScopeEditor> {
  late String kind = '${widget.initial['scopeKind'] ?? 'COMPANY'}';
  late String? unit = widget.initial['scopeId'] as String?;
  late DateTime from =
      DateTime.tryParse('${widget.initial['effectiveFrom']}')?.toLocal() ??
      DateTime.now();
  late DateTime? until = DateTime.tryParse(
    '${widget.initial['effectiveTo']}',
  )?.toLocal();
  Map<String, dynamic> tree = {};
  Object? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await ref
          .read(workRepositoryProvider)
          .request('GET', '/organization');
      if (mounted) setState(() => tree = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  void emit() {
    widget.changed({
      'scopeKind': kind,
      if (kind != 'COMPANY' && unit != null) 'scopeId': unit,
      'effectiveFrom': from.toUtc().toIso8601String(),
      if (until != null) 'effectiveTo': until!.toUtc().toIso8601String(),
    });
  }

  Future<void> date(bool end) async {
    final result = await showDatePicker(
      context: context,
      initialDate: end ? (until ?? from.add(const Duration(days: 365))) : from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (end) {
        until = DateTime(result.year, result.month, result.day, 23, 59, 59);
      } else {
        from = result;
      }
    });
    emit();
  }

  @override
  Widget build(BuildContext context) {
    final units = workMaps(tree[kind == 'TEAM' ? 'teams' : 'departments']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: kind,
          decoration: const InputDecoration(labelText: '适用范围'),
          items: const [
            DropdownMenuItem(value: 'COMPANY', child: Text('全公司')),
            DropdownMenuItem(value: 'DEPARTMENT', child: Text('指定部门')),
            DropdownMenuItem(value: 'TEAM', child: Text('指定团队')),
          ],
          onChanged: (v) {
            setState(() {
              kind = v!;
              unit = null;
            });
            emit();
          },
        ),
        if (kind != 'COMPANY')
          DropdownButtonFormField<String>(
            key: ValueKey(kind),
            initialValue: units.any((u) => u['id'] == unit) ? unit : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '选择组织'),
            items: [
              for (final u in units)
                DropdownMenuItem(
                  value: '${u['id']}',
                  child: Text('${u['name']}'),
                ),
            ],
            onChanged: (v) {
              setState(() => unit = v);
              emit();
            },
          ),
        if (error != null)
          TextButton(onPressed: load, child: const Text('重新加载组织')),
        TextButton(
          onPressed: () => date(false),
          child: Text('生效：${from.year}年${from.month}月${from.day}日'),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => date(true),
              child: Text(
                until == null
                    ? '设置失效日期'
                    : '失效：${until!.year}年${until!.month}月${until!.day}日',
              ),
            ),
            if (until != null)
              TextButton(
                onPressed: () {
                  setState(() => until = null);
                  emit();
                },
                child: const Text('长期有效'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProcedurePageState extends ConsumerState<ProcedurePage> {
  List<Map<String, dynamic>>? items;
  Map<String, dynamic>? detail;
  Object? error;
  bool drafts = false;
  final search = TextEditingController();
  int nextCursor = -1;
  bool loading = false;
  late final account = ref.read(sessionProvider);
  bool get valid =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      account.id == ref.read(sessionProvider).id &&
      account.token == ref.read(sessionProvider).token;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool append = false}) async {
    if (loading || (append && nextCursor < 0)) return;
    setState(() => loading = true);
    try {
      final path = widget.id == null
          ? '/procedures?drafts=$drafts&search=${Uri.encodeQueryComponent(search.text.trim())}&cursor=${append ? nextCursor : 0}'
          : '/procedures/${widget.id}';
      final response = await ref
          .read(workRepositoryProvider)
          .request('GET', path);
      if (valid) {
        setState(() {
          if (widget.id == null) {
            final value = workMap(response);
            final rows = workMaps(value['items']);
            items = append ? [...?items, ...rows] : rows;
            nextCursor = (value['nextCursor'] as num?)?.toInt() ?? -1;
          } else {
            detail = workMap(response);
          }
          error = null;
        });
      }
    } catch (e) {
      if (valid) setState(() => error = e);
    } finally {
      if (valid) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> edit([Map<String, dynamic>? old]) async {
    final title = TextEditingController(text: '${old?['title'] ?? ''}');
    final content = TextEditingController(text: '${old?['content'] ?? ''}');
    var type = '${old?['type'] ?? 'POLICY'}';
    var files = List<String>.from(old?['attachmentIds'] as List? ?? []);
    var ready = true;
    var scope = <String, dynamic>{
      for (final field in [
        'scopeKind',
        'scopeId',
        'effectiveFrom',
        'effectiveTo',
      ])
        if (old?[field] != null) field: old![field],
    };
    var workflow = old?['workflow'] as String?;
    final candidate = await showDialog<Map<String, dynamic>>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: Text(old == null ? '新增公司资料' : '修订公司资料'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'POLICY', child: Text('制度')),
                    DropdownMenuItem(value: 'PROCEDURE', child: Text('办事流程')),
                    DropdownMenuItem(value: 'TEMPLATE', child: Text('模板')),
                  ],
                  onChanged: (v) => type = v!,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: content,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: '正文'),
                ),
                _ProcedureScopeEditor(old ?? {}, (value) => scope = value),
                DropdownButtonFormField<String>(
                  initialValue: workflow,
                  decoration: const InputDecoration(labelText: '关联办理'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('仅提供资料')),
                    DropdownMenuItem(value: 'CREATE_TASK', child: Text('创建任务')),
                    DropdownMenuItem(
                      value: 'SUBMIT_DELIVERY',
                      child: Text('提交反馈'),
                    ),
                    DropdownMenuItem(
                      value: 'REQUEST_RESCHEDULE',
                      child: Text('申请改期'),
                    ),
                    DropdownMenuItem(
                      value: 'REQUEST_REASSIGNMENT',
                      child: Text('申请转派'),
                    ),
                  ],
                  onChanged: (v) => workflow = v,
                ),
                if (files.isNotEmpty) Text('已保留 ${files.length} 份模板附件'),
                AttachmentEditor(
                  onChanged: (value) {
                    ready = value.ready;
                    files = [
                      ...List<String>.from(
                        old?['attachmentIds'] as List? ?? [],
                      ),
                      ...value.files.map((f) => f.id),
                    ];
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!ready ||
                  title.text.trim().isEmpty ||
                  content.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, {
                ...scope,
                if (workflow != null && workflow!.isNotEmpty)
                  'workflow': workflow,
                for (final field in ['acceptanceChecklist'])
                  if (old?[field] != null) field: old![field],
                'title': title.text.trim(),
                'content': content.text.trim(),
                'type': type,
                if (scope['scopeKind'] == null) 'scopeKind': 'COMPANY',
                'attachmentIds': files,
              });
            },
            child: const Text('保存草稿'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    content.dispose();
    if (candidate == null || !valid) return;
    try {
      final repo = ref.read(workRepositoryProvider);
      await repo.request(
        'POST',
        old == null ? '/procedures' : '/procedures/${old['id']}/revisions',
        body: old == null
            ? candidate
            : {'version': old['version'], 'candidate': candidate},
        key: AiWorkRepository.key(),
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> compare(Map<String, dynamic> item) async {
    try {
      final result = await ref
          .read(workRepositoryProvider)
          .request('GET', '/procedures/${item['id']}/comparison');
      if (!valid || !mounted) return;
      await showDialog<void>(
        context: context,
        animationStyle: WorkMotion.dialog(context),
        builder: (context) => AlertDialog(
          title: const Text('版本对比'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前正式版'),
                SelectableText(
                  '${workMap(result['published'])['content'] ?? '尚未发布'}',
                ),
                const Divider(height: 32),
                const Text('维护草稿'),
                SelectableText('${workMap(result['draft'])['content'] ?? ''}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (valid) setState(() => error = e);
    }
  }

  Future<void> withdraw(Map<String, dynamic> item) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: const Text('申请撤回资料'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '撤回原因'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: const Text('提交复核'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    reason.dispose();
    if (value == null || !valid) return;
    try {
      final repo = ref.read(workRepositoryProvider);
      final draft = await repo.request(
        'GET',
        '/procedures/${item['id']}?draft=true',
      );
      if (!valid) return;
      final result = await repo.request(
        'POST',
        '/procedures/${item['id']}/publish-requests',
        body: {'version': draft['version'], 'withdraw': true, 'reason': value},
        key: AiWorkRepository.key(),
      );
      if (valid && mounted) context.push('/me/reviews/${result['id']}');
    } catch (e) {
      if (valid) setState(() => error = e);
    }
  }

  Future<void> template() async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      animationStyle: WorkMotion.dialog(context),
      builder: (context) => AlertDialog(
        title: const Text('填写模板'),
        content: TextField(
          controller: reason,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '事由'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reason.text.trim()),
            child: const Text('准备材料'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    reason.dispose();
    if (value == null || !valid) return;
    try {
      final result = await ref
          .read(workRepositoryProvider)
          .request(
            'POST',
            '/procedures/${widget.id}/template-draft',
            body: {'version': detail!['version'], 'reason': value},
          );
      if (!valid || !mounted) return;
      await showDialog<void>(
        context: context,
        animationStyle: WorkMotion.dialog(context),
        builder: (context) => AlertDialog(
          title: Text('${result['title']}'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                if (result['unfilled'] == true) const Text('还有内容需要补充，请核对后使用。'),
                SelectableText('${result['content']}'),
                for (final entry
                    in (result['attachmentIds'] as List? ?? []).indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _PreparedTemplateDownload(
                      document: widget.id!,
                      version: (result['version'] as num).toInt(),
                      file: '${entry.$2}',
                      reason: value,
                      number: entry.$1 + 1,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${result['content']}'));
                Navigator.pop(context);
              },
              child: const Text('复制内容'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (valid) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(sessionProvider).administrator;
    if (!valid) {
      return const Scaffold(body: Center(child: Text('账号已切换，请重新打开公司资料')));
    }
    return Scaffold(
      backgroundColor: SunnyPalette.paper,
      appBar: AppBar(
        title: Text(widget.id == null ? '制度与模板' : '公司资料'),
        actions: [
          if (admin && widget.id == null)
            IconButton(
              tooltip: '新增资料',
              onPressed: edit,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.id == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: search,
                  decoration: InputDecoration(
                    labelText: '查找制度和模板',
                    suffixIcon: IconButton(
                      onPressed: loading ? null : () => load(),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => load(),
                ),
              ),
            if (widget.id == null && nextCursor >= 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  onPressed: loading ? null : () => load(append: true),
                  child: const Text('查看更多资料'),
                ),
              ),
            if (admin && widget.id == null)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('已发布')),
                  ButtonSegment(value: true, label: Text('维护草稿')),
                ],
                selected: {drafts},
                onSelectionChanged: loading
                    ? null
                    : (v) {
                        setState(() {
                          drafts = v.first;
                          items = null;
                          nextCursor = -1;
                        });
                        load();
                      },
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(workError(error!)),
                    TextButton(
                      onPressed: loading ? null : () => load(),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            if (items == null && detail == null && error == null)
              const Center(child: CircularProgressIndicator()),
            if (items?.isEmpty == true)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有可用的公司资料'),
              ),
            if (detail != null)
              PaperSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${detail!['title']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    SelectableText('${detail!['content']}'),
                    if (detail!['type'] == 'TEMPLATE')
                      FilledButton(
                        onPressed: template,
                        child: const Text('填写模板'),
                      ),
                    for (final id in detail!['attachmentIds'] as List? ?? [])
                      TextButton.icon(
                        onPressed: () => context.push('/attachments/$id'),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('下载模板'),
                      ),
                  ],
                ),
              ),
            for (final item in items ?? <Map<String, dynamic>>[])
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PaperSurface(
                  onTap: drafts
                      ? null
                      : () => context.push('/ai/procedures/${item['id']}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['title']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (drafts && item['review_status'] == 'PENDING')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextButton.icon(
                            onPressed: () => context.push(
                              '/me/reviews/${item['pending_review_id']}',
                            ),
                            icon: const Icon(Icons.schedule_rounded),
                            label: const Text('等待复核 · 查看申请'),
                          ),
                        ),
                      if (admin && !drafts)
                        TextButton(
                          onPressed: () => withdraw(item),
                          child: const Text('申请撤回'),
                        ),
                      if (drafts)
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: () => compare(item),
                              child: const Text('版本对比'),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  final old = await ref
                                      .read(workRepositoryProvider)
                                      .request(
                                        'GET',
                                        '/procedures/${item['id']}?draft=true',
                                      );
                                  await edit(old);
                                } catch (e) {
                                  if (mounted) setState(() => error = e);
                                }
                              },
                              child: const Text('修订'),
                            ),
                            TextButton(
                              onPressed: item['review_status'] == 'PENDING'
                                  ? null
                                  : () async {
                                      try {
                                        final result = await ref
                                            .read(workRepositoryProvider)
                                            .request(
                                              'POST',
                                              '/procedures/${item['id']}/publish-requests',
                                              body: {
                                                'version': item['version'],
                                                'reason': '申请发布公司资料',
                                              },
                                              key: AiWorkRepository.key(),
                                            );
                                        if (context.mounted) {
                                          context.push(
                                            '/me/reviews/${result['id']}',
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) setState(() => error = e);
                                      }
                                    },
                              child: const Text('申请发布'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreparedTemplateDownload extends ConsumerStatefulWidget {
  const _PreparedTemplateDownload({
    required this.document,
    required this.version,
    required this.file,
    required this.reason,
    required this.number,
  });
  final String document, file, reason;
  final int version, number;
  @override
  ConsumerState<_PreparedTemplateDownload> createState() =>
      _PreparedTemplateDownloadState();
}

class _PreparedTemplateDownloadState
    extends ConsumerState<_PreparedTemplateDownload> {
  bool busy = false;
  Object? error;
  final cancel = CancelToken();
  late final account = ref.read(sessionProvider);
  bool get valid =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      account.id == ref.read(sessionProvider).id &&
      account.token == ref.read(sessionProvider).token;
  @override
  void dispose() {
    cancel.cancel();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !valid) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saver = ref.read(attachmentSaverProvider);
      final response = await ref
          .read(workRepositoryProvider)
          .dio
          .post<List<int>>(
            '/procedures/${Uri.encodeComponent(widget.document)}/template-files/${Uri.encodeComponent(widget.file)}',
            data: {'version': widget.version, 'reason': widget.reason},
            cancelToken: cancel,
            options: Options(responseType: ResponseType.bytes),
          );
      if (!valid) return;
      final filename =
          RegExp("filename\\*=UTF-8''([^;]+)", caseSensitive: false)
              .firstMatch(response.headers.value('content-disposition') ?? '')
              ?.group(1);
      final bytes = response.data;
      if (filename == null ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > maximumAttachmentBytes) {
        throw const FormatException('Invalid template response');
      }
      await saver(
        safeAttachmentName(Uri.decodeComponent(filename)),
        Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (valid) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: valid && !busy ? save : null,
          icon: const Icon(Icons.download_outlined),
          label: Text(busy ? '正在准备文件…' : '保存预填文件 ${widget.number}'),
        ),
        if (error != null)
          Semantics(liveRegion: true, child: Text(workError(error!))),
      ],
    );
  }
}

class DeliveryCheckPage extends ConsumerStatefulWidget {
  const DeliveryCheckPage(this.taskId, this.taskVersion, {super.key});
  final String taskId;
  final int taskVersion;
  @override
  ConsumerState<DeliveryCheckPage> createState() => _DeliveryCheckPageState();
}

class _DeliveryCheckPageState extends ConsumerState<DeliveryCheckPage>
    with WidgetsBindingObserver {
  AttachmentSelection selection = const AttachmentSelection([], ready: true);
  Map<String, dynamic>? report;
  bool busy = false;
  Object? error;
  final text = TextEditingController();
  String key = AiWorkRepository.key();
  Timer? polling;
  Timer? revalidation;
  bool foreground = true;
  int generation = 0;
  String? jobId;
  late final account = ref.read(sessionProvider);
  bool get valid =>
      mounted &&
      ref.read(sessionProvider).canReadBusiness &&
      account.id == ref.read(sessionProvider).id &&
      account.token == ref.read(sessionProvider).token;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
    revalidation = Timer.periodic(const Duration(seconds: 8), (_) {
      if (foreground && mounted && TickerMode.of(context)) refreshReport();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refreshReport();
  }

  Future<void> refreshReport() async {
    if (!valid || busy || report == null || report!['state'] == 'STALE') return;
    final ticket = generation;
    final id = report!['id'];
    try {
      final latest = await ref
          .read(workRepositoryProvider)
          .request('GET', '/tasks/${widget.taskId}/delivery-checks/$id');
      if (valid && ticket == generation && !busy) accept(latest);
    } catch (e) {
      if (valid && ticket == generation) {
        setState(() {
          report = null;
          error = e;
        });
      }
    }
  }

  Future<void> restore() async {
    final ticket = generation;
    try {
      final latest = await ref
          .read(workRepositoryProvider)
          .request('GET', '/tasks/${widget.taskId}/delivery-checks');
      if (valid && ticket == generation && latest.isNotEmpty) accept(latest);
    } catch (e) {
      if (valid) setState(() => error = e);
    }
  }

  void accept(Map<String, dynamic> result) {
    if (!valid) return;
    final pending = ['QUEUED', 'RUNNING'].contains(result['state']);
    if (pending) {
      jobId = '${result['id']}';
      polling?.cancel();
      polling = Timer(const Duration(seconds: 1), poll);
    } else {
      jobId = null;
      polling?.cancel();
    }
    setState(() {
      busy = pending;
      if (!pending && result['state'] != 'FAILED') {
        report = result;
      } else if (result['state'] == 'FAILED') {
        error = StateError('材料暂时没能核对，请重试');
        key = AiWorkRepository.key();
      }
    });
  }

  Future<void> poll() async {
    if (!valid || jobId == null) return;
    try {
      accept(
        await ref
            .read(workRepositoryProvider)
            .request('GET', '/tasks/${widget.taskId}/delivery-checks/$jobId'),
      );
    } catch (e) {
      if (valid) {
        setState(() {
          busy = false;
          error = e;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    polling?.cancel();
    revalidation?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> check() async {
    generation++;
    setState(() {
      busy = true;
      error = null;
      report = null;
    });
    try {
      final result = await ref
          .read(workRepositoryProvider)
          .request(
            'POST',
            '/tasks/${widget.taskId}/delivery-checks',
            body: {
              'taskVersion': widget.taskVersion,
              'attachmentIds': selection.files.map((e) => e.id).toList(),
            },
            key: key,
          );
      if (valid) accept(result);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (valid && jobId == null) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (!valid ||
        report == null ||
        report!['snapshotValid'] == false ||
        report!['state'] == 'STALE' ||
        text.text.trim().isEmpty) {
      return;
    }
    final manual = report!['state'] != 'PASS';
    if (manual) {
      final ok = await showDialog<bool>(
        context: context,
        animationStyle: WorkMotion.dialog(context),
        builder: (context) => AlertDialog(
          title: const Text('提交人工核对'),
          content: const Text('未核实的项目会随反馈保留，请确认已检查材料，并在反馈中说明。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('再核对一下'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('提交人工核对'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || !valid) return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(workRepositoryProvider)
          .request(
            'POST',
            '/tasks/${widget.taskId}/deliveries',
            body: {
              'taskVersion': widget.taskVersion,
              'checkId': report!['id'],
              'checkVersion': report!['version'],
              'attachmentIds': report!['attachmentIds'],
              'mode': manual ? 'MANUAL' : 'CHECKED',
              'text': text.text.trim(),
            },
            key: 'submit-$key',
          );
      if (!mounted || !valid) return;
      ref.invalidate(itemProvider(('tasks', widget.taskId)));
      notice(context, '已提交，等待验收', success: true);
      context.pop();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionProvider);
    if (!valid) {
      return Scaffold(
        appBar: AppBar(title: const Text('检查交付')),
        body: const Center(child: Text('账号已切换，请重新打开任务')),
      );
    }
    return Scaffold(
      backgroundColor: SunnyPalette.paper,
      appBar: AppBar(title: const Text('检查交付')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AttachmentEditor(
            aiWork: true,
            enabled: !busy,
            onChanged: (s) => setState(() {
              generation++;
              selection = s;
              report = null;
              key = AiWorkRepository.key();
            }),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy || !selection.ready || selection.files.isEmpty
                ? null
                : check,
            child: Text(busy ? '正在核对…' : '检查材料'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(workError(error!)),
            ),
          if (report != null) ...[
            const SizedBox(height: 20),
            PaperSurface(
              color: SunnyPalette.purple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report!['summary']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (report!['state'] == 'STALE')
                    TextButton(
                      onPressed: () {
                        ref.invalidate(itemProvider(('tasks', widget.taskId)));
                        context.go(
                          '/item/tasks/${Uri.encodeComponent(widget.taskId)}',
                        );
                      },
                      child: const Text('查看最新任务'),
                    ),
                  for (final finding in workMaps(report!['findings']))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '${finding['title']}\n${finding['message']} ${finding['locator']}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: '成果说明'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  busy ||
                      report!['state'] == 'NEEDS_FIX' ||
                      report!['state'] == 'STALE' ||
                      report!['snapshotValid'] == false
                  ? null
                  : submit,
              child: Text(report!['state'] == 'PASS' ? '提交反馈' : '提交人工核对'),
            ),
          ],
        ],
      ),
    );
  }
}
