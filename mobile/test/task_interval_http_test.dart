import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

/// 断言任务列表实际发出的 HTTP 参数，而不是只检查 Repository 的入参对象。
class _CaptureAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'items': <dynamic>[], 'total': 0}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  late _CaptureAdapter adapter;
  late HttpRepository repository;

  setUp(() {
    adapter = _CaptureAdapter();
    repository = HttpRepository('http://localhost/api', 'fixture-token');
    repository.dio.httpClientAdapter = adapter;
  });

  test('task calendar request carries real from/to instead of date/period', () async {
    final from = DateTime.utc(2026, 9, 27);
    final to = DateTime.utc(2026, 11, 8);

    await repository.list(
      'tasks',
      Query(from: from, to: to, ownerId: 'member-1', cursor: '30'),
    );

    final request = adapter.requests.single;
    expect(request.path, '/tasks');
    final query = request.uri.queryParameters;
    expect(query['from'], from.toIso8601String());
    expect(query['to'], to.toIso8601String());
    expect(query.containsKey('date'), isFalse);
    expect(query.containsKey('period'), isFalse);
    expect(query['participantId'], 'member-1');
    expect(query.containsKey('ownerId'), isFalse);
    expect(query['cursor'], '30');
    expect(query['limit'], '30');
  });

  test('received card request keeps its own path without a date range', () async {
    await repository.list('tasks/received-card', const Query());

    final request = adapter.requests.single;
    expect(request.path, '/tasks/received-card');
    final query = request.uri.queryParameters;
    expect(query['limit'], '30');
    expect(query.containsKey('from'), isFalse);
    expect(query.containsKey('to'), isFalse);
    expect(query.containsKey('date'), isFalse);
    expect(query.containsKey('period'), isFalse);
  });

  test('task query without a range still falls back to date/period', () async {
    await repository.list('tasks', Query(from: DateTime.utc(2026, 10, 20)));

    final query = adapter.requests.single.uri.queryParameters;
    expect(query['date'], '2026-10-20');
    expect(query['period'], 'day');
    expect(query.containsKey('from'), isFalse);
    expect(query.containsKey('to'), isFalse);
  });
}
