import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crm_components.dart';
import 'crm_demo_store.dart';
import 'crm_editor.dart';

class CrmWorkspacePage extends ConsumerWidget {
  const CrmWorkspacePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(crmDemoProvider);
    return _Directory(key: ObjectKey(store), store: store);
  }
}

Future<T?> _push<T>(BuildContext context, Widget child) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child));

class _Directory extends StatefulWidget {
  const _Directory({super.key, required this.store});
  final CrmDemoStore store;
  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> {
  final search = TextEditingController(), scroll = ScrollController();
  String query = '', owner = '全部';
  int type = 0, page = 0;
  bool pending = false;
  CrmDemoStore get store => widget.store;
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void resetScroll() {
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void find() {
    FocusScope.of(context).unfocus();
    setState(() {
      query = search.text.trim();
      page = 0;
    });
    resetScroll();
  }

  void clear() {
    search.clear();
    setState(() {
      query = '';
      type = 0;
      owner = '全部';
      pending = false;
      page = 0;
    });
    resetScroll();
  }

  Future<void> showCustomer(CrmCustomer c) async {
    await _push<void>(context, _Customer(store: store, c: c));
    if (mounted) setState(() {});
  }

  Future<void> add() async {
    final c = await _push<CrmCustomer>(context, CrmEditor(store: store));
    if (!mounted || c == null) return;
    setState(() {});
    await _push<void>(
      context,
      _Customer(store: store, c: c, notice: '已保存至原型示例 · 重启后重置'),
    );
    if (mounted) setState(() {});
  }

  Future<void> filter() async {
    var choice = owner, flag = pending;
    final value = await crmSheet<(String, bool)>(
      context,
      (sheet) => StatefulBuilder(
        builder: (context, update) => CrmSheetBody(
          '筛选客户',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              crmText('业务负责人', 14),
              const SizedBox(height: 7),
              CrmSelect(
                value: choice,
                values: const ['全部', ...CrmDemoStore.owners],
                onChanged: (v) => update(() => choice = v),
              ),
              CheckboxListTile(
                value: flag,
                onChanged: (v) => update(() => flag = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: crmText('只看有待完成服务的客户', 14),
              ),
            ],
          ),
          actions: crmActions(
            CrmButton(
              '重置',
              () => update(() {
                choice = '全部';
                flag = false;
              }),
            ),
            CrmButton(
              '查看客户',
              () => Navigator.pop(sheet, (choice, flag)),
              primary: true,
            ),
          ),
        ),
      ),
    );
    if (!mounted || value == null) return;
    setState(() {
      owner = value.$1;
      pending = value.$2;
      page = 0;
    });
    resetScroll();
  }

  @override
  Widget build(BuildContext context) {
    final rows = store.list(
      query: query,
      type: const ['全部', '个人', '企业'][type],
      owner: owner,
      pending: pending,
    );
    final count = rows.isEmpty ? 1 : (rows.length + 3) ~/ 4;
    final current = page.clamp(0, count - 1);
    final blocked = store.readState != CrmReadState.ready;
    return CrmFrame(
      title: '客户手帐',
      subtitle: _blocked(store) ? '账号访问状态' : '每一次来往，都有迹可循',
      back: () => Navigator.maybePop(context),
      scroll: scroll,
      help: _blocked(store)
          ? null
          : () => crmSheet<void>(
              context,
              (c) => CrmSheetBody(
                '一本手帐，三类信息',
                CrmSurface(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, item) in const [
                        ('档案', '客户身份、联系人与负责人。'),
                        ('会员', '会员资格、年卡、有效期和权益使用。'),
                        ('业务', '服务、活动与订单，点开查看独立记录。'),
                      ].indexed) ...[
                        if (i > 0)
                          const Divider(height: 1, color: CrmTone.line),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              crmText(item.$1, 14, bold: true),
                              const SizedBox(height: 5),
                              crmSmall(item.$2),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      body: blocked
          ? _feedback(
              store,
              () => setState(() => store.readState = CrmReadState.ready),
              () => Navigator.maybePop(context),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: crmBox(border: CrmTone.outline, radius: 15),
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          maxLength: 60,
                          style: crmStyle(15),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => find(),
                          decoration: InputDecoration(
                            hintText: '搜索客户、企业或负责人',
                            hintStyle: crmStyle(15, color: CrmTone.muted),
                            counterText: '',
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      CrmButton('搜索', find, plain: true, size: 13),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CrmSegments(const ['全部', '个人', '企业'], type, (i) {
                          setState(() {
                            type = i;
                            page = 0;
                          });
                          resetScroll();
                        }),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 52),
                        child: CrmButton(
                          '筛选${owner != '全部' || pending ? ' •' : ''}',
                          filter,
                          height: 48,
                          size: 13,
                          border: CrmTone.line,
                          semanticLabel: '筛选负责人和待完成服务',
                        ),
                      ),
                    ],
                  ),
                ),
                _listNote(
                  '${rows.length} 位客户${pending ? ' · 有待完成服务' : ''}',
                  '仅显示获准范围',
                ),
                if (rows.isEmpty)
                  crmEmpty(
                    '没有找到匹配客户',
                    '试试其他名称，或清空筛选条件。',
                    action: '清空筛选',
                    onTap: clear,
                  ),
                for (final c in rows.skip(current * 4).take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CrmSurface(
                      Row(
                        children: [
                          _avatar(c),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                crmText(c.name, 15, bold: true),
                                const SizedBox(height: 5),
                                crmText(
                                  c.subtitle,
                                  12,
                                  color: CrmTone.muted,
                                  height: 1.5,
                                ),
                                const SizedBox(height: 5),
                                crmText(
                                  '${c.pending > 0 ? '待完成服务 ${c.pending} 项' : '暂无待完成服务'} · ${c.owner}',
                                  12,
                                  color: CrmTone.muted,
                                  height: 1.5,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          crmText('›', 23, color: const Color(0xff8e7c54)),
                        ],
                      ),
                      onTap: () => showCustomer(c),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                    ),
                  ),
                crmSmall('个人与企业使用同一份客户目录。'),
              ],
            ),
      dock: _blocked(store)
          ? SizedBox(
              width: double.infinity,
              child: CrmButton('返回公司', () => Navigator.maybePop(context)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                crmPager(current, count, (p) {
                  setState(() => page = p);
                  resetScroll();
                }),
                if (store.canManage) ...[
                  const SizedBox(height: 8),
                  CrmButton(
                    '＋ 新增客户',
                    store.writable ? add : null,
                    primary: true,
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: crmText(
                      '当前仅可查看客户资料',
                      12,
                      color: CrmTone.muted,
                      align: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}

Widget _listNote(String first, String second, {Widget? action}) => Padding(
  padding: const EdgeInsets.only(top: 2, bottom: 9),
  child: Row(
    children: [
      Expanded(child: crmSmall(first)),
      if (action != null)
        action
      else
        Expanded(
          child: crmText(
            second,
            12,
            color: CrmTone.muted,
            align: TextAlign.right,
          ),
        ),
    ],
  ),
);
Widget _avatar(CrmCustomer c, {bool identity = false}) => Container(
  width: identity ? 48 : 43,
  height: identity ? 48 : 46,
  alignment: Alignment.center,
  decoration: crmBox(
    radius: identity ? 15 : 14,
    border: null,
    color: identity
        ? CrmTone.surface
        : c.enterprise
        ? const Color(0xffedf0f3)
        : const Color(0xfffff0bc),
  ),
  child: crmText(
    c.initial,
    identity ? 24 : 21,
    rounded: true,
    color: c.enterprise && !identity ? const Color(0xff526575) : CrmTone.accent,
  ),
);

class _Customer extends StatefulWidget {
  const _Customer({required this.store, required this.c, this.notice});
  final CrmDemoStore store;
  final CrmCustomer c;
  final String? notice;
  @override
  State<_Customer> createState() => _CustomerState();
}

class _CustomerState extends State<_Customer> {
  final scroll = ScrollController();
  final positions = <Object, double>{};
  int tab = 0, member = 0, page = 0;
  CrmKind kind = CrmKind.services;
  bool pending = true;
  late String? notice = widget.notice;
  CrmCustomer get c => widget.c;
  CrmDemoStore get store => widget.store;
  Object get positionKey => (
    tab,
    tab == 1 ? member : 0,
    tab == 2 ? kind : null,
    tab == 2 ? page : 0,
    tab == 2 ? pending : false,
  );
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void switchView(VoidCallback apply) {
    if (scroll.hasClients) positions[positionKey] = scroll.offset;
    setState(() {
      notice = null;
      apply();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(
          (positions[positionKey] ?? 0).clamp(
            0.0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  Future<void> edit() async {
    final saved = await _push<CrmCustomer>(
      context,
      CrmEditor(store: store, existing: c),
    );
    if (mounted && saved != null) setState(() => notice = '已保存至原型示例 · 重启后重置');
  }

  Future<void> editContact(int? index) async {
    final saved = await crmSheet<bool>(
      context,
      (_) => CrmContactEditor(store: store, customer: c, index: index),
      dismissible: false,
    );
    if (mounted && saved == true) setState(() => notice = '联系人已保存至原型示例');
  }

  Widget contacts(Iterable<int> indices) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final i in indices)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: crmText(
                      '${c.contacts[i].name}${c.contacts[i].role.isEmpty ? '' : ' · ${c.contacts[i].role}'}',
                      14,
                      bold: true,
                    ),
                  ),
                  if (store.writable && store.contactAllowed)
                    CrmButton(
                      '编辑',
                      () => editContact(i),
                      plain: true,
                      height: 48,
                      size: 13,
                      semanticLabel: '编辑联系人${c.contacts[i].name}',
                    ),
                ],
              ),
              crmSmall(
                c.contacts[i].phone.isEmpty ? '未填写联系方式' : c.contacts[i].phone,
              ),
              if (i < c.contacts.length - 1)
                const Divider(height: 14, color: CrmTone.line),
            ],
          ),
        ),
    ],
  );
  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      crmSection(
        '基本资料',
        action: store.writable
            ? CrmButton('编辑资料', edit, plain: true, height: 48, size: 13)
            : crmSmall('仅可查看'),
      ),
      crmFields([
        ('客户类型', '${c.type}客户'),
        ('业务负责人', c.owner),
        ('建档日期', c.since),
        ('资料来源', c.source),
      ]),
      crmSection(
        c.enterprise ? '企业联系人' : '联系信息',
        action: c.enterprise && store.writable && store.contactAllowed
            ? CrmButton(
                '＋ 添加',
                () => editContact(null),
                plain: true,
                height: 48,
                size: 13,
              )
            : null,
      ),
      if (!store.contactAllowed)
        crmHint('联系信息未授权。可继续查看获准的会员与业务记录。')
      else if (!c.enterprise)
        CrmSurface(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              crmText(c.name, 14, bold: true),
              const SizedBox(height: 5),
              crmSmall(c.phone.isEmpty ? '未填写联系方式' : c.phone),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        )
      else if (c.contacts.isEmpty)
        crmHint('暂无联系人，可先添加一位日常对接人。')
      else ...[
        CrmSurface(
          contacts(List.generate(c.contacts.length, (i) => i).take(2)),
        ),
        if (c.contacts.length > 2) ...[
          crmGap,
          CrmDisclosure(
            '更多联系人 · ${c.contacts.length - 2} 位',
            contacts(List.generate(c.contacts.length, (i) => i).skip(2)),
          ),
        ],
      ],
      crmGap,
      CrmDisclosure('补充说明', crmSmall(c.note.isEmpty ? '暂无补充说明。' : c.note)),
    ],
  );
  Widget membership() {
    if (c.members.isEmpty) {
      return crmEmpty(
        '暂无会员资格',
        '该客户仍可正常参加活动与接受服务。相关记录在“业务”中查看。',
        action: '查看业务',
        onTap: () => switchView(() => tab = 2),
      );
    }
    final items = c.members.map((id) => store.memberships[id]!).toList(),
        item = items[member];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrmSegments(
          items.map((m) => m.label).toList(),
          member,
          (i) => switchView(() => member = i),
        ),
        crmGap,
        Container(
          decoration: crmBox(
            color: const Color(0xfffff3bd),
            border: const Color(0xffe5d38c),
            radius: 20,
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -26,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xffffe781),
                      width: 16,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: crmText(
                            item.source,
                            10,
                            bold: true,
                            color: CrmTone.accent,
                          ),
                        ),
                        crmBadge(item.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    crmText(item.name, 20, rounded: true),
                    const SizedBox(height: 10),
                    crmText(
                      '有效期 ${item.from} — ${item.until}',
                      12,
                      height: 1.6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (item.status == '已到期') ...[
          crmGap,
          crmHint('该资格已到期，权益不可继续使用；历史记录保留。'),
        ],
        crmSection('可享权益', action: crmSmall('按当前资格展示')),
        CrmSurface(
          Column(
            children: [
              for (var i = 0; i < item.benefits.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: CrmTone.line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            crmText(item.benefits[i][0], 14, bold: true),
                            const SizedBox(height: 4),
                            crmSmall(item.benefits[i][1]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      crmText(
                        item.benefits[i][2],
                        18,
                        bold: true,
                        color: CrmTone.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        crmGap,
        CrmDisclosure(
          key: ValueKey(item.id),
          '权益使用记录 · ${item.history.length} 条',
          crmTimeline(item.history),
        ),
        crmGap,
        crmSmall('参与活动与使用权益分别记录。'),
      ],
    );
  }

  Widget business(List<CrmRecord> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CrmSegments(
        CrmKind.values.map((k) => k.label).toList(),
        kind.index,
        (i) => switchView(() {
          kind = CrmKind.values[i];
          page = 0;
        }),
      ),
      const SizedBox(height: 10),
      _listNote(
        '${switch (kind) {
          CrmKind.services => pending ? '待完成服务' : '全部服务',
          CrmKind.activities => '活动参与记录',
          CrmKind.orders => '商城订单',
        }} · ${rows.length} 条',
        '按发生时间排列',
        action: kind == CrmKind.services
            ? CrmButton(
                pending ? '查看全部' : '只看待完成',
                () => switchView(() {
                  pending = !pending;
                  page = 0;
                }),
                height: 48,
                plain: true,
                size: 13,
              )
            : null,
      ),
      if (rows.isEmpty)
        crmEmpty(
          '暂无${kind.label}记录',
          kind == CrmKind.services && pending
              ? '当前没有待完成服务，可切换查看全部历史。'
              : '此分类目前没有关联记录。',
        ),
      for (final r in rows.skip(page * 3).take(3))
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: CrmSurface(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: crmText(r.type, 12, color: CrmTone.accent)),
                    crmBadge(r.status),
                  ],
                ),
                const SizedBox(height: 8),
                crmText(r.name, 15, bold: true, height: 1.55),
                const SizedBox(height: 7),
                crmSmall(
                  '${r.date} · ${r.kind == CrmKind.orders ? (store.amountAllowed ? r.amount : '金额未授权') : '负责人 ${r.owner}'}',
                ),
              ],
            ),
            radius: 17,
            padding: const EdgeInsets.all(13),
            onTap: () async {
              final related = await _push<bool>(
                context,
                _Record(c: c, r: r, amountAllowed: store.amountAllowed),
              );
              if (mounted && related == true) {
                switchView(() {
                  kind = CrmKind.services;
                  pending = false;
                  page = 0;
                });
              }
            },
          ),
        ),
      crmSmall(switch (kind) {
        CrmKind.services => '服务完成情况以实际交付记录为准。',
        CrmKind.activities => '活动状态与服务完成情况分别记录。',
        CrmKind.orders => '来源：商城订单记录 · 金额不等同于营收',
      }),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final rows = store.business(c, kind, pending: pending),
        count = rows.isEmpty ? 1 : (rows.length + 2) ~/ 3;
    return CrmFrame(
      title: '客户详情',
      backLabel: '返回客户目录',
      subtitle: '${c.type}客户',
      back: () => Navigator.maybePop(context),
      scroll: scroll,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notice != null) ...[
            crmHint(notice!, success: true),
            const SizedBox(height: 10),
          ],
          CrmSurface(
            Row(
              children: [
                _avatar(c, identity: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      crmText(c.name, 18, rounded: true, height: 1.45),
                      const SizedBox(height: 4),
                      crmSmall('${c.type}客户 · 负责人 ${c.owner}'),
                    ],
                  ),
                ),
              ],
            ),
            color: const Color(0xfffff5ce),
            border: const Color(0xffeedda0),
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          const SizedBox(height: 14),
          switch (tab) {
            1 => membership(),
            2 => business(rows),
            _ => profile(),
          },
        ],
      ),
      dock: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tab == 2)
            crmPager(page, count, (p) => switchView(() => page = p)),
          CrmSegments(
            const ['档案', '会员', '业务'],
            tab,
            (i) => switchView(() => tab = i),
            dock: true,
          ),
        ],
      ),
    );
  }
}

