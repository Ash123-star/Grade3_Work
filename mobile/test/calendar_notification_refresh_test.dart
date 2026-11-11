import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'live_notifications_contract_test.dart'
    show LiveAdapter, event, liveRepo;
import 'support/local_test_state.dart';

class CalendarLiveAdapter extends LiveAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    if (options.path == '/tasks') {
      requests.add(options);
      return ResponseBody.fromString(
        '{"items":[],"total":0,"snapshotToken":"stable"}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return super.fetch(options, body, cancel);
  }
}

void main() {
  testWidgets(
    'calendar mounted during an SSE burst reads each active month only once',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = CalendarLiveAdapter();
      final repo = liveRepo(adapter);
      addTearDown(() => repo.dio.close(force: true));
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith(
            (_) => const Session(token: 'live-token'),
          ),
          repositoryProvider.overrideWithValue(repo),
          selectedDateProvider.overrideWith((_) => DateTime(2026, 11, 2)),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        OwnedTestProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: CalendarContent(availableHeight: 650)),
          ),
        ),
      );
      await settleLocalIo(t);
      final before = adapter.requests.where((r) => r.path == '/tasks').length;
      expect(before, greaterThan(0));
      expect(adapter.streams, hasLength(1));
      adapter.send(event(1) + event(2) + event(3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(
        adapter.requests.where((r) => r.path == '/tasks').length,
        before,
        reason:
            'surface listener must not perform an immediate second global refresh',
      );
      await t.pump(const Duration(seconds: 2));
      await settleLocalIo(t);
      final reads = adapter.requests.where((r) => r.path == '/tasks').toList();
      final refreshed = reads.skip(before).toList();
      expect(refreshed, isNotEmpty);
      expect(
        refreshed.map((r) => r.queryParameters.toString()).toSet().length,
        refreshed.length,
        reason:
            'each still-mounted month refreshes once; retained offscreen months stay lazy',
      );
      expect(
        refreshed
            .where((r) => r.queryParameters.containsKey('from'))
            .every((r) => r.queryParameters['limit'] == 100),
        isTrue,
        reason: refreshed.map((r) => r.queryParameters).toString(),
      );
      adapter.send(event(3) + event(2));
      await settleLocalIo(t);
      expect(
        adapter.requests.where((r) => r.path == '/tasks').length,
        reads.length,
      );
    },
    skip: AppConfig.mock,
  );
}
