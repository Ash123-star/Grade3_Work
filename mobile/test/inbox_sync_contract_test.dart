import 'support/flutter_sdk_assets.dart';
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
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/settings/diary_sync_page.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'support/local_test_state.dart';

class InboxSyncAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int total = 31, serverVersion = 5;
  bool read = false,
      failWrite = false,
      forbiddenWrite = false,
      badCursor = false,
      lateForbidden = false;
  bool wrongOwner = false,
      wrongDate = false,
      submitted = false,
      emptyDiary = false;
  bool failDiary = false,
      forbiddenDiary = false,
      unknownTarget = false,
      removedTarget = false;
  Completer<void>? commandGate, diaryGate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(o);
    dynamic body = {'items': [], 'total': 0};
    var status = 200;
    final cursor = int.tryParse('${o.queryParameters['cursor'] ?? 0}') ?? 0;
    if (o.method == 'POST' && o.path.startsWith('/notifications/')) {
      if (commandGate != null) await commandGate!.future;
      status = forbiddenWrite
          ? 403
          : failWrite
          ? 503
          : 200;
      if (status == 200) read = true;
      body = {'ok': true};
    } else if ([
      '/tasks',
      '/reviews',
      '/notifications',
      '/organization/audit',
    ].contains(o.path)) {
      if (cursor > 0 && lateForbidden) status = 403;
      body = {
        'items': [
          for (
            var i = cursor;
            i < (cursor == 0 && total > 30 ? 30 : total);
            i++
          )
            {
              'id': 'item-$i',
              'title': i == 30 ? '后页唯一记录' : '工作消息$i',
              if (o.path == '/tasks') 'owner_id': 'u1',
              if (o.path == '/reviews') ...{
                'applicant_id': 'u2',
                'status': 'PENDING',
              },
              if (o.path == '/notifications') ...{
                'recipient_id': 'u1',
                'type': unknownTarget ? 'UNKNOWN' : 'TASK_ASSIGNED',
                'object_id': 'task-real',
                'is_read': read,
              },
              if (o.path == '/organization/audit') ...{
                'actor_id': 'u1',
                'type': 'TASK_ASSIGNED',
              },
              'created_at': '2026-10-12T16:30:00Z',
              'body': {'content': '已有授权内容'},
            },
        ],
        'total': total,
        if (!badCursor) 'nextCursor': '30',
      };
    } else if (o.path == '/logs') {
      if (diaryGate != null) await diaryGate!.future;
      status = forbiddenDiary
          ? 403
          : failDiary
          ? 503
          : 200;
      final date = o.queryParameters['date'] ?? '2026-10-13';
      body = {
        'items': emptyDiary
            ? []
            : [
                {
                  'id': 'diary',
                  'owner_id': wrongOwner ? 'u2' : 'u1',
                  'business_date': wrongDate ? '2026-10-12' : date,
                  'submitted': submitted,
                  'version': serverVersion,
                  'body': {'work': '服务器工作内容'},
                },
              ],
        'total': emptyDiary ? 0 : 1,
      };
    } else if (o.path == '/logs/diary') {
      if (diaryGate != null) await diaryGate!.future;
      status = forbiddenDiary
          ? 403
          : failDiary
          ? 503
          : 200;
      body = {
        'id': 'diary',
        'owner_id': wrongOwner ? 'u2' : 'u1',
        'business_date': wrongDate ? '2026-10-12' : '2026-10-13',
        'submitted': submitted,
        'version': serverVersion,
        'body': {'work': '服务器工作内容', 'tomorrow': '服务器明日计划'},
      };
    } else if (o.path == '/tasks/task-real') {
      status = removedTarget ? 404 : 200;
      body = {
        'id': 'task-real',
        'title': '真正任务详情',
        'owner_id': 'u2',
        'events': [],
      };
    } else if (o.path == '/profiles/u1') {
      body = {
        'id': 'u1',
        'name': '林小满',
        'profile': {'introduction': '清楚记录'},
      };
    }
    if (status != 200) {
      body = {'code': status == 403 ? 'FORBIDDEN' : 'TEST_FAILURE'};
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

HttpRepository inboxRepo(InboxSyncAdapter a) {
  final r = HttpRepository('http://inbox.test', 'old-token');
  r.dio.httpClientAdapter = a;
  return r;
}

Future<ProviderContainer> launchInbox(
  WidgetTester t,
  InboxSyncAdapter a,
  String route, {
  LocalDraft? local,
  int? revision,
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final c = testContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => const Session(token: 'old-token')),
      repositoryProvider.overrideWithValue(inboxRepo(a)),
      fontScaleProvider.overrideWith((ref) => scale),
      logDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
      selectedDateProvider.overrideWith((ref) => DateTime(2027, 2, 3)),
      reportDateProvider.overrideWith((ref) => DateTime(2025, 3, 4)),
      logFilterDateProvider.overrideWith((ref) => DateTime(2024, 4, 5)),
    ],
  );
  addTearDown(c.dispose);
  if (local != null) {
    await t.runAsync(
      () => c
          .read(draftStoreProvider)
          .write(
            revision == null
                ? DraftLocation.diary('u1', DateTime(2026, 10, 13))
                : DraftLocation.revision('u1', 'diary', revision),
            local,
          ),
    );
  }
  c.read(routerProvider).go(route);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const PandoraApp()),
  );
  await settleLocalIo(t);
  return c;
}

