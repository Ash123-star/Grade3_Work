import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class NotificationPageAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final entered = Completer<void>();
  Completer<void>? gate;
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return ResponseBody.fromString(
      status == 304
          ? ''
          : jsonEncode(
              status == 200
                  ? {
                      'items': [
                        {
                          'id': 'notice',
                          'recipient_id': 'owner',
                          'type': 'TASK_ASSIGNED',
                          'summary': '当前授权任务',
                          'is_read': false,
                        },
                      ],
                      'total': 1,
                      'unread': 1,
                      'nextCursor': null,
                    }
                  : {'code': 'UNAVAILABLE', 'message': '请重试'},
            ),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'etag': ['W/"notice-v1"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late NotificationPageAdapter adapter;
  late HttpRepository repository;

  setUp(() {
    adapter = NotificationPageAdapter();
    repository = HttpRepository('http://notification.test', 'owner-token');
    repository.dio.httpClientAdapter = adapter;
  });
  tearDown(() => repository.dio.close(force: true));

  Future<PageResult> read([Query query = const Query()]) => repository
      .list('notifications', query)
      .timeout(const Duration(seconds: 2));

  test(
    'notification request completes and a 304 reuses its cached page',
    () async {
      final first = await read();
      expect(first.unread, 1);
      expect(first.items.single.fields['summary'], '当前授权任务');
      adapter.status = 304;
      expect(await read(), same(first));
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.headers['If-None-Match'], 'W/"notice-v1"');
    },
  );

  test(
    'concurrent identical reads share one request and finish together',
    () async {
      adapter.gate = Completer<void>();
      final first = read();
      final second = read();
      await adapter.entered.future.timeout(const Duration(seconds: 2));
      expect(adapter.requests, hasLength(1));
      adapter.gate!.complete();
      final pages = await Future.wait([first, second]);
      expect(pages.last, same(pages.first));
    },
  );

  test('failed notification requests finish and allow a later retry', () async {
    adapter.status = 503;
    await expectLater(read(), throwsA(isA<ApiFailure>()));
    adapter.status = 200;
    expect((await read()).total, 1);
    expect(adapter.requests, hasLength(2));
  });

  test(
    'filters and accounts keep independent notification validators',
    () async {
      await read();
      await read(const Query(notificationCategory: '任务', unreadOnly: true));
      expect(adapter.requests.last.headers['If-None-Match'], isNull);
      expect(adapter.requests.last.queryParameters['category'], '任务');
      expect(adapter.requests.last.queryParameters['unreadOnly'], true);
      final other = HttpRepository('http://notification.test', 'other-token');
      other.dio.httpClientAdapter = adapter;
      addTearDown(() => other.dio.close(force: true));
      await other
          .list('notifications', const Query())
          .timeout(const Duration(seconds: 2));
      expect(adapter.requests.last.headers['If-None-Match'], isNull);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer other-token',
      );
    },
  );
}
