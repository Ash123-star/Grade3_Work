import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';

class HolidayDay {
  const HolidayDay(this.name, this.off);
  final String name;
  final bool off;
  String get label => off ? '★ $name' : '★ $name·调休上班';
}

class HolidayCalendar {
  const HolidayCalendar(this.days, this.warning);
  final Map<String, HolidayDay> days;
  final String warning;
}

String holidayDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
final holidayCalendarProvider = FutureProvider.autoDispose
    .family<HolidayCalendar, int>((ref, year) async {
      if (AppConfig.mock) return const HolidayCalendar({}, '演示模式未加载真实节假日');
      final repository = ref.watch(httpRepositoryProvider);
      final days = <String, HolidayDay>{};
      var unavailable = false;
      // Next year's announcement can include December of the preceding year.
      for (final sourceYear in [year - 1, year, year + 1]) {
        try {
          final response = await repository.dio.get(
            '/calendar/holidays',
            queryParameters: {'year': sourceYear},
          );
          final body = response.data as Map;
          if (body['status'] != 'FRESH') unavailable = true;
          for (final item in body['days'] as List) {
            days[item['date'] as String] = HolidayDay(
              item['name'] as String,
              item['isOffDay'] as bool,
            );
          }
        } catch (_) {
          unavailable = true;
        }
      }
      return HolidayCalendar(days, unavailable ? '部分节假日数据暂不可用或已过期' : '');
    });
