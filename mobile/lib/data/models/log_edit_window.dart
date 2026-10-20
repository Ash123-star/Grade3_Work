import 'models.dart';

/// Presentation of the first successful submission window. Mock writes enforce
/// the same rule; a real server remains responsible for write authorization.
class LogEditWindow {
  const LogEditWindow(this.record);
  final Record record;
  bool get submitted => isSubmittedDiary(record);
  DateTime? get until {
    final supplied = DateTime.tryParse('${record.fields['editableUntil']}');
    final first = DateTime.tryParse('${record.fields['submittedAt']}');
    return supplied ?? first?.add(const Duration(hours: 24));
  }

  bool canEditAt(DateTime now) {
    if (!submitted) return true;
    if (record.fields['canEdit'] == false) return false;
    final deadline = until;
    return deadline != null && now.isBefore(deadline);
  }
}
