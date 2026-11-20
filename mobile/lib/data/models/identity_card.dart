/// Local format validation; the server remains authoritative. Not real-name verification.
String? identityCardError(String input, {DateTime? now}) {
  final card = input.trim().toUpperCase();
  if (!RegExp(r'^[0-9]{17}[0-9X]$').hasMatch(card)) return '请输入18位身份证号';
  final y = int.parse(card.substring(6, 10)),
      m = int.parse(card.substring(10, 12)),
      d = int.parse(card.substring(12, 14));
  final birth = DateTime.utc(y, m, d);
  final today = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  if (y < 1900 ||
      birth.year != y ||
      birth.month != m ||
      birth.day != d ||
      birth.isAfter(DateTime.utc(today.year, today.month, today.day))) {
    return '身份证号出生日期无效';
  }
  const weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += int.parse(card[i]) * weights[i];
  }
  if (card[17] != '10X98765432'[sum % 11]) return '身份证号校验位无效';
  return null;
}

int? identityCardAge(String input, {DateTime? now}) {
  if (identityCardError(input, now: now) != null) return null;
  final card = input.trim();
  final y = int.parse(card.substring(6, 10)),
      m = int.parse(card.substring(10, 12)),
      d = int.parse(card.substring(12, 14));
  final today = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return today.year -
      y -
      ((today.month < m || today.month == m && today.day < d) ? 1 : 0);
}
