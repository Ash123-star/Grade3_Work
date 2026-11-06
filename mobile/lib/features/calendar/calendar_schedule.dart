import '../../data/models/models.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _shanghai = () {
  tzdata.initializeTimeZones();
  return tz.getLocation('Asia/Shanghai');
}();
DateTime scheduleWallTime(DateTime value) =>
    tz.TZDateTime.from(value, _shanghai);

DateTime dateLabel(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
int businessDayDelta(DateTime anchor, DateTime target) =>
    dateLabel(target).difference(dateLabel(anchor)).inDays;
String businessDateText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DateTime parseBusinessDate(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw const FormatException('日期格式应为 YYYY-MM-DD');
  }
  final day = DateTime.parse(text);
  if (businessDateText(day) != text || day.year < 1) {
    throw const FormatException('日期无效');
  }
  return day;
}

class CalendarConstraints {
  CalendarConstraints(this.min, this.max, this.revision);
  final DateTime min, max;
  final String revision;
  factory CalendarConstraints.parse(Map<String, dynamic>? json) {
    if (json == null ||
        json['zone'] != 'Asia/Shanghai' ||
        !RegExp(r'^calendar-v\d+-\d{4}$').hasMatch('${json['revision']}')) {
      throw const FormatException('服务端未提供可用排期范围，请刷新');
    }
    final min = parseBusinessDate('${json['minDate']}');
    final max = parseBusinessDate('${json['maxDate']}');
    if (min.isAfter(max)) throw const FormatException('排期范围无效');
    return CalendarConstraints(min, max, json['revision'] as String);
  }
  bool contains(DateTime day) =>
      !dateLabel(day).isBefore(dateLabel(min)) &&
      !dateLabel(day).isAfter(dateLabel(max));
  Map<String, dynamic> toJson() => {
    'zone': 'Asia/Shanghai',
    'minDate': businessDateText(min),
    'maxDate': businessDateText(max),
    'revision': revision,
  };
}

class CalendarSchedule {
  const CalendarSchedule(this.start, this.end);
  final DateTime? start;
  final DateTime end;
  factory CalendarSchedule.fromRecord(Record record) {
    DateTime instant(dynamic raw) {
      final text = '$raw';
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
        throw const FormatException('任务排期缺少时区');
      }
      return DateTime.parse(text).toUtc();
    }

    final raw = record.fields['startAt'] ?? record.fields['start_at'];
    final start = raw == null || '$raw'.isEmpty ? null : instant(raw);
    final end = instant(record.fields['deadline']);
    if (start != null && !start.isBefore(end)) {
      throw const FormatException('开始时间必须早于截止时间');
    }
    return CalendarSchedule(start, end);
  }
  DateTime get firstDay => scheduleWallTime(start ?? end);
  CalendarSchedule move(int days, CalendarConstraints constraints) {
    if (days == 0 || days < -2147483648 || days > 2147483647) {
      throw const FormatException('请选择不同的有效日期');
    }
    DateTime shift(DateTime value) {
      final wall = tz.TZDateTime.from(value, _shanghai);
      final day = DateTime.utc(
        wall.year,
        wall.month,
        wall.day,
      ).add(Duration(days: days));
      final next = tz.TZDateTime(
        _shanghai,
        day.year,
        day.month,
        day.day,
        wall.hour,
        wall.minute,
        wall.second,
        wall.millisecond,
        wall.microsecond,
      );
      if (next.hour != wall.hour ||
          next.minute != wall.minute ||
          next.second != wall.second ||
          next.year < 1 ||
          next.year > 9999) {
        throw const FormatException('移动后无法保持原排期时刻');
      }
      return next.toUtc();
    }

    final moved = CalendarSchedule(
      start == null ? null : shift(start!),
      shift(end),
    );
    if (start != null &&
        moved.end.difference(moved.start!) != end.difference(start!)) {
      throw const FormatException('移动后无法保持原排期时长');
    }
    if (!constraints.contains(scheduleWallTime(moved.end)) ||
        moved.start != null &&
            !constraints.contains(scheduleWallTime(moved.start!))) {
      throw const FormatException('新排期超出支持范围');
    }
    return moved;
  }

  String get description {
    String format(DateTime value) {
      final wall = scheduleWallTime(value);
      return '${businessDateText(wall)} ${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
    }

    return '${start == null ? '' : '${format(start!)} → '}${format(end)}';
  }
}
