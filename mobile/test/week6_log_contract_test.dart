import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class LogAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(request);
    final body = request.path.endsWith('/comments') && request.method == 'GET'
        ? [
            {
              'id': 'reply',
              'actor_id': 'author',
              'author_name': '周宁',
              'text': '已补充',
              'parent_id': 'parent',
              'created_at': '2026-10-22T09:00:00Z',
            },
          ]
        : request.path.endsWith('/versions')
        ? []
        : {
            'id': 'log-1',
            'version': 4,
            'submitted': request.method == 'GET',
            'owner_id': 'owner',
            'business_date': '2026-10-22',
            'canEdit': false,
            'canWithdraw': false,
            'submittedAt': '2026-10-21T08:00:00Z',
            'body': {'work': '已完成盘点'},
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  test(
    'log capabilities and comment reply identities use server contract',
    () async {
      final adapter = LogAdapter();
      final repository = HttpRepository('http://localhost/api', 'session');
      repository.dio.httpClientAdapter = adapter;
      final log = await repository.detail('logs', 'log-1');
      expect(log.fields['canEdit'], false);
      expect(log.fields['canWithdraw'], false);
      expect(log.fields['submittedAt'], '2026-10-21T08:00:00Z');
      final reply = (log.fields['comments'] as List).single as Map;
      expect(reply['parentId'], 'parent');
      expect(reply['authorName'], '周宁');
      await repository.execute(
        'logs',
        Command('withdraw', {'id': 'log-1', 'reason': '补充材料'}, version: 4),
      );
      expect(adapter.requests.last.path, '/logs/log-1/withdraw');
      expect(adapter.requests.last.data, {'version': 4, 'reason': '补充材料'});
      await repository.execute(
        'logs/comments',
        const Command('comment', {
          'id': 'log-1',
          'text': '已补充',
          'parentId': 'parent',
        }),
      );
      expect(adapter.requests.last.data, {'text': '已补充', 'parentId': 'parent'});
    },
  );

  test(
    'append only comments do not automatically retry a server failure',
    () async {
      final adapter = LogAdapter()..status = 503;
      final repository = HttpRepository('http://localhost/api', 'session');
      repository.dio.httpClientAdapter = adapter;
      await expectLater(
        repository.execute(
          'logs/comments',
          const Command('comment', {'id': 'log-1', 'text': '评论'}),
        ),
        throwsA(anything),
      );
      expect(adapter.requests.length, 1);
    },
  );
}
