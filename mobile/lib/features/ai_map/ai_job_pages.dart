import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/ai_repository.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'server_ai_page.dart';

class AiJobPage extends ConsumerStatefulWidget {
  const AiJobPage(this.id, {super.key, this.edit = false, this.actionIndex});
  final String id;
  final bool edit;
  final int? actionIndex;
  @override
  ConsumerState<AiJobPage> createState() => _AiJobPageState();
}

class _AiJobPageState extends AiProtectedState<AiJobPage> {
  AiJob? job;
  bool loading = true, saving = false, conflict = false;
  final form = GlobalKey<FormState>();
  final summary = TextEditingController();
  final actions = <TextEditingController>[];
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void clearProtected() {
    job = null;
    summary.clear();
    for (final c in actions) {
      c.clear();
    }
  }

  @override
  void dispose() {
    summary.dispose();
    for (final c in actions) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    if (!alive) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await repo.job(widget.id, token: token);
      if (!alive || token.isCancelled) return;
      if (value.data['owner_id'] != originalAccount.id) {
        throw const ApiFailure(FailureKind.forbidden, '当前账号不能读取该分析');
      }
      setState(() {
        job = value;
        summary.text = value.summary;
        conflict = false;
        while (actions.length < value.actions.length) {
          actions.add(TextEditingController());
        }
        for (var i = 0; i < actions.length; i++) {
          actions[i].text = i < value.actions.length
              ? '${value.actions[i]['title']}'
              : '';
        }
      });
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => loading = false);
    }
  }

  Future<void> reload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => TuantuanDialog(
        title: const Text('重新读取分析草稿'),
        content: const Text('重新读取会替换未保存的正文和建议，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留编辑'),
          ),
          SunnyPrimaryButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('重新读取'),
          ),
        ],
      ),
    );
    if (alive && confirmed == true) await load();
  }

  Future<void> save() async {
    if (!alive ||
        saving ||
        conflict ||
        job == null ||
        !form.currentState!.validate()) {
      return;
    }
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final value = await repo.edit(
        job!,
        summary.text,
        actions.take(job!.actions.length).map((c) => c.text).toList(),
        token: token,
      );
      if (!alive || token.isCancelled) return;
      if (value.data['owner_id'] != originalAccount.id) {
        throw const ApiFailure(FailureKind.forbidden, '当前账号不能读取该分析');
      }
      setState(() {
        job = value;
        error = null;
      });
      if (mounted) notice(context, '建议草稿已保存，尚未创建任务', success: true);
    } catch (e) {
      if (alive && !token.isCancelled) {
        if (e is ApiFailure && e.kind == FailureKind.conflict) {
          setState(() => conflict = true);
        }
        fail(e);
      }
    } finally {
      if (alive && !token.isCancelled) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!guard()) return deniedPage();
    final value = job;
    final index = widget.actionIndex;
    final action =
        index != null &&
            value != null &&
            index >= 0 &&
            index < value.actions.length
        ? value.actions[index]
        : null;
    return PageFrame(
      title: widget.edit ? '编辑建议草稿' : '建议与依据',
      actions: [
        if (widget.edit)
          TextButton(
            onPressed: loading || saving ? null : reload,
            child: const Text('重新读取'),
          ),
      ],
      bottom: value == null || value.state != 'SUCCEEDED'
          ? null
          : BottomActions(
              primary: widget.edit
                  ? SunnyPrimaryButton(
                      loading: saving,
                      onPressed: saving || conflict ? null : save,
                      child: const Text('保存建议草稿'),
                    )
                  : SunnyPrimaryButton(
                      onPressed:
                          originalAccount.dispatch &&
                              originalAccount.manager &&
                              action != null &&
                              value.validRefs(
                                action['sourceIds'],
                                originalAccount.id,
                              )
                          ? () => context.push(
                              '/ai/jobs/${encode(value.id)}/confirm/$index',
                            )
                          : null,
                      child: const Text('人工确认创建任务'),
                    ),
              secondary: widget.edit
                  ? null
                  : OutlinedButton(
                      onPressed: () =>
                          context.push('/ai/jobs/${encode(value.id)}/edit'),
                      child: const Text('编辑建议'),
                    ),
              note: error ?? 'AI建议需人工核实，保存草稿不会自动派发任务',
            ),
      child: PageBody(
        children: [
          if (loading) const LoadingSkeleton(),
          if (error != null && value == null)
            ErrorPanel(error!, retry: conflict ? reload : load),
          if (!loading && value != null) ...[
            Text(
              value.input['scope'] == 'SELF'
                  ? '分析范围：本人'
                  : aiScope(originalAccount),
            ),
            Text(
              '${value.input['date']} · ${aiPeriod(value.input['period'])} · ${aiTime(value.output?['generatedAt'])}',
            ),
            const SizedBox(height: 16),
            if (value.state != 'SUCCEEDED')
              Text('当前作业${value.state}，没有可编辑的完成结果，请返回AI地图查看状态。')
            else if (widget.edit)
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '分析正文',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: summary,
                      minLines: 6,
                      maxLines: 16,
                      maxLength: 20000,
                      decoration: const InputDecoration(labelText: '分析与依据'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请填写分析正文' : null,
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < value.actions.length; i++) ...[
                      TextFormField(
                        controller: actions[i],
                        maxLength: 200,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(labelText: '建议${i + 1}'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请填写建议' : null,
                      ),
                      AiSources(value, value.actions[i]['sourceIds']),
                      const SizedBox(height: 12),
                    ],
                    const Text('来源引用和节点保持，修改不会绕过服务端权限校验。'),
                  ],
                ),
              )
            else if (action == null)
              const Text('该建议不可用，请返回重新读取。')
            else ...[
              Text(
                '${action['title']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                '依据与不确定性',
                style: TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(value.summary, style: const TextStyle(height: 1.7)),
              const SizedBox(height: 16),
              const Text('这是基于当前记录的建议，无法证明所有依赖和实际影响。请核实原始材料。'),
              const SizedBox(height: 20),
              const Text('原始来源', style: TextStyle(fontWeight: FontWeight.w700)),
              AiSources(value, action['sourceIds']),
              if (!value.validRefs(action['sourceIds'], originalAccount.id))
                const Text('有效来源不足，不能确认创建任务。'),
              if (!originalAccount.dispatch || !originalAccount.manager)
                const Text('当前账号没有派发资格，可阅读来源和编辑自己的建议草稿。'),
            ],
          ],
        ],
      ),
    );
  }
}

