import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

/// 断言任务列表实际发出的 HTTP 参数，而不是只检查 Repository 的入参对象。
class _CaptureAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, dynamic> response = {'items': <dynamic>[], 'total': 0};

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
      jsonEncode(response),
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

  test('task creation submits selected server label ID and idempotency key', () async {
    adapter.response = {'id': 'review-1', 'status': 'PENDING', 'expected_version': 0};
    await repository.execute(
      'tasks',
      const Command('create', {
        '任务名称': '演示任务',
        'participantIds': ['member-1'],
        'deadline': '2026-11-01T10:00:00Z',
        'tagId': 'current-label-id',
      }, idempotencyKey: 'create-demo-1'),
    );
    final request = adapter.requests.single;
    expect(request.path, '/tasks');
    expect(request.method, 'POST');
    expect(request.headers['Idempotency-Key'], 'create-demo-1');
    expect((request.data as Map)['labelIds'], ['current-label-id']);
  });

  test(
    'list completion uses canonical lifecycle and retains missing dispatch',
    () async {
      for (final entry in <String?, String>{
        'DISPATCHED': '待接收',
        'RECEIVED': '进行中',
        'FEEDBACK': '待验收',
        'ACCEPTED': '已验收',
        'ARCHIVED': '已归档',
        'WITHDRAWN': '已撤回',
        'FUTURE_PHASE': '情况未知',
        null: '情况未知',
      }.entries) {
        adapter.response = {
          'items': [
            {
              'id': 'task-completion',
              'issuer_id': 'issuer',
              'title': '真实任务',
              'phase': entry.key,
              'created_at': '2026-10-01T00:00:00Z',
              'dispatchAt': null,
              'fields': {'status': '已验收'},
            },
          ],
          'total': 1,
        };
        final task = (await repository.list(
          'tasks',
          const Query(),
        )).items.single;
        expect(task.fields['phase'], entry.key);
        expect(task.fields['status'], entry.value);
        expect(task.fields['dispatchAt'], isNull);
      }
    },
  );

  test('creation review decision sends expected version zero', () async {
    adapter.response = {'id': 'review-1', 'status': 'APPROVED', 'expected_version': 0};
    await repository.execute(
      'reviews',
      const Command('approve', {'id': 'review-1'}, version: 0),
    );
    final request = adapter.requests.single;
    expect(request.path, '/reviews/review-1/decision');
    expect(request.method, 'POST');
    expect((request.data as Map)['expectedVersion'], 0);
    expect((request.data as Map)['approve'], isTrue);
  });
}
