import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/data/models/diary_task_links.dart';
import 'package:pandora_mobile/shared/diary_task_links.dart';
import 'catalog.dart';

class FormPage extends ConsumerStatefulWidget {
  const FormPage(
    this.kind, {
    super.key,
    this.id,
    this.source,
    this.version = 1,
    this.restoreDiaryDraft = false,
  });
  final String kind;
  final String? id, source;
  final int version;
  final bool restoreDiaryDraft;
  @override
  ConsumerState<FormPage> createState() => _FormPageState();
}

class _FormPageState extends ConsumerState<FormPage> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  final visiblePasswords = <String>{};
  late final ScreenSpec spec;
  final String idem = DateTime.now().microsecondsSinceEpoch.toString();
  Timer? timer;
  bool busy = false, saved = false, submitted = false, loadingExisting = false;
  bool loadFailed = false, conflict = false;
  DateTime? savedAt;
  late DateTime businessDate;
  late final String accountId;
  late final DraftStore draftStore;
  int editGeneration = 0;
  bool draftRestoring = false;
  Future<void> saveQueue = Future.value();
  String? error;
  String? selectedOwner;
  String? selectedDepartment;
  final collaborators = <String, Record>{};
  List<UploadedAttachment> uploadedAttachments = [];
  bool attachmentsReady = true;
  DateTime? deadline;
  int? loadedVersion;
  String? serverDraftId;
  Record? original;
  bool get log => widget.kind == 'log-edit';
  bool get document => log || widget.kind == 'log-revise';
  DraftLocation get draftLocation => log
      ? DraftLocation.diary(accountId, businessDate)
      : DraftLocation.revision(
          accountId,
          widget.id!,
          loadedVersion ?? widget.version,
        );
  @override
  void initState() {
    super.initState();
    spec = screens[widget.kind]!;
    businessDate = ref.read(logDateProvider);
    accountId = ref.read(sessionProvider).id;
    if (document) draftStore = ref.read(draftStoreProvider);
    for (final field in spec.fields) {
      controllers[field] = TextEditingController();
    }
    if (log && widget.id == null) restore();
    if (widget.id != null ||
        widget.source != null ||
        widget.kind == 'profile-edit') {
      loadExisting();
    }
  }

  Future<void> loadExisting({bool reload = false}) async {
    loadingExisting = true;
    loadFailed = false;
    try {
      if (widget.kind == 'note') {
        final target = PrivateNoteTarget.parse(widget.id ?? '');
        if (target == null) {
          throw const ApiFailure(FailureKind.validation, '请从对应详情进入私人备注');
        }
        if (target.accountId != accountId) {
          throw const ApiFailure(FailureKind.forbidden, '仅本人可以读取私人备注');
        }
      }
      final resource = widget.source != null
          ? 'ai-maps'
          : widget.kind == 'note'
          ? 'private-notes'
          : widget.kind == 'comment'
          ? 'logs'
          : spec.resource;
      final item = await ref
          .read(repositoryProvider)
          .detail(
            resource,
            widget.source ??
                widget.id ??
                serverDraftId ??
                ref.read(sessionProvider).id,
          );
      if (!mounted || ref.read(sessionProvider).id != accountId) return;
      original = item;
      loadedVersion = item.version;
      if (widget.kind == 'profile-edit') {
        controllers['姓名']!.text = item.fields['姓名']?.toString() ?? item.title;
      }
      if (!reload &&
          widget.id != null &&
          widget.kind != 'note' &&
          item.version != widget.version) {
        conflict = true;
        loadFailed = true;
        setState(() => error = '版本已更新，请明确重新读取后再编辑；本机草稿不会自动覆盖新版本');
        return;
      }
      if (document) {
        businessDate =
            DateTime.tryParse('${item.fields['businessDate']}') ?? businessDate;
      }
      for (final entry in controllers.entries) {
        if (widget.kind != 'profile-edit' || entry.key != '姓名') {
          entry.value.text = entry.key == '关联任务'
              ? DiaryTaskLinks.encode(
                  item.fields['taskIds'] ?? item.fields[entry.key],
                )
              : '${item.fields[entry.key] ?? ''}';
        }
      }
      for (final title in ['标题', '任务名称']) {
        if (controllers.containsKey(title)) {
          controllers[title]!.text = item.title;
        }
      }
      if (controllers.containsKey('任务内容')) {
        controllers['任务内容']!.text =
            '${item.fields['任务内容'] ?? item.fields['body'] ?? ''}';
      }
      if (controllers.containsKey('内容')) {
        controllers['内容']!.text =
            '${item.fields['内容'] ?? item.fields['body'] ?? ''}';
      }
      if (controllers.containsKey('个人介绍')) {
        controllers['个人介绍']!.text =
            '${item.fields['个人介绍'] ?? item.fields['body'] ?? ''}';
      }
      selectedOwner = item.ownerId;
      deadline = DateTime.tryParse('${item.fields['deadline']}');
      if (controllers.containsKey('截止时间') && deadline != null) {
        controllers['截止时间']!.text = deadline!.toLocal().toString().substring(
          0,
          16,
        );
      }
      if (document && !reload) await restore();
      if (reload) {
        saved = false;
        savedAt = null;
        conflict = false;
        error = null;
      }
      setState(() {});
    } catch (e) {
      // An absent own note is an empty editor, not a failed record load.
      loadFailed =
          !(widget.kind == 'note' &&
              e is ApiFailure &&
              e.kind == FailureKind.notFound);
      if (mounted && loadFailed) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loadingExisting = false);
    }
  }

  Future<void> restore() async {
    draftRestoring = true;
    final generation = editGeneration;
    try {
      var draft = await draftStore.read(draftLocation);
      if (draft == null &&
          widget.kind == 'log-revise' &&
          widget.restoreDiaryDraft &&
          original?.ownerId == accountId) {
        final diary = await draftStore.read(
          DraftLocation.diary(accountId, businessDate),
        );
        if (diary?.serverId == widget.id &&
            diary?.serverVersion == widget.version) {
          draft = diary;
        }
      }
      if (!mounted ||
          ref.read(sessionProvider).id != accountId ||
          generation != editGeneration ||
          draft == null) {
        return;
      }
      for (final entry in controllers.entries) {
        if (draft.fields.containsKey(entry.key)) {
          entry.value.text = draft.fields[entry.key]!;
        }
      }
      if (log && draft.serverId != null) {
        if (original != null &&
            (original!.id != draft.serverId ||
                original!.version != draft.serverVersion)) {
          conflict = true;
          error = '服务器草稿版本已变化，本机输入已保留，请明确重新读取';
        } else {
          serverDraftId = draft.serverId;
          loadedVersion = draft.serverVersion;
        }
      }
      savedAt = draft.savedAt;
      setState(() => saved = true);
    } catch (e) {
      if (mounted) setState(() => error = '草稿读取失败：$e');
    } finally {
      if (mounted) setState(() => draftRestoring = false);
    }
  }

  Future<void> persist(
    LocalDraft draft,
    DraftLocation location,
    int generation,
  ) async {
    await draftStore.write(location, draft);
    if (mounted &&
        ref.read(sessionProvider).id == accountId &&
        generation == editGeneration) {
      setState(() {
        saved = true;
        savedAt = draft.savedAt;
        if (error?.startsWith('草稿保存失败') == true ||
            error?.startsWith('草稿读取失败') == true) {
          error = null;
        }
      });
    }
  }

  Future<void> saveDraft({bool notify = false}) async {
    if (loadingExisting || draftRestoring || submitted) return;
    timer?.cancel();
    final snapshot = {for (final e in controllers.entries) e.key: e.value.text};
    final location = draftLocation, generation = editGeneration;
    final draft = LocalDraft(
      fields: snapshot,
      savedAt: DateTime.now(),
      serverId: log ? serverDraftId : null,
      serverVersion: log ? loadedVersion : null,
    );
    saveQueue = saveQueue
        .catchError((Object _) {})
        .then((_) => persist(draft, location, generation));
    try {
      await saveQueue;
      if (mounted && ref.read(sessionProvider).id == accountId) {
        ref.invalidate(todayDraftProvider(accountId));
        if (notify) notice(context, '草稿已加密保存到此设备', success: true);
      }
    } catch (e) {
      if (mounted) setState(() => error = '草稿保存失败，内容仍在编辑器中：$e');
    }
  }

  void autoSave() {
    if (!document) return;
    editGeneration++;
    timer?.cancel();
    setState(() => saved = false);
    timer = Timer(const Duration(milliseconds: 600), saveDraft);
  }

  @override
  void dispose() {
    timer?.cancel();
    if (document &&
        !submitted &&
        !saved &&
        controllers.values.any((c) => c.text.isNotEmpty)) {
      final snapshot = {
            for (final e in controllers.entries) e.key: e.value.text,
          },
          location = draftLocation,
          generation = editGeneration;
      final draft = LocalDraft(
        fields: snapshot,
        savedAt: DateTime.now(),
        serverId: log ? serverDraftId : null,
        serverVersion: log ? loadedVersion : null,
      );
      unawaited(
        saveQueue
            .catchError((Object _) {})
            .then((_) => persist(draft, location, generation))
            .catchError((Object _) {}),
      );
    }
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool requiredField(String field) => [
    '任务名称',
    '标题',
    '账号',
    '密码',
    '手机号',
    '部门',
    '主负责人',
    '截止时间',
    '今日工作',
    '成果说明',
    '问题描述',
    '验收意见',
    '驳回原因',
    '变更理由',
    '修改理由',
    '撤回原因',
    '原密码',
    '新密码',
    '确认密码',
    '名称',
    '员工',
    '停用理由',
  ].contains(field);
  String? validate(String field, String? value) {
    if (requiredField(field) && (value ?? '').trim().isEmpty) {
      return '请填写$field';
    }
    if (field == '手机号' && !RegExp(r'^1\d{10}$').hasMatch(value ?? '')) {
      return '请输入11位手机号';
    }
    if (field.contains('密码') &&
        (value ?? '').length <
            (!AppConfig.mock && widget.kind != 'login' && field != '原密码'
                ? 12
                : 8)) {
      return !AppConfig.mock && widget.kind != 'login' && field != '原密码'
          ? '密码至少12个字符'
          : '密码至少8位';
    }
    if (field == '截止时间' &&
        deadline != null &&
        !deadline!.isAfter(DateTime.now())) {
      return '截止时间必须晚于当前时间';
    }
    if (field == '确认密码' && value != controllers['新密码']?.text) return '两次密码不一致';
    if (field == '工时' &&
        (value ?? '').isNotEmpty &&
        (double.tryParse(value!) == null ||
            !double.parse(value).isFinite ||
            double.parse(value) < 0 ||
            double.parse(value) > 24)) {
      return '工时应在0到24之间';
    }
    return null;
  }

  Future<void> selectPerson(String field) async {
    final result = await showTuantuanBottomSheet<Record>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PersonPicker(
        dispatch: ['dispatch', 'transfer', 'ai-draft'].contains(widget.kind),
      ),
    );
    if (result != null &&
        mounted &&
        ref.read(sessionProvider).id == accountId) {
      setState(() {
        if (field == '协作人') {
          if (result.id != selectedOwner) collaborators[result.id] = result;
          controllers[field]!.text = collaborators.values
              .map((p) => p.title)
              .join('、');
        } else {
          controllers[field]!.text = result.title;
          if (field == '主负责人') {
            selectedOwner = result.id;
            collaborators.remove(result.id);
            controllers['协作人']?.text = collaborators.values
                .map((p) => p.title)
                .join('、');
          }
        }
      });
    }
  }

  Widget field(String label) {
    final controller = controllers[label]!;
    if (widget.kind == 'register' && label == '部门' && !AppConfig.mock) {
      return ref
          .watch(registrationDepartmentsProvider)
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorPanel(
              '无法加载注册部门：$e',
              retry: () => ref.invalidate(registrationDepartmentsProvider),
            ),
            data: (page) => DropdownButtonFormField<String>(
              initialValue: page.items.any((r) => r.id == selectedDepartment)
                  ? selectedDepartment
                  : null,
              decoration: const InputDecoration(labelText: '申请部门'),
              items: page.items
                  .map(
                    (r) => DropdownMenuItem(value: r.id, child: Text(r.title)),
                  )
                  .toList(),
              onChanged: (id) {
                selectedDepartment = id;
                controller.text = id ?? '';
              },
              validator: (id) => id == null ? '请选择申请部门' : null,
            ),
          );
    }
    final options = switch (label) {
      '部门' || '上级部门' => ['产品部', '市场部', '技术部'],
      '紧急程度' => ['紧急', '普通', '不紧急'],
      '所属分组' => ['产品设计', '客户调研', '日常协作'],
      '角色' => UserRole.values.map((r) => r.label).toList(),
      '展示受众' => ['本团队', '本部门', '全公司'],
      _ => <String>[],
    };
    if (options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        key: ValueKey('$label:${controller.text}'),
        initialValue: options.contains(controller.text)
            ? controller.text
            : null,
        decoration: InputDecoration(labelText: label),
        items: options
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) {
          controller.text = v ?? '';
        },
        validator: (v) => validate(label, v),
      );
    }
    if (label.startsWith('允许') || label.endsWith('需复核')) {
      return SwitchListTile(
        title: Text(label),
        value: controller.text == 'true',
        onChanged: (v) => setState(() => controller.text = '$v'),
      );
    }
    if (['附件', '头像'].contains(label)) {
      if (label == '附件' && !['dispatch'].contains(widget.kind)) {
        return const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('附件关联暂不可用'),
          subtitle: Text('当前成果反馈/意见反馈接口不支持附件关联，请在说明中补充材料信息。'),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label == '头像')
            Row(
              children: [
                ProtectedAvatar(
                  name: controllers['姓名']?.text ?? '',
                  attachmentId:
                      uploadedAttachments.firstOrNull?.id ??
                      original?.fields['avatarAttachmentId'] as String?,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('当前/候选头像 · 保存资料后生效')),
              ],
            ),
          AttachmentEditor(
            key: ValueKey('$accountId:$label'),
            avatar: label == '头像',
            enabled: !busy && !loadingExisting && !loadFailed,
            onChanged: (selection) {
              if (mounted && ref.read(sessionProvider).id == accountId) {
                setState(() {
                  uploadedAttachments = selection.files;
                  attachmentsReady = selection.ready;
                  controller.text = selection.files
                      .map((f) => f.name)
                      .join('、');
                });
              }
            },
          ),
        ],
      );
    }
    if (label == '协作人') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('协作人（可选）'),
          Wrap(
            spacing: 8,
            children: [
              for (final p in collaborators.values)
                InputChip(
                  label: Text(p.title),
                  onDeleted: busy
                      ? null
                      : () => setState(() {
                          collaborators.remove(p.id);
                          controller.text = collaborators.values
                              .map((p) => p.title)
                              .join('、');
                        }),
                ),
              TextButton.icon(
                onPressed: busy ? null : () => selectPerson(label),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('添加协作人'),
              ),
            ],
          ),
        ],
      );
    }
    if (label == '关联任务') {
      return DiaryTaskLinksEditor(
        value: controller.text,
        enabled:
            !busy &&
            !loadFailed &&
            !loadingExisting &&
            ref.watch(sessionProvider).id == accountId,
        onChanged: (value) {
          if (!mounted || busy || ref.read(sessionProvider).id != accountId) {
            return;
          }
          setState(() => controller.text = value);
          autoSave();
        },
      );
    }
    final person = ['主负责人', '协作人', '员工', '直属上级', '指定公司复核人'].contains(label);
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: document
            ? null
            : '$label${requiredField(label) ? ' *' : ''}',
        hintText: document ? '填写$label' : null,
        filled: document ? false : null,
        border: document ? InputBorder.none : null,
        enabledBorder: document ? InputBorder.none : null,
        focusedBorder: document ? InputBorder.none : null,
        contentPadding: document
            ? const EdgeInsets.symmetric(vertical: 8)
            : null,
        suffixIcon: label.contains('密码')
            ? IconButton(
                tooltip: visiblePasswords.contains(label) ? '隐藏密码' : '显示密码',
                onPressed: () => setState(
                  () => visiblePasswords.contains(label)
                      ? visiblePasswords.remove(label)
                      : visiblePasswords.add(label),
                ),
                icon: Icon(
                  visiblePasswords.contains(label)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : person
            ? const Icon(Icons.person_search_outlined)
            : label == '截止时间'
            ? const Icon(Icons.calendar_today)
            : null,
      ),
      obscureText: label.contains('密码') && !visiblePasswords.contains(label),
      readOnly:
          person ||
          label == '截止时间' ||
          (widget.kind == 'profile-edit' && label == '姓名'),
      minLines: document && label == '今日工作' ? 2 : null,
      maxLines:
          [
            '内容',
            '任务内容',
            '今日工作',
            '明日计划',
            '成果说明',
            '备注',
            '个人介绍',
            '评语',
            '问题描述',
            '遇到的阻碍',
            '验收意见',
          ].contains(label)
          ? (document ? null : 4)
          : 1,
      keyboardType: ['手机号', '工时', '排序位置'].contains(label)
          ? TextInputType.number
          : TextInputType.text,
      onChanged: (_) => autoSave(),
      validator: (value) => validate(label, value),
      onTap: person
          ? () => selectPerson(label)
          : label == '截止时间'
          ? () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime(2040),
              );
              if (date == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 18, minute: 0),
              );
              if (time != null && mounted) {
                setState(() {
                  deadline = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                  controller.text =
                      '${date.year}-${date.month}-${date.day} ${time.format(context)}';
                });
              }
            }
          : null,
    );
  }

  Future<void> submit() async {
    if (loadingExisting ||
        loadFailed ||
        conflict ||
        busy ||
        !attachmentsReady) {
      return;
    }
    if (!['login', 'register', 'password'].contains(widget.kind) &&
        (ref.read(sessionProvider).id != accountId ||
            !ref.read(sessionProvider).canReadBusiness)) {
      return;
    }
    if (widget.kind == 'register' &&
        !AppConfig.mock &&
        selectedDepartment == null) {
      setState(() => error = '请先加载并选择申请部门');
      return;
    }
    if (!form.currentState!.validate()) return;
    if (document) await saveDraft();
    if (!mounted || ref.read(sessionProvider).id != accountId) return;
    if (!mounted) return;
    if (['withdraw', 'disable'].contains(widget.kind)) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => TuantuanDialog(
          title: Text(spec.title),
          content: const Text('确认执行此操作？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            SunnyPrimaryButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认'),
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
    final values = <String, dynamic>{
      for (final e in controllers.entries) e.key: e.value.text,
      if (widget.id != null || serverDraftId != null)
        'id': serverDraftId ?? widget.id,
      if (widget.kind == 'profile-edit') 'id': ref.read(sessionProvider).id,
      if (widget.kind == 'profile-edit')
        'avatarAttachmentId':
            uploadedAttachments.firstOrNull?.id ??
            original?.fields['avatarAttachmentId'] ??
            '',
      if (widget.kind == 'dispatch')
        'attachments': uploadedAttachments.map((f) => f.id).toList(),
      if (widget.kind == 'dispatch')
        'collaborators': collaborators.keys
            .where((id) => id != selectedOwner)
            .toList(),
      if (widget.id == null ||
          controllers.containsKey('任务名称') ||
          controllers.containsKey('标题'))
        'title':
            controllers['任务名称']?.text ??
            controllers['标题']?.text ??
            controllers['问题描述']?.text ??
            (log
                ? '${businessDate.toIso8601String().split('T').first} 工作日报'
                : spec.title),
      if (selectedOwner != null) 'ownerId': selectedOwner,
      if (selectedDepartment != null) 'departmentId': selectedDepartment,
      if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      if (log) 'businessDate': businessDate.toIso8601String().split('T').first,
      if (controllers.containsKey('驳回原因')) 'reason': controllers['驳回原因']!.text,
    };
    try {
      final result = await ref
          .read(repositoryProvider)
          .execute(
            spec.resource,
            Command(
              spec.action,
              values,
              version:
                  log || widget.kind == 'note' || widget.kind == 'profile-edit'
                  ? loadedVersion
                  : widget.id == null
                  ? null
                  : (loadedVersion ?? widget.version),
              idempotencyKey: idem,
            ),
          );
      if (!mounted || ref.read(sessionProvider).id != accountId) return;
      refreshBusiness(ref);
      ref.invalidate(todayDraftProvider(accountId));
      ref.invalidate(recordsProvider(spec.resource));
      ref.invalidate(datedRecordsProvider(spec.resource));
      if (widget.id != null) {
        ref.invalidate(itemProvider((spec.resource, widget.id!)));
      }
      if (!mounted) return;
      if (document) {
        submitted = true;
        timer?.cancel();
        await saveQueue.catchError((Object _) {});
        try {
          await draftStore.remove(draftLocation);
        } catch (cleanup) {
          if (mounted) notice(context, '$cleanup');
        }
        ref.invalidate(todayDraftProvider(accountId));
      }
      if (!mounted) return;
      if (widget.kind == 'login') {
        if (AppConfig.mock && result.fields['accessToken'] == null) {
          ref.read(sessionProvider.notifier).state = const Session();
          context.go('/dashboard');
        } else {
          final token = result.fields['accessToken'] as String?;
          if (token == null || token.isEmpty) throw StateError('登录响应缺少访问令牌');
          final session = Session.fromRecord(result);
          try {
            await ref.read(sessionStoreProvider).save(session);
            ref.read(sessionStorageErrorProvider.notifier).state = null;
          } catch (storage) {
            if (!mounted) return;
            ref.read(sessionStorageErrorProvider.notifier).state = '$storage';
            notice(context, '$storage');
          }
          if (!mounted || ref.read(sessionProvider).id != accountId) return;
          ref.read(sessionCheckProvider.notifier).state = null;
          ref.read(sessionProvider.notifier).state = session;
          context.go(
            session.mustChangePassword
                ? '/auth/password'
                : session.canReadBusiness
                ? '/dashboard'
                : '/auth/pending',
          );
        }
      } else if (widget.kind == 'register') {
        ref.read(sessionProvider.notifier).state = Session(
          id: result.id,
          name: controllers['账号']!.text,
          active: false,
          role: UserRole.employee,
          dispatch: false,
          status: 'PENDING',
          departmentId: selectedDepartment,
        );
        context.go('/auth/pending');
      } else if (widget.kind == 'password') {
        if (!AppConfig.mock && result.fields['reloginRequired'] != true) {
          throw const ApiFailure(FailureKind.server, '改密响应未确认，请重新登录确认账号状态');
        }
        try {
          await ref.read(sessionStoreProvider).clear();
        } catch (storage) {
          if (mounted) {
            ref.read(sessionStorageErrorProvider.notifier).state = '$storage';
          }
        }
        if (!mounted) return;
        ref.read(sessionCheckProvider.notifier).state = null;
        ref.read(sessionProvider.notifier).state = const Session(
          id: '',
          name: '',
          active: false,
          dispatch: false,
          role: UserRole.employee,
        );
        context.go('/auth/login');
        notice(context, '密码已修改，请使用新密码重新登录');
      } else {
        notice(context, AppConfig.mock ? '已保存到演示数据' : '已提交');
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (log && e is DiarySubmitFailure) {
        serverDraftId = e.draftId;
        loadedVersion = e.draftVersion;
        await saveDraft();
      }
      conflict = e is ApiFailure && e.kind == FailureKind.conflict;
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  Widget submitButton() => SunnyPrimaryButton(
    loading: busy,
    onPressed:
        busy ||
            submitted ||
            draftRestoring ||
            !attachmentsReady ||
            loadingExisting ||
            loadFailed ||
            conflict ||
            (!AppConfig.mock && widget.kind == 'return')
        ? null
        : submit,
    child: Text(
      loadingExisting
          ? '正在读取…'
          : widget.kind == 'login'
          ? '登录'
          : widget.kind == 'register'
          ? '申请加入团队'
          : error != null
          ? '重试提交'
          : document
          ? (log ? '提交日志' : '提交修订申请')
          : spec.title,
    ),
  );
  Widget failure() => PaperSurface(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          document ? '提交失败，内容已保留' : '操作未完成',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if ((conflict || loadFailed) &&
            (widget.id != null ||
                serverDraftId != null ||
                widget.kind == 'profile-edit'))
          TextButton(
            onPressed: loadingExisting
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => TuantuanDialog(
                        title: const Text('重新读取最新版本？'),
                        content: const Text(
                          '编辑区将替换为最新内容。本机已保存的草稿保留，不会自动提交或覆盖服务器。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('保留当前编辑'),
                          ),
                          SunnyPrimaryButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('重新读取'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true && mounted) {
                      if (document &&
                          controllers.values.any((c) => c.text.isNotEmpty)) {
                        await saveDraft();
                      }
                      if (mounted) {
                        setState(() => loadingExisting = true);
                        await loadExisting(reload: true);
                      }
                    }
                  },
            child: const Text('重新读取最新版本'),
          ),
      ],
    ),
  );
  Widget recordContext() {
    final item = original!;
    final f = item.fields;
    final task = spec.resource == 'tasks';
    final fields = widget.kind == 'acceptance' || widget.kind == 'return'
        ? ['成果说明', '遇到的阻碍', '附件']
        : task
        ? ['主负责人', '截止时间']
        : widget.kind == 'log-revise' || widget.kind == 'comment'
        ? ['业务日期', '今日工作']
        : ['内容'];
    String value(String label) => switch (label) {
      '主负责人' => '${f[label] ?? f['ownerName'] ?? item.ownerId}',
      '截止时间' => f['deadline'] == null ? '未设置' : '${f['deadline']}',
      '业务日期' => '${f['businessDate'] ?? '未标记'}',
      '内容' => '${f['内容'] ?? f['body'] ?? '暂无内容'}',
      _ => '${f[label] ?? '暂无内容'}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          widget.kind == 'acceptance' || widget.kind == 'return'
              ? '本次成果 · 只读'
              : '当前生效 · v${item.version}',
        ),
        PaperSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final label in fields) ...[
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: CuteTokens.muted),
                ),
                const SizedBox(height: 4),
                Text(value(label)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.kind == 'withdraw')
          const Text('撤回影响当前负责人及协作人，确认后任务不再继续派发。原记录与流转历史保留。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.mock && widget.kind == 'ai-draft') {
      return PageFrame(
        title: '确认AI建议',
        child: PageBody(
          children: [
            const Text('请从已完成的AI作业打开建议，核对来源后进入人工确认页面。'),
            SunnyPrimaryButton(
              onPressed: () => context.go('/ai'),
              child: const Text('打开AI地图'),
            ),
          ],
        ),
      );
    }
    final user = ref.watch(sessionProvider);
    if (!['login', 'register', 'password'].contains(widget.kind) &&
        (user.id != accountId || !user.canReadBusiness)) {
      return const PageFrame(
        title: '编辑已停止',
        child: EmptyIllustration(
          showCharacter: false,
          title: '账号状态已变化',
          subtitle: '请返回后重新进入编辑',
        ),
      );
    }
    final denied =
        (spec.manager && !user.manager) ||
        (spec.admin && !user.administrator) ||
        (['dispatch', 'ai-draft'].contains(widget.kind) && !user.dispatch);
    final auth = ['login', 'register'].contains(widget.kind);
    if (denied) {
      return PageFrame(
        title: spec.title,
        child: const EmptyIllustration(
          showCharacter: false,
          title: '无权操作',
          subtitle: '请确认账号权限',
        ),
      );
    }
    final groups = widget.kind == 'dispatch'
        ? [
            ('任务内容', ['任务名称', '所属分组', '任务内容']),
            ('工作安排', ['截止时间', '紧急程度', '进度备注']),
            ('成员与附件', ['主负责人', '协作人', '附件']),
          ]
        : widget.kind == 'feedback'
        ? [
            ('成果与交付', ['成果说明']),
            ('阻碍与材料', ['遇到的阻碍', '附件']),
          ]
        : [(auth ? '账号信息' : '填写内容', spec.fields)];
    return PageFrame(
      title: document ? (log ? '写日志' : '修订日志') : spec.title,
      actions: document
          ? [
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: Text('草稿', style: TextStyle(color: CuteTokens.muted)),
                ),
              ),
            ]
          : null,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(child: failure()),
              ),
            ),
          BottomActions(
            primary: submitButton(),
            secondary: document
                ? OutlinedButton(
                    onPressed:
                        busy || loadingExisting || draftRestoring || submitted
                        ? null
                        : () => saveDraft(notify: true),
                    child: const Text('保存草稿'),
                  )
                : null,
            note: widget.kind == 'reject' ? '驳回必须填写原因；冲突后请重新读取' : null,
          ),
        ],
      ),
      child: PageBody(
        children: [
          if (auth) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.kind == 'login'
                            ? '把工作理清楚，\n从今天开始。'
                            : '和团队一起，\n把事情做好。',
                        style: const TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '阳光纸张 · 你的协作工作台',
                        style: TextStyle(color: CuteTokens.muted),
                      ),
                    ],
                  ),
                ),
                const TuantuanMascot('welcome', size: 96),
              ],
            ),
            const SizedBox(height: 24),
          ],
          if (widget.kind == 'register')
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                '注册仅创建待确认员工。选择申请部门，管理员确认后可访问公司内容。短信验证尚未接入。',
                style: TextStyle(height: 1.6, color: CuteTokens.muted),
              ),
            ),
          if (widget.kind == 'password') ...[
            PaperSurface(
              child: Text(
                user.mustChangePassword
                    ? '首次登录需要设置新密码，完成后请重新登录。'
                    : '修改密码会撤销所有旧会话，完成后请重新登录。',
              ),
            ),
            const SizedBox(height: 20),
            if (user.mustChangePassword)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await logoutCurrentSession(ref);
                          if (!context.mounted) return;
                          context.go('/auth/login');
                        } catch (failure) {
                          if (mounted) setState(() => error = '$failure');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('退出登录'),
              ),
          ],
          if (document) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${businessDate.year}年${businessDate.month}月${businessDate.day}日 · 周${['一', '二', '三', '四', '五', '六', '日'][businessDate.weekday - 1]}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        savedAt == null
                            ? '尚未保存 · 草稿仅本人可见'
                            : saved
                            ? '上次本机保存 ${savedAt!.hour.toString().padLeft(2, '0')}:${savedAt!.minute.toString().padLeft(2, '0')}'
                            : '保存中…',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CuteTokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const TuantuanMascot('welcome', size: 56),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (widget.kind == 'note')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('私人备注仅本人可见，不进入下属面板或 AI。'),
            ),
          if (!AppConfig.mock && widget.kind == 'return')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('退回补充服务尚未接入；可以阅读成果，当前任务不会改变。'),
            ),
          if (widget.kind == 'profile-edit')
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('姓名、部门与角色为身份信息；在这里编辑个人介绍。'),
            ),
          if ([
            'publish',
            'log-revise',
            'transfer',
            'reschedule',
            'role',
            'membership',
            'policy',
            'reporting',
          ].contains(widget.kind))
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '提交候选修改后等待独立审核，原版本继续生效。',
                style: TextStyle(color: CuteTokens.muted),
              ),
            ),
          if (loadingExisting) const LoadingSkeleton(),
          if (original != null &&
              [
                'acceptance',
                'return',
                'transfer',
                'reschedule',
                'withdraw',
                'publish',
                'log-revise',
                'comment',
              ].contains(widget.kind))
            recordContext(),
          if (widget.kind == 'policy') ...[
            const SectionHeader('策略范围'),
            const PaperSurface(
              child: Text(
                '任务关键修改 · 提交候选配置后等待独立审核。当前生效策略与完整组织审核链需要服务端返回，不用下方预览替代。',
              ),
            ),
            const SizedBox(height: 16),
          ],
          IgnorePointer(
            ignoring: loadingExisting,
            child: Form(
              key: form,
              child: document
                  ? PaperSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (index, label) in spec.fields.indexed) ...[
                            if (label != '关联任务')
                              Text(
                                '$label${label == '工时'
                                    ? '（选填）'
                                    : requiredField(label)
                                    ? ' *'
                                    : ''}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            field(label),
                            if (index < spec.fields.length - 1)
                              const Divider(height: 28),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final group in groups) ...[
                          if (!auth) SectionHeader(group.$1),
                          if (auth) ...[
                            for (final label in group.$2)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: field(label),
                              ),
                          ] else
                            PaperSurface(
                              child: Column(
                                children: [
                                  for (final label in group.$2)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: field(label),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ),
          if (widget.kind == 'dispatch')
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '附件需上传完成后随任务提交；上传失败可重试或移除。',
                style: TextStyle(fontSize: 12, color: CuteTokens.muted),
              ),
            ),
          if (widget.kind == 'policy') ...[
            const SectionHeader('候选路由预览'),
            PaperSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1 · 申请人提交候选修改'),
                  const SizedBox(height: 12),
                  const Text('2 · 按服务端组织范围解析独立复核节点'),
                  const SizedBox(height: 12),
                  Text(
                    '3 · 公司复核人：${controllers['指定公司复核人']!.text.isEmpty ? '尚未指定' : controllers['指定公司复核人']!.text}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '申请人不能自审；节点缺失时等待配置，不自动通过。此处为候选配置示意，实际人选、顺序与生效结果以服务端为准。',
                  ),
                ],
              ),
            ),
          ],
          if (widget.kind == 'login')
            TextButton(
              onPressed: () => context.push('/auth/register'),
              child: const Text('注册员工账号'),
            ),
          const DemoLabel(),
        ],
      ),
    );
  }
}

