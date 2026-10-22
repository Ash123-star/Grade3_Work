import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/ai_work_repository.dart';
import 'package:pandora_mobile/data/sse_client.dart';
import 'package:pandora_mobile/features/ai_map/workbench_page.dart';
import 'package:pandora_mobile/features/ai_map/work_management_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'ai_workbench_test.dart' show WorkFixture;
import 'support/local_test_state.dart';

class ReplayClient extends SseClient {
  ReplayClient() : super('http://localhost', 'test');
  final cursors = <String?>[];
  @override
  Stream<ServerEvent> connect(
    String path, {
    String? lastEventId,
    CancelToken? cancel,
  }) async* {
    cursors.add(lastEventId);
    if (cursors.length == 1) {
      yield const ServerEvent('change', '10', '{"version":4}');
      yield const ServerEvent('change', '10', '{"version":4}');
      yield const ServerEvent('change', '8', '{"version":2}');
      yield const ServerEvent('change', 'bad', '{}');
      yield const ServerEvent('refresh', null, '{"version":4}');
    } else {
      yield const ServerEvent('change', '11', '{"version":5}');
      yield const ServerEvent('access-lost', null, '{"status":404}');
    }
  }
}

class DeferredWork extends WorkFixture {
  Completer<WorkItem>? pendingGet, pendingConfirm;
  @override
  Future<WorkItem> get(String id) => pendingGet?.future ?? super.get(id);
  @override
  Future<WorkItem> confirm(WorkItem item, String key) =>
      pendingConfirm?.future ?? super.confirm(item, key);
}

class ContinuationWork extends WorkFixture {
  int revision = 1;
  String state = 'WAITING_INPUT';
  Object? failure;
  Completer<WorkItem>? pendingMessage;
  final keys = <String>[];
  final versions = <int>[];
  final actions = <String>[];
  final messages = <Map<String, dynamic>>[];
  @override
  WorkItem get value => WorkItem({
    ...super.value.json,
    'version': revision,
    'state': state,
    'messages': messages.toList(),
    'result': {
      'summary': state == 'CANCELLED' ? '已停止后续办理，已创建的任务仍保留' : '请补充交付时间',
    },
    'plan': {
      'questions': ['这项任务什么时候交？'],
    },
    'receipts': [
      {
        'step_key': 'done',
        'result': {'summary': '已创建一项任务', 'taskId': 'existing-task'},
      },
    ],
  });
  @override
  Future<WorkItem> message(
    WorkItem item,
    String text,
    List<String> files,
    String key, {
    String? ownerId,
    String? taskId,
    int? taskVersion,
  }) async {
    keys.add(key);
    versions.add(item.version);
    if (failure != null) throw failure!;
    if (pendingMessage != null) return pendingMessage!.future;
    messages.add({
      'body': {'text': text, 'attachmentIds': files},
    });
    revision++;
    state = 'QUEUED';
    return value;
  }

  @override
  Future<WorkItem> command(WorkItem item, String action, String key) async {
    keys.add(key);
    versions.add(item.version);
    actions.add(action);
    if (failure != null) throw failure!;
    revision++;
    state = action == 'cancel' ? 'CANCELLED' : 'QUEUED';
    return value;
  }
}

