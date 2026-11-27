part of 'crm_live_workspace.dart';

class _ValueField {
  const _ValueField(
    this.key,
    this.label,
    this.limit, {
    this.required = false,
    this.date = false,
    this.multiline = false,
    this.choices = const {},
    this.maximum,
  });
  final String key, label;
  final int limit;
  final bool required, date, multiline;
  final Map<String, String> choices;
  final int? maximum;
}

const _profileFields = [
  _ValueField('name', '客户名称', 200, required: true),
  _ValueField('phone', '联系电话', 40),
  _ValueField('email', '联系邮箱', 200),
  _ValueField('externalId', '商城外部 ID', 200),
  _ValueField('note', '备注', 2000, multiline: true),
];
const _contactFields = [
  _ValueField('name', '联系人姓名', 100, required: true),
  _ValueField('role', '职务', 100),
  _ValueField('phone', '联系电话', 40),
  _ValueField('email', '联系邮箱', 200),
];

String? _checkValue(_ValueField field, String text) {
  final value = text.trim();
  if (value.isEmpty) return field.required ? '请填写${field.label}' : null;
  if (field.key == 'email' &&
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
    return '请填写有效邮箱';
  }
  if (field.date) {
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.year < 1900 ||
        date.year > 2100 ||
        date.toIso8601String().split('T').first != value) {
      return '请输入有效日期（YYYY-MM-DD）';
    }
  }
  if (field.maximum case final max?) {
    final number = int.tryParse(value);
    if (number == null || number < 1 || number > max) return '请输入 1 至 $max 的整数';
  }
  return null;
}

Widget _field(
  _ValueField field,
  TextEditingController controller,
  bool enabled,
) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextFormField(
    controller: controller,
    enabled: enabled,
    maxLength: field.limit,
    minLines: field.multiline ? 3 : 1,
    maxLines: field.multiline ? 5 : 1,
    keyboardType: field.date
        ? TextInputType.datetime
        : field.maximum != null
        ? TextInputType.number
        : field.key == 'email'
        ? TextInputType.emailAddress
        : field.key == 'phone'
        ? TextInputType.phone
        : field.multiline
        ? TextInputType.multiline
        : TextInputType.text,
    validator: (value) => _checkValue(field, value ?? ''),
    decoration: InputDecoration(
      labelText: field.label,
      hintText: field.date ? 'YYYY-MM-DD' : null,
      counterText: '',
      border: const OutlineInputBorder(),
    ),
  ),
);