class AiConfirmPage extends ConsumerStatefulWidget {
  const AiConfirmPage(this.id, this.index, {super.key});
  final String id;
  final int index;
  @override
  ConsumerState<AiConfirmPage> createState() => _AiConfirmPageState();
}

class _AiConfirmPageState extends AiProtectedState<AiConfirmPage> {
  AiJob? job;
  bool loading = true, busy = false, ready = true, stale = false;
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      content = TextEditingController(),
      group = TextEditingController(),
      progress = TextEditingController();
  Record? owner;
  final collaborators = <String, Record>{};
  DateTime? deadline;
  List<UploadedAttachment> files = [];
  String? successfulId;
  bool successfulReview = false;
  String? attemptedPayload, attemptedKey;
  Map<String, dynamic>? get action =>
      job != null && widget.index >= 0 && widget.index < job!.actions.length
      ? job!.actions[widget.index]
      : null;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void clearProtected() {
    job = null;
    owner = null;
    collaborators.clear();
    files = [];
    title.clear();
    content.clear();
    progress.clear();
    group.clear();
    successfulId = null;
    successfulReview = false;
    attemptedPayload = null;
    attemptedKey = null;
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    group.dispose();
    progress.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!alive) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    try {
      final value = await repo.job(widget.id, token: token);
      if (!alive || token.isCancelled) return;
      if (value.data['owner_id'] != originalAccount.id) {
        throw const ApiFailure(FailureKind.forbidden, '当前账号不能读取该分析');
      }
      if (value.state != 'SUCCEEDED' ||
          widget.index < 0 ||
          widget.index >= value.actions.length ||
          !value.validRefs(
            value.actions[widget.index]['sourceIds'],
            originalAccount.id,
          )) {
        throw const ApiFailure(FailureKind.validation, '建议或来源不可用，不能创建任务');
      }
      setState(() {
        job = value;
        title.text = '${value.actions[widget.index]['title']}';
        content.text = value.summary;
      });
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => loading = false);
    }
  }

  Future<void> pickPerson(bool collaborator) async {
    final selected = await showTuantuanBottomSheet<Record>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PersonPicker(dispatch: true),
    );
    if (!alive || selected == null) return;
    setState(() {
      if (collaborator) {
        if (selected.id != owner?.id) collaborators[selected.id] = selected;
      } else {
        owner = selected;
        collaborators.remove(selected.id);
      }
    });
  }

  Future<void> pickDeadline() async {
    final date = await showPremiumDatePicker(
      context,
      initial: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (!mounted || !alive || date == null) return;
    final time = await showPremiumTimePicker(
      context,
      initial: const TimeOfDay(hour: 18, minute: 0),
    );
    if (alive && time != null) {
      setState(
        () => deadline = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> submit() async {
    if (!alive ||
        busy ||
        !ready ||
        stale ||
        successfulId != null ||
        !originalAccount.dispatch ||
        !originalAccount.manager ||
        job == null ||
        !form.currentState!.validate()) {
      return;
    }
    if (owner == null ||
        deadline == null ||
        !deadline!.isAfter(DateTime.now())) {
      setState(() => error = '请选择主负责人和未来截止时间');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => TuantuanDialog(
        title: const Text('确认派发任务'),
        content: Text(
          '将“${title.text.trim()}”派发给${owner!.title}。建议来源与负责人需由你核实。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回编辑'),
          ),
          SunnyPrimaryButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认派发'),
          ),
        ],
      ),
    );
    if (!alive || approved != true) return;
    final repo = ref.read(aiRepositoryProvider), token = nextTransport();
    final task = <String, dynamic>{
      'title': title.text.trim(),
      'content': content.text.trim(),
      'group': group.text.trim(),
      'ownerId': owner!.id,
      'urgency': 'NORMAL',
      'deadline': deadline!.toUtc().toIso8601String(),
      'collaborators': collaborators.keys.toList(),
      'attachments': files.map((f) => f.id).toList(),
    };
    // Identical retry keeps its key; a changed human-confirmed payload gets a new key.
    final payload = jsonEncode(task);
    if (payload != attemptedPayload) {
      attemptedPayload = payload;
      attemptedKey = 'ai-${DateTime.now().microsecondsSinceEpoch}';
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // 原版本由服务端在确认事务中校验；同键重试仍可取得已成功的原回执。
      final result = await repo.confirm(
        job!,
        widget.index,
        task,
        attemptedKey!,
        token: token,
      );
      if (!alive || token.isCancelled) return;
      setState(() {
        successfulId = '${result['id']}';
        successfulReview = result['kind'] == 'TASK_CREATE';
      });
      refreshBusiness(ref);
    } catch (e) {
      if (alive && !token.isCancelled) fail(e);
    } finally {
      if (alive && !token.isCancelled) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!guard()) return deniedPage();
    if (!originalAccount.dispatch || !originalAccount.manager) {
      return const PageFrame(
        title: '人工确认任务',
        child: Center(child: Text('当前账号没有任务派发资格')),
      );
    }
    return PageFrame(
      title: '人工确认任务',
      bottom: BottomActions(
        primary: SunnyPrimaryButton(
          loading: busy,
          onPressed: successfulId != null
              ? () => context.push('/item/${successfulReview ? 'reviews' : 'tasks'}/${encode(successfulId!)}')
              : loading || busy || !ready || stale || job == null
              ? null
              : submit,
          child: Text(successfulId != null ? (successfulReview ? '查看任务申请' : '查看已创建任务') : '确认并提交任务申请'),
        ),
        note: job == null ? '核对来源与分工后人工派发' : error ?? '核对来源与分工后人工派发，包含实际附件ID',
      ),
      child: PageBody(
        children: [
          if (loading) const LoadingSkeleton(),
          if (error != null && job == null)
            ErrorPanel(error!, retry: job == null ? load : null),
          if (successfulId != null) Text(successfulReview ? '任务申请已提交，请以审核结果确认生效状态。原AI建议仍保留。' : '任务已创建，原AI建议仍保留为草稿。'),
          if (job != null)
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '建议→人工核对→正式任务',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  AiSources(job!, action?['sourceIds']),
                  const Divider(height: 24),
                  TextFormField(
                    controller: title,
                    enabled: !busy && successfulId == null,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '任务名称'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请填写任务名称' : null,
                  ),
                  TextFormField(
                    controller: content,
                    enabled: !busy && successfulId == null,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(labelText: '任务内容与验收要求'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: group,
                    enabled: !busy && successfulId == null,
                    decoration: const InputDecoration(labelText: '所属分组'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: progress,
                    enabled: !busy && successfulId == null,
                    decoration: const InputDecoration(labelText: '进度备注（文字说明）'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy || successfulId != null
                        ? null
                        : pickDeadline,
                    icon: const Icon(Icons.schedule),
                    label: Text(deadline == null ? '选择截止时间' : aiTime(deadline)),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || successfulId != null
                        ? null
                        : () => pickPerson(false),
                    icon: const Icon(Icons.person_outline),
                    label: Text(
                      owner == null ? '选择主负责人' : '主负责人：${owner!.title}',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final person in collaborators.values)
                        InputChip(
                          label: Text(person.title),
                          onDeleted: busy || successfulId != null
                              ? null
                              : () => setState(
                                  () => collaborators.remove(person.id),
                                ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: busy || successfulId != null
                        ? null
                        : () => pickPerson(true),
                    child: const Text('添加协作人'),
                  ),
                  AttachmentEditor(
                    enabled: !busy && successfulId == null,
                    onChanged: (selection) {
                      if (alive) {
                        setState(() {
                          files = selection.files;
                          ready = selection.ready;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
