import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/repositories/ai_work_repository.dart';

Map<String, dynamic> record({
  String state = 'WAITING_INPUT',
  int version = 1,
}) => {
  'contractVersion': 1,
  'id': 'work',
  'title': '整理交付材料',
  'state': state,
  'version': version,
  'planVersion': 1,
  'eventsCursor': 8,
  'messages': [
    {
      'body': {
        'text': '请根据截图整理',
        'attachmentIds': ['image'],
      },
    },
  ],
  'result': {'summary': '请补充截止时间'},
  'receipts': [],
  'steps': [],
  'plan': {
    'questions': ['这项任务什么时候交？'],
    'actions': [],
  },
};

const capabilities = {
  'contractVersion': 1,
  'enabled': true,
  'configured': true,
  'executionEnabled': false,
  'imageEnabled': true,
  'canCreateTask': true,
  'actions': ['CREATE_TASK', 'CHECK_DELIVERY'],
  'limits': {
    'text': 10000,
    'files': 5,
    'fileBytes': 10485760,
    'totalBytes': 31457280,
    'formats': ['png', 'pdf', 'docx'],
  },
};

class WireRequest {
  WireRequest(this.path, this.method, this.body, this.key, this.match);
  final String path, method;
  final dynamic body;
  final String? key, match;
}

/// 使用真实本地HTTP，验证序列化、错误映射及恢复，不调用模型或正式业务。
class WorkWire {
  late final HttpServer server;
  late final AiWorkRepository repo;
  final requests = <WireRequest>[];
  Object? response = record();
  int status = 200;
  Completer<void>? gate;
  Future<void> start({bool Function()? isCurrent}) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    repo = AiWorkRepository(
      Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:${server.port}',
          headers: {'Authorization': 'Bearer local-contract-test'},
        ),
      ),
      isCurrent: isCurrent,
    );
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      requests.add(
        WireRequest(
          request.uri.toString(),
          request.method,
          raw.isEmpty ? null : jsonDecode(raw),
          request.headers.value('Idempotency-Key'),
          request.headers.value('If-Match'),
        ),
      );
      final data = response, code = status;
      if (gate != null) await gate!.future;
      request.response.statusCode = code;
      request.response.headers.contentType = ContentType.json;
      if (code != 204) request.response.write(jsonEncode(data));
      await request.response.close();
    });
  }

  Future<void> close() async {
    repo.dio.close(force: true);
    await server.close(force: true);
  }
}

