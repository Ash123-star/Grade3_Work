/// 工龄展示：只用服务端 employmentStartDate，不从注册时间推测。
/// [today] 为上海业务日期；入职日期为空或晚于今天返回“未提供”。
String tenureLabel(DateTime? start, DateTime today) {
  if (start == null) return '未提供';
  final from = DateTime.utc(start.year, start.month, start.day);
  final to = DateTime.utc(today.year, today.month, today.day);
  if (from.isAfter(to)) return '未提供';
  DateTime anniversary(int months) {
    final month = DateTime.utc(from.year, from.month + months);
    final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
    return DateTime.utc(
      month.year,
      month.month,
      from.day > lastDay ? lastDay : from.day,
    );
  }

  var months = (to.year - from.year) * 12 + to.month - from.month;
  if (anniversary(months).isAfter(to)) months--;
  final days = to.difference(anniversary(months)).inDays;
  return '${months ~/ 12}年${months % 12}个月$days天';
}

DateTime? parseEmploymentDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year != int.parse(value.substring(0, 4)) ||
      date.month != int.parse(value.substring(5, 7)) ||
      date.day != int.parse(value.substring(8, 10))) {
    return null;
  }
  return date;
}

/// 入职日期显示为 yyyy-MM-dd；无值返回“未提供”。
String employmentDateLabel(Object? value) {
  final date = parseEmploymentDate(value);
  if (date == null) return '未提供';
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
