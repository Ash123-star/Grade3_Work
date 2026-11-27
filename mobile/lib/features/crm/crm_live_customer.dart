part of 'crm_live_workspace.dart';

const _memberStates = {'ACTIVE': '有效', 'EXPIRED': '已到期', 'DISABLED': '已停用'};
const _benefitKinds = {
  'ANNUAL_CARD': '演出年卡',
  'MALL_MEMBER': '会员权益',
  'OTHER': '其他权益',
};
const _orderStates = {
  'PENDING_PAYMENT': '待支付',
  'PAID': '已支付',
  'COMPLETED': '已完成',
  'CANCELLED': '已取消',
  'REFUNDED': '已退款',
  'PARTIALLY_REFUNDED': '部分退款',
};

String _shown(CrmRow row, String key, [String fallback = '未填写']) {
  final value = crmValue(row, key);
  return value.isEmpty ? fallback : value;
}

String _businessDay(Object? value) {
  final date = DateTime.tryParse('${value ?? ''}');
  if (date == null) return '未记录';
  return date
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .split('T')
      .first;
}

class _Customer extends StatefulWidget {
  const _Customer(this.scope, this.identity, this.profileChanged);
  final _Scope scope;
  final CrmRow identity;
  final VoidCallback profileChanged;

  @override
  State<_Customer> createState() => _CustomerState();
}

class _CustomerState extends State<_Customer> {
  int tab = 0;
  final scroll = ScrollController();
  String get id => crmValue(widget.identity, 'id');
  late Future<CrmRow> detail = widget.scope.api.customer(id);

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void refresh() => setState(() {
    detail = widget.scope.api.customer(id);
  });

  Future<void> edit(CrmRow row) async {
    final saved = await widget.scope.open<CrmRow>(
      context,
      _ProfileForm(widget.scope, profile: row),
    );
    if (!mounted || saved == null) return;
    widget.profileChanged();
    refresh();
  }

  Future<void> memberForm(CrmRow? member) async {
    final saved = await widget.scope.open<bool>(
      context,
      _ValueForm(
        title: member == null ? '绑定商城会员' : '编辑商城会员',
        fields: const [
          _ValueField('mallMemberId', '商城会员 ID', 200, required: true),
          _ValueField('level', '会员等级', 100),
          _ValueField('joinedAt', '加入日期', 10, date: true),
          _ValueField('expiresAt', '到期日期', 10, date: true),
          _ValueField('status', '会员状态', 16, choices: _memberStates),
        ],
        initial: member ?? const {'status': 'ACTIVE'},
        dateRange: ('joinedAt', 'expiresAt'),
        submit: (body, _) => widget.scope.api.saveMembership(id, {
          ...body,
          'joinedAt': body['joinedAt'] == '' ? null : body['joinedAt'],
          'expiresAt': body['expiresAt'] == '' ? null : body['expiresAt'],
          'version': member?['version'] ?? 0,
        }),
        onConflict: refresh,
      ),
    );
    if (mounted && saved == true) refresh();
  }

  Future<void> grant() async {
    final saved = await widget.scope.open<bool>(
      context,
      _ValueForm(
        title: '发放权益',
        fields: const [
          _ValueField('kind', '权益类别', 16, choices: _benefitKinds),
          _ValueField('name', '权益名称', 200, required: true),
          _ValueField('validFrom', '有效期开始', 10, required: true, date: true),
          _ValueField('validTo', '有效期结束', 10, required: true, date: true),
          _ValueField('maxUses', '可用次数（不填不限次）', 6, maximum: 100000),
        ],
        initial: const {'kind': 'ANNUAL_CARD'},
        dateRange: ('validFrom', 'validTo'),
        submit: (body, key) => widget.scope.api.createBenefit(id, body, key),
      ),
    );
    if (mounted && saved == true) refresh();
  }

  Future<void> progress() async {
    final saved = await widget.scope.open<bool>(
      context,
      _ValueForm(
        title: '记录服务进度',
        fields: const [
          _ValueField('stage', '服务阶段', 100, required: true),
          _ValueField('note', '服务说明', 1000, multiline: true),
        ],
        submit: (body, key) => widget.scope.api.addProgress(id, body, key),
      ),
    );
    if (mounted && saved == true) refresh();
  }

