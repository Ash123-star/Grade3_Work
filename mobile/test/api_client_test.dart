import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/sse_client.dart';

/// 可编程的 Dio 适配器：按序返回预置响应或模拟瞬时错误，记录请求次数与头。
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handlers);
  final List<ResponseBody Function(RequestOptions options)> handlers;
  int calls = 0;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler =
        handlers[calls < handlers.length ? calls : handlers.length - 1];
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, String body) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody _transient() => throw DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.connectionError,
);

ResponseBody _status(int code) => throw DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: ''),
    statusCode: code,
  ),
);

ResponseBody _sse(String text) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(text))),
  200,
  headers: {
    Headers.contentTypeHeader: ['text/event-stream'],
  },
);

HttpRepository _repo(FakeAdapter adapter) {
  final repo = HttpRepository('http://x/api', 't');
  repo.dio.httpClientAdapter = adapter;
  return repo;
}

void main() {
  group('retry', () {
    test('GET retries 503 then succeeds within two attempts', () async {
      final adapter = FakeAdapter([
        (o) => _status(503),
        (o) => _status(503),
        (o) => _json(200, '{"items":[],"total":0}'),
      ]);
      final result = await _repo(adapter).list('tasks', const Query());
      expect(adapter.calls, 3);
      expect(result.total, 0);
    });

    test('GET retries transient connection error', () async {
      final adapter = FakeAdapter([
        (o) => _transient(),
        (o) => _json(200, '{"id":"1","title":"t"}'),
      ]);
      final record = await _repo(adapter).detail('tasks', '1');
      expect(adapter.calls, 2);
      expect(record.id, '1');
    });

    test('GET gives up after two retries (three attempts total)', () async {
      final adapter = FakeAdapter([(o) => _status(503)]);
      await expectLater(
        _repo(adapter).list('tasks', const Query()),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.kind,
            'kind',
            FailureKind.unavailable,
          ),
        ),
      );
      expect(adapter.calls, 3);
    });

    test('GET does not retry 4xx', () async {
      final adapter = FakeAdapter([(o) => _status(403)]);
      await expectLater(
        _repo(adapter).list('tasks', const Query()),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.kind,
            'kind',
            FailureKind.forbidden,
          ),
        ),
      );
      expect(adapter.calls, 1);
    });

    test('POST write is not retried on transient failure', () async {
      final adapter = FakeAdapter([(o) => _transient()]);
      await expectLater(
        _repo(
          adapter,
        ).execute('tasks', const Command('create', {}, idempotencyKey: 'k')),
        throwsA(isA<ApiFailure>()),
      );
      expect(adapter.calls, 1);
    });
  });

  group('sse', () {
    SseClient client(FakeAdapter adapter) {
      final c = SseClient('http://x/api', 't');
      c.dio.httpClientAdapter = adapter;
      return c;
    }

    test('parses multi-line data and multiple fields', () async {
      final adapter = FakeAdapter([
        (o) => _sse('event:notification\nid:5\ndata:line1\ndata:line2\n\n'),
      ]);
      final events = await client(
        adapter,
      ).connect('/notifications/stream').toList();
      expect(events.length, 1);
      expect(events.first.event, 'notification');
      expect(events.first.id, '5');
      expect(events.first.data, 'line1\nline2');
    });

    test('notification stream updates Last-Event-ID on reconnect', () async {
      final adapter = FakeAdapter([
        (o) => _sse('event:notification\nid:7\ndata:a\n\n'),
        (o) => _sse('event:notification\nid:8\ndata:b\n\n'),
      ]);
      final stream = client(adapter).notifications();
      final collected = <ServerEvent>[];
      await for (final e in stream) {
        collected.add(e);
        if (collected.length == 2) break;
      }
      expect(adapter.requests.first.headers['Last-Event-ID'], '0');
      expect(adapter.requests[1].headers['Last-Event-ID'], '7');
    });

    test('ai job stream ends on result event', () async {
      final adapter = FakeAdapter([
        (o) => _sse(
          'event:chunk\ndata:partial\n\nevent:result\ndata:done\n\nevent:extra\ndata:ignored\n\n',
        ),
      ]);
      final events = await client(adapter).aiJob('job1').toList();
      expect(events.map((e) => e.event), ['chunk', 'result']);
    });
  });
}
