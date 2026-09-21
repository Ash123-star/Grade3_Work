enum UserRole { admin, founder, director, leader, employee }

extension RoleLabel on UserRole {
  String get label => ['管理员', '创始人', '部门老总', '团队长', '员工'][index];
}

class Session {
  const Session({
    this.id = 'u1',
    this.name = '林小满',
    this.role = UserRole.leader,
    this.dispatch = true,
    this.active = true,
    this.token,
  });
  final String id, name;
  final UserRole role;
  final bool dispatch, active;
  final String? token;
  bool get manager => role != UserRole.employee;
  bool get administrator => role == UserRole.admin;
}

class Record {
  const Record({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.ownerId = 'u1',
    this.version = 1,
    this.fields = const {},
  });
  final String id, title, subtitle, ownerId;
  final int version;
  final Map<String, dynamic> fields;
  factory Record.fromJson(Map<String, dynamic> j) => Record(
    id: j['id'].toString(),
    title: j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String? ?? '',
    ownerId: j['ownerId'] as String? ?? '',
    version: j['version'] as int? ?? 1,
    fields: Map<String, dynamic>.from(j['fields'] as Map? ?? {}),
  );
}

class PageResult {
  const PageResult(this.items, {this.total = 0, this.nextCursor});
  final List<Record> items;
  final int total;
  final String? nextCursor;
}

class Query {
  const Query({
    this.search = '',
    this.cursor,
    this.ownerId,
    this.from,
    this.to,
  });
  final String search;
  final String? cursor, ownerId;
  final DateTime? from, to;
  Map<String, dynamic> toJson() => {
    'search': search,
    'limit': 30,
    if (cursor != null) 'cursor': cursor,
    if (ownerId != null) 'ownerId': ownerId,
    if (from != null) 'from': from!.toUtc().toIso8601String(),
    if (to != null) 'to': to!.toUtc().toIso8601String(),
  };
}

class Command {
  const Command(this.action, this.values, {this.version, this.idempotencyKey});
  final String action;
  final Map<String, dynamic> values;
  final int? version;
  final String? idempotencyKey;
  Map<String, dynamic> toJson() => {
    'action': action,
    'values': values,
    if (version != null) 'version': version,
  };
}

class BusinessRange {
  BusinessRange(DateTime date, String period) {
    var day = DateTime.utc(date.year, date.month, date.day);
    if (period == '周') day = day.subtract(Duration(days: day.weekday - 1));
    if (period == '月') day = DateTime.utc(day.year, day.month);
    final end = period == '月'
        ? DateTime.utc(day.year, day.month + 1)
        : day.add(Duration(days: period == '周' ? 7 : 1));
    from = day.subtract(const Duration(hours: 8));
    to = end.subtract(const Duration(hours: 8));
  }
  late final DateTime from, to;
}
