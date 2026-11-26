import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

import 'crm_components.dart';
import 'crm_demo_store.dart';

class CrmSelect extends StatelessWidget {
  const CrmSelect({
    super.key,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => PremiumDropdownField<String>(
    initialValue: value,
    key: ValueKey(value),
    isExpanded: true,
    sheetTitle: '选择业务负责人',
    decoration: _inputDecoration(),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v, style: crmStyle(16)),
          ),
        )
        .toList(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

InputDecoration _inputDecoration({String? placeholder}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: CrmTone.outline),
  );
  return InputDecoration(
    filled: true,
    fillColor: CrmTone.canvas,
    isDense: true,
    counterText: '',
    hintText: placeholder,
    hintStyle: crmStyle(16, color: CrmTone.muted),
    constraints: const BoxConstraints(minHeight: 48),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: CrmTone.accent, width: 2),
    ),
  );
}

Widget _label(
  String label,
  Widget field, {
  bool required = false,
  String? error,
  String? hint,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 13),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Flexible(child: crmText(label, 14, bold: true)),
            if (required)
              crmText(' *', 14, color: CrmTone.red)
            else ...[
              const Spacer(),
              crmText('可选', 11, color: CrmTone.muted),
            ],
          ],
        ),
      ),
      Semantics(label: label, child: field),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: crmText(hint, 11, color: CrmTone.muted, height: 1.6),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            liveRegion: true,
            child: crmText(error, 12, color: CrmTone.red, height: 1.6),
          ),
        ),
    ],
  ),
);

Widget _input(
  TextEditingController controller, {
  FocusNode? focus,
  bool phone = false,
  int length = 100,
  int lines = 1,
  String? placeholder,
}) => TextField(
  controller: controller,
  focusNode: focus,
  maxLines: lines,
  minLines: lines,
  inputFormatters: [LengthLimitingTextInputFormatter(length)],
  style: crmStyle(16),
  keyboardType: phone
      ? TextInputType.phone
      : lines > 1
      ? TextInputType.multiline
      : TextInputType.text,
  decoration: _inputDecoration(placeholder: placeholder),
);

Future<bool> _confirmLeave(
  BuildContext context,
  String title,
  String message,
) => crmSheet<bool>(
  context,
  (c) => CrmSheetBody(
    title,
    crmSmall(message),
    actions: crmActions(
      CrmButton('放弃修改', () => Navigator.pop(c, true)),
      CrmButton('继续编辑', () => Navigator.pop(c, false), primary: true),
    ),
  ),
).then((value) => value ?? false);

class CrmEditor extends StatefulWidget {
  const CrmEditor({super.key, required this.store, this.existing});
  final CrmDemoStore store;
  final CrmCustomer? existing;
  @override
  State<CrmEditor> createState() => _CrmEditorState();
}

