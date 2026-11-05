import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/live_notifications.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/dashboard/logs_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

import 'live_notifications_contract_test.dart'
    show LiveAdapter, event, liveRepo;
import 'support/local_test_state.dart';

const _employee = Session(role: UserRole.employee, dispatch: false);

class _DiaryRepository extends MockRepository {
  _DiaryRepository(this.load) : super(_employee);
  final Future<PageResult> Function(Query query) load;
  final queries = <Query>[];

  @override
  Future<PageResult> list(String resource, Query query) {
    expect(resource, 'logs');
    queries.add(query);
    return load(query);
  }
}

class _DiaryLiveAdapter extends LiveAdapter {
  String title = '通知前日志';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    if (options.path != '/logs') return super.fetch(options, body, cancel);
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': 'live-log',
            'title': title,
            'owner_id': 'u1',
            'business_date': '2026-11-05',
            'submitted': true,
          },
        ],
        'total': 1,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required List<Override> overrides,
  Session session = _employee,
}) async {
  tester.view.physicalSize = const Size(412, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = testContainer(
    overrides: [
      sessionProvider.overrideWith((_) => session),
      todayDraftProvider.overrideWith((_, _) async => null),
      ...overrides,
    ],
  );
  await tester.pumpWidget(
    OwnedTestProviderScope(
      container: container,
      child: MaterialApp(theme: appTheme(), home: const LogsPage()),
    ),
  );
  await tester.pump();
  expect(find.text('任务管理 ›'), findsNothing);
  return container;
}

List<Override> _withRepository(
  _DiaryRepository repository,
  DateTime Function() now,
) => [
  repositoryProvider.overrideWithValue(repository),
  recentDiaryClockProvider.overrideWithValue(now),
];

Record _diary(String id, String title, String day) => Record(
  id: id,
  title: title,
  ownerId: 'u1',
  fields: {
    'businessDate': day,
    'status': '已提交',
    'submittedAt': '2026-11-05T01:00:00Z',
  },
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'three business days use owner scope and preserve historical access',
    (tester) async {
      final recent = _diary('first', '今天补交的前天日志', '2026-11-03');
      final older = _diary('old', '十月历史日志', '2026-10-01');
      final repository = _DiaryRepository(
        (query) async => query.from == null
            ? PageResult([recent, older], total: 2)
            : PageResult([recent], total: 1),
      );
      await _mount(
        tester,
        overrides: _withRepository(
          repository,
          () => DateTime.utc(2026, 11, 5, 3),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('近三天'), findsOneWidget);
      final positions = [
        for (final day in ['2026-11-03', '2026-11-04', '2026-11-05'])
          tester.getTopLeft(find.byKey(ValueKey('recent-diary-day:$day'))).dy,
      ];
      expect(positions[0], lessThan(positions[1]));
      expect(positions[1], lessThan(positions[2]));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recent-diary-day:2026-11-03')),
          matching: find.text('今天补交的前天日志'),
        ),
        findsOneWidget,
      );
      expect(find.text('昨天暂无日志'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recent-diary-write:2026-11-03')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('recent-diary-write:2026-11-04')),
        findsOneWidget,
      );
      expect(repository.queries.single.ownerId, 'u1');
      expect(repository.queries.single.from, DateTime.utc(2026, 11, 2, 16));
      expect(repository.queries.single.to, DateTime.utc(2026, 11, 5, 16));

      await tester.tap(find.text('近三天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部日期').last);
      await tester.pumpAndSettle();
      expect(find.text('十月历史日志'), findsOneWidget);
      expect(repository.queries.last.from, isNull);
      expect(repository.queries.last.to, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading and retryable failure do not become empty diary days', (
    tester,
  ) async {
    final gate = Completer<PageResult>();
    var calls = 0;
    final repository = _DiaryRepository(
      (_) => calls++ == 0
          ? gate.future
          : Future.value(const PageResult([], total: 0)),
    );
    await _mount(
      tester,
      overrides: _withRepository(
        repository,
        () => DateTime.utc(2026, 11, 5, 3),
      ),
    );
    expect(find.text('前天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.textContaining('暂无日志'), findsNothing);
    gate.completeError(const ApiFailure(FailureKind.unavailable, '网络暂不可用'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无日志'), findsNothing);
    expect(find.text('写这天的日志'), findsNothing);
    expect(find.text('重新加载'), findsNWidgets(3));

    await tester.tap(find.text('重新加载').first);
    await tester.pumpAndSettle();
    expect(find.text('前天暂无日志'), findsOneWidget);
    expect(find.text('今天暂无日志'), findsOneWidget);
    expect(repository.queries, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Shanghai midnight changes all date sections and query boundaries',
    (tester) async {
      var now = DateTime.utc(2026, 12, 31, 15, 59, 59);
      final repository = _DiaryRepository(
        (_) async => const PageResult([], total: 0),
      );
      await _mount(tester, overrides: _withRepository(repository, () => now));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-diary-day:2026-12-29')),
        findsOneWidget,
      );

      now = DateTime.utc(2026, 12, 31, 16, 0, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recent-diary-day:2026-12-29')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('recent-diary-day:2027-01-01')),
        findsOneWidget,
      );
      expect(repository.queries.last.from, DateTime.utc(2026, 12, 29, 16));
      expect(repository.queries.last.to, DateTime.utc(2027, 1, 1, 16));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an old account response cannot populate the new account sections',
    (tester) async {
      final oldResponse = Completer<PageResult>();
      final repository = _DiaryRepository(
        (query) => query.ownerId == 'u1'
            ? oldResponse.future
            : Future.value(
                PageResult([_diary('mine', '新账号日志', '2026-11-05')], total: 1),
              ),
      );
      final container = await _mount(
        tester,
        overrides: _withRepository(
          repository,
          () => DateTime.utc(2026, 11, 5, 3),
        ),
      );
      container.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        role: UserRole.employee,
        dispatch: false,
      );
      await tester.pumpAndSettle();
      oldResponse.complete(
        PageResult([_diary('other', '旧账号私密日志', '2026-11-05')], total: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('新账号日志'), findsOneWidget);
      expect(find.text('旧账号私密日志'), findsNothing);
      expect(repository.queries.map((query) => query.ownerId), ['u1', 'u2']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('own submission refreshes the visible three day range', (
    tester,
  ) async {
    final store = DemoStore()..records['logs'] = [];
    final repository = MockRepository(_employee, store: store);
    await _mount(
      tester,
      overrides: [repositoryProvider.overrideWithValue(repository)],
    );
    await tester.pumpAndSettle();
    expect(find.text('今天暂无日志'), findsOneWidget);
    await tester.tap(find.byTooltip('创建日志'));
    await settleLocalIo(tester);
    final editor = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.enabled == true,
    );
    await waitForLocalState(tester, editor);
    await tester.enterText(editor, '验收三日分区提交后立即刷新');
    await tester.tap(find.text('提交').last);
    final today = shanghaiWallTime(DateTime.now());
    await waitForLocalState(
      tester,
      find.text('${today.month}月${today.day}日工作日志'),
    );
    await tester.pumpAndSettle();
    expect(find.text('今天暂无日志'), findsNothing);
    expect(
      find.byKey(ValueKey('diary-row:${store.records['logs']!.single.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('log notifications invalidate the visible range', (tester) async {
    final adapter = _DiaryLiveAdapter();
    final repository = liveRepo(adapter);
    addTearDown(() => repository.dio.close(force: true));
    final container = await _mount(
      tester,
      session: const Session(
        token: 'live-token',
        role: UserRole.employee,
        dispatch: false,
      ),
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        recentDiaryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 5, 3),
        ),
      ],
    );
    container.listen(liveNotificationsProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(find.text('通知前日志'), findsOneWidget);
    expect(adapter.streams, hasLength(1));
    adapter.title = '通知后日志';
    adapter.send(event(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(find.text('通知后日志'), findsOneWidget);
    expect(find.text('通知前日志'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.mock);
}
