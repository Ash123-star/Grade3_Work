import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../core/config.dart';
import '../data/models.dart';
import '../shared/widgets.dart';
import 'catalog.dart';

class FormPage extends ConsumerStatefulWidget {
  const FormPage(
    this.kind, {
    super.key,
    this.id,
    this.source,
    this.version = 1,
  });
  final String kind;
  final String? id, source;
  final int version;
  @override
  ConsumerState<FormPage> createState() => _FormPageState();
}

class _FormPageState extends ConsumerState<FormPage> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  late final ScreenSpec spec;
  final String idem = DateTime.now().microsecondsSinceEpoch.toString();
  Timer? timer;
  bool busy = false, saved = false;
  String? error;
  String? selectedOwner;
  DateTime? deadline;
  int? loadedVersion;
  bool get log => widget.kind == 'log-edit';
  String get draftKey =>
      'draft:${ref.read(sessionProvider).id}:${ref.read(logDateProvider).toIso8601String().split('T').first}';
  @override
  void initState() {
    super.initState();
    spec = screens[widget.kind]!;
    for (final field in spec.fields) {
      controllers[field] = TextEditingController();
    }
    if (log) restore();
    if (widget.id != null ||
        widget.source != null ||
        widget.kind == 'profile-edit') {
      loadExisting();
    }
  }

  Future<void> loadExisting() async {
    try {
      final resource = widget.source != null
          ? 'ai-maps'
          : widget.kind == 'note'
          ? 'private-notes'
          : spec.resource;
      final item = await ref
          .read(repositoryProvider)
          .detail(
            resource,
            widget.source ?? widget.id ?? ref.read(sessionProvider).id,
          );
      if (!mounted) return;
      loadedVersion = item.version;
      for (final entry in controllers.entries) {
        entry.value.text = '${item.fields[entry.key] ?? ''}';
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
      setState(() {});
    } catch (e) {
      if (mounted && widget.kind != 'note') setState(() => error = '$e');
    }
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    for (final entry in controllers.entries) {
      entry.value.text = prefs.getString('$draftKey:${entry.key}') ?? '';
    }
    setState(() => saved = true);
  }

  void autoSave() {
    if (!log) return;
    timer?.cancel();
    setState(() => saved = false);
    final key = draftKey;
    timer = Timer(const Duration(milliseconds: 600), () async {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in controllers.entries) {
        await prefs.setString('$key:${entry.key}', entry.value.text);
      }
      if (mounted) setState(() => saved = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
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
    if (field.contains('密码') && (value ?? '').length < 8) return '密码至少8位';
    if (field == '确认密码' && value != controllers['新密码']?.text) return '两次密码不一致';
    if (field == '工时' &&
        (value ?? '').isNotEmpty &&
        (double.tryParse(value!) == null ||
            double.parse(value) < 0 ||
            double.parse(value) > 24)) {
      return '工时应在0到24之间';
    }
    return null;
  }

  Future<void> selectPerson(String field) async {
    final result = await showModalBottomSheet<Record>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PersonPicker(),
    );
    if (result != null && mounted) {
      setState(() {
        controllers[field]!.text = result.title;
        if (field == '主负责人') selectedOwner = result.id;
      });
    }
  }

  Widget field(String label) {
    final controller = controllers[label]!;
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
      return OutlinedButton.icon(
        onPressed: () async {
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: label == '附件',
          );
          if (result != null && mounted) {
            setState(
              () => controller.text = result.files.map((e) => e.name).join('、'),
            );
          }
        },
        icon: const Icon(Icons.attach_file),
        label: Text(
          controller.text.isEmpty ? '选择$label（仅本地）' : controller.text,
        ),
      );
    }
    if (label == '关联任务') {
      return ref
          .watch(recordsProvider('tasks'))
          .when(
            data: (page) => DropdownButtonFormField<String>(
              key: ValueKey('task:${controller.text}'),
              initialValue: page.items.any((r) => r.id == controller.text)
                  ? controller.text
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '关联任务'),
              items: page.items
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.id,
                      child: Text(r.title, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                controller.text = value ?? '';
                autoSave();
              },
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, s) => Text('$e'),
          );
    }
    final person = ['主负责人', '协作人', '员工', '直属上级', '指定公司复核人'].contains(label);
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: '$label${requiredField(label) ? ' *' : ''}',
        suffixIcon: person
            ? const Icon(Icons.person_search_outlined)
            : label == '截止时间'
            ? const Icon(Icons.calendar_today)
            : null,
      ),
      obscureText: label.contains('密码'),
      readOnly: person || label == '截止时间',
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
          ? 4
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
    if (!form.currentState!.validate()) return;
    if (['withdraw', 'disable'].contains(widget.kind)) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(spec.title),
          content: const Text('确认执行此操作？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
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
      if (widget.id != null) 'id': widget.id,
      if (widget.kind == 'profile-edit') 'id': ref.read(sessionProvider).id,
      if (widget.id == null ||
          controllers.containsKey('任务名称') ||
          controllers.containsKey('标题'))
        'title':
            controllers['任务名称']?.text ??
            controllers['标题']?.text ??
            controllers['问题描述']?.text ??
            (log
                ? '${ref.read(logDateProvider).toIso8601String().split('T').first} 工作日报'
                : spec.title),
      if (selectedOwner != null) 'ownerId': selectedOwner,
      if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      if (log)
        'businessDate': ref
            .read(selectedDateProvider)
            .toIso8601String()
            .split('T')
            .first,
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
              version: widget.kind == 'note' ? loadedVersion : widget.id == null ? null : (loadedVersion ?? widget.version),
              idempotencyKey: idem,
            ),
          );
      refreshBusiness(ref);
      ref.invalidate(recordsProvider(spec.resource));
      ref.invalidate(datedRecordsProvider(spec.resource));
      if (widget.id != null) {
        ref.invalidate(itemProvider((spec.resource, widget.id!)));
      }
      if (!mounted) return;
      if (log) {
        final prefs = await SharedPreferences.getInstance();
        for (final field in controllers.keys) {
          await prefs.remove('$draftKey:$field');
        }
      }
      if (!mounted) return;
      if (widget.kind == 'profile-edit') {
        final old = ref.read(sessionProvider);
        ref.read(sessionProvider.notifier).state = Session(
          id: old.id,
          name: controllers['姓名']!.text.isEmpty
              ? old.name
              : controllers['姓名']!.text,
          role: old.role,
          dispatch: old.dispatch,
          active: old.active,
          token: old.token,
        );
      }
      if (widget.kind == 'login') {
        if (AppConfig.mock) {
          ref.read(sessionProvider.notifier).state = const Session();
          context.go('/dashboard');
        } else {
          final token = result.fields['accessToken'] as String?;
          if (token == null) throw StateError('登录响应缺少访问令牌');
          ref.read(sessionProvider.notifier).state = Session(
            id: result.ownerId,
            role: UserRole.employee,
            dispatch: false,
            token: token,
          );
          context.go('/dashboard');
        }
      } else if (widget.kind == 'register') {
        context.go('/pending');
      } else {
        notice(context, AppConfig.mock ? '已保存到演示数据' : '已提交');
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final denied =
        (spec.manager && !user.manager) ||
        (spec.admin && !user.administrator) ||
        (['dispatch', 'ai-draft'].contains(widget.kind) && !user.dispatch);
    return PageFrame(
      title: spec.title,
      child: denied
          ? const EmptyIllustration(title: '无权操作', subtitle: '请联系管理员确认账号权限')
          : PageBody(
              children: [
                const DemoLabel(),
                if (['login', 'register'].contains(widget.kind)) ...[
                  const CuteArt('1F680', size: 80),
                  const SizedBox(height: 20),
                ],
                if (widget.kind == 'register')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('注册为员工，部门归属确认后可访问公司内容。短信验证暂未接入。'),
                  ),
                if (widget.kind == 'note')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('仅本人可见，不纳入管理者穿透或 AI 检索。'),
                  ),
                if (widget.kind == 'publish' || widget.kind == 'log-revise')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('提交后进入审核，原版本继续生效。'),
                  ),
                if (log) Padding(padding:const EdgeInsets.only(bottom:12),child:Text('日志日期：${ref.watch(logDateProvider).year}年${ref.watch(logDateProvider).month}月${ref.watch(logDateProvider).day}日')),
                if (log)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(saved ? '草稿已保存到此设备' : '正在保存草稿…'),
                  ),
                Form(
                  key: form,
                  child: Column(
                    children: spec.fields
                        .map(
                          (label) => Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: field(label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: busy ? null : submit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    busy
                        ? '正在提交'
                        : widget.kind == 'login'
                        ? '登录'
                        : '确认提交',
                  ),
                ),
                if (widget.kind == 'login')
                  TextButton(
                    onPressed: () => openForm(context, 'register'),
                    child: const Text('注册员工账号'),
                  ),
              ],
            ),
    );
  }
}

class PersonPicker extends ConsumerStatefulWidget {
  const PersonPicker({super.key});
  @override
  ConsumerState<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends ConsumerState<PersonPicker> {
  String search = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '搜索姓名或部门',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ref
                    .watch(recordsProvider('organization'))
                    .when(
                      loading: () => const LoadingSkeleton(),
                      error: (e, s) => ErrorPanel(
                        '$e',
                        retry: () =>
                            ref.invalidate(recordsProvider('organization')),
                      ),
                      data: (page) => Column(
                        children: page.items
                            .where(
                              (r) => '${r.title}${r.subtitle}'.contains(search),
                            )
                            .map(
                              (r) => ListTile(
                                title: Text(r.title),
                                subtitle: Text(r.subtitle),
                                onTap: () => Navigator.pop(context, r),
                              ),
                            )
                            .toList(),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