class _CrmEditorState extends State<CrmEditor> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      contact = TextEditingController(),
      note = TextEditingController();
  final nameFocus = FocusNode(),
      phoneFocus = FocusNode(),
      contactFocus = FocusNode();
  final error = <String, String>{};
  late String type, owner;
  late int? version;
  late Object original;
  bool conflict = false, leaving = false, saving = false;
  String? message;
  CrmCustomer? get existing => widget.existing;
  CrmDemoStore get store => widget.store;
  bool get enterprise => type == '企业';
  Object get current =>
      (type, name.text, owner, phone.text, contact.text, note.text);
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    type = existing?.type ?? '个人';
    name.text = existing?.name ?? '';
    owner = existing?.owner ?? '陈晨';
    note.text = existing?.note ?? '';
    phone.clear();
    contact.clear();
    version = existing?.version;
    original = current;
    message = null;
    conflict = false;
    error.clear();
  }

  @override
  void dispose() {
    for (final c in [name, phone, contact, note]) {
      c.dispose();
    }
    for (final f in [nameFocus, phoneFocus, contactFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> cancel() async {
    if (leaving) return;
    leaving = true;
    final allowed =
        original == current ||
        await _confirmLeave(context, '有尚未保存的内容', '离开后，这次填写的内容不会保存。');
    leaving = false;
    if (mounted && allowed) Navigator.pop(context);
  }

  Future<void> reload() async {
    if (original != current &&
        !await _confirmLeave(context, '有尚未保存的内容', '离开后，这次填写的内容不会保存。')) {
      return;
    }
    if (mounted) setState(load);
  }

  bool validate() {
    setState(() {
      error.clear();
      message = null;
      final text = name.text.trim();
      if (text.isEmpty) {
        error['name'] = enterprise ? '请输入企业名称' : '请输入客户姓名';
      } else if (RegExp(r'[<>\x00-\x1f]').hasMatch(text) ||
          text.runes.length > 100) {
        error['name'] = '名称请使用 1–100 个文字字符，不包含尖括号或控制字符';
      }
      if (store.contactAllowed) {
        if (!CrmDemoStore.validPhone(phone.text)) {
          error['phone'] = '请填写有效电话，可含 +、区号、空格或连字符';
        }
        if (enterprise &&
            existing == null &&
            phone.text.trim().isNotEmpty &&
            contact.text.trim().isEmpty) {
          error['contact'] = '填写联系人电话时，请同时填写联系人姓名';
        }
      }
    });
    if (error.isNotEmpty) {
      (error.containsKey('name')
              ? nameFocus
              : error.containsKey('contact')
              ? contactFocus
              : phoneFocus)
          .requestFocus();
      return false;
    }
    return true;
  }

  Future<bool> reviewDuplicates(List<CrmCustomer> duplicates) async {
    CrmCustomer? selected;
    return await crmSheet<bool>(
          context,
          (sheet) => StatefulBuilder(
            builder: (ctx, update) {
              final c = selected;
              return CrmSheetBody(
                c == null ? '先核对，避免重复建档' : '已有客户 · 核对资料',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c == null) ...[
                      crmSmall('获准查看的客户中有相同名称或联系方式。请先核对；系统不会自动合并。'),
                      for (final candidate in duplicates)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: CrmSurface(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                crmText(candidate.name, 15, bold: true),
                                crmSmall(
                                  '${candidate.type}客户 · ${candidate.owner} ›',
                                ),
                              ],
                            ),
                            color: CrmTone.canvas,
                            radius: 14,
                            padding: const EdgeInsets.all(12),
                            onTap: () => update(() => selected = candidate),
                          ),
                        ),
                    ] else ...[
                      crmFields([
                        ('客户名称', c.name),
                        ('客户类型', c.type),
                        ('负责人', c.owner),
                        (
                          '联系方式',
                          store.contactAllowed
                              ? (c.phone.isEmpty ? '未填写' : c.phone)
                              : '未授权',
                        ),
                      ]),
                      crmGap,
                      crmSmall('这里只核对已有档案；本次填写仍保留在表单中。'),
                    ],
                  ],
                ),
                actions: c == null
                    ? crmActions(
                        CrmButton('返回修改', () => Navigator.pop(sheet, false)),
                        CrmButton(
                          existing == null ? '确认不同，仍新建' : '确认无误，保存',
                          () => Navigator.pop(sheet, true),
                          primary: true,
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: CrmButton(
                          '返回核对选择',
                          () => update(() => selected = null),
                          primary: true,
                        ),
                      ),
              );
            },
          ),
        ) ??
        false;
  }

  Future<void> save() async {
    if (saving || !store.writable || conflict || !validate()) return;
    saving = true;
    try {
      final duplicates = store.duplicates(name.text, phone.text, existing);
      if (duplicates.isNotEmpty) {
        FocusScope.of(context).unfocus();
        if (!await reviewDuplicates(duplicates)) return;
      }
      if (!mounted) return;
      final d = shanghaiToday();
      final since =
          '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
      final (status, customer) = store.save(
        customer: existing,
        version: version,
        type: type,
        name: name.text,
        owner: owner,
        phone: phone.text,
        note: note.text,
        contactName: contact.text,
        since: since,
      );
      if (status == CrmSaveResult.success) {
        Navigator.pop(context, customer);
        return;
      }
      setState(() {
        conflict = status == CrmSaveResult.conflict;
        message = switch (status) {
          CrmSaveResult.conflict => '资料已有更新，本次尚未保存。请重新载入后核对并编辑。',
          CrmSaveResult.denied => '当前仅可查看，暂时不能保存修改。',
          _ => '保存未成功，填写内容已保留，请重试。',
        };
      });
    } finally {
      saving = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<CrmCustomer>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) cancel();
    },
    child: CrmFrame(
      title: existing == null ? '新增客户' : '编辑客户',
      subtitle: '先记基本资料，其余可慢慢补齐',
      back: cancel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (existing == null)
            CrmSegments(
              const ['个人客户', '企业客户'],
              enterprise ? 1 : 0,
              (i) => setState(() {
                type = i == 0 ? '个人' : '企业';
                error.clear();
              }),
            )
          else
            crmSmall('$type客户 · ${existing!.source} · 类型不可在此修改'),
          crmGap,
          if (message != null) ...[
            crmHint(message!, error: true),
            if (conflict) CrmButton('重新载入资料', reload, plain: true, height: 48),
            crmGap,
          ],
          if (!store.writable) ...[
            crmHint('当前仅可查看，暂时不能保存修改。', error: true),
            crmGap,
          ],
          CrmSurface(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(
                  enterprise ? '企业名称' : '客户姓名',
                  _input(name, focus: nameFocus),
                  required: true,
                  error: error['name'],
                ),
                if (store.contactAllowed && enterprise && existing == null)
                  _label(
                    '主要联系人',
                    _input(
                      contact,
                      focus: contactFocus,
                      placeholder: '主要对接人，可后补',
                    ),
                    error: error['contact'],
                  ),
                if (store.contactAllowed && (!enterprise || existing == null))
                  _label(
                    enterprise ? '联系人电话' : '联系电话',
                    _input(
                      phone,
                      phone: true,
                      focus: phoneFocus,
                      length: 30,
                      placeholder: '可后补，支持区号或国际号码',
                    ),
                    error: error['phone'],
                    hint: existing == null
                        ? null
                        : existing!.phone.isEmpty
                        ? '留空保留当前联系方式。'
                        : '当前 ${existing!.phone}；留空保留原号码。',
                  ),
                _label(
                  '业务负责人',
                  CrmSelect(
                    value: owner,
                    values: CrmDemoStore.owners,
                    onChanged: (v) => setState(() => owner = v),
                  ),
                  required: true,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 1),
          ),
          if (!store.contactAllowed) ...[
            crmGap,
            crmSmall('联系字段未授权，本次编辑不会改动这些字段。'),
          ],
          crmGap,
          CrmDisclosure(
            '补充信息 · 备注',
            _label('客户备注', _input(note, length: 500, lines: 3)),
          ),
          crmGap,
          crmSmall('会员资格、权益和订单由对应业务记录维护。'),
        ],
      ),
      dock: crmActions(
        CrmButton('取消', cancel),
        CrmButton(
          existing == null ? '保存客户' : '保存修改',
          store.writable && !conflict ? save : null,
          primary: true,
        ),
        primaryFlex: 2,
      ),
    ),
  );
}

