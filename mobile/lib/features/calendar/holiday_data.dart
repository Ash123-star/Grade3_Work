import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunar/lunar.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Festival names and administrative vacation arrangements are separate facts.
class HolidayDay {
  const HolidayDay(this.name, [this.off, this.arrangementSource = '']);
  final String name;
  final bool? off;
  final String arrangementSource;
  String get label => name;
  String get arrangementLabel => off == null ? '' : (off! ? '休' : '班');
}

class HolidayCalendar {
  const HolidayCalendar(this.days, this.warning);
  final Map<String, HolidayDay> days;
  final String warning;
}

String holidayDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// No network or device clock: the month grid also needs adjacent-year dates.
HolidayCalendar festivalCalendar(int year) {
  if (year < 1900 || year > 2100) {
    return const HolidayCalendar({}, '节日计算支持1900至2100年');
  }
  final days = <String, HolidayDay>{};
  void add(Solar date, String name) {
    if (date.getYear() < 1900 || date.getYear() > 2100) return;
    final key = date.toYmd();
    final previous = days[key];
    days[key] = HolidayDay(previous == null ? name : '${previous.name}·$name');
  }

  for (final y in [year - 1, year, year + 1]) {
    if (y < 1900 || y > 2100) continue;
    add(Solar.fromYmd(y, 1, 1), '元旦');
    add(Solar.fromYmd(y, 5, 1), '劳动节');
    add(Solar.fromYmd(y, 10, 1), '国庆节');
    final spring = Lunar.fromYmd(y, 1, 1);
    add(spring.getSolar(), '春节');
    // Lunar December can have 29 or 30 days; New Year's Eve is not fixed.
    add(spring.getSolar().next(-1), '除夕');
    // Positive months exclude the leap fifth/eighth month's duplicate dates.
    add(Lunar.fromYmd(y, 5, 5).getSolar(), '端午节');
    add(Lunar.fromYmd(y, 8, 15).getSolar(), '中秋节');
    add(spring.getJieQiTable()['清明']!, '清明节');
  }
  return HolidayCalendar(Map.unmodifiable(days), '');
}

typedef HolidayYearFetch = Future<Map<String, dynamic>> Function(int year);
typedef HolidayCacheRead = Future<String?> Function(int year);
typedef HolidayCacheWrite = Future<void> Function(int year, String value);

Map<String, bool> _arrangements(Map<String, dynamic> body, int year) {
  if (body['year'] != year ||
      !['FRESH', 'STALE'].contains(body['status']) ||
      body['days'] is! List ||
      (body['days'] as List).length > 400) {
    throw const FormatException('Invalid holiday snapshot');
  }
  final days = <String, bool>{};
  for (final item in body['days'] as List) {
    if (item is! Map || item['date'] is! String || item['isOffDay'] is! bool) {
      throw const FormatException('Invalid holiday day');
    }
    final key = item['date'] as String;
    final date = DateTime.tryParse(key);
    if (date == null ||
        holidayDateKey(date) != key ||
        !(date.year == year || (date.year == year - 1 && date.month == 12)) ||
        days.containsKey(key)) {
      throw const FormatException('Invalid holiday date');
    }
    days[key] = item['isOffDay'] as bool;
  }
  return days;
}

/// Emit offline festivals immediately, then durable cache, then online updates.
/// Public announcements contain no account data. Failed writes/reads are optional.
Stream<HolidayCalendar> loadHolidayCalendar(
  int year, {
  required HolidayYearFetch fetchYear,
  required HolidayCacheRead readCache,
  required HolidayCacheWrite writeCache,
}) async* {
  final local = festivalCalendar(year);
  if (local.warning.isNotEmpty) {
    yield local;
    return;
  }
  yield HolidayCalendar(local.days, '节日已离线计算，放假调休更新中');
  final years = [
    year - 1,
    year,
    year + 1,
  ].where((y) => y >= 2007 && y <= 2100).toList();
  final snapshots = <int, Map<String, bool>>{};
  final sources = <int, String>{};
  HolidayCalendar merge(String warning) {
    final days = {...local.days};
    // Later announcements may include December of the previous year.
    for (final y in years) {
      for (final entry in (snapshots[y] ?? <String, bool>{}).entries) {
        days[entry.key] = HolidayDay(
          days[entry.key]?.name ?? '',
          entry.value,
          sources[y]!,
        );
      }
    }
    return HolidayCalendar(Map.unmodifiable(days), warning);
  }

  for (final y in years) {
    try {
      final saved = await readCache(y);
      if (saved == null) continue;
      snapshots[y] = _arrangements(
        Map<String, dynamic>.from(jsonDecode(saved) as Map),
        y,
      );
      sources[y] = '本地缓存，联网后更新';
    } catch (_) {
      // Corrupt/unavailable storage cannot suppress offline festivals.
    }
  }
  if (snapshots.isNotEmpty) yield merge('放假调休使用缓存，正在联网更新');
  final results = await Future.wait([
    for (final y in years)
      () async {
        try {
          final body = await fetchYear(y);
          final days = _arrangements(body, y);
          return (year: y, body: body, days: days);
        } catch (_) {
          return null;
        }
      }(),
  ]);
  var fresh = 0;
  for (final result in results) {
    if (result == null) continue;
    snapshots[result.year] = result.days;
    final isFresh = result.body['status'] == 'FRESH';
    if (isFresh) fresh++;
    sources[result.year] = isFresh ? '联网公告' : '服务端缓存，更新暂不可用';
    try {
      await writeCache(result.year, jsonEncode(result.body));
    } catch (_) {
      // Keep successful network data even when the local disk is unavailable.
    }
  }
  yield merge(
    years.isNotEmpty && fresh == years.length
        ? ''
        : snapshots.isEmpty
        ? '节日已离线计算，暂无放假调休信息'
        : '部分放假调休信息未更新，已有安排来自公告或缓存',
  );
}

final holidayCalendarProvider = StreamProvider.autoDispose
    .family<HolidayCalendar, int>((ref, year) {
      if (AppConfig.mock) {
        return Stream.value(
          HolidayCalendar(festivalCalendar(year).days, '离线节日，演示模式不加载放假调休'),
        );
      }
      final repository = ref.watch(httpRepositoryProvider);
      String cacheKey(int y) => 'calendar.official-holidays.v1.$y';
      return loadHolidayCalendar(
        year,
        fetchYear: (y) async {
          final response = await repository.dio.get(
            '/calendar/holidays',
            queryParameters: {'year': y},
            options: Options(receiveTimeout: const Duration(seconds: 8)),
          );
          return Map<String, dynamic>.from(response.data as Map);
        },
        readCache: (y) async =>
            (await SharedPreferences.getInstance()).getString(cacheKey(y)),
        writeCache: (y, value) async {
          await (await SharedPreferences.getInstance()).setString(
            cacheKey(y),
            value,
          );
        },
      );
    });
