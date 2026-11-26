import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';

import 'crm_demo_fixture.dart';

final crmDemoProvider = Provider<CrmDemoStore>((ref) {
  // Discard mutable samples on a session/account change; never persist them.
  ref.watch(
    sessionProvider.select(
      (s) => (s.companyId, s.id, s.token, s.canReadBusiness),
    ),
  );
  final store = CrmDemoStore();
  ref.onDispose(store.revoke);
  return store;
});

class CrmContact {
  const CrmContact(this.name, this.role, this.phone);
  final String name, role, phone;
}

class CrmCustomer {
  CrmCustomer({
    required this.id,
    required this.name,
    required this.type,
    required this.subtitle,
    required this.owner,
    required this.since,
    required this.source,
    this.pending = 0,
    this.phone = '',
    this.note = '',
    this.members = const [],
    List<CrmContact>? contacts,
  }) : contacts = contacts ?? [];
  final String id, type, subtitle, since, source;
  final int pending;
  final List<String> members;
  final List<CrmContact> contacts;
  String name, owner, phone, note;
  int version = 1;
  bool get enterprise => type == '企业';
  String get initial =>
      name.isEmpty ? '' : String.fromCharCode(name.runes.first);
}

class CrmMembership {
  CrmMembership(this.id, Map<String, dynamic> row)
    : name = row['name'] as String,
      source = row['source'] as String,
      status = row['status'] as String,
      from = row['from'] as String,
      until = row['until'] as String,
      benefits = _lines(row['benefits']),
      history = _lines(row['history']);
  final String id, name, source, status, from, until;
  final List<List<String>> benefits, history;
  String get label => id == 'club' ? '商城会员' : '演出年卡';
}

List<List<String>> _lines(dynamic rows) =>
    (rows as List).map((r) => (r as List).cast<String>()).toList();

enum CrmKind {
  services('服务'),
  activities('活动'),
  orders('订单');

  const CrmKind(this.label);
  final String label;
}

class CrmRecord {
  CrmRecord(Map<String, dynamic> row)
    : id = row['id'] as String,
      customerId = row['customer'] as String,
      kind = CrmKind.values.byName(row['kind'] as String),
      type = row['type'] as String,
      name = row['name'] as String,
      date = row['date'] as String,
      status = row['status'] as String,
      owner = row['owner'] as String? ?? '',
      staff = row['staff'] as String? ?? '',
      source = row['source'] as String? ?? '',
      number = row['number'] as String? ?? '',
      amount = row['amount'] as String? ?? '',
      refund = row['refund'] as String? ?? '',
      description = row['description'] as String,
      events = _lines(row['events']);
  final String id,
      customerId,
      type,
      name,
      date,
      status,
      owner,
      staff,
      source,
      number,
      amount,
      refund,
      description;
  final CrmKind kind;
  final List<List<String>> events;
}

enum CrmSaveResult { success, failed, conflict, denied }

enum CrmReadState {
  ready,
  loading,
  empty,
  failed,
  unavailable,
  forbidden,
  expired,
}