LocalDraft localDraft({int version = 4}) => LocalDraft(
  fields: {'今日工作': '本机未提交工作', '明日计划': '本机明日计划'},
  savedAt: DateTime.utc(2026, 10, 12, 16, 20),
  serverId: 'diary',
  serverVersion: version,
);

void main() {
  test(
    'common providers include all scoped pages and reject partial data',
    () async {
      SharedPreferences.setMockInitialValues({});
      for (final resource in ['tasks', 'reviews', 'notifications', 'audit']) {
        final a = InboxSyncAdapter(),
            c = testContainer(
              overrides: [
                sessionProvider.overrideWith((ref) => const Session()),
                repositoryProvider.overrideWithValue(inboxRepo(a)),
              ],
            );
        final p = resource == 'audit'
            ? auditRecordsProvider
            : recordsProvider(resource);
        final sub = c.listen(p, (_, _) {});
        try {
          final page = await c.read(p.future);
          expect(page.items.length, 31);
          expect(page.total, 31);
          expect(page.items.last.title, '后页唯一记录');
          a.badCursor = true;
          c.invalidate(recordsProvider(resource));
          await expectLater(c.read(p.future), throwsA(isA<ApiFailure>()));
        } finally {
          sub.close();
          c.dispose();
        }
      }
    },
  );

  testWidgets('late task/review/message records participate in search', (
    t,
  ) async {
    for (final resource in ['tasks', 'reviews', 'notifications']) {
      final a = InboxSyncAdapter();
      await launchInbox(t, a, '/list/$resource');
      await t.enterText(find.byType(TextField).first, '后页唯一');
      await t.pumpAndSettle();
      expect(find.text('后页唯一记录'), findsOneWidget);
      expect(
        a.requests.where((o) => o.queryParameters['cursor'] == '30'),
        isNotEmpty,
      );
      expect(find.text('已完成'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'profile counts include late notifications and pending approvals',
    (t) async {
      await launchInbox(t, InboxSyncAdapter(), '/me');
      expect(find.text('31'), findsNWidgets(2));
    },
  );

  testWidgets('late403 removes rows on refresh and preserves search context', (
    t,
  ) async {
    final a = InboxSyncAdapter();
    final c = await launchInbox(t, a, '/list/tasks');
    await t.enterText(find.byType(TextField).first, '后页唯一');
    await t.pumpAndSettle();
    expect(find.text('后页唯一记录'), findsOneWidget);
    a.lateForbidden = true;
    c.invalidate(recordsProvider('tasks'));
    await t.pump();
    await t.pump();
    expect(find.text('后页唯一记录'), findsNothing);
    await t.pumpAndSettle();
    expect(find.text('无权访问'), findsOneWidget);
    expect(find.text('暂无匹配记录'), findsNothing);
    expect(find.text('安全返回'), findsOneWidget);
  });

  testWidgets('individual read deduplicates, waits then opens real target', (
    t,
  ) async {
    final a = InboxSyncAdapter()
      ..total = 1
      ..commandGate = Completer<void>();
    final c = await launchInbox(t, a, '/list/notifications');
    await t.tap(find.text('工作消息0'));
    await settleLocalIo(t);
    await t.tap(find.text('工作消息0'));
    await t.tap(find.text('全部已读'));
    await t.pump();
    expect(a.requests.where((o) => o.method == 'POST').length, 1);
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/list/notifications',
    );
    a.commandGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('真正任务详情'), findsOneWidget);
    expect(a.requests.any((o) => o.path == '/tasks/task-real'), isTrue);
  });

  testWidgets('read-all failure retains unread and allows explicit retry', (
    t,
  ) async {
    final a = InboxSyncAdapter()
      ..total = 1
      ..failWrite = true;
    await launchInbox(t, a, '/list/notifications');
    await t.tap(find.text('全部已读'));
    await t.pumpAndSettle();
    expect(find.textContaining('消息操作未完成'), findsOneWidget);
    expect(find.textContaining('未读 ·'), findsOneWidget);
    a.failWrite = false;
    await t.tap(find.text('全部已读'));
    await t.pumpAndSettle();
    expect(find.textContaining('已读 ·'), findsOneWidget);
    expect(find.textContaining('消息操作未完成'), findsNothing);
    expect(a.requests.where((o) => o.method == 'POST').length, 2);
  });

  testWidgets(
    'read-all busy prevents competing read and stale account completion',
    (t) async {
      final a = InboxSyncAdapter()
        ..total = 1
        ..commandGate = Completer<void>();
      final c = await launchInbox(t, a, '/list/notifications');
      await t.tap(find.text('全部已读'));
      await settleLocalIo(t);
      await t.tap(find.text('工作消息0'));
      await settleLocalIo(t);
      expect(a.requests.where((o) => o.method == 'POST').length, 1);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        token: 'new-token',
      );
      await t.pumpAndSettle();
      final count = a.requests.length;
      a.commandGate!.complete();
      await t.pumpAndSettle();
      expect(a.requests.length, count);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/list/notifications',
      );
      expect(find.textContaining('消息操作未完成'), findsNothing);
    },
  );

  testWidgets(
    'message command403 clears protected rows until explicit permission recheck',
    (t) async {
      final a = InboxSyncAdapter()
        ..total = 1
        ..forbiddenWrite = true;
      await launchInbox(t, a, '/list/notifications');
      await t.tap(find.text('工作消息0'));
      await t.pumpAndSettle();
      expect(find.text('无权访问'), findsOneWidget);
      expect(find.text('工作消息0'), findsNothing);
      expect(find.textContaining('未读 ·'), findsNothing);
      a.forbiddenWrite = false;
      await t.tap(find.text('重新检查消息权限'));
      await t.pumpAndSettle();
      expect(find.text('工作消息0'), findsOneWidget);
      expect(find.textContaining('未读 ·'), findsOneWidget);
    },
  );

  testWidgets(
    'individual read failure and old-session response never navigate',
    (t) async {
      final a = InboxSyncAdapter()
        ..total = 1
        ..failWrite = true;
      final c = await launchInbox(t, a, '/list/notifications');
      await t.tap(find.text('工作消息0'));
      await t.pumpAndSettle();
      expect(find.textContaining('消息操作未完成'), findsOneWidget);
      expect(find.textContaining('未读 ·'), findsOneWidget);
      a.failWrite = false;
      a.commandGate = Completer<void>();
      await t.tap(find.text('工作消息0'));
      await settleLocalIo(t);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        token: 'new-token',
      );
      await t.pumpAndSettle();
      final count = a.requests.length;
      a.commandGate!.complete();
      await t.pumpAndSettle();
      expect(a.requests.length, count);
      expect(find.text('真正任务详情'), findsNothing);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/list/notifications',
      );
    },
  );

  testWidgets(
    'unknown target stays safe and deleted actual target explains return',
    (t) async {
      final a = InboxSyncAdapter()
        ..total = 1
        ..unknownTarget = true;
      final c = await launchInbox(t, a, '/list/notifications');
      await t.tap(find.text('工作消息0'));
      await t.pumpAndSettle();
      expect(find.textContaining('关联内容暂不可用'), findsOneWidget);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/list/notifications',
      );
      a.unknownTarget = false;
      a.removedTarget = true;
      c.invalidate(recordsProvider('notifications'));
      await t.pumpAndSettle();
      await t.tap(find.text('工作消息0'));
      await t.pumpAndSettle();
      expect(find.text('内容不可用'), findsOneWidget);
      expect(find.text('安全返回'), findsOneWidget);
    },
  );

  testWidgets(
    'real sync reads local/server version, rechecks without overwriting and retains original editor version',
    (t) async {
      final a = InboxSyncAdapter();
      final c = await launchInbox(
        t,
        a,
        '/conflict?date=2026-10-13',
        local: localDraft(),
      );
      expect(find.text('本机未提交工作'), findsOneWidget);
      expect(find.text('服务器工作内容'), findsOneWidget);
      expect(find.text('服务器草稿 · v5'), findsOneWidget);
      final query = a.requests
          .firstWhere((o) => o.path == '/logs')
          .queryParameters;
      expect(query['ownerId'], 'u1');
      expect(query['date'], '2026-10-13');
      expect(query['period'], 'day');
      a.serverVersion = 6;
      await t.tap(find.text('重新检查'));
      await settleLocalIo(t);
      expect(find.text('服务器草稿 · v6'), findsOneWidget);
      expect(a.requests.where((o) => o.method != 'GET'), isEmpty);
      final readback = await t.runAsync(
        () => c
            .read(draftStoreProvider)
            .read(DraftLocation.diary('u1', DateTime(2026, 10, 13))),
      );
      expect(readback!.fields['今日工作'], '本机未提交工作');
      expect(readback.serverVersion, 4);
      await t.tap(find.text('继续编辑'));
      await settleLocalIo(t);
      final editor = t.widget<FormPage>(find.byType(FormPage));
      expect(editor.kind, 'log-edit');
      expect(editor.id, 'diary');
      expect(editor.version, 4);
      expect(find.textContaining('版本已更新'), findsOneWidget);
      expect(c.read(selectedDateProvider), DateTime(2027, 2, 3));
      expect(c.read(reportDateProvider), DateTime(2025, 3, 4));
      expect(c.read(logFilterDateProvider), DateTime(2024, 4, 5));
    },
  );

  testWidgets(
    'revision sync reads original encrypted version and returns guarded revision editor',
    (t) async {
      final a = InboxSyncAdapter()..submitted = true;
      await launchInbox(
        t,
        a,
        '/conflict?date=2026-10-13&id=diary&version=3',
        local: localDraft(version: 3),
        revision: 3,
      );
      expect(find.text('本机未提交工作'), findsOneWidget);
      expect(find.text('当前生效 · v5'), findsOneWidget);
      expect(a.requests.where((o) => o.path == '/logs'), isEmpty);
      await t.tap(find.text('继续编辑'));
      await settleLocalIo(t);
      final editor = t.widget<FormPage>(find.byType(FormPage));
      expect(editor.kind, 'log-revise');
      expect(editor.id, 'diary');
      expect(editor.version, 3);
      expect(find.textContaining('版本已更新'), findsOneWidget);
    },
  );

  testWidgets(
    'submitted server diary preserves original local version and restores matching local draft in revision',
    (t) async {
      for (final version in [4, 5]) {
        final a = InboxSyncAdapter()..submitted = true;
        final c = await launchInbox(
          t,
          a,
          '/conflict?date=2026-10-13',
          local: localDraft(version: version),
        );
        await t.tap(find.text('继续编辑'));
        await settleLocalIo(t);
        final editor = t.widget<FormPage>(find.byType(FormPage));
        expect(editor.kind, 'log-revise');
        expect(editor.version, version);
        expect(editor.restoreDiaryDraft, isTrue);
        if (version == 4) {
          expect(find.textContaining('版本已更新'), findsOneWidget);
        } else {
          final input = t.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(input.controller!.text, '本机未提交工作');
        }
        final draft = await t.runAsync(
          () => c
              .read(draftStoreProvider)
              .read(DraftLocation.diary('u1', DateTime(2026, 10, 13))),
        );
        expect(draft!.fields['今日工作'], '本机未提交工作');
        expect(draft.serverVersion, version);
        expect(a.requests.where((o) => o.method != 'GET'), isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('invalid sync dates and revision versions perform no reads', (
    t,
  ) async {
    for (final suffix in [
      'date=2026-02-30',
      'date=oops',
      'id=diary',
      'version=3',
      'id=diary&version=0',
      'id=diary&version=no',
    ]) {
      final a = InboxSyncAdapter();
      await launchInbox(t, a, '/conflict?$suffix');
      expect(find.textContaining('日志日期或原版本无效'), findsOneWidget);
      expect(a.requests.where((o) => o.path.startsWith('/logs')), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'sync distinguishes empty/network/forbidden and rejects wrong owner or date',
    (t) async {
      final a = InboxSyncAdapter()..emptyDiary = true;
      final c = await launchInbox(t, a, '/conflict?date=2026-10-13');
      expect(find.textContaining('服务器暂无该日期日志'), findsOneWidget);
      a.emptyDiary = false;
      a.failDiary = true;
      await t.tap(find.text('重新检查'));
      // 等待实际 HTTP 重试退避（300ms + 900ms）结束再检查失败状态。
      for (var attempt = 0; attempt < 3; attempt++) {
        await settleLocalIo(t);
      }
      expect(find.text('暂时无法连接'), findsOneWidget);
      expect(find.textContaining('服务器暂无'), findsNothing);
      for (final kind in ['owner', 'date', 'forbidden']) {
        a.failDiary = false;
        a.wrongOwner = kind == 'owner';
        a.wrongDate = kind == 'date';
        a.forbiddenDiary = kind == 'forbidden';
        c.invalidate(diarySyncProvider(('2026-10-13', null, null)));
        await settleLocalIo(t);
        expect(find.text('无权访问'), findsOneWidget);
        expect(find.text('服务器工作内容'), findsNothing);
        expect(find.text('安全返回'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'independent sync date selection and account replacement discard old local/server results',
    (t) async {
      final a = InboxSyncAdapter()..emptyDiary = true;
      final c = await launchInbox(
        t,
        a,
        '/conflict?date=2026-10-13',
        local: localDraft(),
      );
      await t.tap(find.text('2026-10-13'));
      await t.pumpAndSettle();
      await t.tap(find.text('14').last);
      await t.tap(find.text('确定'));
      await settleLocalIo(t);
      expect(find.text('2026-10-14'), findsOneWidget);
      expect(find.text('本机未提交工作'), findsNothing);
      expect(c.read(logDateProvider), DateTime(2026, 10, 13));
      a.diaryGate = Completer<void>();
      c.read(routerProvider).go('/conflict?date=2026-10-13');
      await settleLocalIo(t);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        token: 'new-token',
      );
      await settleLocalIo(t);
      a.diaryGate!.complete();
      await settleLocalIo(t);
      expect(find.text('本机未提交工作'), findsNothing);
      expect(find.text('服务器工作内容'), findsNothing);
      final oldDraft = await t.runAsync(
        () => c
            .read(draftStoreProvider)
            .read(DraftLocation.diary('u1', DateTime(2026, 10, 13))),
      );
      expect(oldDraft!.fields['今日工作'], '本机未提交工作');
    },
  );

  testWidgets('actual notification/sync routes render at360dp with1.5 text', (
    t,
  ) async {
    for (final (family, path) in [
      ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
      ('MaterialIcons', materialIconsFontPath),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    for (final (route, name) in [
      ('/list/notifications', '50-notifications-large'),
      ('/conflict?date=2026-10-13', '51-diary-sync-large'),
    ]) {
      final a = InboxSyncAdapter()..total = 2;
      final c = await launchInbox(t, a, route, local: localDraft(), scale: 1.5);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: UncontrolledProviderScope(
            container: c,
            child: const PandoraApp(),
          ),
        ),
      );
      await settleLocalIo(t);
      expect(t.takeException(), isNull, reason: name);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        final output = File('../output/flutter-evidence/$name.png');
        output.parent.createSync(recursive: true);
        await output.writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
}