class CrmContactEditor extends StatefulWidget {
  const CrmContactEditor({
    super.key,
    required this.store,
    required this.customer,
    this.index,
  });
  final CrmDemoStore store;
  final CrmCustomer customer;
  final int? index;
  @override
  State<CrmContactEditor> createState() => _CrmContactEditorState();
}

class _CrmContactEditorState extends State<CrmContactEditor> {
  final name = TextEditingController(),
      role = TextEditingController(),
      phone = TextEditingController();
  final nameFocus = FocusNode(), phoneFocus = FocusNode();
  late int version;
  late Object original;
  String? message, nameError, phoneError;
  bool conflict = false, leaving = false;
  CrmContact? get old =>
      widget.index == null ? null : widget.customer.contacts[widget.index!];
  Object get current => (name.text, role.text, phone.text);
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    name.text = old?.name ?? '';
    role.text = old?.role ?? '';
    phone.clear();
    original = current;
    version = widget.customer.version;
    message = null;
    conflict = false;
    nameError = null;
    phoneError = null;
  }

  @override
  void dispose() {
    name.dispose();
    role.dispose();
    phone.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (leaving) return;
    leaving = true;
    final allowed =
        original == current ||
        await _confirmLeave(context, '放弃联系人修改？', '联系人还没有保存，是否继续填写？');
    leaving = false;
    if (allowed && mounted) Navigator.pop(context);
  }

  Future<void> reload() async {
    if (original != current &&
        !await _confirmLeave(context, '放弃联系人修改？', '联系人还没有保存，是否继续填写？')) {
      return;
    }
    if (mounted) setState(load);
  }

  void save() {
    setState(() {
      nameError = name.text.trim().isEmpty ? '请输入联系人姓名' : null;
      phoneError = CrmDemoStore.validPhone(phone.text) ? null : '请填写有效电话';
    });
    if (nameError != null || phoneError != null) {
      (nameError != null ? nameFocus : phoneFocus).requestFocus();
      return;
    }
    final status = widget.store.saveContact(
      widget.customer,
      version,
      widget.index,
      CrmContact(name.text.trim(), role.text.trim(), phone.text.trim()),
    );
    if (status == CrmSaveResult.success) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      conflict = status == CrmSaveResult.conflict;
      message = switch (status) {
        CrmSaveResult.conflict => '联系人资料已有更新，请重新载入并编辑。',
        CrmSaveResult.denied => '当前仅可查看，暂时不能保存修改。',
        _ => '保存失败，内容已保留，请重试。',
      };
    });
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: CrmSheetBody(
      widget.index == null ? '添加联系人' : '编辑联系人',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          crmText(widget.customer.name, 12, color: CrmTone.accent),
          crmGap,
          if (message != null) ...[
            crmHint(message!, error: true),
            if (conflict) CrmButton('重新载入联系人', reload, plain: true, height: 48),
            crmGap,
          ],
          _label(
            '联系人姓名',
            _input(name, focus: nameFocus, length: 60),
            required: true,
            error: nameError,
          ),
          _label('对接职责', _input(role, length: 60)),
          _label(
            '联系电话',
            _input(phone, phone: true, length: 30, focus: phoneFocus),
            error: phoneError,
            hint: old?.phone.isNotEmpty == true
                ? '当前 ${old!.phone}；留空保留。'
                : '可后补，支持区号或国际号码',
          ),
        ],
      ),
      close: close,
      actions: crmActions(
        CrmButton('取消', close),
        CrmButton('保存联系人', conflict ? null : save, primary: true),
      ),
    ),
  );
}