class CrmDemoStore {
  CrmDemoStore({
    this.canManage = true,
    this.contactAllowed = true,
    this.amountAllowed = true,
    this.readState = CrmReadState.ready,
  }) {
    final data = jsonDecode(crmDemoFixture) as Map<String, dynamic>;
    for (final row
        in (data['customers'] as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      final members = (row['members'] as List).cast<String>();
      customers.add(
        CrmCustomer(
          id: id,
          name: row['name'] as String,
          type: row['type'] as String,
          subtitle: row['subtitle'] as String,
          owner: row['owner'] as String,
          since: row['since'] as String,
          source: members.contains('club') ? '商城关联' : '线下建档',
          pending: row['pending'] as int,
          phone: row['contact'] as String,
          note: row['note'] as String,
          members: members,
          contacts: id == 'heyu'
              ? const [
                  CrmContact('顾言', '项目联系人', '021 **** 0620'),
                  CrmContact('叶青', '行政对接', '021 **** 0916'),
                ].toList()
              : null,
        ),
      );
    }
    for (final row
        in (data['qualifications'] as Map<String, dynamic>).entries) {
      memberships[row.key] = CrmMembership(
        row.key,
        row.value as Map<String, dynamic>,
      );
    }
    records.addAll(
      (data['records'] as List).cast<Map<String, dynamic>>().map(CrmRecord.new),
    );
  }
  static const owners = ['陈晨', '许禾'];
  final bool canManage, contactAllowed, amountAllowed;
  CrmReadState readState;
  CrmSaveResult nextSave = CrmSaveResult.success;
  final customers = <CrmCustomer>[];
  final memberships = <String, CrmMembership>{};
  final records = <CrmRecord>[];
  int _next = 1;
  bool _active = true;
  void revoke() => _active = false;
  bool get writable => _active && canManage && readState == CrmReadState.ready;

  List<CrmCustomer> list({
    String query = '',
    String type = '全部',
    String owner = '全部',
    bool pending = false,
  }) => customers
      .where(
        (c) =>
            (type == '全部' || type == c.type) &&
            (owner == '全部' || owner == c.owner) &&
            (!pending || c.pending > 0) &&
            [c.name, c.subtitle, c.owner].any((v) => v.contains(query.trim())),
      )
      .toList();

  List<CrmRecord> business(
    CrmCustomer c,
    CrmKind kind, {
    required bool pending,
  }) =>
      records
          .where(
            (r) =>
                r.customerId == c.id &&
                r.kind == kind &&
                (kind != CrmKind.services || !pending || r.status == '待完成'),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  static String _normalized(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');
  static bool validPhone(String phone) {
    phone = phone.trim();
    if (phone.isEmpty) return true;
    final n = _digits(phone).length;
    return RegExp(r'^\+?[\d ()-]+$').hasMatch(phone) && n >= 6 && n <= 20;
  }

  List<CrmCustomer> duplicates(
    String name,
    String phone,
    CrmCustomer? except,
  ) => customers
      .where(
        (c) =>
            c != except &&
            (_normalized(c.name) == _normalized(name) ||
                (contactAllowed &&
                    phone.trim().isNotEmpty &&
                    [c.phone, ...c.contacts.map((p) => p.phone)].any(
                      (p) =>
                          p.isNotEmpty &&
                          !p.contains('*') &&
                          _digits(p) == _digits(phone),
                    ))),
      )
      .toList();

  CrmSaveResult _check(CrmCustomer? c, int? version) {
    if (!writable) return CrmSaveResult.denied;
    final result = nextSave;
    nextSave = CrmSaveResult.success;
    if (c != null && c.version != version) return CrmSaveResult.conflict;
    return result;
  }

  (CrmSaveResult, CrmCustomer?) save({
    CrmCustomer? customer,
    int? version,
    required String type,
    required String name,
    required String owner,
    required String phone,
    required String note,
    required String contactName,
    required String since,
  }) {
    final result = _check(customer, version);
    if (result != CrmSaveResult.success) return (result, null);
    if (customer != null) {
      customer.name = name.trim();
      customer.owner = owner;
      customer.note = note.trim();
      if (!customer.enterprise && contactAllowed && phone.trim().isNotEmpty) {
        customer.phone = phone.trim();
      }
      customer.version++;
      return (result, customer);
    }
    final c = CrmCustomer(
      id: 'local-${_next++}',
      name: name.trim(),
      type: type,
      subtitle: '$type客户 · 新建档案',
      owner: owner,
      since: since,
      source: '手工建档',
      note: note.trim(),
      phone: contactAllowed && type == '个人' ? phone.trim() : '',
    );
    if (c.enterprise && contactAllowed && contactName.trim().isNotEmpty) {
      c.contacts.add(CrmContact(contactName.trim(), '主要联系人', phone.trim()));
    }
    customers.insert(0, c);
    return (result, c);
  }

  CrmSaveResult saveContact(
    CrmCustomer c,
    int version,
    int? index,
    CrmContact contact,
  ) {
    if (!contactAllowed || !c.enterprise) return CrmSaveResult.denied;
    final result = _check(c, version);
    if (result != CrmSaveResult.success) return result;
    if (index == null) {
      c.contacts.add(contact);
    } else {
      final old = c.contacts[index];
      c.contacts[index] = CrmContact(
        contact.name,
        contact.role,
        contact.phone.isEmpty ? old.phone : contact.phone,
      );
    }
    c.version++;
    return result;
  }
}
