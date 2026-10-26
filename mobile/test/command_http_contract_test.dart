import 'support/local_test_state.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class CommandAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int mutationStatus = 200, submitStatus = 200, draftVersion = 0;
  final task = <String, dynamic>{
    'id': 'task-1',
    'title': '发布验收',
    'version': 5,
    'issuer_id': 'issuer-1',
    'start_at': '2027-10-14T08:00:00Z',
    'deadline': '2027-10-14T10:00:00Z',
    'participants': [
      {'id': 'member-1', 'name': '成员一'},
    ],
    'label': {
      'id': 'label-1',
      'name': '发布',
      'category': '项目',
      'color': '#2255AA',
    },
    'fields': {
      'group': '发布',
      'content': '核对接口',
      'urgency': 'LOW',
      'attachments': ['attachment-1'],
    },
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    dynamic body = {'id': 'response', 'title': '成功', 'version': 1};
    var status = options.method == 'GET' ? 200 : mutationStatus;
    if (options.path == '/tasks' && options.method == 'POST') {
      body = {
        'id': 'review-create',
        'kind': 'TASK_CREATE',
        'target_id': 'future-task',
        'applicant_id': 'issuer-1',
        'status': 'PENDING',
      };
    } else if (options.path == '/tasks/task-1' && options.method == 'GET') {
      body = task;
    } else if (options.path == '/tasks/task-1/comments' &&
        options.method == 'GET') {
      body = {
        'items': [
          {
            'id': 'comment-1',
            'parent_id': null,
            'body': '已核对',
            'author_id': 'member-1',
            'nickname': '成员一',
            'avatar_id': 'avatar-1',
            'created_at': '2027-10-14T09:00:00Z',
          },
        ],
      };
    } else if (options.path == '/logs/draft' && status == 200) {
      final data = options.data as Map;
      if (data['version'] != draftVersion) {
        status = 409;
      } else {
        draftVersion = draftVersion == 0 ? 9 : draftVersion + 1;
        body = {'id': 'saved-log', 'title': '日报', 'version': draftVersion};
      }
    } else if (options.path.endsWith('/submit')) {
      status = submitStatus;
      if (draftVersion != 0 &&
          (options.data as Map)['version'] != draftVersion) {
        status = 409;
      }
      body = {'id': 'saved-log', 'title': '正式日报', 'version': draftVersion + 1};
    } else if (options.path == '/tasks/task-1/revisions' && status == 200) {
      body = {'id': 'review-task', 'title': '任务修订', 'status': 'PENDING'};
    } else if (options.method == 'GET') {
      body = {'items': [], 'total': 0};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpRepository repo;
  late CommandAdapter adapter;
  setUp(() {
    repo = HttpRepository('http://localhost/api', 'fixture-token');
    adapter = CommandAdapter();
    repo.dio.httpClientAdapter = adapter;
  });
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((e) => e.kind, 'kind', kind);

  test('log withdrawal carries optimistic version and reason', () async {
    await repo.execute(
      'logs',
      const Command('withdraw', {'id': 'log-1', '撤回原因': '补充说明'}, version: 5),
    );
    expect(adapter.requests.single.path, '/logs/log-1/withdraw');
    expect(adapter.requests.single.data, {'version': 5, 'reason': '补充说明'});
  });

  test('log reply maps frontend parentCommentId to backend parentId', () async {
    await repo.execute(
      'logs/comments',
      const Command('comment', {
        'id': 'log-1',
        'text': '回复',
        'parentCommentId': 'parent-1',
      }),
    );
    expect(adapter.requests.single.path, '/logs/log-1/comments');
    expect(adapter.requests.single.data, {
      'text': '回复',
      'parentId': 'parent-1',
    });
  });

  test(
    'existing object actions retain ID in task/log/comment/review/notification paths',
    () async {
      for (final (resource, action, path, expected) in [
        (
          'tasks',
          'receive',
          '/tasks/task-1/events',
          {'type': 'RECEIVED', 'version': 5},
        ),
        ('logs', 'submit', '/logs/log-1/submit', {'version': 5}),
        ('logs/comments', 'comment', '/logs/log-1/comments', {'text': '已核对'}),
        (
          'reviews',
          'approve',
          '/reviews/review-1/decision',
          {'approve': true, 'reason': ''},
        ),
        ('notifications', 'read', '/notifications/message-1/read', null),
      ]) {
        final id = switch (resource) {
          'tasks' => 'task-1',
          'logs' || 'logs/comments' => 'log-1',
          'reviews' => 'review-1',
          _ => 'message-1',
        };
        await repo.execute(
          resource,
          Command(action, {
            'id': id,
            if (resource == 'logs/comments') '评语': '已核对',
          }, version: 5),
        );
        expect(adapter.requests.last.path, path);
        expect(adapter.requests.last.data, expected);
      }
    },
  );

  test(
    'missing existing IDs and unsupported return issue no mutation',
    () async {
      for (final (resource, action) in [
        ('tasks', 'receive'),
        ('logs/comments', 'comment'),
        ('reviews', 'approve'),
        ('notifications', 'read'),
        ('logs', 'request-review'),
      ]) {
        await expectLater(
          repo.execute(resource, Command(action, const {})),
          throwsA(failure(FailureKind.validation)),
        );
      }
      await expectLater(
        repo.execute('tasks', const Command('return', {'id': 'task-1'})),
        throwsA(failure(FailureKind.unavailable)),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'unregistered list/detail resources fail before HTTP requests',
    () async {
      for (final resource in ['feedback', 'organization/teams']) {
        await expectLater(
          repo.list(resource, const Query()),
          throwsA(failure(FailureKind.unavailable)),
        );
        await expectLater(
          repo.detail(resource, 'record-1'),
          throwsA(failure(FailureKind.unavailable)),
        );
      }
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'submitted log update never writes through the draft endpoint',
    () async {
      await expectLater(
        repo.execute(
          'logs',
          const Command('update', {
            'id': 'submitted-log',
            'businessDate': '2026-10-20',
            '今日工作': '修订内容',
          }, version: 3),
        ),
        throwsA(failure(FailureKind.unavailable)),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'transfer and reschedule submit participant candidates without changing effective task',
    () async {
      for (final action in ['transfer', 'reschedule']) {
        adapter.requests.clear();
        final result = await repo.execute(
          'tasks',
          Command(action, {
            'id': 'task-1',
            '变更理由': '调整交付安排',
            if (action == 'transfer') 'ownerId': 'owner-2',
            if (action == 'reschedule') 'deadline': '2027-10-15T10:00:00Z',
          }, version: 5),
        );
        expect(adapter.requests.map((r) => r.path), [
          '/tasks/task-1',
          '/tasks/task-1/comments',
          '/tasks/task-1/revisions',
        ]);
        final body = adapter.requests.last.data as Map;
        expect(body['version'], 5);
        expect(body['reason'], '调整交付安排');
        expect(body['candidate'], {
          'title': '发布验收',
          'participants': action == 'transfer' ? ['owner-2'] : ['member-1'],
          'startAt': '2027-10-14T08:00:00Z',
          'deadline': action == 'reschedule'
              ? '2027-10-15T10:00:00Z'
              : '2027-10-14T10:00:00Z',
          'group': '发布',
          'content': '核对接口',
          'urgency': 'LOW',
          'labelId': 'label-1',
          'attachments': ['attachment-1'],
        });
        expect(result.id, 'review-task');
        expect(adapter.task['participants'], [
          {'id': 'member-1', 'name': '成员一'},
        ]);
        expect(adapter.task['deadline'], '2027-10-14T10:00:00Z');
      }
    },
  );

  test(
    'task creation uses the participant review contract and does not create an effective task',
    () async {
      final request = await repo.execute(
        'tasks',
        const Command('create', {
          '任务名称': '待审任务',
          'participantIds': ['member-1', 'member-2', 'member-1'],
          'startAt': '2027-10-14T08:00:00+08:00',
          'deadline': '2027-10-15T10:00:00+08:00',
          '标签': 'label-1',
          '任务内容': '审核后生效',
        }, idempotencyKey: 'task-create-1'),
      );
      final sent = adapter.requests.single;
      expect(sent.path, '/tasks');
      expect(sent.headers['Idempotency-Key'], 'task-create-1');
      expect(sent.data, {
        'title': '待审任务',
        'participants': ['member-1', 'member-2'],
        'startAt': '2027-10-14T08:00:00+08:00',
        'deadline': '2027-10-15T10:00:00+08:00',
        'content': '审核后生效',
        'urgency': 'NORMAL',
        'labelId': 'label-1',
        'attachments': [],
      });
      expect((sent.data as Map).containsKey('ownerId'), isFalse);
      expect((sent.data as Map).containsKey('collaborators'), isFalse);
      expect((sent.data as Map).containsKey('progressNote'), isFalse);
      expect(request.id, 'review-create');
      expect(request.fields['targetId'], 'future-task');
      expect(request.fields['targetResource'], 'tasks');
      expect(request.fields['reviewState'], '待审');
    },
  );

  test(
    'task detail maps server participants, label colour and public comments',
    () async {
      final task = await repo.detail('tasks', 'task-1');
      expect(adapter.requests.map((request) => request.path), [
        '/tasks/task-1',
        '/tasks/task-1/comments',
      ]);
      expect(task.ownerId, isEmpty);
      expect(task.fields['participantIds'], ['member-1']);
      expect(task.fields['participantNames'], ['成员一']);
      expect(task.fields['tagId'], 'label-1');
      expect(task.fields['tagColor'], '#2255AA');
      expect(task.fields['status'], isNull);
      expect(task.fields['comments'], [
        {
          'id': 'comment-1',
          'parentCommentId': null,
          'actorId': 'member-1',
          'actorName': '成员一',
          'avatarId': 'avatar-1',
          'text': '已核对',
          'createdAt': '2027-10-14T09:00:00Z',
          'time': '2027-10-14T09:00:00Z',
        },
      ]);
    },
  );

  test(
    'task comments and label management use their dedicated endpoints',
    () async {
      await repo.execute(
        'tasks/comments',
        const Command('comment', {
          'id': 'task-1',
          'text': '回复任务',
          'parentCommentId': 'comment-1',
        }, idempotencyKey: 'task-comment-1'),
      );
      expect(adapter.requests.single.path, '/tasks/task-1/comments');
      expect(
        adapter.requests.single.headers['Idempotency-Key'],
        'task-comment-1',
      );
      expect(adapter.requests.single.data, {
        'text': '回复任务',
        'parentId': 'comment-1',
      });

      adapter.requests.clear();
      await repo.execute(
        'task-labels',
        const Command('create', {'名称': '紧急', '分类': '优先级', '颜色': '#DD0000'}),
      );
      expect(adapter.requests.single.path, '/task-labels');
      expect(adapter.requests.single.data, {
        'name': '紧急',
        'category': '优先级',
        'color': '#DD0000',
      });

      adapter.requests.clear();
      await repo.list('task-labels', const Query());
      expect(adapter.requests.single.path, '/task-labels');
    },
  );

  test(
    'task deletion is submitted for review with its current version and reason',
    () async {
      await repo.execute(
        'tasks',
        const Command('request-delete', {
          'id': 'task-1',
          '删除理由': '重复任务',
        }, version: 5),
      );
      expect(adapter.requests.single.path, '/tasks/task-1/deletions');
      expect(adapter.requests.single.data, {'version': 5, 'reason': '重复任务'});
    },
  );

  test('stale candidate or missing reason fails without mutation', () async {
    await expectLater(
      repo.execute(
        'tasks',
        const Command('transfer', {
          'id': 'task-1',
          'ownerId': 'owner-2',
          '变更理由': '调整',
        }, version: 4),
      ),
      throwsA(failure(FailureKind.conflict)),
    );
    await expectLater(
      repo.execute(
        'tasks',
        const Command('reschedule', {
          'id': 'task-1',
          'deadline': '2027-10-15T10:00:00Z',
        }, version: 5),
      ),
      throwsA(failure(FailureKind.validation)),
    );
    expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
  });

  test(
    'new diary uses returned draft version and existing edits save before submit',
    () async {
      await repo.execute(
        'logs',
        const Command('submit', {'businessDate': '2026-10-13', '今日工作': '验收接口'}),
      );
      expect(adapter.requests.map((r) => r.path), [
        '/logs/draft',
        '/logs/saved-log/submit',
      ]);
      expect(adapter.requests.first.data, {
        'businessDate': '2026-10-13',
        'body': {
          'work': '验收接口',
          'blockers': '',
          'tomorrow': '',
          'hours': 0,
          'taskIds': [],
        },
        'version': 0,
      });
      expect(adapter.requests.last.data, {'version': 9});
      adapter.requests.clear();
      await repo.execute(
        'logs',
        const Command('submit', {
          'id': 'saved-log',
          'businessDate': '2026-10-13',
          '今日工作': '修改后正文',
        }, version: 9),
      );
      expect((adapter.requests.first.data as Map)['version'], 9);
      expect(adapter.requests.last.data, {'version': 10});
    },
  );

  test(
    'focus update/archive/publication preserve IDs and send only allowed contract fields',
    () async {
      await repo.execute(
        'dashboard/personal',
        const Command('archive', {
          'id': 'focus-1',
          'title': '保留重点',
          '内容': '保留正文',
          '排序位置': 2,
          'pinned': true,
        }, version: 8),
      );
      expect(adapter.requests.last.data, {
        'id': 'focus-1',
        'title': '保留重点',
        'text': '保留正文',
        'version': 8,
        'position': 2,
        'pinned': true,
        'archived': true,
      });
      await repo.execute(
        'dashboard/company',
        const Command('request-review', {
          'id': 'company-1',
          '标题': '公司目标',
          '内容': '候选正文',
          '展示受众': '全公司',
          '修改理由': '补充说明',
        }, version: 3),
      );
      expect(adapter.requests.last.data, {
        'id': 'company-1',
        'title': '公司目标',
        'text': '候选正文',
        'version': 3,
        'position': 0,
        'pinned': false,
        'archived': false,
        'reason': '补充说明',
      });
    },
  );

  test(
    'all existing async write endpoints surface typed conflict errors',
    () async {
      adapter.mutationStatus = 409;
      for (final (resource, action, values) in [
        ('tasks', 'receive', {'id': 'task-1'}),
        ('logs/comments', 'comment', {'id': 'log-1', '评语': '内容'}),
        ('reviews', 'approve', {'id': 'review-1'}),
        ('dashboard/personal', 'create', {'title': '内容'}),
        (
          'dashboard/company',
          'request-review',
          {'title': '内容', 'reason': '原因'},
        ),
        ('notifications', 'read', {'id': 'message-1'}),
      ]) {
        await expectLater(
          repo.execute(resource, Command(action, values)),
          throwsA(failure(FailureKind.conflict)),
        );
      }
    },
  );

  testWidgets(
    'diary editor retries failed submit using confirmed server draft version',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => const Session()),
          repositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      c.read(routerProvider).go('/form/log-edit');
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '不能丢失的工作正文');
      adapter.submitStatus = 503;
      await t.tap(find.widgetWithText(FilledButton, '提交'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      expect(find.text('无法连接企业服务，请确认后端已启动及连接地址正确'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '不能丢失的工作正文',
      );
      // Recreate the editor: the next PUT must use the confirmed server version
      // persisted alongside encrypted input, rather than an in-memory variable.
      c.read(routerProvider).go('/dashboard');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      c.read(routerProvider).go('/form/log-edit?draftSource=diary');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '不能丢失的工作正文',
      );
      adapter.submitStatus = 200;
      await t.tap(find.widgetWithText(FilledButton, '提交'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await t.pumpAndSettle();
      final puts = adapter.requests
          .where((r) => r.path == '/logs/draft')
          .toList();
      expect(puts.length, 2);
      expect((puts.last.data as Map)['version'], 9);
      expect(
        adapter.requests.lastWhere((r) => r.path.endsWith('/submit')).data,
        {'version': 10},
      );
      expect(find.text('无法连接企业服务，请确认后端已启动及连接地址正确'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
