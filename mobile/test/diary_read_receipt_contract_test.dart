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
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/diary_read_receipt.dart';
import 'read_http_contract_test.dart' show ReadAdapter;
import 'support/local_test_state.dart';

class ReceiptAdapter extends ReadAdapter {
  int readStatus = 200;
  dynamic response = {'ok': true};
  Completer<void>? holdRead;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    if (o.path.endsWith('/read')) {
      requests.add(o);
      if (holdRead != null) await holdRead!.future;
      return ResponseBody.fromString(
        jsonEncode(
          readStatus == 200
              ? response
              : {
                  'code': readStatus == 403 ? 'FORBIDDEN' : 'ERROR',
                  'message': '登记未完成',
                },
        ),
        readStatus,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (o.path == '/logs/log-1') {
      requests.add(o);
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'log-1',
          'owner_id': 'u1',
          'business_date': '2026-10-12',
          'submitted': submitted,
          'submitted_at': '2026-10-12T09:30:00Z',
          'version': 3,
          'body': {'work': '受保护的日志正文', 'blockers': '真实阻碍'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return super.fetch(o, body, cancelFuture);
  }
}

void main() {
  late ReceiptAdapter adapter;
  late HttpRepository repo;
  late GlobalKey captureKey;
  const session = Session(id: 'u1', token: 'receipt-token');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = ReceiptAdapter();
    repo = HttpRepository('http://localhost/api', session.token);
    repo.dio.httpClientAdapter = adapter;
    captureKey = GlobalKey();
  });
  Future<ProviderContainer> launch(
    WidgetTester t, {
    String route = '/item/logs/log-1',
    double scale = 1,
  }) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
        repositoryProvider.overrideWithValue(repo),
        fontScaleProvider.overrideWith((ref) => scale),
      ],
    );
    addTearDown(c.dispose);
    c.read(routerProvider).go(route);
    await t.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: UncontrolledProviderScope(
          container: c,
          child: const PandoraApp(),
        ),
      ),
    );
    await settleLocalIo(t);
    await t.pumpAndSettle();
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await settleLocalIo(t);
  }

  Future<void> showReceipt(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.byType(DiaryReadReceipt),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.byType(DiaryReadReceipt));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('记录已读'));
    await t.pumpAndSettle();
  }

  int readCount() =>
      adapter.requests.where((o) => o.path.endsWith('/read')).length;

  test(
    'receipt exact encoded ID empty body and ok=true; invalidID and malformed response fail',
    () async {
      final result = await repo.execute(
        'logs',
        const Command('read', {
          'id': 'log/encoded',
          'version': 99,
          '今日工作': '不能发送正文',
        }, version: 99),
      );
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/logs/log%2Fencoded/read');
      expect(request.headers['Authorization'], 'Bearer receipt-token');
      expect(request.data, isEmpty);
      expect(result.id, 'log/encoded');
      expect(result.fields['ok'], true);
      for (final body in [
        {'ok': false},
        {'ok': 'true'},
        {},
        null,
        'unexpected',
      ]) {
        adapter.response = body;
        await expectLater(
          repo.execute('logs', const Command('read', {'id': 'log-1'})),
          throwsA(
            isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.server),
          ),
        );
      }
      final before = readCount();
      for (final id in [null, '', '   ']) {
        await expectLater(
          repo.execute('logs', Command('read', {'id': id})),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.validation,
            ),
          ),
        );
      }
      expect(readCount(), before);
    },
  );
  test('server read401/403/503 become typed failures', () async {
    for (final (status, kind) in [
      (401, FailureKind.unauthorized),
      (403, FailureKind.forbidden),
      (503, FailureKind.server),
    ]) {
      adapter.readStatus = status;
      await expectLater(
        repo.execute('logs', const Command('read', {'id': 'log-1'})),
        throwsA(isA<ApiFailure>().having((e) => e.kind, 'kind', kind)),
      );
    }
  });
  test(
    'Mock GET is read-only, explicit receipt retains version/body and rejects other draft',
    () async {
      final store = DemoStore()
        ..records['logs'] = [
          const Record(
            id: 'submitted',
            title: '正式日报',
            ownerId: 'u2',
            version: 7,
            fields: {'status': '已提交', '今日工作': '保持正文'},
          ),
          const Record(
            id: 'draft',
            title: '草稿',
            ownerId: 'u2',
            fields: {'status': '草稿'},
          ),
        ];
      final mock = MockRepository(session, store: store);
      final before = await mock.detail('logs', 'submitted');
      expect(before.fields.containsKey('readBy'), false);
      await mock.execute('logs', const Command('read', {'id': 'submitted'}));
      final after = await mock.detail('logs', 'submitted');
      expect(after.version, 7);
      expect(after.fields['今日工作'], '保持正文');
      expect(after.fields['readBy'], contains(session.name));
      await expectLater(
        mock.detail('logs', 'draft'),
        throwsA(isA<ApiFailure>()),
      );
      final own = MockRepository(const Session(id: 'u2'), store: store);
      await expectLater(
        own.execute('logs', const Command('read', {'id': 'draft'})),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  testWidgets(
    'detail/history/rebuild never writes, actual submitted time and unknown reading list',
    (t) async {
      final c = await launch(t);
      expect(find.text('提交于 10月12日 17:30'), findsOneWidget);
      expect(readCount(), 0);
      c.invalidate(itemProvider(('logs', 'log-1')));
      await settleLocalIo(t);
      expect(readCount(), 0);
      c.read(routerProvider).go('/history?id=log-1');
      await settleLocalIo(t);
      await t.drag(find.byType(ListView).first, const Offset(0, -700));
      await t.pumpAndSettle();
      expect(find.text('服务暂未提供阅读人员清单，不能据此判断是否已读。'), findsOneWidget);
      expect(find.text('暂无上级阅读记录'), findsNothing);
      expect(readCount(), 0);
      await close(t);
    },
  );
  testWidgets(
    'busy receipt deduplicates and only actual response confirms without new GET or write',
    (t) async {
      await launch(t);
      await showReceipt(t);
      adapter.holdRead = Completer<void>();
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      final button = t.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text('正在记录…'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      expect(readCount(), 1);
      expect(find.text('本次阅读已登记'), findsNothing);
      final requestCount = adapter.requests.length;
      adapter.holdRead!.complete();
      await settleLocalIo(t);
      expect(find.text('本次阅读已登记'), findsOneWidget);
      expect(find.text('记录已读'), findsNothing);
      expect(adapter.requests.length, requestCount);
      await close(t);
    },
  );
  testWidgets(
    '503/malformed receipt retains actual content and explicit retry succeeds',
    (t) async {
      final c = await launch(t);
      adapter.readStatus = 503;
      await showReceipt(t);
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      expect(find.textContaining('阅读登记未完成：'), findsOneWidget);
      expect(find.text('受保护的日志正文'), findsOneWidget);
      expect(find.text('本次阅读已登记'), findsNothing);
      adapter.readStatus = 200;
      adapter.response = {'ok': false};
      await t.ensureVisible(find.text('记录已读'));
      await t.pumpAndSettle();
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      expect(find.text('本次阅读已登记'), findsNothing);
      adapter.response = {'ok': true};
      await t.ensureVisible(find.text('记录已读'));
      await t.pumpAndSettle();
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      expect(find.text('本次阅读已登记'), findsOneWidget);
      expect(readCount(), 3);
      expect(c.read(sessionProvider).id, 'u1');
      await close(t);
    },
  );
  for (final status in [401, 403]) {
    testWidgets('receipt$status removes whole protected diary and comments', (
      t,
    ) async {
      await launch(t);
      adapter.readStatus = status;
      await showReceipt(t);
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      expect(find.text('受保护的日志正文'), findsNothing);
      expect(find.text('服务端实际评语'), findsNothing);
      expect(find.text('记录已读'), findsNothing);
      expect(find.text(status == 401 ? '登录已失效' : '无权访问'), findsOneWidget);
      await close(t);
    });
  }
  for (final replacement in [
    const Session(id: 'u2', token: 'other'),
    const Session(id: 'u1', token: 'renewed'),
  ]) {
    testWidgets('late receipt ignores ${replacement.id} token replacement', (
      t,
    ) async {
      final c = await launch(t);
      adapter.holdRead = Completer<void>();
      await showReceipt(t);
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      c.read(sessionProvider.notifier).state = replacement;
      await settleLocalIo(t);
      expect(find.text('受保护的日志正文'), findsNothing);
      adapter.holdRead!.complete();
      await settleLocalIo(t);
      expect(find.text('本次阅读已登记'), findsNothing);
      expect(readCount(), 1);
      await close(t);
    });
  }
  testWidgets(
    'draft/unknown submission hides receipt; disposed response does not publish',
    (t) async {
      adapter.submitted = false;
      final c = await launch(t);
      expect(find.byType(DiaryReadReceipt), findsNothing);
      expect(readCount(), 0);
      adapter.submitted = true;
      c.invalidate(itemProvider(('logs', 'log-1')));
      await settleLocalIo(t);
      adapter.holdRead = Completer<void>();
      await showReceipt(t);
      await t.tap(find.text('记录已读'));
      await settleLocalIo(t);
      c.read(routerProvider).go('/me');
      await settleLocalIo(t);
      adapter.holdRead!.complete();
      await settleLocalIo(t);
      expect(find.text('本次阅读已登记'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            home: Scaffold(
              body: DiaryReadReceipt(
                const Record(id: 'unknown', title: '未确认'),
                onAccessDenied: (_) {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('记录已读'), findsNothing);
      await close(t);
    },
  );
  testWidgets(
    'actual reading-list availability differs from explicit empty and malformed',
    (t) async {
      for (final (fields, message) in [
        (<String, dynamic>{}, '服务暂未提供阅读人员清单，不能据此判断是否已读。'),
        (<String, dynamic>{'readBy': ''}, '暂无阅读记录'),
        (<String, dynamic>{'readBy': '实际上级 · 实际时间'}, '实际上级 · 实际时间'),
        (<String, dynamic>{'readBy': 42}, '阅读人员清单格式未确认，请稍后重新读取。'),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            home: DiaryReadingHistory(
              Record(id: 'r', title: '', fields: fields),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
      }
      await close(t);
    },
  );
  testWidgets('actual diary reading recovery renders at360dp text1.5', (
    t,
  ) async {
    for (final (family, path) in [
      ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        materialIconsFontPath,
      ),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    await launch(t, scale: 1.5);
    adapter.readStatus = 503;
    await showReceipt(t);
    await t.tap(find.text('记录已读'));
    await settleLocalIo(t);
    await t.ensureVisible(find.text('记录已读'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final bitmap = await boundary.toImage(pixelRatio: 1);
      final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/evidence/stage3-rebuild/54-diary-reading-recovery-large.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      bitmap.dispose();
    });
    await close(t);
  });
}