Future<bool> _confirmClose(
  BuildContext context,
  String title,
  String message,
  String confirm,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

class _ProfileForm extends StatefulWidget {
  const _ProfileForm(this.scope, {this.profile});
  final _Scope scope;
  final CrmRow? profile;
  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final form = GlobalKey<FormState>();
  final text = {
    for (final field in _profileFields) field.key: TextEditingController(),
  };
  final keys = <String, String>{};
  String? confirmedDuplicate;
  bool busy = false, conflict = false, passThrough = false;
  String? error, ownerId, ownerName;
  late String kind, initial;
  late List<CrmRow> contacts;
  late CrmRow? source;

  @override
  void initState() {
    super.initState();
    restore(widget.profile);
  }

  void restore(CrmRow? row) {
    source = row;
    kind = row?['kind'] == 'ENTERPRISE' ? 'ENTERPRISE' : 'INDIVIDUAL';
    ownerId = row?['ownerId'] as String?;
    ownerName = row?['ownerName'] as String?;
    contacts = [...crmRows(row?['contacts'])];
    for (final entry in text.entries) {
      entry.value.text = row?[entry.key]?.toString() ?? '';
    }
    initial = jsonEncode(payload());
  }

  @override
  void dispose() {
    for (final controller in text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  CrmRow payload() => {
    'kind': kind,
    for (final entry in text.entries) entry.key: entry.value.text.trim(),
    'ownerId': ownerId,
    'contacts': contacts,
    if (source != null) ...{
      'status': source!['status'],
      'version': source!['version'],
    },
  };

  Future<void> close() async {
    if (busy || passThrough) return;
    final dirty = initial != jsonEncode(payload());
    if (dirty &&
        !await _confirmClose(context, '放弃未保存的修改？', '退出后不会保存本次填写的内容。', '放弃修改')) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> pickOwner() async {
    final row = await widget.scope.open<CrmRow>(
      context,
      _EmployeePicker(widget.scope, const {}),
    );
    if (!mounted || row == null) return;
    setState(() {
      ownerId = crmValue(row, 'id');
      ownerName = crmValue(row, 'name');
    });
  }

  Future<void> contact([int? index]) async {
    final current = index == null ? null : contacts[index];
    CrmRow? draft;
    final accepted = await widget.scope.open<bool>(
      context,
      _ValueForm(
        title: index == null ? '新增联系人' : '编辑联系人',
        fields: _contactFields,
        initial: current ?? const {},
        submit: (body, _) async {
          draft = {if (current?['id'] != null) 'id': current!['id'], ...body};
        },
      ),
    );
    if (!mounted || accepted != true || draft == null) return;
    setState(() {
      if (index == null) {
        contacts.add(draft!);
      } else {
        contacts[index] = draft!;
      }
    });
  }

  Future<void> removeContact(int index) async {
    if (await _confirmClose(context, '移除此联系人？', '保存档案后生效。', '移除') && mounted) {
      setState(() => contacts.removeAt(index));
    }
  }

  Future<void> reload() async {
    if (busy || source == null) return;
    if (!await _confirmClose(context, '读取新版档案？', '本次未保存的修改将被丢弃。', '读取新版') ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      final value = await widget.scope.api.customer(crmValue(source!, 'id'));
      if (!mounted) return;
      setState(() {
        restore(value['customer'] as CrmRow);
        error = null;
        conflict = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || conflict || !(form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final body = payload();
    final fingerprint = jsonEncode(body);
    if (confirmedDuplicate == fingerprint) body['confirmDuplicate'] = true;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final created = source == null
          ? await widget.scope.api.createCustomer(
              body,
              keys.putIfAbsent(jsonEncode(body), newCalendarCommandKey),
            )
          : await widget.scope.api.updateCustomer(
              crmValue(source!, 'id'),
              body,
            );
      if (!mounted) return;
      passThrough = true;
      Navigator.of(context).pop(created);
    } on ApiFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'CUSTOMER_POSSIBLE_DUPLICATE' &&
          confirmedDuplicate != fingerprint) {
        final confirmed = await _confirmClose(
          context,
          '可能已有同一客户',
          '本公司已有同名或联系方式相同的档案。可取消并在目录核对，确认是不同客户后再建档。',
          '仍然建档',
        );
        if (confirmed && mounted) {
          confirmedDuplicate = fingerprint;
          setState(() => busy = false);
          await save();
        }
      } else {
        setState(() {
          error = _error(e);
          conflict = e.code == 'VERSION_CONFLICT';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: passThrough,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: CrmFrame(
      title: source == null ? '新增客户' : '编辑客户档案',
      subtitle: '客户手帐',
      back: close,
      dock: SizedBox(
        width: double.infinity,
        child: CrmButton(
          busy ? '处理中…' : '保存档案',
          busy || conflict ? null : save,
          primary: true,
        ),
      ),
      body: Form(
        key: form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[crmHint(error!, error: true), crmGap],
            if (conflict) CrmButton('读取新版', busy ? null : reload),
            CrmSegments(const ['个人客户', '企业客户'], kind == 'INDIVIDUAL' ? 0 : 1, (
              index,
            ) async {
              if (busy || (index == 0) == (kind == 'INDIVIDUAL')) return;
              if (index == 0 &&
                  contacts.isNotEmpty &&
                  !await _confirmClose(
                    context,
                    '改为个人客户？',
                    '保存后将移除企业联系人。',
                    '确认变更',
                  )) {
                return;
              }
              if (!mounted) return;
              setState(() {
                kind = index == 0 ? 'INDIVIDUAL' : 'ENTERPRISE';
                if (index == 0) contacts = [];
              });
            }),
            crmGap,
            for (final field in _profileFields)
              _field(field, text[field.key]!, !busy),
            crmSection('业务负责人'),
            CrmButton(ownerName ?? '选择业务负责人', busy ? null : pickOwner),
            if (ownerId != null)
              CrmButton(
                '清除负责人',
                busy
                    ? null
                    : () => setState(() {
                        ownerId = null;
                        ownerName = null;
                      }),
                plain: true,
              ),
            if (kind == 'ENTERPRISE') ...[
              crmSection(
                '企业联系人',
                action: CrmButton(
                  '新增联系人',
                  busy || contacts.length >= 30 ? null : contact,
                  plain: true,
                ),
              ),
              for (var i = 0; i < contacts.length; i++)
                ListTile(
                  title: crmText(crmValue(contacts[i], 'name'), 15, bold: true),
                  subtitle: crmSmall(crmValue(contacts[i], 'role')),
                  onTap: busy ? null : () => contact(i),
                  trailing: IconButton(
                    tooltip: '移除联系人',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: busy ? null : () => removeContact(i),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ValueForm extends StatefulWidget {
  const _ValueForm({
    required this.title,
    required this.fields,
    required this.submit,
    this.initial = const {},
    this.submitLabel = '保存',
    this.dateRange,
    this.onConflict,
  });
  final String title, submitLabel;
  final List<_ValueField> fields;
  final CrmRow initial;
  final (String, String)? dateRange;
  final Future<void> Function(CrmRow, String) submit;
  final VoidCallback? onConflict;
  @override
  State<_ValueForm> createState() => _ValueFormState();
}

class _ValueFormState extends State<_ValueForm> {
  final form = GlobalKey<FormState>();
  final requests = <String, String>{};
  late final text = {
    for (final field in widget.fields)
      field.key: TextEditingController(
        text: crmValue(widget.initial, field.key),
      ),
  };
  late final initial = jsonEncode(payload());
  bool busy = false, stale = false;
  String? error;

  @override
  void initState() {
    super.initState();
    initial;
  }

  @override
  void dispose() {
    for (final controller in text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  CrmRow payload() => {
    for (final field in widget.fields)
      field.key: field.maximum != null
          ? int.tryParse(text[field.key]!.text.trim())
          : text[field.key]!.text.trim(),
  };

  Future<void> close() async {
    if (busy) return;
    if (initial != jsonEncode(payload()) &&
        !await _confirmClose(context, '放弃未保存的修改？', '退出后不会保存本次填写的内容。', '放弃修改')) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> save() async {
    if (busy || stale || !(form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final body = payload();
    if (widget.dateRange case (final start, final end)) {
      final from = crmValue(body, start), to = crmValue(body, end);
      if (from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0) {
        setState(() => error = '结束日期不能早于开始日期。');
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit(
        body,
        requests.putIfAbsent(jsonEncode(body), newCalendarCommandKey),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = _error(e);
        stale =
            e is ApiFailure &&
            e.code == 'VERSION_CONFLICT' &&
            widget.onConflict != null;
      });
      if (stale) widget.onConflict!();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: CrmFrame(
      title: widget.title,
      subtitle: '客户手帐',
      back: close,
      dock: SizedBox(
        width: double.infinity,
        child: CrmButton(
          busy ? '处理中…' : widget.submitLabel,
          busy || stale ? null : save,
          primary: true,
        ),
      ),
      body: Form(
        key: form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[crmHint(error!, error: true), crmGap],
            for (final field in widget.fields)
              if (field.choices.isEmpty)
                _field(field, text[field.key]!, !busy)
              else ...[
                crmSection(field.label),
                CrmSegments(
                  field.choices.values.toList(),
                  field.choices.keys.toList().indexOf(text[field.key]!.text),
                  (index) {
                    if (!busy) {
                      setState(
                        () => text[field.key]!.text = field.choices.keys
                            .elementAt(index),
                      );
                    }
                  },
                ),
                crmGap,
              ],
          ],
        ),
      ),
    ),
  );
}
