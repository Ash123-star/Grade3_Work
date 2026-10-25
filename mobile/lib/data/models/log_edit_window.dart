import 'models.dart';

bool canInitiallySubmitDiaryOn(DateTime businessDate, {DateTime? now}) {
  final shanghaiNow = (now ?? DateTime.now()).toUtc().add(
    const Duration(hours: 8),
  );
  final today = DateTime.utc(shanghaiNow.year, shanghaiNow.month, shanghaiNow.day);
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
  DateTime? get until {
    final supplied = DateTime.tryParse('${record.fields['editableUntil']}');
    final first = DateTime.tryParse('${record.fields['submittedAt']}');
    return supplied ?? first?.add(const Duration(hours: 24));
  }

  bool canEditAt(DateTime now) {
    if (record.fields['canEdit'] == false) return false;
    if (!submitted && until == null) return true;
    final deadline = until;
    return deadline != null && now.isBefore(deadline);
  }
}
