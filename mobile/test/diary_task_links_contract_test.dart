import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class _DiaryBodyAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(request);
    return ResponseBody.fromString(
      jsonEncode({'id': 'log-draft', 'title': '工作日志', 'version': 2}),
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
  test('diary draft contract sends only the 今日工作正文', () async {
    final adapter = _DiaryBodyAdapter();
    final repository = HttpRepository('http://localhost/api', 'session');
    repository.dio.httpClientAdapter = adapter;

    await repository.execute(
      'logs',
      const Command('save-draft', {
        'id': 'log-draft',
        'businessDate': '2026-10-22',
        '今日工作': '完成了本日交付',
        '遇到的阻碍': '不得发送',
        '明日计划': '不得发送',
        '工时': 8,
        '关联任务': 'task-1,task-2',
      }, version: 1),
    );

    expect(adapter.requests.single.method, 'PUT');
    expect(adapter.requests.single.path, '/logs/draft');
    expect(adapter.requests.single.data, {
      'businessDate': '2026-10-22',
      'body': {'work': '完成了本日交付'},
      'version': 1,
    });
  });
  test(
    'diary selected tasks reach both draft and content update contracts',
    () async {
      final adapter = _DiaryBodyAdapter();
      final repository = HttpRepository('http://localhost/api', 'session');
      repository.dio.httpClientAdapter = adapter;
      for (final action in ['save-draft', 'update-content']) {
        await repository.execute(
          'logs',
          Command(action, {
            'id': 'log-draft',
            'businessDate': '2026-11-17',
            '今日工作': '处理任务',
            'taskIds': ['task-1', 'task-2'],
          }, version: 1),
        );
      }
      expect((adapter.requests.first.data as Map)['body'], {
        'work': '处理任务',
        'taskIds': ['task-1', 'task-2'],
      });
      expect(adapter.requests.last.path, '/logs/log-draft/content');
      expect(adapter.requests.last.data, {
        'work': '处理任务',
        'version': 1,
        'taskIds': ['task-1', 'task-2'],
      });
    },
  );
}