class PersonPicker extends ConsumerStatefulWidget {
  const PersonPicker({super.key, this.dispatch = false});
  final bool dispatch;
  @override
  ConsumerState<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends ConsumerState<PersonPicker> {
  final items = <Record>[];
  final scroll = ScrollController();
  Timer? debounce;
  String search = '';
  String? cursor;
  bool loading = true, more = false, exhausted = false;
  Object? error;
  int generation = 0;
  late final String account = ref.read(sessionProvider).id;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    final ticket = reset ? ++generation : generation;
    if (more && !reset) return;
    final repository = ref.read(repositoryProvider);
    final querySearch = search;
    setState(() {
      error = null;
      if (reset) {
        items.clear();
        cursor = null;
        loading = true;
        exhausted = false;
      } else {
        more = true;
      }
    });
    try {
      final page = await repository.list(
        widget.dispatch ? 'organization/dispatch-people' : 'organization',
        Query(search: querySearch, cursor: reset ? null : cursor),
      );
      if (!mounted ||
          ticket != generation ||
          account != ref.read(sessionProvider).id) {
        return;
      }
      setState(() {
        final seen = items.map((p) => p.id).toSet();
        final rawLength = items.length + page.items.length;
        for (final p in page.items) {
          if (seen.add(p.id) &&
              (!widget.dispatch || p.fields['status'] == 'ACTIVE')) {
            items.add(p);
          }
        }
        exhausted =
            page.items.isEmpty ||
            rawLength >= page.total ||
            page.nextCursor == null ||
            page.nextCursor == cursor;
        cursor = page.nextCursor;
        loading = false;
        more = false;
      });
    } catch (e) {
      if (mounted &&
          ticket == generation &&
          account == ref.read(sessionProvider).id) {
        setState(() {
          error = e;
          loading = false;
          more = false;
          if (e is ApiFailure &&
              [
                FailureKind.forbidden,
                FailureKind.unauthorized,
              ].contains(e.kind)) {
            items.clear();
            exhausted = true;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session.id != account || !session.canReadBusiness) {
      return const SafeArea(
        child: EmptyIllustration(showCharacter: false, title: '账号状态已变化，请重新选择'),
      );
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Text(
                widget.dispatch ? '选择可派发的在职人员' : '选择授权成员',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: '搜索姓名或部门',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) {
                  search = v;
                  debounce?.cancel();
                  generation++;
                  setState(() {
                    items.clear();
                    loading = true;
                  });
                  debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => load(reset: true),
                  );
                },
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    if (loading) const LoadingSkeleton(),
                    if (error != null)
                      RecordFailure(
                        error!,
                        retry: () => load(reset: items.isEmpty),
                      ),
                    if (!loading && error == null && items.isEmpty)
                      const EmptyIllustration(
                        title: '暂无匹配成员',
                        subtitle: '可以更换姓名或部门',
                      ),
                    for (final p in items)
                      ListTile(
                        title: Text(p.title),
                        subtitle: Text(
                          '${p.fields['departmentName'] ?? p.subtitle}',
                        ),
                        onTap: () => Navigator.pop(context, p),
                      ),
                    if (!loading && !exhausted)
                      TextButton(
                        onPressed: more ? null : () => load(),
                        child: Text(more ? '正在读取…' : '加载更多成员'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
