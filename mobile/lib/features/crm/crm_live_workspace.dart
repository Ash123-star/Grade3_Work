import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/local/calendar_command_store.dart';
import 'package:pandora_mobile/shared/premium_pickers.dart';

import 'crm_components.dart';
import 'crm_live_api.dart';

const _kinds = {
  'PERFORMANCE': '赛演',
  'PRIVATE_BANQUET': '私宴',
  'COMPANY_VISIT': '企业参访',
  'SALON': '沙龙',
};
const _actions = {
  'EDIT': '修改资料',
  'END_ACTIVITY': '结束活动',
  'CONFIRM_DELIVERY': '确认交付',
};

class LiveCrmWorkspace extends ConsumerWidget {
  const LiveCrmWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.administrator || !session.canReadBusiness) {
      return const _AccessDenied(directory: true);
    }
    final epoch = ref.watch(sessionEpochProvider);
    return _Directory(
      key: ValueKey(epoch),
      scope: _Scope(ref.watch(liveCrmApiProvider), epoch),
    );
  }
}

class _Scope {
  const _Scope(this.api, this.epoch);
  final LiveCrmApi api;
  final int epoch;

  Future<T?> open<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(
        MaterialPageRoute(
          builder: (context) => Consumer(
            builder: (_, ref, _) => ref.watch(sessionEpochProvider) == epoch
                ? page
                : const _AccessDenied(),
          ),
        ),
      );
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({this.directory = false});
  final bool directory;

  @override
  Widget build(BuildContext context) => CrmFrame(
    title: '客户手帐',
    subtitle: '',
    backLabel: directory ? '返回公司' : '返回',
    back: () => context.canPop() ? context.pop() : context.go('/view'),
    body: crmEmpty('无权访问客户目录', '仅在职管理员可查看。'),
  );
}

String _error(Object? error) => error is ApiFailure
    ? switch (error.code) {
        'DELIVERY_REVIEW_PENDING' => '已有待审申请，请刷新记录。',
        'INVALID_DELIVERY_TRANSITION' => '活动或交付状态已改变，请刷新记录。',
        'INVALID_EMPLOYEE' => '负责人或参与员工已不可用，请重新选择。',
        'CUSTOMER_ARCHIVED' => '客户已归档，不能修改此记录。',
        'NO_CHANGE' => '资料没有变化。',
        _ => error.message,
      }
    : '暂时无法读取数据，请重试。';

Widget _failure(Object? error, VoidCallback retry) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    crmHint(_error(error)),
    if (error is! ApiFailure ||
        ![FailureKind.forbidden, FailureKind.unauthorized].contains(error.kind))
      CrmButton('重试', retry),
  ],
);

Widget _tile(String title, String subtitle, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: CrmSurface(
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [crmText(title, 16, bold: true), crmSmall(subtitle)],
          ),
        ),
        const Icon(Icons.chevron_right, color: CrmTone.muted),
      ],
    ),
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
);

class _Paged extends StatefulWidget {
  const _Paged({
    super.key,
    required this.load,
    required this.row,
    this.empty = '暂无记录',
  });
  final Future<CrmPage> Function(int cursor) load;
  final Widget Function(CrmRow row) row;
  final String empty;

  @override
  State<_Paged> createState() => _PagedState();
}

class _PagedState extends State<_Paged> {
  final cursors = [0];
  late Future<CrmPage> page = widget.load(0);

