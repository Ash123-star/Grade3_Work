import 'models.dart';

/// Presentation only: every mutation must still be authorized by the server.
/// The first submission deadline is immutable.

bool canInitiallySubmitDiaryOn(DateTime businessDate, {DateTime? now}) {
  final shanghaiNow = (now ?? DateTime.now()).toUtc().add(
    const Duration(hours: 8),
  );
  final today = DateTime.utc(
    shanghaiNow.year,
    shanghaiNow.month,
    shanghaiNow.day,
  );
  final selected = DateTime.utc(
    businessDate.year,
    businessDate.month,
    businessDate.day,
  );
  final daysAgo = today.difference(selected).inDays;
  return daysAgo >= 0 && daysAgo <= 2;
}

/// Resolves the first successful submission window for UI behavior.
/// Mock writes enforce it; the matching HTTP endpoint must enforce it server-side.
class LogEditWindow {
  const LogEditWindow(this.record);
  final Record record;
  bool get submitted => isSubmittedDiary(record);

  DateTime? get until =>
      DateTime.tryParse('${record.fields['editableUntil']}') ??
      DateTime.tryParse(
        '${record.fields['submittedAt']}',
      )?.add(const Duration(hours: 24));

  bool _open(DateTime now) {
    final deadline = until;
    if (deadline != null) return now.isBefore(deadline);
    return !isSubmittedDiary(record) &&
        record.fields['submittedAt'] == null &&
        record.fields['editableUntil'] == null;
  }

  bool canEditAt(DateTime now) =>
      record.fields['canEdit'] != false && _open(now);
}
