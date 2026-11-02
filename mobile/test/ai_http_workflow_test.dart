import 'package:pandora_mobile/shared/premium_pickers.dart';
import 'support/flutter_sdk_assets.dart';
import 'support/local_test_state.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/ai.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/ai_repository.dart';
import 'package:pandora_mobile/features/ai_map/server_ai_page.dart';
import 'package:pandora_mobile/features/ai_map/ai_job_pages.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_tools.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

HttpRepository buildHttp(Session user, AiAdapter adapter) {
  final repository = HttpRepository('http://localhost/api', user.token);
  repository.dio.httpClientAdapter = adapter;
  return repository;
}

Map<String, dynamic> fixture({
  String id = 'job',
  String state = 'SUCCEEDED',
  int version = 4,
  String title = '先核对发布依赖',
}) => {
  'id': id,
  'owner_id': 'u1',
  'state': state,
  'version': version,
  'created_at': '2026-10-13T01:30:00Z',
  'error': state == 'FAILED' ? '每日预算不足' : null,
  'input': {
    'date': '2026-10-13',
    'period': 'day',
    'purpose': 'SUMMARY',
    'sources': [
      {
        'id': 'task:task-1',
        'ownerId': 'u1',
        'title': '发布依赖清单',
        'url': '/api/tasks/task-1',
        'overdue': true,
      },
      {
        'id': 'log:log-1',
        'ownerId': 'u1',
        'date': '2026-10-13',
        'url': '/api/logs/log-1',
      },
      {
        'id': 'item:focus-1',
        'title': '提升评审能力',
        'url': '/api/dashboard/personal?ownerId=u1',
      },
    ],
    'candidates': [
      {'id': 'owner', 'name': '实际负责人'},
    ],
  },
  'output': state == 'SUCCEEDED'
      ? {
          'summary': '来源显示发布依赖仍需确认，影响范围需要人工核实。',
          'sourceIds': ['task:task-1', 'log:log-1'],
          'generatedAt': '2026-10-13T01:30:00Z',
          'draft': true,
          'actions': [
            {
              'title': title,
              'ownerId': 'owner',
              'sourceIds': ['task:task-1'],
            },
            {
              'title': '整理边界说明',
              'ownerId': '',
              'sourceIds': ['log:log-1'],
            },
            {
              'title': '安排复核时间',
              'ownerId': '',
              'sourceIds': ['item:focus-1'],
            },
          ],
          'nodes': [
            {
              'title': '完成发布复核',
              'type': 'GOAL',
              'sourceIds': ['task:task-1'],
            },
            {
              'title': '依赖风险待核实',
              'type': 'RISK',
              'sourceIds': ['log:log-1'],
            },
          ],
        }
      : null,
};

class AiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int createStatus = 200,
      getStatus = 200,
      editStatus = 200,
      confirmStatus = 200;
  String failureCode = 'AI_NOT_CONFIGURED', afterStream = 'SUCCEEDED';
  final jobs = <String, Map<String, dynamic>>{'job': fixture()};
  StreamController<Uint8List>? heldStream;
  Completer<void>? heldGet;
  int count = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    var status = 200;
    dynamic data = <String, dynamic>{};
    final pieces = o.path.split('/');
    final id = pieces.length > 3 ? pieces[3] : '';
    if (o.path == '/notifications/stream') {
      return ResponseBody.fromString(
        ': keepalive\n\n',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    } else if (o.path.endsWith('/stream')) {
      if (heldStream != null) {
        return ResponseBody(
          heldStream!.stream,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        );
      }
      jobs[id] = fixture(id: id, state: afterStream);
      final event =
          'event: delta\r\ndata: {"text":"尚未完成的中文输出"}\r\n\r\n: keepalive\r\n\r\nevent: result\r\ndata: ${jsonEncode(jobs[id])}\r\n\r\n';
      final encoded = utf8.encode(event);
      return ResponseBody(
        Stream<Uint8List>.fromIterable([
          for (var i = 0; i < encoded.length; i += 7)
            Uint8List.fromList(
              encoded.sublist(i, (i + 7).clamp(0, encoded.length)),
            ),
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    } else if (o.path == '/ai/jobs' || o.path.endsWith('/retry')) {
      status = createStatus;
      final created = 'generated-${++count}';
      data = fixture(id: created, state: 'QUEUED', version: 1);
      jobs[created] = data;
    } else if (o.path.endsWith('/draft')) {
      status = editStatus;
      final original = AiJob.fromJson(jobs[id]);
      if (status == 200) {
        data = {
          ...jobs[id]!,
          'version': original.version + 1,
          'output': {...o.data as Map}..remove('version'),
        };
        jobs[id] = data;
      }
    } else if (o.path.endsWith('/confirm-task')) {
      status = confirmStatus;
      if (status == 200 && o.data['version'] != jobs[id]?['version']) {
        status = 409;
        data = {'code': 'VERSION_CONFLICT', 'message': '建议已变化，请重新读取'};
      } else {
        data = {'id': 'task-created'};
      }
    } else if (o.path.startsWith('/ai/jobs/')) {
      if (o.method == 'DELETE') {
        jobs[id] = fixture(id: id, state: 'CANCELLED');
        data = {'ok': true};
      } else {
        if (heldGet != null) await heldGet!.future;
        status = getStatus;
        data = jobs[id] ?? fixture(id: id);
      }
    } else if (o.path == '/ai-maps') {
      final job = AiJob.fromJson(jobs['job']);
      data = {
        'nodes': [
          for (final (i, node) in job.nodes.indexed)
            {'id': 'node-$i', 'job_id': 'job', 'owner_id': 'u1', 'body': node},
        ],
        'edges': [
          {
            'id': 'edge',
            'source_id': 'node-0',
            'target_id': 'node-1',
            'body': {'label': '前置条件'},
          },
        ],
      };
    } else if (o.path == '/ai-maps/edges') {
      data = {'id': 'new-edge'};
    } else if (o.path == '/ai/usage') {
      data = {
        'dailyLimit': 15000,
        'usage': [
          {'date': '2026-10-13', 'tokens': 850, 'jobs': 2},
        ],
      };
    } else if (o.path == '/organization/people') {
      data = {
        'items': [
          {
            'id': 'owner',
            'name': '实际负责人',
            'status': 'ACTIVE',
            'department': '技术部',
          },
        ],
        'total': 1,
      };
    } else if (o.path.startsWith('/tasks/')) {
      data = {
        'id': 'task-created',
        'title': '先核对发布依赖',
        'owner_id': 'owner',
        'fields': {},
      };
    } else {
      data = {'items': [], 'total': 0};
    }
    if (status != 200) {
      data = {
        'code': status == 409
            ? 'VERSION_CONFLICT'
            : status == 403
            ? 'FORBIDDEN'
            : failureCode,
      };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const session = Session(
  id: 'u1',
  name: '小橙',
  role: UserRole.admin,
  token: 'token',
);
void main() {
  late AiAdapter adapter;
  late AiRepository repo;
  setUp(() {
    adapter = AiAdapter();
    repo = AiRepository(
      Dio(
        BaseOptions(
          baseUrl: 'http://localhost/api',
          headers: {'Authorization': 'Bearer token'},
        ),
      )..httpClientAdapter = adapter,
    );
  });
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((e) => e.kind, 'kind', kind);
  test(
    'nested AI job retains sources/version/time; source routes are exact internal matches only',
    () {
      final job = AiJob.fromJson(fixture());
      expect(job.actions.length, 3);
      final largest = fixture();
      (largest['input'] as Map)['sources'] = [
        for (var i = 0; i < 110; i++)
          {'id': 'task:t-$i', 'url': '/api/tasks/t-$i'},
      ];
      expect(AiJob.fromJson(largest).sources.length, 110);
      expect(job.version, 4);
      expect(job.summary, contains('人工核实'));
      expect(job.sources[0].route('u1'), '/item/tasks/task-1');
      expect(job.sources[1].route('u1'), '/item/logs/log-1');
      expect(
        job.sources[2].route('u1'),
        '/item/dashboard%2Fpersonal/focus-1?ownerId=u1',
      );
      expect(job.sources[2].route('other'), isNull);
      for (final url in [
        'https://evil.test/api/tasks/task-1',
        '//evil.test/api/tasks/task-1',
        '/api/tasks/other',
        '/api/tasks/task-1?token=x',
        '/api/tasks/task-1#x',
      ]) {
        expect(AiSource({'id': 'task:task-1', 'url': url}).route('u1'), isNull);
      }
      expect(job.validRefs(['task:task-1'], 'u1'), isTrue);
      for (final ids in [
        [],
        ['task:missing'],
        ['task:task-1', 'task:task-1'],
      ]) {
        expect(job.validRefs(ids, 'u1'), isFalse);
      }
      expect(
        () => AiJob.fromJson({...fixture(), 'output': null}),
        throwsA(failure(FailureKind.server)),
      );
    },
  );
  test(
    'SSE supports split UTF8/CRLF/comments/multiline and rejects oversized frames',
    () async {
      final encoded = utf8.encode(
        'event: delta\r\ndata: {"text":\r\ndata: "中文草稿"}\r\n\r\n: keepalive\r\n\r\nevent: result\r\ndata: {"id":"job"}\r\n\r\n',
      );
      final events = await parseAiEvents(
        Stream.fromIterable(encoded.map((b) => [b])),
      ).toList();
      expect(events.map((e) => e.kind), ['delta', 'result']);
      expect(events[0].data['text'], '中文草稿');
      expect(
        await parseAiEvents(
          Stream.value(
            utf8.encode('event: delta\ndata: {"text":"incomplete"}'),
          ),
        ).toList(),
        isEmpty,
      );
      await expectLater(
        parseAiEvents(
          Stream.value(utf8.encode('data: ${'x' * 150001}\n\n')),
        ).toList(),
        throwsA(failure(FailureKind.server)),
      );
    },
  );
  test(
    'AI gateway sends exact existing contracts and preserves draft references; no automatic task',
    () async {
      final created = await repo.create(
        '2026-10-13',
        'week',
        purpose: 'EXPLAIN_RISK',
        focus: 'task:task-1',
      );
      expect(adapter.requests.first.data, {
        'date': '2026-10-13',
        'period': 'week',
        'purpose': 'EXPLAIN_RISK',
        'scope': 'AUTHORIZED',
        'focusSourceId': 'task:task-1',
      });
      expect(adapter.requests.first.headers['Authorization'], 'Bearer token');
      await repo.stream(created.id, CancelToken()).toList();
      final job = await repo.job('job');
      final edited = await repo.edit(job, '人工整理的建议', [
        '修改第一步',
        '整理边界说明',
        '安排复核时间',
      ]);
      final body = adapter.requests.last.data as Map;
      expect(body['version'], 4);
      expect(body['sourceIds'], job.output!['sourceIds']);
      expect(body['nodes'], job.nodes);
      expect((body['actions'] as List).first['sourceIds'], ['task:task-1']);
      expect(edited.version, 5);
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        isEmpty,
      );
      final task = {
        'title': '人工任务',
        'ownerId': 'owner',
        'deadline': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'attachments': ['file'],
        'collaborators': ['person'],
      };
      expect((await repo.confirm(edited, 0, task, 'stable-key'))['id'], 'task-created');
      expect(adapter.requests.last.path, '/ai/jobs/job/confirm-task');
      expect(adapter.requests.last.data, {'version': 5, 'actionIndex': 0, 'task': task});
      expect(adapter.requests.last.headers['Idempotency-Key'], 'stable-key');
      await repo.cancel(created.id);
      expect(adapter.requests.last.method, 'DELETE');
      final retried = await repo.retry(created.id);
      expect(retried.id, isNot(created.id));
      await repo.edge('node-0', 'node-1', '依赖');
      expect(adapter.requests.last.data, {
        'sourceId': 'node-0',
        'targetId': 'node-1',
        'label': '依赖',
      });
      expect((await repo.usage())['dailyLimit'], 15000);
      expect((await repo.map())['edges'], isNotEmpty);
    },
  );
  test(
    'AI invalid input has no HTTP mutation and403/409/503 remain typed failures',
    () async {
      await expectLater(
        repo.create('invalid', 'day'),
        throwsA(failure(FailureKind.validation)),
      );
      await expectLater(
        repo.create('2026-10-13', 'day', purpose: 'DRAFT_TASK'),
        throwsA(failure(FailureKind.validation)),
      );
      await expectLater(
        repo.edge('node', 'node', ''),
        throwsA(failure(FailureKind.validation)),
      );
      await expectLater(
        repo.confirm(AiJob.fromJson(fixture()), 99, {}, 'key'),
        throwsA(failure(FailureKind.validation)),
      );
      expect(adapter.requests, isEmpty);
      adapter.getStatus = 403;
      await expectLater(
        repo.job('job'),
        throwsA(failure(FailureKind.forbidden)),
      );
      adapter.editStatus = 409;
      await expectLater(
        repo.edit(AiJob.fromJson(fixture()), '修改', ['1', '2', '3']),
        throwsA(failure(FailureKind.conflict)),
      );
      adapter.createStatus = 503;
      await expectLater(
        repo.create('2026-10-13', 'day'),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'AI_NOT_CONFIGURED'),
        ),
      );
      adapter.createStatus = 429;
      adapter.failureCode = 'AI_BUDGET';
      await expectLater(
        repo.create('2026-10-13', 'day'),
        throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'AI_BUDGET')),
      );
    },
  );
  Future<void> settle(WidgetTester t) async {
    // HTTP/SSE work crosses real and fake clocks; a live progress indicator
    // must not be treated as an animation that can settle by itself.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pump();
  }

  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    Session user = session,
    double scale = 1,
    Size size = const Size(390, 844),
    GlobalKey? boundary,
    String? latest,
    bool productionRouter = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => user),
        fontScaleProvider.overrideWith((ref) => scale),
        httpRepositoryProvider.overrideWith((ref) {
          final r = ref.watch(sessionProvider);
          // Reuse production HttpRepository in both mock and formal test invocations.
          return buildHttp(r, adapter);
        }),
        repositoryProvider.overrideWith(
          (ref) => ref.watch(httpRepositoryProvider),
        ),
        if (!productionRouter)
          routerProvider.overrideWith((ref) {
            final router = GoRouter(
              initialLocation: route,
              routes: [
                GoRoute(path: '/ai', builder: (_, _) => const ServerAiPage()),
                GoRoute(
                  path: '/ai/graph',
                  builder: (_, _) => const ServerAiGraphPage(),
                ),
                GoRoute(
                  path: '/ai/usage',
                  builder: (_, _) => const ServerAiUsagePage(),
                ),
                GoRoute(
                  path: '/ai/jobs/:id/edit',
                  builder: (_, s) => AiJobPage(
                    s.pathParameters['id']!,
                    edit: true,
                    key: ValueKey(s.uri),
                  ),
                ),
                GoRoute(
                  path: '/ai/jobs/:id/actions/:index',
                  builder: (_, s) => AiJobPage(
                    s.pathParameters['id']!,
                    actionIndex: int.parse(s.pathParameters['index']!),
                    key: ValueKey(s.uri),
                  ),
                ),
                GoRoute(
                  path: '/ai/jobs/:id/confirm/:index',
                  builder: (_, s) => AiConfirmPage(
                    s.pathParameters['id']!,
                    int.parse(s.pathParameters['index']!),
                    key: ValueKey(s.uri),
                  ),
                ),
              ],
            );
            ref.onDispose(router.dispose);
            return router;
          }),
      ],
    );
    addTearDown(c.dispose);
    if (latest != null) {
      c.read(latestAiJobProvider(user.id).notifier).state = latest;
    }
    c.read(routerProvider).go(route);
    Widget app = UncontrolledProviderScope(
      container: c,
      child: const PandoraApp(),
    );
    if (boundary != null) app = RepaintBoundary(key: boundary, child: app);
    await t.pumpWidget(app);
    if (adapter.heldGet != null) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump();
    } else {
      await settle(t);
    }
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      if (finder.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable).first,
        );
      }
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await settle(t);
  }

  // Formal pages run in both modes through the same dedicated test router.
  Future<ProviderContainer> home(WidgetTester t, {String? latest}) async {
    return launch(t, '/ai', latest: latest);
  }

  testWidgets(
    'formal AI generation displays sourced priorities after final GET, no task mutation',
    (t) async {
      await home(t);
      expect(find.text('发展分析'), findsOneWidget);
      expect(find.text('堵点风险'), findsOneWidget);
      expect(find.text('行动规划'), findsOneWidget);
      expect(find.text('把下一步想清楚'), findsNothing);
      expect(find.textContaining('点击开始分析，基于已有任务'), findsNothing);
      expect(
        t.getTopLeft(find.text('开始分析')).dy,
        greaterThan(t.getTopLeft(find.text('发展分析')).dy),
      );
      await tapVisible(t, find.text('开始分析'));
      await settle(t);
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('今天优先处理的三件事'), findsNothing);
      expect(find.text('打开工作关系图'), findsNothing);
      expect(find.byTooltip('长期记忆与发展分析'), findsNothing);
      expect(find.text('用量'), findsNothing);
      expect(find.text('建议草稿'), findsNothing);
      expect(find.text('本人及授权公司范围'), findsNothing);
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsOneWidget);
      expect(adapter.requests.any((r) => r.path.endsWith('/stream')), isTrue);
      expect(
        adapter.requests
            .lastWhere((r) => r.path.startsWith('/ai/jobs/'))
            .method,
        'GET',
      );
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        isEmpty,
      );
      await tapVisible(t, find.text('行动规划'));
      expect(find.text('先核对发布依赖'), findsOneWidget);
      await tapVisible(t, find.text('堵点风险'));
      expect(find.textContaining('1 个任务已逾期'), findsOneWidget);
      expect(find.text('AI风险推测 · 需核实实际影响'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    '503/429 and failed generation retain previous result and input without fake success',
    (t) async {
      await home(t, latest: 'job');
      adapter.createStatus = 503;
      await tapVisible(t, find.text('开始分析'));
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      expect(find.textContaining('企业AI服务尚未配置'), findsOneWidget);
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsOneWidget);
      adapter.createStatus = 429;
      adapter.failureCode = 'AI_BUDGET';
      await tapVisible(t, find.text('开始分析'));
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      expect(find.textContaining('今日AI预算不足'), findsOneWidget);
      adapter.createStatus = 200;
      adapter.afterStream = 'FAILED';
      await tapVisible(t, find.text('开始分析'));
      await settle(t);
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      expect(find.textContaining('生成未完成'), findsOneWidget);
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsOneWidget);
      expect(find.textContaining('上一次完成'), findsOneWidget);
      expect(adapter.requests.where((r) => r.path.endsWith('/retry')), isEmpty);
      await tapVisible(t, find.text('重试生成'));
      expect(
        adapter.requests.where((r) => r.path.endsWith('/retry')).length,
        1,
      );
      await close(t);
    },
  );
  testWidgets(
    'explicit cancellation aborts stream, retains input; old account cannot receive late output',
    (t) async {
      adapter.heldStream = StreamController<Uint8List>();
      final c = await home(t);
      await tapVisible(t, find.text('开始分析'));
      expect(find.textContaining('等待生成'), findsOneWidget);
      final streaming = adapter.requests.lastWhere(
        (r) => r.path.endsWith('/stream'),
      );
      await tapVisible(t, find.text('取消生成'));
      expect(streaming.cancelToken!.isCancelled, isTrue);
      expect(find.textContaining('生成已取消'), findsOneWidget);
      await t.runAsync(() => adapter.heldStream!.close());
      adapter.heldStream = null;
      c.read(sessionProvider.notifier).state = const Session(
        id: 'other',
        role: UserRole.admin,
        token: 'other',
      );
      await t.pump();
      expect(find.text('访问已停止，请返回后重新确认账号与权限'), findsOneWidget);
      expect(c.read(latestAiJobProvider('other')), isNull);
      await close(t);
    },
  );
  testWidgets(
    '403 refresh clears previously rendered output and disables protected actions',
    (t) async {
      await home(t, latest: 'job');
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsOneWidget);
      adapter.getStatus = 403;
      adapter.createStatus = 403;
      await tapVisible(t, find.text('开始分析'));
      await settle(t);
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsNothing);
      expect(find.textContaining('访问已停止'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'AI draft409 keeps inputs, confirmed reload replaces them, saving never creates a task',
    (t) async {
      await launch(t, '/ai/jobs/job/edit');
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '分析与依据',
      );
      await t.enterText(field, '人工编辑但尚未保存');
      adapter.editStatus = 409;
      await t.tap(find.text('保存建议草稿'));
      await settle(t);
      expect(find.textContaining('内容已有新版本'), findsOneWidget);
      expect(t.widget<TextField>(field).controller!.text, '人工编辑但尚未保存');
      expect(
        (t.widget(
                  find.ancestor(
                    of: find.text('保存建议草稿'),
                    matching: find.byWidgetPredicate((w) => w is FilledButton),
                  ),
                )
                as FilledButton)
            .onPressed,
        isNull,
      );
      await t.tap(find.text('重新读取').first);
      await t.pumpAndSettle();
      await t.tap(find.text('保留编辑'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, '人工编辑但尚未保存');
      adapter.jobs['job'] = fixture(version: 6, title: '新版本建议');
      await t.tap(find.text('重新读取').first);
      await t.pumpAndSettle();
      await t.tap(find.text('重新读取').last);
      await settle(t);
      expect(t.widget<TextField>(field).controller!.text, contains('来源显示'));
      expect(find.text('新版本建议'), findsOneWidget);
      adapter.editStatus = 200;
      await t.tap(find.text('保存建议草稿'));
      await settle(t);
      expect(
        adapter.requests.lastWhere((r) => r.method == 'PUT').data['version'],
        6,
      );
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        isEmpty,
      );
      await close(t);
    },
  );
  testWidgets(
    'missing sources and employee direct confirmation cannot dispatch',
    (t) async {
      final data = fixture();
      (data['output'] as Map)['actions'][0]['sourceIds'] = [];
      adapter.jobs['job'] = data;
      var c = await launch(t, '/ai/jobs/job/actions/0');
      expect(find.text('有效来源不足，不能确认创建任务。'), findsOneWidget);
      expect(
        (t.widget(
                  find.ancestor(
                    of: find.text('人工确认创建任务'),
                    matching: find.byWidgetPredicate((w) => w is FilledButton),
                  ),
                )
                as FilledButton)
            .onPressed,
        isNull,
      );
      c.read(routerProvider).go('/ai/jobs/job/confirm/0');
      await settle(t);
      expect(find.textContaining('建议或来源不可用'), findsOneWidget);
      await close(t);
      c = await launch(
        t,
        '/ai/jobs/job/confirm/0',
        user: const Session(
          id: 'u1',
          role: UserRole.employee,
          dispatch: false,
          token: 'token',
        ),
      );
      expect(find.text('当前账号没有任务派发资格'), findsOneWidget);
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        isEmpty,
      );
      await close(t);
    },
  );
  Future<void> fillConfirmation(WidgetTester t) async {
    await tapVisible(t, find.text('选择主负责人'));
    await t.tap(find.text('实际负责人'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('选择截止时间'));
    await t.pumpAndSettle();
    await t.tap(find.text('选择截止时间'));
    await t.pumpAndSettle();
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester t) async {
    await t.tap(find.text('确认并提交任务申请'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认派发'));
    await settle(t);
  }

  testWidgets(
    'human task confirmation retries with stable idempotency and actual active owner',
    (t) async {
      await launch(t, '/ai/jobs/job/confirm/0');
      await fillConfirmation(t);
      adapter.confirmStatus = 503;
      await confirm(t);
      expect(find.text('查看已创建任务'), findsNothing);
      final first = adapter.requests.lastWhere(
        (r) => r.path.endsWith('/confirm-task'),
      );
      adapter.confirmStatus = 200;
      await confirm(t);
      final second = adapter.requests.lastWhere(
        (r) => r.path.endsWith('/confirm-task'),
      );
      expect(
        first.headers['Idempotency-Key'],
        second.headers['Idempotency-Key'],
      );
      expect(second.data['actionIndex'], 0);
      expect(second.data['task']['ownerId'], 'owner');
      expect(second.data['task']['urgency'], 'NORMAL');
      expect(second.data['task'].containsKey('status'), isFalse);
      expect(
        adapter.requests
            .lastWhere((r) => r.path == '/organization/people')
            .queryParameters['dispatch'],
        isTrue,
      );
      expect(find.text('查看已创建任务'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'changed recommendation is rejected atomically by server and preserves human input',
    (t) async {
      await launch(t, '/ai/jobs/job/confirm/0');
      await fillConfirmation(t);
      adapter.jobs['job'] = fixture(version: 9, title: '已改变的建议');
      await confirm(t);
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      expect(find.textContaining('内容已有新版本'), findsWidgets);
      expect(find.text('先核对发布依赖'), findsOneWidget);
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        hasLength(1),
      );
      await close(t);
    },
  );
  testWidgets(
    'map uses real node/job sources, accessible list/search, and actual usage',
    (t) async {
      final c = await launch(t, '/ai/graph');
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('节点列表 · 与关系图相同内容'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '依赖风险');
      await t.pumpAndSettle();
      expect(find.text('完成发布复核'), findsNothing);
      expect(find.text('依赖风险待核实'), findsWidgets);
      await t.enterText(find.byType(TextField).first, '');
      await t.pumpAndSettle();
      c.read(routerProvider).go('/ai/usage');
      await settle(t);
      expect(find.text('15000 tokens'), findsOneWidget);
      expect(find.text('850 tokens'), findsOneWidget);
      expect(find.text('2 次作业'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'disposed pending AI read cannot publish into successor account',
    (t) async {
      adapter.heldGet = Completer<void>();
      final c = await launch(t, '/ai/jobs/job/edit');
      for (var tick = 0; tick < 10; tick++) {
        await t.pump(const Duration(milliseconds: 30));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        if (adapter.requests.any((r) => r.path == '/ai/jobs/job')) break;
      }
      final request = adapter.requests.lastWhere(
        (r) => r.path == '/ai/jobs/job',
      );
      c.read(sessionProvider.notifier).state = const Session(
        id: 'other',
        role: UserRole.admin,
        token: 'other',
      );
      await t.pump();
      expect(request.cancelToken!.isCancelled, isTrue);
      adapter.heldGet!.complete();
      await settle(t);
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsNothing);
      expect(find.textContaining('访问已停止'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'reconnect consumes existing running job without another generation or confirmation',
    (t) async {
      adapter.jobs['job'] = fixture(state: 'RUNNING');
      await home(t, latest: 'job');
      await tapVisible(t, find.text('继续接收'));
      await settle(t);
      t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await t.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(
        adapter.requests.where((r) => r.path == '/ai/jobs/job/stream').length,
        1,
      );
      await t.scrollUntilVisible(
        find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('来源显示发布依赖仍需确认，影响范围需要人工核实。'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'map creates actual directed edge and source purpose uses original date/period',
    (t) async {
      await launch(t, '/ai/graph');
      final source = find.byWidgetPredicate(
        (w) =>
            w is PremiumDropdownField<String> &&
            w.decoration.labelText == '前置节点',
      );
      final target = find.byWidgetPredicate(
        (w) =>
            w is PremiumDropdownField<String> &&
            w.decoration.labelText == '后续节点',
      );
      await tapVisible(t, source);
      await t.tap(find.text('完成发布复核').last);
      await t.pumpAndSettle();
      await tapVisible(t, target);
      await t.tap(find.text('依赖风险待核实').last);
      await t.pumpAndSettle();
      await tapVisible(t, find.text('保存依赖关系'));
      final edge = adapter.requests.lastWhere(
        (r) => r.path == '/ai-maps/edges',
      );
      expect(edge.data, {
        'sourceId': 'node-0',
        'targetId': 'node-1',
        'label': '',
      });
      await tapVisible(t, find.widgetWithText(ListTile, '完成发布复核'));
      await t.tap(find.byTooltip('分析此来源'));
      await t.pumpAndSettle();
      await t.tap(find.text('解释风险'));
      await settle(t);
      final request = adapter.requests.lastWhere((r) => r.path == '/ai/jobs');
      expect(request.data, {
        'date': '2026-10-13',
        'period': 'day',
        'purpose': 'EXPLAIN_RISK',
        'focusSourceId': 'task:task-1',
        'scope': 'AUTHORIZED',
      });
      expect(
        adapter.requests.where((r) => r.path.endsWith('/confirm-task')),
        isEmpty,
      );
      await close(t);
    },
  );
  testWidgets(
    'real router source tap navigates to authorized original task request',
    (t) async {
      await launch(t, '/ai/jobs/job/actions/0', productionRouter: true);
      await tapVisible(t, find.widgetWithText(ListTile, '发布依赖清单'));
      expect(adapter.requests.any((r) => r.path == '/tasks/task-1'), isTrue);
      final detail = t.widget<DetailPage>(find.byType(DetailPage));
      expect(detail.resource, 'tasks');
      expect(detail.id, 'task-1');
      await close(t);
    },
  );
  testWidgets(
    'account switch clears protected node modal as well as underlying graph',
    (t) async {
      final c = await launch(t, '/ai/graph');
      await tapVisible(t, find.widgetWithText(ListTile, '完成发布复核'));
      expect(find.text('发布依赖清单'), findsOneWidget);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'other',
        role: UserRole.admin,
        token: 'other',
      );
      await t.pump();
      expect(find.text('发布依赖清单'), findsNothing);
      expect(find.text('节点访问已停止，请重新确认账号与权限'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('formal AI screens render actual HTTP data at360dp and1.5 text', (
    t,
  ) async {
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    final displayFont = FontLoader(AppTypography.displayFamily)
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/GenSenRoundedTW-B.ttf').readAsBytesSync(),
          ),
        ),
      );
    await displayFont.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(File(materialIconsFontPath).readAsBytesSync()),
        ),
      );
    await icons.load();
    final key = GlobalKey();
    final c = await launch(
      t,
      '/ai/jobs/job/actions/0',
      scale: 1.5,
      size: const Size(360, 800),
      boundary: key,
      latest: 'job',
      productionRouter: !AppConfig.mock,
    );
    for (final (label, route) in [
      ('34-ai-priority', '/ai'),
      ('35-ai-sources', '/ai/jobs/job/actions/0'),
      ('36-ai-draft', '/ai/jobs/job/edit'),
      ('37-ai-confirm', '/ai/jobs/job/confirm/0'),
      ('38-ai-map', '/ai/graph'),
      ('39-ai-usage', '/ai/usage'),
    ]) {
      c.read(routerProvider).go(route);
      await settle(t);
      expect(t.takeException(), isNull, reason: label);
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await render.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        final output = File(
          '${const String.fromEnvironment('SCREENSHOT_OUTPUT', defaultValue: '../output/flutter-evidence')}/$label.png',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(data!.buffer.asUint8List());
        img.dispose();
      });
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await t.drag(scrollable.first, const Offset(0, -900));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '$label scrolled');
      }
    }
    await close(t);
  });
}
