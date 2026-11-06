import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/calendar/holiday_data.dart';

Map<String, dynamic> announcement(
  int year, {
  String status = 'FRESH',
  List<Map<String, dynamic>> days = const [],
}) => {'year': year, 'status': status, 'days': days};

Map<String, dynamic> day(String date, bool off) => {
  'date': date,
  'name': '国庆节', // Announcement labels describe the whole vacation period.
  'isOffDay': off,
};

void main() {
  test(
    'National Day is October 1 only, without stars or presumed time off',
    () {
      final calendar = festivalCalendar(2026);
      expect(calendar.days['2026-10-01']!.label, '国庆节');
      expect(calendar.days['2026-10-01']!.off, isNull);
      for (var d = 2; d <= 7; d++) {
        expect(calendar.days['2026-10-0$d'], isNull);
      }
      expect(calendar.days.values.any((d) => d.label.contains('★')), isFalse);
    },
  );

  // Gregorian/lunar conversion reference: Hong Kong Observatory 2024–2026
  // conversion tables (https://www.hko.gov.hk/tc/gts/time/conversion.htm).
  for (final entry in {
    '2024-02-09': '除夕',
    '2024-02-10': '春节',
    '2024-04-04': '清明节',
    '2025-01-28': '除夕',
    '2025-01-29': '春节',
    '2025-04-04': '清明节',
    '2025-05-31': '端午节',
    '2025-10-06': '中秋节',
    '2026-02-16': '除夕',
    '2026-02-17': '春节',
    '2026-04-05': '清明节',
    '2026-06-19': '端午节',
    '2026-09-25': '中秋节',
  }.entries) {
    test('offline reference ${entry.key} ${entry.value}', () {
      final y = int.parse(entry.key.substring(0, 4));
      expect(festivalCalendar(y).days[entry.key]!.name, entry.value);
    });
  }

  test(
    'coincident festivals retain both names, leap month does not repeat',
    () {
      expect(festivalCalendar(2020).days['2020-10-01']!.name, '国庆节·中秋节');
      final calendar = festivalCalendar(2009);
      expect(calendar.days['2009-05-28']!.name, '端午节');
      expect(
        calendar.days['2009-06-27'],
        isNull,
      ); // Leap fifth month, day five.
      expect(
        calendar.days.entries.where(
          (e) => e.key.startsWith('2009-') && e.value.name.contains('端午节'),
        ),
        hasLength(1),
      );
    },
  );

  test('adjacent years and supported bounds are deterministic', () {
    expect(festivalCalendar(2026).days['2027-01-01']!.name, '元旦');
    expect(festivalCalendar(2027).days['2026-12-31'], isNull);
    for (final year in [1900, 2100]) {
      expect(festivalCalendar(year).days['$year-10-01']!.name, '国庆节');
    }
    for (final year in [1899, 2101]) {
      expect(festivalCalendar(year).days, isEmpty);
      expect(festivalCalendar(year).warning, contains('1900至2100'));
    }
  });

  test(
    'online vacation never repeats festival names; cache survives reload',
    () async {
      final cache = <int, String>{};
      final outputs = await loadHolidayCalendar(
        2026,
        readCache: (y) async => cache[y],
        writeCache: (y, value) async {
          cache[y] = value;
        },
        fetchYear: (y) async => announcement(
          y,
          days: y == 2026
              ? [
                  for (var d = 1; d <= 7; d++) day('2026-10-0$d', true),
                  day('2026-10-10', false),
                ]
              : [],
        ),
      ).toList();
      final online = outputs.last;
      expect(online.warning, isEmpty);
      expect(online.days['2026-10-01']!.name, '国庆节');
      expect(online.days['2026-10-02']!.label, isEmpty);
      expect(online.days['2026-10-02']!.arrangementLabel, '休');
      expect(online.days['2026-10-10']!.arrangementLabel, '班');
      expect(cache.length, 3);
      final offline = await loadHolidayCalendar(
        2026,
        readCache: (y) async => cache[y],
        writeCache: (_, _) async =>
            fail('Failed fetch must not overwrite cache'),
        fetchYear: (_) async => throw StateError('offline'),
      ).last;
      expect(offline.days['2026-10-02']!.off, isTrue);
      expect(offline.days['2026-10-10']!.off, isFalse);
      expect(offline.days['2026-10-10']!.arrangementSource, contains('本地缓存'));
      expect(offline.warning, contains('缓存'));
    },
  );

  test(
    'first offline launch and damaged cache retain exact festival dates',
    () async {
      final offline = await loadHolidayCalendar(
        2026,
        readCache: (_) async => '{broken JSON',
        writeCache: (_, _) async {},
        fetchYear: (_) async => throw StateError('offline'),
      ).last;
      expect(offline.days['2026-02-17']!.name, '春节');
      expect(offline.days['2026-10-01']!.off, isNull);
      expect(offline.days['2026-10-02'], isNull);
      expect(offline.warning, contains('暂无放假调休信息'));
    },
  );

  test('offline snapshot is emitted before a slow network responds', () async {
    final pending = Completer<Map<String, dynamic>>();
    final stream = StreamIterator(
      loadHolidayCalendar(
        2026,
        readCache: (_) async => null,
        writeCache: (_, _) async {},
        fetchYear: (y) async => y == 2026 ? pending.future : announcement(y),
      ),
    );
    expect(await stream.moveNext(), isTrue);
    expect(pending.isCompleted, isFalse);
    expect(stream.current.days['2026-09-25']!.name, '中秋节');
    final next = stream.moveNext();
    pending.complete(announcement(2026));
    expect(await next, isTrue);
    expect(stream.current.warning, isEmpty);
    await stream.cancel();
  });

  test(
    'bad network snapshots preserve cached arrangements, valid years update',
    () async {
      for (final bad in [
        announcement(2025), // Incorrect source year.
        announcement(2026, days: [day('2026-02-30', true)]),
        announcement(
          2026,
          days: [day('2026-10-01', true), day('2026-10-01', false)],
        ),
        announcement(2026, days: [day('2027-01-01', true)]),
        announcement(2026, status: 'UNAVAILABLE'),
      ]) {
        final calendar = await loadHolidayCalendar(
          2026,
          readCache: (y) async => y == 2026
              ? jsonEncode(announcement(2026, days: [day('2026-10-10', false)]))
              : null,
          writeCache: (y, _) async {
            expect(y, isNot(2026));
          },
          fetchYear: (y) async => y == 2026 ? bad : announcement(y),
        ).last;
        expect(calendar.days['2026-10-10']!.off, isFalse);
        expect(calendar.days['2026-10-01']!.name, '国庆节');
        expect(calendar.warning, contains('未更新'));
      }
    },
  );

  test(
    'storage failures retain network data and STALE stays explicitly stale',
    () async {
      final calendar = await loadHolidayCalendar(
        2026,
        readCache: (_) async => throw StateError('disk unavailable'),
        writeCache: (_, _) async => throw StateError('disk full'),
        fetchYear: (y) async => announcement(
          y,
          status: 'STALE',
          days: y == 2026 ? [day('2026-10-02', true)] : [],
        ),
      ).last;
      expect(calendar.days['2026-10-02']!.off, isTrue);
      expect(calendar.days['2026-10-02']!.arrangementSource, contains('服务端缓存'));
      expect(calendar.warning, contains('未更新'));
    },
  );

  test(
    'next announcement includes previous December; unsupported years never fetch',
    () async {
      final calendar = await loadHolidayCalendar(
        2026,
        readCache: (_) async => null,
        writeCache: (_, _) async {},
        fetchYear: (y) async =>
            announcement(y, days: y == 2027 ? [day('2026-12-31', true)] : []),
      ).last;
      expect(calendar.days['2026-12-31']!.name, isEmpty);
      expect(calendar.days['2026-12-31']!.off, isTrue);
      for (final y in [1899, 2101]) {
        final result = await loadHolidayCalendar(
          y,
          readCache: (_) async => fail('No read for unsupported year'),
          writeCache: (_, _) async => fail('No write for unsupported year'),
          fetchYear: (_) async => fail('No fetch for unsupported year'),
        ).last;
        expect(result.days, isEmpty);
      }
    },
  );
}
