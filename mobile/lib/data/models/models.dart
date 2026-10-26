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
    this.status = 'ACTIVE',
    this.mustChangePassword = false,
    this.expired = false,
    this.expiresAt,
    this.departmentId,
    this.teamId,
  });
  final String id, name;
  final UserRole role;
  final bool dispatch, active;
  final String? token;
  final String status;
  final bool mustChangePassword, expired;
  final DateTime? expiresAt;
  final String? departmentId, teamId;
  bool get authenticated => !expired && (token != null || active);
  bool get canReadBusiness =>
      authenticated && active && status == 'ACTIVE' && !mustChangePassword;
  Session restrict({
    String? status,
    bool? mustChangePassword,
    bool expired = false,
  }) => Session(
    id: id,
    name: name,
    role: role,
    dispatch: dispatch,
    active: !expired && (status ?? this.status) == 'ACTIVE',
    token: expired ? null : token,
    status: status ?? this.status,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    expired: expired,
    expiresAt: expiresAt,
    departmentId: departmentId,
    teamId: teamId,
  );

  /// Uses the server's public identity; an absent status never grants access.
  factory Session.fromRecord(
    Record record, {
    String? token,
    DateTime? expiresAt,
  }) {
    final f = record.fields;
    final state = '${f['status'] ?? 'UNKNOWN'}';
    return Session(
      id: record.id,
      name: record.title,
      role: switch ('${f['role']}'.toUpperCase()) {
        'ADMIN' => UserRole.admin,
        'FOUNDER' => UserRole.founder,
        'DIRECTOR' => UserRole.director,
        'LEADER' => UserRole.leader,
        _ => UserRole.employee,
      },
      active: state == 'ACTIVE',
      status: state,
      dispatch: f['dispatch_enabled'] == true,
      mustChangePassword: f['must_change_password'] == true,
      token: token ?? f['accessToken'] as String?,
      expiresAt: expiresAt ?? DateTime.tryParse('${f['expiresAt'] ?? ''}'),
      departmentId: f['department_id'] as String?,
      teamId: f['team_id'] as String?,
    );
  }
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

/// Account-scoped UI lookup key; this is never a server note UUID or object ID.
class PrivateNoteTarget {
  const PrivateNoteTarget(this.resource, this.objectId, this.accountId);
  final String resource, objectId, accountId;
  String get key => '$resource:$objectId:$accountId';
  bool get supported => resource == 'tasks' || resource == 'dashboard/company';
  static PrivateNoteTarget? parse(String key) {
    final parts = key.split(':');
    if (parts.length != 3 || parts.any((part) => part.trim().isEmpty)) {
      return null;
    }
    return PrivateNoteTarget(parts[0], parts[1], parts[2]);
  }
}

class PageResult {
  const PageResult(this.items, {this.total = 0, this.nextCursor});
  final List<Record> items;
  final int total;
  final String? nextCursor;
}

enum MemberLogDayStatus { submitted, missing, future, unknown }

class MemberLogMonth {
  const MemberLogMonth({
    required this.ownerId,
    required this.month,
    required this.days,
    this.employmentStartDate,
  });

  final String ownerId;
  final DateTime month;
  final DateTime? employmentStartDate;
  final Map<int, MemberLogDayStatus> days;

  factory MemberLogMonth.fromJson(Map<String, dynamic> json) {
    final rawDays = Map<String, dynamic>.from(json['days'] as Map? ?? {});
    final days = <int, MemberLogDayStatus>{};
    for (final entry in rawDays.entries) {
      final day = int.tryParse(entry.key);
      if (day == null) continue;
      days[day] = switch ('${entry.value}'.toUpperCase()) {
        'SUBMITTED' => MemberLogDayStatus.submitted,
        'MISSING' => MemberLogDayStatus.missing,
        'FUTURE' => MemberLogDayStatus.future,
        _ => MemberLogDayStatus.unknown,
      };
    }
    final rawMonth = '${json['month'] ?? ''}';
    return MemberLogMonth(
      ownerId: '${json['ownerId'] ?? ''}',
      month: DateTime.tryParse(
            rawMonth.length == 7 ? '$rawMonth-01' : rawMonth,
          ) ??
          DateTime.now(),
      employmentStartDate: DateTime.tryParse(
        '${json['employmentStartDate'] ?? ''}',
      ),
      days: days,
    );
  }
}

class Query {
  const Query({
    this.search = '',
    this.departmentId,
    this.cursor,
    this.ownerId,
    this.from,
    this.to,
  });
  final String search;
  final String? cursor, ownerId, departmentId;
  final DateTime? from, to;
  Map<String, dynamic> toJson() => {
    'search': search,
    'limit': 30,
    if (cursor != null) 'cursor': cursor,
    if (ownerId != null) 'ownerId': ownerId,
    if (departmentId != null) 'departmentId': departmentId,
    if (from != null) 'from': from!.toUtc().toIso8601String(),
    if (to != null) 'to': to!.toUtc().toIso8601String(),
  };
}

class AnalyticsQuery {
  const AnalyticsQuery({
    required this.date,
    required this.period,
    this.groupBy = 'department',
    this.departmentId,
    this.teamId,
    this.ownerId,
  });
  final DateTime date;
  final String period;
  final String groupBy;
  final String? departmentId, teamId, ownerId;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().split('T').first,
    'period': period,
    'groupBy': groupBy,
    if (departmentId != null) 'departmentId': departmentId,
    if (teamId != null) 'teamId': teamId,
    if (ownerId != null) 'ownerId': ownerId,
  };
}

class AnalyticsDetailsQuery extends AnalyticsQuery {
  const AnalyticsDetailsQuery({
    required super.date,
    required super.period,
    super.groupBy,
    super.departmentId,
    super.teamId,
    super.ownerId,
    required this.metric,
    this.groupId,
    this.bucket,
    this.cursor,
    this.limit = 30,
  });

  final String metric;
  final String? groupId, bucket, cursor;
  final int limit;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'metric': metric,
    if (groupId != null) 'groupId': groupId,
    if (bucket != null) 'bucket': bucket,
    if (cursor != null) 'cursor': cursor,
    'limit': limit,
  };
}

class AnalyticsFilters {
  const AnalyticsFilters({
    this.departmentId = '',
    this.teamId = '',
    this.ownerId = '',
    this.groupBy = 'department',
    this.visibleMetrics = const [
      'dispatched', 'received', 'feedback', 'accepted', 'overdue', 'diarySubmitted',
    ],
  });
  final String departmentId, teamId, ownerId;
  final String groupBy;
  final List<String> visibleMetrics;
  AnalyticsFilters copyWith({
    String? departmentId,
    String? teamId,
    String? ownerId,
    String? groupBy,
    List<String>? visibleMetrics,
  }) => AnalyticsFilters(
    departmentId: departmentId ?? this.departmentId,
    teamId: teamId ?? this.teamId,
    ownerId: ownerId ?? this.ownerId,
    groupBy: groupBy ?? this.groupBy,
    visibleMetrics: visibleMetrics ?? this.visibleMetrics,
  );
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

/// Shanghai wall dates are independent of the phone's timezone.
DateTime shanghaiWallTime(DateTime instant) {
  final shifted = instant.toUtc().add(const Duration(hours: 8));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

/// Server instant strings carry Z/offset; legacy offsetless fixture times are wall time.
DateTime? businessEventTime(dynamic value) {
  final text = '$value', parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc ? shanghaiWallTime(parsed) : parsed;
}

bool isSubmittedDiary(Record record) =>
    record.fields['submitted'] == true ||
    record.fields['submitted'] != false && record.fields['status'] == '已提交';