  Widget archive(CrmRow row) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      crmSection(
        '客户资料',
        action: CrmButton('编辑档案', () => edit(row), plain: true),
      ),
      crmFields([
        ('业务负责人', _shown(row, 'ownerName', '未分配')),
        ('联系电话', _shown(row, 'phone')),
        ('联系邮箱', _shown(row, 'email')),
        ('商城外部 ID', _shown(row, 'externalId', '未设置')),
        ('备注', _shown(row, 'note', '无')),
      ]),
      if (row['kind'] == 'ENTERPRISE') ...[
        crmSection('企业联系人'),
        if (crmRows(row['contacts']).isEmpty) crmHint('暂无联系人'),
        for (final contact in crmRows(row['contacts']))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: crmFields([
              ('姓名', crmValue(contact, 'name')),
              ('职务', _shown(contact, 'role')),
              ('电话', _shown(contact, 'phone')),
              ('邮箱', _shown(contact, 'email')),
            ]),
          ),
      ],
    ],
  );

  Widget membership(CrmRow data, bool active) {
    final member = data['membership'] as CrmRow?;
    final benefits = crmRows(data['benefits']);
    final stages = crmRows(data['progress']);
    final expiry = member?['expiresAt'] as String?;
    final status =
        member?['status'] == 'ACTIVE' &&
            expiry != null &&
            expiry.compareTo(_businessDay(DateTime.now())) < 0
        ? 'EXPIRED'
        : member?['status'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        crmSection(
          '商城会员',
          action: active
              ? CrmButton(
                  member == null ? '绑定会员' : '编辑会员',
                  () => memberForm(member),
                  plain: true,
                )
              : null,
        ),
        if (member == null)
          crmHint('暂无绑定商城会员')
        else
          crmFields([
            ('会员 ID', crmValue(member, 'mallMemberId')),
            ('会员等级', _shown(member, 'level')),
            ('资格状态', _memberStates[status] ?? '未知'),
            ('加入日期', _shown(member, 'joinedAt')),
            ('到期日期', _shown(member, 'expiresAt', '未设置')),
          ]),
        crmSection(
          '客户权益',
          action: active ? CrmButton('发放权益', grant, plain: true) : null,
        ),
        if (benefits.isEmpty) crmHint('暂无权益'),
        for (final benefit in benefits)
          _tile(
            crmValue(benefit, 'name'),
            '${_benefitKinds[benefit['kind']] ?? '权益'} · ${_benefitStatus(benefit)}\n'
            '${crmValue(benefit, 'validFrom')} 至 ${crmValue(benefit, 'validTo')}',
            () => widget.scope.open<void>(
              context,
              _Benefit(widget.scope, id, benefit, active),
            ),
          ),
        crmSection(
          '服务进度',
          action: active ? CrmButton('记录进度', progress, plain: true) : null,
        ),
        if (stages.isEmpty) crmHint('暂无服务进度'),
        if (stages.isNotEmpty)
          crmTimeline([
            for (final stage in stages)
              [
                '${_businessDay(stage['createdAt'])} ${crmValue(stage, 'note')}'
                    .trim(),
                crmValue(stage, 'stage'),
              ],
          ]),
      ],
    );
  }

  Widget business(CrmRow profile, bool hasMember) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      crmSection('业务记录'),
      _tile(
        '线下业务',
        '赛演、私宴、企业参访、沙龙与服务交付',
        () => widget.scope.open<void>(
          context,
          _Records(widget.scope, profile, employee: false),
        ),
      ),
      _tile(
        '商城订单',
        hasMember ? '按已绑定商城会员查询' : '尚未绑定商城会员',
        () => widget.scope.open<void>(
          context,
          _Orders(widget.scope, id, hasMember),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => FutureBuilder(
    key: ObjectKey(detail),
    future: detail,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final profile = data?['customer'] as CrmRow?;
      final active = profile?['status'] == 'ACTIVE';
      return CrmFrame(
        title: profile == null ? '客户详情' : crmValue(profile, 'name'),
        subtitle: profile == null
            ? '客户手帐'
            : '${profile['kind'] == 'ENTERPRISE' ? '企业客户' : '个人客户'} · ${active ? '正常' : '已归档'}',
        back: () => Navigator.of(context).pop(),
        scroll: scroll,
        dock: profile == null
            ? null
            : CrmSegments(const ['档案', '会员', '业务'], tab, (next) {
                if (next == tab) return;
                if (scroll.hasClients) scroll.jumpTo(0);
                setState(() => tab = next);
              }, dock: true),
        body: snapshot.hasError
            ? _failure(snapshot.error, refresh)
            : profile == null || data == null
            ? const LinearProgressIndicator()
            : switch (tab) {
                1 => membership(data, active),
                2 => business(profile, data['membership'] != null),
                _ => archive(profile),
              },
      );
    },
  );
}

String _benefitStatus(CrmRow row) {
  if (row['status'] != 'ACTIVE') return '已停用';
  final today = _businessDay(DateTime.now());
  if (crmValue(row, 'validFrom').compareTo(today) > 0) return '未生效';
  if (crmValue(row, 'validTo').compareTo(today) < 0) return '已到期';
  return '有效';
}