void main() {
  testWidgets(
    'capability refresh failure pauses submission while retaining the draft',
    (tester) async {
      var offline = false;
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          workRepositoryProvider.overrideWithValue(WorkFixture()),
          workCapabilitiesProvider.overrideWith((_) async {
            if (offline) {
              throw const ApiFailure(FailureKind.unavailable, 'offline');
            }
            return const WorkCapabilities(enabled: true, configured: true);
          }),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: appTheme(), home: const WorkbenchPage()),
        ),
      );
      await settleLocalIo(tester);
      await tester.enterText(find.byType(TextField), '连接恢复后继续整理');
      offline = true;
      container.invalidate(workCapabilitiesProvider);
      await settleLocalIo(tester);
      expect(find.text('连接恢复后继续整理'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      offline = false;
      container.invalidate(workCapabilitiesProvider);
      await settleLocalIo(tester);
      expect(find.text('连接恢复后继续整理'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets(
    'unavailable capability hides submit and invalid list never becomes demo empty state',
    (tester) async {
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          workCapabilitiesProvider.overrideWith(
            (_) => Future.error(
              const ApiFailure(FailureKind.unavailable, 'offline'),
            ),
          ),
          workListProvider.overrideWith(
            (_) => Future.error(
              const ApiFailure(
                FailureKind.server,
                'damaged',
                code: 'WORK_INVALID_RESPONSE',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: appTheme(), home: const WorkbenchPage()),
        ),
      );
      await settleLocalIo(tester);
      expect(find.text('把事情交给我'), findsNothing);
      expect(find.text('暂时无法确认办理结果，请刷新后重试'), findsOneWidget);
      expect(find.byType(WorkComposer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  Future<ProviderContainer> openDetail(
    WidgetTester tester,
    ContinuationWork repo,
  ) async {
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith((_) => const Session()),
        workRepositoryProvider.overrideWithValue(repo),
        workEventsProvider('work').overrideWith((_) => const Stream.empty()),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appTheme(),
          home: const WorkDetailPage('work'),
        ),
      ),
    );
    await settleLocalIo(tester);
    return container;
  }

  testWidgets(
    'reopening restores questions messages cancellation and committed receipts',
    (tester) async {
      final repo = ContinuationWork();
      var container = await openDetail(tester, repo);
      expect(find.text('这项任务什么时候交？'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '十月三十日下午五点');
      await tester.tap(find.text('发送'));
      await settleLocalIo(tester);
      expect(repo.versions, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = await openDetail(tester, repo);
      expect(find.text('十月三十日下午五点'), findsOneWidget);
      expect(find.text('已创建一项任务'), findsOneWidget);
      await tester.tap(find.text('停止'));
      await settleLocalIo(tester);
      expect(repo.actions, ['cancel']);
      expect(repo.versions, [1, 2]);
      expect(find.byType(WorkComposer), findsNothing);
      expect(find.text('已创建一项任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = await openDetail(tester, repo);
      expect(find.text('已停止'), findsOneWidget);
      expect(find.text('已创建一项任务'), findsOneWidget);
      expect(repo.actions, ['cancel']);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'message in flight disables cancellation and restores current server version',
    (tester) async {
      final repo = ContinuationWork()..pendingMessage = Completer<WorkItem>();
      final container = await openDetail(tester, repo);
      await tester.enterText(find.byType(TextField), '补充材料要求');
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '停止'))
            .onPressed,
        isNull,
      );
      repo.revision = 2;
      repo.state = 'QUEUED';
      repo.pendingMessage!.complete(repo.value);
      await settleLocalIo(tester);
      await tester.tap(find.text('停止'));
      await settleLocalIo(tester);
      expect(repo.versions, [1, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'message conflict refreshes version preserves text and rotates changed request key',
    (tester) async {
      final repo = ContinuationWork()
        ..failure = const ApiFailure(
          FailureKind.conflict,
          'conflict',
          code: 'VERSION_CONFLICT',
        );
      final container = await openDetail(tester, repo);
      repo.revision = 4;
      await tester.enterText(find.byType(TextField), '补充截止时间');
      await tester.tap(find.text('发送'));
      await settleLocalIo(tester);
      expect(find.text('补充截止时间'), findsOneWidget);
      expect(find.text('内容已更新，请刷新后再试'), findsWidgets);
      repo.failure = null;
      await tester.tap(find.text('发送'));
      await settleLocalIo(tester);
      expect(repo.versions, [1, 4]);
      expect(repo.keys[0], isNot(repo.keys[1]));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'retry keeps timeout key and uses a separate key for cancellation',
    (tester) async {
      final repo = ContinuationWork()
        ..state = 'PARTIAL'
        ..failure = const ApiFailure(FailureKind.timeout, 'timeout');
      final container = await openDetail(tester, repo);
      await tester.ensureVisible(find.text('继续处理'));
      await tester.tap(find.text('继续处理'));
      await settleLocalIo(tester);
      repo.failure = null;
      await tester.ensureVisible(find.text('继续处理'));
      await tester.tap(find.text('继续处理'));
      await settleLocalIo(tester);
      expect(repo.keys[0], repo.keys[1]);
      expect(find.text('已创建一项任务'), findsOneWidget);
      await tester.tap(find.text('停止'));
      await settleLocalIo(tester);
      expect(repo.actions, ['retry', 'retry', 'cancel']);
      expect(repo.keys[2], isNot(repo.keys[1]));
      expect(repo.versions, [1, 1, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'command permission failure immediately removes private data without waiting for SSE',
    (tester) async {
      final repo = ContinuationWork()
        ..failure = const ApiFailure(FailureKind.forbidden, 'denied');
      final container = await openDetail(tester, repo);
      await tester.enterText(find.byType(TextField), '私人补充');
      await tester.tap(find.text('停止'));
      await settleLocalIo(tester);
      expect(find.text('你目前无法办理这项操作'), findsOneWidget);
      expect(find.text('私人补充'), findsNothing);
      expect(find.text('已创建一项任务'), findsNothing);
      expect(find.byType(WorkComposer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'membership restriction hides cached task options with unchanged token',
    (tester) async {
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          workRepositoryProvider.overrideWithValue(WorkFixture()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: WorkTargetPicker('CHECK_DELIVERY')),
          ),
        ),
      );
      await settleLocalIo(tester);
      expect(find.text(WorkFixture.longTaskTitle), findsOneWidget);
      container.read(sessionProvider.notifier).state = const Session(
        active: false,
        status: 'PENDING',
      );
      await tester.pump();
      expect(find.text(WorkFixture.longTaskTitle), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  test('SSE replay advances cursor once and stops on lost access', () async {
    final client = ReplayClient(), events = <ServerEvent>[];
    final stopped = Completer<ApiFailure>();
    final container = testContainer(
      overrides: [sseClientProvider.overrideWithValue(client)],
    );
    final subscription = container.listen(workEventsProvider('work'), (
      _,
      value,
    ) {
      if (!value.hasError && value.hasValue) events.add(value.requireValue);
      if (value.error is ApiFailure && !stopped.isCompleted) {
        stopped.complete(value.error as ApiFailure);
      }
    });
    try {
      expect(
        (await stopped.future.timeout(const Duration(seconds: 7))).kind,
        FailureKind.notFound,
      );
      expect(client.cursors, ['0', '10']);
      expect(events.where((e) => e.event == 'change').map((e) => e.id), [
        '10',
        '11',
      ]);
      expect(
        events.where((e) => e.event == 'refresh').length,
        greaterThanOrEqualTo(2),
      );
    } finally {
      subscription.close();
      container.dispose();
      client.dio.close(force: true);
    }
  });

  testWidgets(
    'late GET cannot restore private content after same-token account switch',
    (tester) async {
      final repo = DeferredWork(),
          events = StreamController<ServerEvent>.broadcast();
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          workRepositoryProvider.overrideWithValue(repo),
          workEventsProvider('work').overrideWith((_) => events.stream),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const WorkDetailPage('work'),
          ),
        ),
      );
      await settleLocalIo(tester);
      expect(find.text('请核对负责人和截止时间'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '私人补充内容');
      repo.pendingGet = Completer<WorkItem>();
      events.add(const ServerEvent('change', '12', '{"version":5}'));
      await tester.pump();
      container.read(sessionProvider.notifier).state = const Session(
        id: 'second',
      );
      await tester.pump();
      repo.pendingGet!.complete(repo.value);
      await settleLocalIo(tester);
      expect(find.text('请核对负责人和截止时间'), findsNothing);
      expect(find.text('私人补充内容'), findsNothing);
      expect(find.text('账号已切换，请重新打开事项'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      unawaited(events.close());
    },
  );

  testWidgets('stream access loss fences a late command and clears input', (
    tester,
  ) async {
    final repo = DeferredWork(),
        events = StreamController<ServerEvent>.broadcast();
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith((_) => const Session()),
        workRepositoryProvider.overrideWithValue(repo),
        workEventsProvider('work').overrideWith((_) => events.stream),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appTheme(),
          home: const WorkDetailPage('work'),
        ),
      ),
    );
    await settleLocalIo(tester);
    repo.pendingConfirm = Completer<WorkItem>();
    await tester.ensureVisible(find.text('创建任务'));
    await tester.tap(find.text('创建任务'));
    await tester.pump();
    events.addError(const ApiFailure(FailureKind.notFound, '这件事已无法查看，请返回事项列表'));
    await tester.pump();
    repo.completed = true;
    repo.pendingConfirm!.complete(repo.value);
    await settleLocalIo(tester);
    expect(find.text('任务已创建'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('这件事已清除或暂时无法访问'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    unawaited(events.close());
  });

  testWidgets(
    'GET cannot roll back version and same-version refresh removes stale sources',
    (tester) async {
      final repo = DeferredWork()..completed = true;
      final events = StreamController<ServerEvent>.broadcast();
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          workRepositoryProvider.overrideWithValue(repo),
          workEventsProvider('work').overrideWith((_) => events.stream),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(),
            home: const WorkDetailPage('work'),
          ),
        ),
      );
      await settleLocalIo(tester);
      expect(find.text('任务已创建'), findsWidgets);
      repo.pendingGet = Completer<WorkItem>();
      events.add(const ServerEvent('change', '30', '{"version":4}'));
      await tester.pump();
      repo.pendingGet!.complete(
        WorkItem({
          ...repo.value.json,
          'version': 2,
          'result': {'summary': '过时的正文'},
        }),
      );
      await settleLocalIo(tester);
      expect(find.text('过时的正文'), findsNothing);
      repo.pendingGet = Completer<WorkItem>();
      events.add(const ServerEvent('refresh', null, '{"version":4}'));
      await tester.pump();
      repo.pendingGet!.complete(
        WorkItem({
          ...repo.value.json,
          'planValid': false,
          'plan': {},
          'receipts': [],
          'result': {'summary': '依据已更新，请重新核对'},
        }),
      );
      await settleLocalIo(tester);
      expect(find.text('任务已创建'), findsNothing);
      expect(find.text('依据已更新，请重新核对'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      unawaited(events.close());
    },
  );
}
