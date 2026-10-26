import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class _NoopAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(request);
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('diary detail has no read-receipt command or read-state mutation', () async {
    final store = DemoStore()
      ..records['logs'] = [
        const Record(
          id: 'submitted',
          title: '工作日志',
          ownerId: 'u1',
          version: 3,
          fields: {'status': '已提交', '今日工作': '保留正文'},
        ),
      ];
    final repository = MockRepository(const Session(id: 'u1'), store: store);

    await expectLater(
      repository.execute('logs', const Command('read', {'id': 'submitted'})),
      throwsA(isA<ApiFailure>()),
    );
    final detail = await repository.detail('logs', 'submitted');
    expect(detail.version, 3);
    expect(detail.fields['今日工作'], '保留正文');
    expect(detail.fields.containsKey('readBy'), isFalse);
    expect(detail.fields.containsKey('readAt'), isFalse);
  });

  test('HTTP read-receipt action is rejected before any request is sent', () async {
    final adapter = _NoopAdapter();
    final repository = HttpRepository('http://localhost/api', 'session');
    repository.dio.httpClientAdapter = adapter;

    await expectLater(
      repository.execute('logs', const Command('read', {'id': 'log-1'})),
      throwsA(isA<ApiFailure>()),
    );
    expect(adapter.requests, isEmpty);
  });
}
