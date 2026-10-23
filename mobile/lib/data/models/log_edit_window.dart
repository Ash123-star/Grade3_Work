import 'models.dart';

/// Presentation only: every mutation must still be authorized by the server.
/// A withdrawn diary retains its original submission deadline.
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

  bool canWithdrawAt(DateTime now) =>
      isSubmittedDiary(record) &&
      record.fields['canWithdraw'] == true &&
      _open(now);
}