void main() {
  test(
    'completed processing never claims failed material checks are handled',
    () {
      for (final entry in {
        'NEEDS_FIX': '需要补充材料',
        'UNVERIFIABLE': '有些内容需核对',
        'STALE': '需要重新检查',
        'PASS': '材料已核对',
      }.entries) {
        final item = WorkItem.fromJson({
          ...record(state: 'SUCCEEDED'),
          'result': {
            'report': {'state': entry.key},
          },
        });
        expect(item.label, entry.value);
      }
      expect(
        WorkItem.fromJson({
          ...record(state: 'SUCCEEDED'),
          'result': {'kind': 'TASK_CREATED'},
        }).label,
        '任务已创建',
      );
      expect(
        WorkItem.fromJson({
          ...record(state: 'SUCCEEDED'),
          'result': {'summary': '已提交，等待验收'},
        }).label,
        '已提交反馈',
      );
    },
  );
  test('DTO recognizes every server state and freezes persisted inputs', () {
    for (final state in WorkItem.states) {
      final item = WorkItem.fromJson(record(state: state));
      expect(item.label, isNotEmpty);
      if (state != 'SUCCEEDED') expect(item.label, isNot('已办妥'));
    }
    expect(const WorkItem({'state': 'UNKNOWN'}).label, '状态暂时无法确认');
    expect(WorkItem.fromJson(record(state: 'CANCEL_REQUESTED')).label, '正在停止');
    final raw = record(), item = WorkItem.fromJson(raw);
    (raw['result'] as Map)['summary'] = '不应污染';
    expect(item.result['summary'], '请补充截止时间');
    expect(() => item.json['version'] = 99, throwsUnsupportedError);
    expect(
      () => (item.json['messages'] as List).clear(),
      throwsUnsupportedError,
    );
  });

  test(
    'real HTTP rejects missing unknown or damaged work data without success',
    () async {
      final wire = WorkWire();
      await wire.start();
      addTearDown(wire.close);
      final invalid = <Object?>[
        null,
        [],
        'upstream unavailable',
        {},
        {...record(), 'contractVersion': 2},
        {...record(), 'id': 'another-work'},
        {...record(), 'version': 1.5},
        {...record(), 'state': 'COMPLETED'},
        {
          ...record(),
          'messages': [null],
        },
        {
          ...record(),
          'messages': [
            {'body': 'damaged'},
          ],
        },
        {
          ...record(),
          'plan': {'questions': 'missing array'},
        },
        {
          ...record(),
          'plan': {
            'actions': [
              {'payload': []},
            ],
          },
        },
        {
          ...record(),
          'receipts': [
            {
              'step_key': 'a',
              'result': {
                'report': {'findings': 'broken'},
              },
            },
          ],
        },
      ];
      for (final response in invalid) {
        wire.response = response;
        await expectLater(
          wire.repo.get('work'),
          throwsA(
            isA<ApiFailure>()
                .having((e) => e.code, 'code', 'WORK_INVALID_RESPONSE')
                .having(workError, 'copy', '暂时无法确认办理结果，请刷新后重试'),
          ),
        );
      }
      wire.status = 204;
      await expectLater(wire.repo.get('work'), throwsA(isA<ApiFailure>()));
    },
  );

  test(
    'real HTTP capabilities and pagination require explicit valid contracts',
    () async {
      final wire = WorkWire();
      await wire.start();
      addTearDown(wire.close);
      wire.response = capabilities;
      expect((await wire.repo.capabilities()).enabled, isTrue);
      wire.response = {...capabilities, 'enabled': 'yes'};
      await expectLater(wire.repo.capabilities(), throwsA(isA<ApiFailure>()));
      wire.response = {
        'contractVersion': 1,
        'items': [record()],
        'nextCursor': -1,
      };
      final page = await wire.repo.page(30);
      expect(page.nextCursor, -1);
      expect(page.items.single.id, 'work');
      expect(wire.requests.last.path, '/ai/work-items?cursor=30&limit=30');
      wire.response = {
        'contractVersion': 1,
        'items': [record(), 'corrupt'],
        'nextCursor': -1,
      };
      await expectLater(wire.repo.list(), throwsA(isA<ApiFailure>()));
      wire.response = {'contractVersion': 1, 'items': []};
      await expectLater(wire.repo.list(), throwsA(isA<ApiFailure>()));
    },
  );

  test(
    'real HTTP resumes messages confirmation retry cancellation and receipts',
    () async {
      final wire = WorkWire();
      await wire.start();
      addTearDown(wire.close);
      wire.status = 202;
      final created = await wire.repo.create('请根据截图整理', [
        'image',
      ], 'create-key');
      expect(created.state, 'WAITING_INPUT');
      expect(wire.requests.single.key, 'create-key');
      expect(wire.requests.single.body, {
        'text': '请根据截图整理',
        'attachmentIds': ['image'],
      });
      wire.response = {
        ...record(state: 'WAITING_CONFIRMATION', version: 2),
        'planHash': 'hash-2',
        'confirmationId': 'confirmation-2',
        'steps': [
          {'step_key': 'new-task', 'state': 'WAITING'},
          {'step_key': 'old-task', 'state': 'SUCCEEDED'},
        ],
      };
      final clarified = await wire.repo.message(
        created,
        '明天下午五点',
        [],
        'message-key',
        ownerId: 'person',
      );
      expect(wire.requests.last.body['version'], 1);
      expect(wire.requests.last.body['answers'], {'ownerId': 'person'});
      final restored = await wire.repo.get('work');
      expect(restored.version, clarified.version);
      wire.response = record(state: 'EXECUTING', version: 3);
      await wire.repo.confirm(restored, 'confirm-key');
      expect(wire.requests.last.body, {
        'version': 2,
        'planVersion': 1,
        'planHash': 'hash-2',
        'confirmationId': 'confirmation-2',
        'actions': ['new-task'],
      });
      wire.response = {
        ...record(state: 'PARTIAL', version: 4),
        'receipts': [
          {
            'step_key': 'old-task',
            'result': {'summary': '任务已创建', 'taskId': 'task-1'},
          },
        ],
      };
      final partial = await wire.repo.get('work');
      wire.response = {...partial.json, 'state': 'QUEUED', 'version': 5};
      final retry = await wire.repo.command(partial, 'retry', 'retry-key');
      expect(retry.receipts, hasLength(1));
      expect(retry.label, isNot('已办妥'));
      wire.response = {...retry.json, 'state': 'CANCELLED', 'version': 6};
      final cancelled = await wire.repo.command(retry, 'cancel', 'cancel-key');
      expect(cancelled.receipts.single['result']['taskId'], 'task-1');
      expect(cancelled.label, '已停止');
      expect((await wire.repo.get('work')).state, 'CANCELLED');
      await wire.repo.delete(cancelled, 'delete-key');
      expect(wire.requests.last.match, '6');
      expect(wire.requests.last.key, 'delete-key');
      wire.response = {};
      await expectLater(
        wire.repo.delete(cancelled, 'delete-key'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'real HTTP error responses remain errors and never leak provider text',
    () async {
      final wire = WorkWire();
      await wire.start();
      addTearDown(wire.close);
      for (final status in [401, 403, 404, 409, 429, 503]) {
        wire.status = status;
        wire.response = {
          'code': status == 409 ? 'VERSION_CONFLICT' : 'ERROR',
          'message': 'PRIVATE_RAW_TEXT',
        };
        await expectLater(
          wire.repo.command(WorkItem(record()), 'retry', 'stable-key'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => workError(e).contains('PRIVATE'),
              'safe copy',
              false,
            ),
          ),
        );
      }
    },
  );

  test(
    'replaced account rejects late HTTP result and blocks further writes',
    () async {
      var current = true;
      final wire = WorkWire();
      await wire.start(isCurrent: () => current);
      addTearDown(wire.close);
      wire.gate = Completer<void>();
      final pending = wire.repo.get('work');
      while (wire.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      current = false;
      final rejected = expectLater(
        pending,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'account guard',
            'WORK_ACCOUNT_CHANGED',
          ),
        ),
      );
      wire.gate!.complete();
      await rejected;
      await expectLater(
        wire.repo.create('新的内容', [], 'new-key'),
        throwsA(isA<ApiFailure>()),
      );
      expect(wire.requests, hasLength(1));
    },
  );
}
