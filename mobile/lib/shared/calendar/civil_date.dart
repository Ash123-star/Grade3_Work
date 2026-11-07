/// Shanghai civil dates are values, never local/UTC midnight instants.
DateTime shanghaiToday([DateTime? now]) {
  final date = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime(date.year, date.month, date.day);
}

String civilDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime parseCivilDate(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw const FormatException('无效业务日期');
  }
  final parts = text.split('-').map(int.parse).toList();
  final date = DateTime(parts[0], parts[1], parts[2]);
  if (civilDate(date) != text || date.year < 1900 || date.year > 2100) {
    throw const FormatException('无效业务日期');
  }
  return date;
}

String civilMonth(DateTime date) => civilDate(date).substring(0, 7);

List<DateTime> monthDays(DateTime date) {
  final first = DateTime(date.year, date.month, 1);
  final start = DateTime(date.year, date.month, 2 - first.weekday);
  final count =
      ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
          .ceil() *
      7;
  return List.generate(
    count,
    (i) => DateTime(start.year, start.month, start.day + i),
  );
}
