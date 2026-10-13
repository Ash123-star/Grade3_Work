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

class ReadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int focusStatus = 200, versionStatus = 200, commentStatus = 200;
  bool submitted = true;
  final task = <String, dynamic>{
    'id': 'task-1',
    'title': '真实任务内容',
    'owner_id': 'u1',
    'issuer_id': 'u2',
    'version': 7,
    'deadline': '2027-10-14T10:00:00Z',
    'fields': {
      'content': '正文内容',
      'collaborators': ['u3'],
      'attachments': ['file-1'],
    },
    'events': [
      {
        'sequence': 1,
        'type': 'DISPATCHED',
        'actor_id': 'u2',
        'created_at': '2026-10-10T01:00:00Z',
      },
    ],
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    var status = 200;
    dynamic body = {'items': [], 'total': 0};
    if (options.path == '/tasks/task-1') {
      body = task;
    } else if (options.path == '/logs/log-1') {
      body = {
        'id': 'log-1',
        'business_date': '2026-10-12',
        'owner_id': 'u1',
        'submitted': submitted,
        'version': 3,
        'body': {
          'work': '当前生效正文',
          'blockers': '当前阻碍',
          'taskIds': ['task-1'],
        },
      };
    } else if (options.path == '/logs/log-1/versions') {
      status = versionStatus;
      body = [
        {
          'id': 20,
          'version': 2,
          'created_at': '2026-10-11T12:00:00Z',
          'body': {
            'work': '历史独立正文',
            'blockers': '历史阻碍',
            'tomorrow': '历史计划',
            'hours': 6,
            'taskIds': ['old-task'],
          },
        },
        {
          'id': 10,
          'version': 1,
          'created_at': '2026-10-10T12:00:00Z',
          'body': jsonEncode({'work': '最早版本正文'}),
        },
      ];
    } else if (options.path == '/logs/log-1/comments') {
      status = commentStatus;
      body = [
        {
          'id': 'comment-1',
          'text': '服务端实际评语',
          'actor_id': 'u2',
          'created_at': '2026-10-12T12:00:00Z',
        },
      ];
    } else if (options.path.startsWith('/dashboard/')) {
      status = focusStatus;
      final own = options.queryParameters['ownerId'];
      final cursor =
          int.tryParse('${options.queryParameters['cursor'] ?? 0}') ?? 0;
      body = {
        'items': [
          if (cursor == 0)
            for (var i = 0; i < 30; i++)
              {
                'id': 'first-$i',
                'title': '不能代替目标的首项$i',
                'owner_id': own ?? 'u1',
              },
          if (cursor == 30)
            {
              'id': 'target',
              'title': '目标重点',
              'owner_id': own ?? 'u1',
              'body': {'text': '重点实际正文'},
              'version': 4,
            },
        ],
        'total': 31,
        'nextCursor': cursor == 0 ? '30' : '60',
      };
    } else if (options.path == '/notifications') {
      body = {
        'items': [
          {
            'id': 'note-task',
            'recipient_id': 'u1',
            'type': 'TASK_EVENT',
            'object_id': 'task-1',
            'is_read': true,
          },
          {
            'id': 'note-log',
            'recipient_id': 'u1',
            'type': 'LOG_COMMENT',
            'object_id': 'log-1',
            'is_read': false,
          },
          {
            'id': 'note-review',
            'recipient_id': 'u1',
            'type': 'REVIEW_PENDING',
            'object_id': 'review-1',
            'is_read': false,
          },
          {
            'id': 'note-unknown',
            'recipient_id': 'u1',
            'type': 'FUTURE_EVENT',
            'object_id': 'do-not-guess',
            'is_read': false,
          },
        ],
        'total': 4,
      };
    } else if (options.path.endsWith('/read')) {
      body = {'ok': true};
    } else if (options.path == '/private-notes') {
      body = [];
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
  late ReadAdapter adapter;
  late HttpRepository repo;
  setUp(() {
    adapter = ReadAdapter();
    repo = HttpRepository('http://localhost/api', 'fixture-token');
    repo.dio.httpClientAdapter = adapter;
  });
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((e) => e.kind, 'kind', kind);

  test(
    'focus detail pages through scoped authorized list instead of nonexistent GET',
    () async {
      final record = await repo.detail(
        'dashboard/personal',
        'target',
        ownerId: 'u2',
      );
      expect(record.title, '目标重点');
      expect(record.fields['内容'], '重点实际正文');
      expect(record.ownerId, 'u2');
      expect(adapter.requests.map((r) => r.path), [
        '/dashboard/personal',
        '/dashboard/personal',
      ]);
      expect(adapter.requests.map((r) => r.queryParameters['ownerId']), [
        'u2',
        'u2',
      ]);
      expect(adapter.requests.last.queryParameters['cursor'], '30');
      adapter.requests.clear();
      await expectLater(
        repo.detail('dashboard/company', 'absent'),
        throwsA(failure(FailureKind.notFound)),
      );
      expect(adapter.requests.length, 2);
      expect(adapter.requests.any((r) => r.path.endsWith('/absent')), isFalse);
      adapter.focusStatus = 403;
      await expectLater(
        repo.detail('dashboard/personal', 'target', ownerId: 'outside'),
        throwsA(failure(FailureKind.forbidden)),
      );
    },
  );

  test(
    'submitted diary reads actual independent history and comments while draft does not',
    () async {
      final record = await repo.detail('logs', 'log-1');
      final versions = record.fields['versions'] as List;
      expect((versions.first as Map)['fields']['今日工作'], '历史独立正文');
      expect((versions.last as Map)['fields']['今日工作'], '最早版本正文');
      expect((versions.first as Map)['time'], '2026-10-11T12:00:00Z');
      expect((record.fields['comments'] as List).single['text'], '服务端实际评语');
      expect(record.fields['今日工作'], '当前生效正文');
      expect(adapter.requests.map((r) => r.path).toSet(), {
        '/logs/log-1',
        '/logs/log-1/versions',
        '/logs/log-1/comments',
      });
      adapter.requests.clear();
      adapter.submitted = false;
      final draft = await repo.detail('logs', 'log-1');
      expect(draft.fields['status'], '草稿');
      expect(adapter.requests.single.path, '/logs/log-1');
    },
  );

  test(
    'auxiliary server failure retains context but access failure rejects protected diary',
    () async {
      adapter.versionStatus = 503;
      final record = await repo.detail('logs', 'log-1');
      expect(record.fields['今日工作'], '当前生效正文');
      expect(record.fields['versionsError'], failure(FailureKind.server));
      expect(record.fields.containsKey('versions'), isFalse);
      adapter.commentStatus = 403;
      await expectLater(
        repo.detail('logs', 'log-1'),
        throwsA(failure(FailureKind.forbidden)),
      );
    },
  );

  test(
    'task status follows ordered events with revised reset and nonphase changes',
    () async {
      adapter.task['events'] = [
        {'sequence': 5, 'type': 'TRANSFERRED'},
        {'sequence': 2, 'type': 'RECEIVED'},
        {'sequence': 1, 'type': 'DISPATCHED'},
        {
          'sequence': 3,
          'type': 'FEEDBACK',
          'body': {'text': '实际成果'},
        },
        {'sequence': 4, 'type': 'RESCHEDULED'},
      ];
      var record = await repo.detail('tasks', 'task-1');
      expect(record.fields['status'], '待验收');
      expect(record.fields['成果说明'], '实际成果');
      expect(record.fields['附件'], '附件 ID：file-1');
      expect((record.fields['events'] as List).first, contains('派发任务'));
      (adapter.task['events'] as List).add({'sequence': 6, 'type': 'REVISED'});
      record = await repo.detail('tasks', 'task-1');
      expect(record.fields['status'], '待接收');
      expect(record.fields.containsKey('成果说明'), isFalse);
      adapter.task['events'] = [
        {'sequence': 1, 'type': 'FUTURE_EVENT'},
      ];
      record = await repo.detail('tasks', 'task-1');
      expect(record.fields.containsKey('status'), isFalse);
    },
  );

  test(
    'notification maps real read flag, recipient and only known object targets',
    () async {
      final records = (await repo.list('notifications', const Query())).items;
      expect(records.first.ownerId, 'u1');
      expect(records.first.fields['read'], isTrue);
      expect(records[1].fields['read'], isFalse);
      expect(records.map((r) => r.fields['targetResource']), [
        'tasks',
        'logs',
        'reviews',
        null,
      ]);
      expect(records.map((r) => r.fields['targetId']), [
        'task-1',
        'log-1',
        'review-1',
        null,
      ]);
    },
  );

  Future<void> settleHttp(WidgetTester t) async {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
  }

  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    Session user = const Session(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => user),
        repositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    c.read(routerProvider).go(route);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    await settleHttp(t);
    return c;
  }

  Future<void> closeUi(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  testWidgets(
    'historical document displays HTTP version body rather than current content',
    (t) async {
      final c = await launch(t, '/history/log-1/version/2');
      expect(find.text('历史独立正文'), findsOneWidget);
      expect(find.text('历史阻碍'), findsOneWidget);
      expect(find.text('当前生效正文'), findsNothing);
      expect(find.text('记录时间：2026-10-11T12:00:00Z'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      c.read(routerProvider).go('/item/logs/log-1');
      await settleHttp(t);
      await t.drag(find.byType(ListView).first, const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.text('服务端实际评语'), findsOneWidget);
      expect(find.text('作者 u2 · 2026-10-12T12:00:00Z'), findsOneWidget);
      await closeUi(t);
    },
  );

  testWidgets(
    'history server failure exposes retry, forbidden comments clear body',
    (t) async {
      adapter.versionStatus = 503;
      final c = await launch(t, '/history/log-1/version/2');
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('该版本正文不可用'), findsNothing);
      adapter.versionStatus = 200;
      await t.tap(find.text('重新加载'));
      await settleHttp(t);
      expect(find.text('历史独立正文'), findsOneWidget);
      adapter.commentStatus = 403;
      c.invalidate(itemProvider(('logs', 'log-1')));
      c.read(routerProvider).go('/item/logs/log-1');
      await settleHttp(t);
      expect(find.text('无权访问'), findsOneWidget);
      expect(find.text('当前生效正文'), findsNothing);
      expect(find.text('服务端实际评语'), findsNothing);
      expect(find.text('申请修订日志'), findsNothing);
      await closeUi(t);
    },
  );

  testWidgets(
    'member focus route retains owner and rejects forbidden target safely',
    (t) async {
      final c = await launch(t, '/item/dashboard%2Fpersonal/target?ownerId=u2');
      expect(find.text('目标重点'), findsOneWidget);
      expect(find.text('重点实际正文'), findsOneWidget);
      expect(find.text('编辑与排序'), findsNothing);
      expect(
        adapter.requests
            .where((r) => r.path == '/dashboard/personal')
            .every((r) => r.queryParameters['ownerId'] == 'u2'),
        isTrue,
      );
      adapter.focusStatus = 403;
      await t.runAsync(() async {
        await expectLater(
          c.refresh(
            scopedItemProvider(('dashboard/personal', 'target', 'u2')).future,
          ),
          throwsA(failure(FailureKind.forbidden)),
        );
      });
      await settleHttp(t);
      expect(find.text('无权访问'), findsOneWidget);
      expect(find.text('重点实际正文'), findsNothing);
      await closeUi(t);
    },
  );

  testWidgets(
    'actual task events drive one owner or dispatcher action and unknown stays read-only',
    (t) async {
      final c = await launch(
        t,
        '/item/tasks/task-1',
        user: const Session(role: UserRole.employee),
      );
      expect(find.widgetWithText(FilledButton, '接收任务'), findsOneWidget);
      adapter.task['events'] = [
        {'sequence': 1, 'type': 'RECEIVED'},
        {
          'sequence': 2,
          'type': 'FEEDBACK',
          'body': {'text': '实际提交成果'},
        },
      ];
      adapter.task['owner_id'] = 'u2';
      adapter.task['issuer_id'] = 'u1';
      c.read(sessionProvider.notifier).state = const Session();
      await t.runAsync(() async {
        await c.refresh(itemProvider(('tasks', 'task-1')).future);
      });
      await settleHttp(t);
      expect(find.widgetWithText(FilledButton, '查看成果并验收'), findsOneWidget);
      expect(find.text('接收任务'), findsNothing);
      adapter.task['events'] = [
        {'sequence': 1, 'type': 'FUTURE_EVENT'},
      ];
      await t.runAsync(() async {
        await c.refresh(itemProvider(('tasks', 'task-1')).future);
      });
      await settleHttp(t);
      expect(find.widgetWithText(FilledButton, '查看成果并验收'), findsNothing);
      await t.tap(find.text('更多 …'));
      await t.pumpAndSettle();
      expect(find.text('转派任务'), findsNothing);
      await closeUi(t);
    },
  );
}