class _Benefit extends StatefulWidget {
  const _Benefit(this.scope, this.customerId, this.benefit, this.active);
  final _Scope scope;
  final String customerId;
  final CrmRow benefit;
  final bool active;
  @override
  State<_Benefit> createState() => _BenefitState();
}

class _BenefitState extends State<_Benefit> {
  String get benefitId => crmValue(widget.benefit, 'id');
  Future<List<CrmRow>> load() =>
      widget.scope.api.redemptions(widget.customerId, benefitId);
  late Future<List<CrmRow>> history = load();
  void refresh() => setState(() {
    history = load();
  });

  Future<void> redeem() async {
    final saved = await widget.scope.open<bool>(
      context,
      _ValueForm(
        title: '确认核销一次',
        submitLabel: '确认核销',
        fields: const [_ValueField('note', '核销说明', 500, multiline: true)],
        submit: (body, key) =>
            widget.scope.api.redeem(widget.customerId, benefitId, body, key),
      ),
    );
    if (mounted && saved == true) refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    key: ObjectKey(history),
    future: history,
    builder: (context, snapshot) {
      final rows = snapshot.data;
      final benefit = widget.benefit;
      final max = benefit['maxUses'] as int?;
      final remaining = max == null || rows == null
          ? null
          : (max - rows.length).clamp(0, max);
      final status = _benefitStatus(benefit);
      return CrmFrame(
        title: rows == null ? '客户权益' : crmValue(benefit, 'name'),
        subtitle: '使用记录',
        back: () => Navigator.of(context).pop(),
        dock: rows != null && widget.active && status == '有效' && remaining != 0
            ? SizedBox(
                width: double.infinity,
                child: CrmButton('核销一次', redeem, primary: true),
              )
            : null,
        body: snapshot.hasError
            ? _failure(snapshot.error, refresh)
            : rows == null
            ? const LinearProgressIndicator()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  crmFields([
                    (
                      '有效期',
                      '${crmValue(benefit, 'validFrom')} 至 ${crmValue(benefit, 'validTo')}',
                    ),
                    ('状态', status),
                    ('已核销', '${rows.length} 次'),
                    ('剩余次数', remaining == null ? '不限次' : '$remaining 次'),
                  ]),
                  crmSection('核销历史'),
                  if (rows.isEmpty) crmHint('暂无核销记录'),
                  if (rows.isNotEmpty)
                    crmTimeline([
                      for (final row in rows)
                        [
                          _businessDay(row['redeemedAt']),
                          _shown(row, 'note', '核销一次'),
                        ],
                    ]),
                ],
              ),
      );
    },
  );
}

String _orderStatus(CrmRow row) => _orderStates[row['status']] ?? '状态待核对';

class _Orders extends StatelessWidget {
  const _Orders(this.scope, this.customerId, this.hasMember);
  final _Scope scope;
  final String customerId;
  final bool hasMember;

  @override
  Widget build(BuildContext context) => CrmFrame(
    title: '商城订单',
    subtitle: '客户业务',
    back: () => Navigator.of(context).pop(),
    body: _Paged(
      load: (cursor) => scope.api.orders(customerId, cursor),
      empty: hasMember ? '暂无已导入的商城订单' : '尚未绑定商城会员',
      row: (row) => _tile(
        '订单 ${crmValue(row, 'externalOrderId')}',
        '${_businessDay(row['orderedAt'])} · ${_orderStatus(row)}\n'
            '原始金额 ${crmValue(row, 'currency')} ${crmValue(row, 'amount')}',
        () => scope.open<void>(
          context,
          _Order(scope, customerId, crmValue(row, 'externalOrderId')),
        ),
      ),
    ),
  );
}

class _Order extends StatefulWidget {
  const _Order(this.scope, this.customerId, this.id);
  final _Scope scope;
  final String customerId, id;
  @override
  State<_Order> createState() => _OrderState();
}

class _OrderState extends State<_Order> {
  Future<CrmRow> load() => widget.scope.api.order(widget.customerId, widget.id);
  late Future<CrmRow> order = load();
  @override
  Widget build(BuildContext context) => CrmFrame(
    title: '订单详情',
    subtitle: '商城订单',
    back: () => Navigator.of(context).pop(),
    body: FutureBuilder(
      key: ObjectKey(order),
      future: order,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _failure(snapshot.error, () {
            setState(() {
              order = load();
            });
          });
        }
        final row = snapshot.data;
        if (row == null) return const LinearProgressIndicator();
        return crmFields([
          ('订单号', crmValue(row, 'externalOrderId')),
          ('订单状态', _orderStatus(row)),
          ('下单日期', _businessDay(row['orderedAt'])),
          ('原始订单金额', '${crmValue(row, 'currency')} ${crmValue(row, 'amount')}'),
          ('导入批次', _shown(row, 'importId', '未记录')),
        ]);
      },
    ),
  );
}
