import 'dart:convert';
import 'dart:math';
import '../models/models.dart';
import 'draft_store.dart';
import 'secure_values.dart';

String newCalendarCommandKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class CalendarMoveCommand {
  const CalendarMoveCommand({
    required this.taskId,
    required this.version,
    required this.days,
    required this.reason,
    required this.key,
    required this.revision,
    this.reviewId,
  });
  final String taskId, reason, key, revision;
  final String? reviewId;
  final int version, days;
  CalendarMoveCommand reviewed(String id) => CalendarMoveCommand(
    taskId: taskId,
    version: version,
    days: days,
    reason: reason,
    key: key,
    revision: revision,
    reviewId: id,
  );
  Command get command => Command(
    'move-schedule',
    {'id': taskId, 'moveDays': days, 'reason': reason},
    version: version,
    idempotencyKey: key,
    scheduleRevision: revision,
  );
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'version': version,
    'days': days,
    'reason': reason,
    'key': key,
    'revision': revision,
    'reviewId': reviewId,
  };
  factory CalendarMoveCommand.fromJson(Map<String, dynamic> data) =>
      CalendarMoveCommand(
        taskId: data['taskId'] as String,
        version: data['version'] as int,
        days: data['days'] as int,
        reason: data['reason'] as String,
        key: data['key'] as String,
        revision: data['revision'] as String,
        reviewId: data['reviewId'] as String?,
      );
}

/// One encrypted account/company scoped pending command. No credentials or task snapshots.
/// A second intent cannot replace an uncertain command before explicit confirmation.
class CalendarCommandStore {
  CalendarCommandStore(this.drafts);
  final DraftStore drafts;
  DraftLocation _location(Session session) {
    if (session.companyId.isEmpty || session.id.isEmpty) {
      throw const LocalStorageFailure('账号公司信息缺失，不能安全保存改期命令');
    }
    return DraftLocation(
      account: jsonEncode([session.companyId, session.id]),
      kind: 'calendar-move',
      object: 'pending',
    );
  }

  Future<CalendarMoveCommand?> read(Session session) async {
    final draft = await drafts.read(_location(session));
    if (draft == null) return null;
    return CalendarMoveCommand.fromJson(
      Map<String, dynamic>.from(jsonDecode(draft.fields['command']!)),
    );
  }

  Future<void> save(Session session, CalendarMoveCommand command) async {
    final encoded = jsonEncode(command.toJson());
    await drafts.write(
      _location(session),
      LocalDraft(fields: {'command': encoded}, savedAt: DateTime.now()),
    );
    final result = await read(session);
    if (result == null || jsonEncode(result.toJson()) != encoded) {
      throw const LocalStorageFailure('无法确认改期命令已保存，尚未发送');
    }
  }

  Future<void> clear(Session session) => drafts.remove(_location(session));
}
