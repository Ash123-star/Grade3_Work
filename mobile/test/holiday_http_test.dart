import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/calendar/holiday_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HolidayAdapter implements HttpClientAdapter {
  bool offline = false;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final year = options.queryParameters['year'];
    return ResponseBody.fromString(
      jsonEncode({
        'year': year,
        'status': 'FRESH',
        'papers': ['https://www.gov.cn/'],
        'fetchedAt': '2026-11-05T00:00:00Z',
        'days': year == 2026
            ? [
                {'date': '2026-10-02', 'name': '国庆节', 'isOffDay': true},
                {'date': '2026-10-10', 'name': '国庆节', 'isOffDay': false},
              ]
            : [],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'real provider requests existing API, persists public data, restores and refreshes',
    () async {
      final repository = HttpRepository(
        'https://calendar.invalid/api',
        'synthetic-token',
      );
      final adapter = HolidayAdapter();
      repository.dio.httpClientAdapter = adapter;
      ProviderContainer create() => ProviderContainer(
        overrides: [httpRepositoryProvider.overrideWithValue(repository)],
      );
      final online = create();
      final ready = Completer<HolidayCalendar>();
      final subscription = online.listen(holidayCalendarProvider(2026), (
        _,
        next,
      ) {
        final value = next.valueOrNull;
        if (value != null && value.warning.isEmpty && !ready.isCompleted) {
          ready.complete(value);
        }
      });
      final result = await ready.future.timeout(const Duration(seconds: 10));
      expect(result.days['2026-10-02']!.name, isEmpty);
      expect(result.days['2026-10-10']!.off, isFalse);
      expect(adapter.requests.map((r) => r.path).toSet(), {
        '/calendar/holidays',
      });
      expect(adapter.requests.map((r) => r.queryParameters['year']).toSet(), {
        2025,
        2026,
        2027,
      });
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(
        'calendar.official-holidays.v1.2026',
      )!;
      expect(saved, contains('2026-10-10'));
      expect(saved, isNot(contains('synthetic-token')));
      subscription.close();
      online.dispose();

      adapter.offline = true;
      final offline = create(); // Simulate a new app/provider session.
      addTearDown(offline.dispose);
      final restored = Completer<HolidayCalendar>();
      final refreshed = Completer<HolidayCalendar>();
      offline.listen(holidayCalendarProvider(2026), (_, next) {
        final value = next.valueOrNull;
        if (value == null) return;
        if (value.warning.contains('未更新') && !restored.isCompleted) {
          restored.complete(value);
        }
        if (value.warning.isEmpty && !refreshed.isCompleted) {
          refreshed.complete(value);
        }
      });
      final cached = await restored.future.timeout(const Duration(seconds: 10));
      expect(cached.days['2026-10-02']!.arrangementSource, contains('本地缓存'));
      expect(cached.days['2026-02-17']!.name, '春节');
      adapter.offline = false;
      offline.invalidate(holidayCalendarProvider(2026));
      final updated = await refreshed.future.timeout(
        const Duration(seconds: 10),
      );
      expect(updated.days['2026-10-02']!.arrangementSource, '联网公告');
      expect(adapter.requests, hasLength(9));
    },
  );
}