  void reload() => setState(() {
    page = widget.load(cursors.last);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder(
    key: ObjectKey(page),
    future: page,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _failure(snapshot.error, reload);
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final data = snapshot.requireData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.rows.isEmpty) crmHint(widget.empty),
          ...data.rows.map(widget.row),
          if (cursors.length > 1 || data.next != null)
            Row(
              children: [
                Expanded(
                  child: CrmButton(
                    '上一页',
                    cursors.length == 1
                        ? null
                        : () {
                            cursors.removeLast();
                            reload();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CrmButton(
                    '下一页',
                    data.next == null
                        ? null
                        : () {
                            cursors.add(data.next!);
                            reload();
                          },
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );
}

class _Search extends StatefulWidget {
  const _Search(this.label, this.onChanged);
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    FocusScope.of(context).unfocus();
    widget.onChanged(controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: 100,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => submit(),
    decoration: InputDecoration(
      labelText: widget.label,
      counterText: '',
      suffixIcon: IconButton(
        tooltip: '搜索',
        onPressed: submit,
        icon: const Icon(Icons.search),
      ),
      border: const OutlineInputBorder(),
    ),
  );
}

class _Directory extends StatefulWidget {
  const _Directory({super.key, required this.scope});
  final _Scope scope;

  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> {
  int view = 0, type = 0;
  String search = '';

  @override
  Widget build(BuildContext context) {
    final employee = view == 1;
    final scope = widget.scope;
    return CrmFrame(
      title: '客户手帐',
      subtitle: '线下业务与服务交付',
      backLabel: '返回公司',
      back: () => context.canPop() ? context.pop() : context.go('/view'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSegments(['客户目录', '员工视角'], view, (value) {
            if (view != value) {
              setState(() {
                view = value;
                search = '';
              });
            }
          }),
          crmGap,
          KeyedSubtree(
            key: ValueKey(view),
            child: _Search(
              employee ? '搜索员工' : '搜索客户',
              (s) => setState(() => search = s),
            ),
          ),
          if (!employee) ...[
            crmGap,
            CrmSegments(
              ['全部', '个人', '企业'],
              type,
              (value) => setState(() => type = value),
            ),
          ],
          crmGap,
          _Paged(
            key: ValueKey((view, type, search)),
            load: (cursor) => employee
                ? scope.api.employees(cursor, search, activeOnly: false)
                : scope.api.customers(
                    cursor,
                    search,
                    ['', 'INDIVIDUAL', 'ENTERPRISE'][type],
                  ),
            empty: employee ? '暂无匹配员工' : '暂无匹配客户',
            row: (row) => _tile(
              crmValue(row, 'name'),
              employee
                  ? row['status'] == 'DISABLED'
                        ? '已停用'
                        : '在职'
                  : row['kind'] == 'ENTERPRISE'
                  ? '企业客户'
                  : '个人客户',
              () => scope.open<void>(
                context,
                _Records(scope, row, employee: employee),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Records extends StatefulWidget {
  const _Records(this.scope, this.identity, {required this.employee});
  final _Scope scope;
  final CrmRow identity;
  final bool employee;

  @override
  State<_Records> createState() => _RecordsState();
}

class _RecordsState extends State<_Records> {
  bool pending = false;
  var pageKey = GlobalKey<_PagedState>();

  Future<void> create() async {
    final id = await widget.scope.open<String>(
      context,
      _Change(widget.scope, customerId: crmValue(widget.identity, 'id')),
    );
    if (!mounted || id == null) return;
    pageKey.currentState?.reload();
    await open(id);
  }

  Future<void> open(String id) async {
    await widget.scope.open<void>(context, _Detail(widget.scope, id));
    if (mounted) pageKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => CrmFrame(
    title: crmValue(widget.identity, 'name'),
    subtitle: widget.employee ? '负责与参与的线下业务' : '客户线下业务',
    back: () => Navigator.of(context).pop(),
    dock: !widget.employee && widget.identity['status'] == 'ACTIVE'
        ? SizedBox(
            width: double.infinity,
            child: CrmButton('登记线下业务', create, primary: true),
          )
        : null,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrmSegments(['全部记录', '待交付'], pending ? 1 : 0, (selected) {
          if (pending != (selected == 1)) {
            setState(() {
              pending = selected == 1;
              pageKey = GlobalKey<_PagedState>();
            });
          }
        }),
        crmGap,
        KeyedSubtree(
          key: ValueKey(pending),
          child: _Paged(
            key: pageKey,
            load: (cursor) => widget.scope.api.records(
              cursor,
              id: crmValue(widget.identity, 'id'),
              byEmployee: widget.employee,
              pendingOnly: pending,
            ),
            row: (row) => _tile(
              crmValue(row, 'title'),
              '${widget.employee ? '${crmValue(row, 'customerName')} · ' : ''}'
              '${_kinds[row['kind']] ?? ''} · ${crmValue(row, 'businessDate')}\n${_status(row)}',
              () => open(crmValue(row, 'id')),
            ),
          ),
        ),
      ],
    ),
  );
}

String _status(CrmRow row) =>
    '${row['activityStatus'] == 'ENDED' ? '活动已结束' : '活动待结束'} · '
    '${row['deliveryStatus'] == 'DELIVERED' ? '服务已交付' : '服务待交付'}';

class _Detail extends StatefulWidget {
  const _Detail(this.scope, this.id);
  final _Scope scope;
  final String id;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late Future<CrmRow> record = widget.scope.api.detail(widget.id);
  bool withdrawing = false, submitted = false;
  String? error;

  void reload() => setState(() {
    error = null;
    record = widget.scope.api.detail(widget.id);
  });

  Future<void> change(String action, CrmRow row) async {
    final value = await widget.scope.open<String>(
      context,
      _Change(widget.scope, current: row, action: action),
    );
    if (mounted) {
      submitted = value != null;
      reload();
    }
  }

  Future<void> withdraw(String id) async {
    if (withdrawing) return;
    setState(() {
      withdrawing = true;
      error = null;
    });
    try {
      await widget.scope.api.withdraw(id);
      if (mounted) {
        submitted = false;
        reload();
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmFrame(
    title: '线下业务详情',
    subtitle: '',
    back: () => Navigator.of(context).pop(),
    body: FutureBuilder(
      key: ObjectKey(record),
      future: record,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _failure(snapshot.error, reload);
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final row = snapshot.requireData;
        final review = row['pendingReview'] as CrmRow?;
        final transition = row['activityStatus'] != 'ENDED'
            ? 'END_ACTIVITY'
            : row['deliveryStatus'] != 'DELIVERED'
            ? 'CONFIRM_DELIVERY'
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            crmText(crmValue(row, 'title'), 20, bold: true),
            crmText(_status(row), 14),
            crmGap,
            for (final pair in [
              ('客户', crmValue(row, 'customerName')),
              ('业务类型', _kinds[row['kind']] ?? ''),
              ('业务日期', crmValue(row, 'businessDate')),
              ('业务负责人', crmValue(row, 'ownerName')),
              (
                '参与员工',
                crmRows(
                  row['participantDetails'],
                ).map((p) => p['name']).join('、'),
              ),
            ]) ...[
              crmSmall(pair.$1),
              crmText(pair.$2.isEmpty ? '无' : pair.$2, 15),
            ],
            crmGap,
            if (error != null) crmHint(error!),
            if (review != null) ...[
              crmHint(
                '${_actions[review['action']] ?? '变更'}待审，正式记录尚未改变。',
                success: submitted,
              ),
              if (review['canOpen'] == true)
                CrmButton('查看审核申请', () async {
                  await context.push(
                    '/me/reviews/${Uri.encodeComponent(crmValue(review, 'id'))}',
                  );
                  if (mounted) reload();
                }),
              if (review['canWithdraw'] == true)
                CrmButton(
                  withdrawing ? '正在撤回' : '撤回申请',
                  withdrawing ? null : () => withdraw(crmValue(review, 'id')),
                ),
            ] else if (row['customerStatus'] == 'ARCHIVED') ...[
              crmHint('客户已归档，此记录仅供查看。'),
            ] else ...[
              if (transition != null)
                CrmButton(
                  _actions[transition]!,
                  () => change(transition, row),
                  primary: true,
                ),
              CrmButton('修改资料', () => change('EDIT', row)),
            ],
            CrmButton('刷新记录', withdrawing ? null : reload, plain: true),
          ],
        );
      },
    ),
  );
}

class _Change extends StatefulWidget {
  const _Change(this.scope, {this.customerId, this.current, this.action});
  final _Scope scope;
  final String? customerId, action;
  final CrmRow? current;

  @override
  State<_Change> createState() => _ChangeState();
}

class _ChangeState extends State<_Change> {
  final form = GlobalKey<FormState>();
  final keys = <String, String>{};
  late final title = TextEditingController(
    text: widget.current?['title'] as String?,
  );
  late final date = TextEditingController(
    text: widget.current?['businessDate'] as String?,
  );
  final reason = TextEditingController();
  late String kind = widget.current?['kind'] as String? ?? 'COMPANY_VISIT';
  late CrmRow? owner = widget.current == null
      ? null
      : {
          'id': widget.current!['ownerId'],
          'name': widget.current!['ownerName'],
        };
  late final people = [...crmRows(widget.current?['participantDetails'])];
  bool busy = false;
  String? error;
  bool get editFields => widget.action == null || widget.action == 'EDIT';

  @override
  void dispose() {
    title.dispose();
    date.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> pick({required bool responsible}) async {
    final result = await widget.scope.open<CrmRow>(
      context,
      _EmployeePicker(widget.scope, {
        if (!responsible && owner != null) crmValue(owner!, 'id'),
        if (!responsible) ...people.map((p) => crmValue(p, 'id')),
      }),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (responsible) {
        owner = result;
        people.removeWhere((person) => person['id'] == result['id']);
      } else {
        people.add(result);
      }
      error = null;
    });
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (editFields && owner == null) {
      setState(() => error = '请选择业务负责人。');
      return;
    }
    final body = <String, dynamic>{
      if (widget.customerId != null) 'customerId': widget.customerId,
      if (widget.action != null) ...{
        'action': widget.action,
        'reason': reason.text.trim(),
        'version': widget.current!['version'],
      },
      if (editFields) ...{
        'kind': kind,
        'title': title.text.trim(),
        'businessDate': date.text.trim(),
        'ownerId': owner!['id'],
        'participants': people.map((p) => crmValue(p, 'id')).toList()..sort(),
      },
    };
    final key = keys.putIfAbsent(jsonEncode(body), newCalendarCommandKey);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = widget.action == null
          ? await widget.scope.api.create(body, key)
          : await widget.scope.api.submit(
              crmValue(widget.current!, 'id'),
              body,
              key,
            );
      if (mounted) Navigator.of(context).pop(crmValue(result, 'id'));
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget input(
    TextEditingController controller,
    String label,
    int max, {
    bool isDate = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      maxLength: max,
      keyboardType: isDate ? TextInputType.datetime : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return '必填';
        if (isDate) {
          final parsed = DateTime.tryParse(text);
          if (parsed == null ||
              parsed.year < 1 ||
              parsed.toIso8601String().split('T').first != text) {
            return '请输入有效日期（YYYY-MM-DD）';
          }
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: CrmFrame(
      title: _actions[widget.action] ?? '登记线下业务',
      subtitle: '',
      back: () {
        if (!busy) Navigator.of(context).pop();
      },
      dock: SizedBox(
        width: double.infinity,
        child: CrmButton(
          busy
              ? '正在提交'
              : widget.action == null
              ? '登记'
              : '提交审核',
          busy ? null : save,
          primary: true,
        ),
      ),
      body: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (editFields) ...[
              if (widget.action == null)
                PremiumDropdownField<String>(
                  initialValue: kind,
                  isExpanded: true,
                  sheetTitle: '业务类型',
                  decoration: const InputDecoration(labelText: '业务类型'),
                  items: _kinds.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => kind = value);
                        },
                ),
              crmGap,
              input(title, '业务标题', 120),
              input(date, '业务日期（YYYY-MM-DD）', 10, isDate: true),
              CrmButton(
                owner == null ? '选择业务负责人' : '负责人：${owner!['name']}',
                busy ? null : () => pick(responsible: true),
              ),
              crmGap,
              CrmButton(
                '添加参与员工',
                busy || people.length >= 50
                    ? null
                    : () => pick(responsible: false),
              ),
              for (final person in people)
                ListTile(
                  title: Text(crmValue(person, 'name')),
                  trailing: IconButton(
                    tooltip: '移除${crmValue(person, 'name')}',
                    onPressed: busy
                        ? null
                        : () => setState(() => people.remove(person)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              crmGap,
            ],
            if (widget.action != null) input(reason, '申请理由', 500),
            if (error != null) crmHint(error!),
          ],
        ),
      ),
    ),
  );
}

class _EmployeePicker extends StatefulWidget {
  const _EmployeePicker(this.scope, this.excluded);
  final _Scope scope;
  final Set<String> excluded;

  @override
  State<_EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends State<_EmployeePicker> {
  String search = '';

  @override
  Widget build(BuildContext context) => CrmFrame(
    title: '选择员工',
    subtitle: '',
    back: () => Navigator.of(context).pop(),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Search('搜索员工', (value) => setState(() => search = value)),
        crmGap,
        _Paged(
          key: ValueKey(search),
          load: (cursor) =>
              widget.scope.api.employees(cursor, search, activeOnly: true),
          empty: '没有匹配的在职员工',
          row: (row) => widget.excluded.contains(row['id'])
              ? ListTile(
                  title: Text(crmValue(row, 'name')),
                  subtitle: const Text('已选择'),
                )
              : _tile(
                  crmValue(row, 'name'),
                  '在职',
                  () => Navigator.of(context).pop(row),
                ),
        ),
      ],
    ),
  );
}