class _Record extends StatelessWidget {
  const _Record({
    required this.c,
    required this.r,
    required this.amountAllowed,
  });
  final CrmCustomer c;
  final CrmRecord r;
  final bool amountAllowed;
  @override
  Widget build(BuildContext context) {
    final order = r.kind == CrmKind.orders;
    return CrmFrame(
      title: '业务记录',
      subtitle: c.name,
      back: () => Navigator.maybePop(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 9),
            child: Row(
              children: [
                Expanded(child: crmSmall(r.type)),
                crmBadge(r.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 14),
            child: crmText(r.name, 22, rounded: true, height: 1.5),
          ),
          crmFields([
            ('关联客户', c.name),
            ('业务类型', r.type),
            ('业务日期', r.date),
            if (order) ...[
              ('订单来源', r.source),
              ('原实付金额', amountAllowed ? r.amount : '未授权'),
              ('已退款金额', amountAllowed ? r.refund : '未授权'),
            ] else ...[
              ('主要负责人', r.owner),
              ('参与员工', r.staff),
              if (r.kind == CrmKind.services) ('服务依据', r.source),
            ],
          ]),
          crmGap,
          CrmDisclosure(
            order ? '订单编号与来源说明' : '业务说明',
            crmSmall(order ? '${r.number}\n${r.description}' : r.description),
          ),
          crmGap,
          CrmDisclosure(
            r.kind == CrmKind.services ? '服务进度' : '发生记录',
            crmTimeline(r.events),
            initiallyOpen: true,
          ),
          if (r.kind == CrmKind.activities) ...[
            crmGap,
            CrmButton('查看该客户的服务记录', () => Navigator.pop(context, true)),
          ],
        ],
      ),
      dock: SizedBox(
        width: double.infinity,
        child: CrmButton(
          '‹ 返回客户详情',
          () => Navigator.maybePop(context),
          primary: true,
        ),
      ),
    );
  }
}

