/// 工龄展示：只用服务端 employmentStartDate，不从注册时间推测。
/// [today] 为上海业务日期；入职日期为空或晚于今天返回“未提供”。
String tenureLabel(DateTime? start, DateTime today) {
  if (start == null) return '未提供';
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(today.year, today.month, today.day);
  if (from.isAfter(to)) return '未提供';
  var months = (to.year - from.year) * 12 + to.month - from.month;
  // 未到当月入职日不计满月；月末入职（如 1 月 31 日）在短月最后一天计满。
  final lastDay = DateTime(to.year, to.month + 1, 0).day;
  if (to.day < from.day && to.day != lastDay) months--;
  if (months < 1) return '不满1个月';
  final years = months ~/ 12, rest = months % 12;
  if (years == 0) return '$rest个月';
  return rest == 0 ? '$years年' : '$years年$rest个月';
}

DateTime? parseEmploymentDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// 入职日期显示为 yyyy-MM-dd；无值返回“未提供”。
String employmentDateLabel(Object? value) {
  final date = parseEmploymentDate(value);
  if (date == null) return '未提供';
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