bool _blocked(CrmDemoStore store) =>
    [CrmReadState.forbidden, CrmReadState.expired].contains(store.readState);
Widget _feedback(CrmDemoStore store, VoidCallback recover, VoidCallback back) {
  final (title, message, action) = switch (store.readState) {
    CrmReadState.loading => ('正在读取记录', '请稍候，资料加载后会显示在这里。', '结束加载演示'),
    CrmReadState.empty => ('这里还没有记录', '当前范围没有可展示的记录。你可以返回调整筛选。', '返回正常示例'),
    CrmReadState.failed => ('记录暂时没有加载出来', '请检查网络后重试，当前筛选会保留。', '重新加载'),
    CrmReadState.unavailable => ('数据来源暂不可用', '这部分资料暂时无法读取，请稍后重试。', '重试'),
    CrmReadState.forbidden => ('暂时无法访问', '当前账号没有此范围的访问权限，请联系管理员。', '返回公司'),
    CrmReadState.expired => ('登录已失效', '请重新登录后继续查看客户资料。', '返回公司'),
    _ => ('', '', ''),
  };
  if (store.readState == CrmReadState.loading) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: CrmTone.accent),
          crmGap,
          crmText(title, 20, rounded: true),
          crmGap,
          crmSmall(message),
          crmGap,
          CrmButton(action, recover),
        ],
      ),
    );
  }
  return crmEmpty(
    title,
    message,
    icon: switch (store.readState) {
      CrmReadState.forbidden => 'identity',
      CrmReadState.expired => 'person',
      CrmReadState.empty => 'empty',
      _ => 'error',
    },
    useStatusIcon: true,
    action: action,
    onTap: _blocked(store) ? back : recover,
  );
}
