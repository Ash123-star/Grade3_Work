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
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/state/live_notifications.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/repositories/notification_stream.dart';
import 'support/local_test_state.dart';

String event(int sequence, {String id = 'notice', int? row}) =>
    'id: $sequence\r\nevent: notification\r\ndata: ${jsonEncode({'sequence': row ?? sequence, 'id': id, 'type': 'TASK_ASSIGNED', 'object_id': 'task', 'title': '中文消息'})}\r\n\r\n';

class LiveAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final streams = <StreamController<Uint8List>>[];
  int streamStatus = 200, notices = 0, people = 31;
  bool jsonStream = false, badCursor = false, laterForbidden = false;
  Completer<void>? meGate;
  int canceled = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    requests.add(o);
    if (o.path == '/notifications/stream' &&
        streamStatus == 200 &&
        !jsonStream) {
      final s = StreamController<Uint8List>(onCancel: () => canceled++);
      streams.add(s);
      return ResponseBody(
        s.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    var status = 200;
    dynamic data = {'items': [], 'total': 0};
    final cursor = int.tryParse('${o.queryParameters['cursor'] ?? 0}') ?? 0;
    if (o.path == '/notifications/stream') {
      status = streamStatus;
      data = {'code': 'FORBIDDEN'};
    } else if (o.path == '/notifications') {
      data = {
        'items': [
          for (var i = 0; i < notices; i++)
            {
              'id': 'notice-$i',
              'title': '实际通知$i',
              'recipient_id': 'u1',
              'type': 'TASK_ASSIGNED',
              'object_id': 'task',
              'is_read': false,
            },
        ],
        'total': notices,
      };
    } else if (o.path == '/organization') {
      data = {
        'departments': [
          {'id': 'd1', 'name': '产品部'},
        ],
        'teams': [
          {'id': 't1', 'name': '体验团队', 'department_id': 'd1'},
        ],
      };
    } else if ([
      '/organization/people',
      '/dashboard/personal',
      '/dashboard/company',
      '/organization/audit',
    ].contains(o.path)) {
      if (cursor > 0 && laterForbidden) status = 403;
      data = {
        'items': [
          for (
            var i = cursor;
            i < (cursor == 0 && people > 30 ? 30 : people);
            i++
          )
            {
              'id': 'record-$i',
              'title': i == 30 ? '最后一页成员或重点' : '授权记录$i',
              'name': i == 30 ? '最后一页成员或重点' : '授权记录$i',
              'owner_id': o.queryParameters['ownerId'] ?? 'u1',
              'department_id': 'd1',
              'team_id': 't1',
              'status': 'ACTIVE',
              'body': {'text': '真实正文$i'},
            },
        ],
        'total': people,
        if (!badCursor) 'nextCursor': '30',
      };
    } else if (o.path == '/auth/me') {
      if (meGate != null) await meGate!.future;
      data = {
        'id': 'u1',
        'name': '林小满',
        'status': 'ACTIVE',
        'role': 'LEADER',
        'dispatch_enabled': true,
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
  void send(String text) {
    final bytes = utf8.encode(text);
    for (var i = 0; i < bytes.length; i += 3) {
      streams.last.add(
        Uint8List.fromList(bytes.sublist(i, (i + 3).clamp(0, bytes.length))),
      );
    }
  }
}

HttpRepository liveRepo(LiveAdapter a, [String token = 'live-token']) {
  final r = HttpRepository('http://live.test', token);
  r.dio.httpClientAdapter = a;
  return r;
}

Future<ProviderContainer> launchLive(
  WidgetTester t,
  LiveAdapter a, {
  String route = '/list/notifications',
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final c = testContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => const Session(token: 'live-token')),
      repositoryProvider.overrideWithValue(liveRepo(a)),
      fontScaleProvider.overrideWith((ref) => scale),
    ],
  );
  addTearDown(c.dispose);
  c.read(routerProvider).go(route);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const PandoraApp()),
  );
  await settleLocalIo(t);
  return c;
}

void main() {
  test(
    'parser accepts fragmented UTF8 CRLF heartbeat and retains metadata only',
    () async {
      final bytes = utf8.encode(
        ': keepalive\r\n\r\nevent: unknown\ndata: ignored\n\n${event(123)}',
      );
      final signals = await parseNotificationSignals(
        Stream.fromIterable([
          for (var i = 0; i < bytes.length; i++) [bytes[i]],
        ]),
      ).toList();
      expect(signals.length, 1);
      expect(signals.single.sequence, 123);
    },
  );
  test(
    'invalid sequence mismatches malformed and oversized frames fail',
    () async {
      for (final text in [
        event(0),
        event(5, row: 6),
        event(1, id: ''),
        'event: notification\nid: 2\ndata: invalid\n\n',
        'data: ${'x' * 65537}',
        'event: notification\nid: 2\ndata: {}',
      ]) {
        await expectLater(
          parseNotificationSignals(Stream.value(utf8.encode(text))).toList(),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
  test(
    'gateway sends actual auth Accept and replay header and rejects response format',
    () async {
      final a = LiveAdapter(), cancel = CancelToken();
      final received = <NotificationSignal>[];
      final sub = NotificationStream(
        liveRepo(a).dio,
      ).connect(41, cancel).listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final o = a.requests.single;
      expect(o.path, '/notifications/stream');
      expect(o.headers['Authorization'], 'Bearer live-token');
      expect(o.headers['Accept'], 'text/event-stream');
      expect(o.headers['Last-Event-ID'], '41');
      a.send(event(42));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received.last.sequence, 42);
      cancel.cancel();
      await sub.cancel();
      await a.streams.single.close();
      a.jsonStream = true;
      await expectLater(
        NotificationStream(liveRepo(a).dio).connect(0, CancelToken()).toList(),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'contextual tree and detail read31st with owner and reject partial/403 not false404',
    () async {
      for (final resource in [
        'organization/tree',
        'dashboard/personal',
        'dashboard/company',
        'audit',
      ]) {
        final a = LiveAdapter(), r = liveRepo(LiveAdapter());
        r.dio.httpClientAdapter = a;
        final record = await r.detail(
          resource,
          resource == 'organization/tree' ? 'tree' : 'record-30',
          ownerId: 'u2',
        );
        if (resource == 'organization/tree') {
          expect((record.fields['people'] as List).length, 31);
        } else {
          expect(record.id, 'record-30');
          expect(
            a.requests.every((o) => o.queryParameters['ownerId'] == 'u2'),
            isTrue,
          );
        }
        a.badCursor = true;
        await expectLater(
          r.detail(resource, 'missing', ownerId: 'u2'),
          throwsA(
            isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.server),
          ),
        );
        a.badCursor = false;
        a.laterForbidden = true;
        await expectLater(
          r.detail(resource, 'record-0', ownerId: 'u2'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.forbidden,
            ),
          ),
        );
      }
    },
  );
  testWidgets('tree scoped search and refresh403 clears all names', (t) async {
    final a = LiveAdapter();
    final c = await launchLive(t, a, route: '/me/organization');
    await t.enterText(find.byType(TextField), '最后一页');
    await t.pumpAndSettle();
    expect(find.text('最后一页成员或重点'), findsOneWidget);
    a.laterForbidden = true;
    c.invalidate(organizationTreeProvider);
    await t.pumpAndSettle();
    expect(find.text('无权访问'), findsOneWidget);
    expect(find.text('最后一页成员或重点'), findsNothing);
    expect(find.text('产品部'), findsNothing);
    c.dispose();
    await t.pumpWidget(const SizedBox.shrink());
    await settleLocalIo(t);
  });
  if (AppConfig.mock) {
    testWidgets(
      'explicit mock never opens remote live notification transport',
      (t) async {
        final a = LiveAdapter();
        final c = await launchLive(t, a);
        expect(a.streams, isEmpty);
        expect(find.text('消息实时更新中'), findsNothing);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
      },
    );
  } else {
    testWidgets(
      'real signals debounce full list refresh, skip duplicates and reconnect with cursor',
      (t) async {
        final a = LiveAdapter();
        final c = await launchLive(t, a);
        expect(find.text('消息实时更新中'), findsOneWidget);
        final initial = a.requests
            .where((o) => o.path == '/notifications')
            .length;
        a.notices = 2;
        a.send(event(4) + event(5));
        await settleLocalIo(t);
        expect(find.text('实际通知1'), findsOneWidget);
        expect(
          a.requests.where((o) => o.path == '/notifications').length,
          initial + 1,
        );
        a.send(event(5) + event(4));
        await settleLocalIo(t);
        expect(
          a.requests.where((o) => o.path == '/notifications').length,
          initial + 1,
        );
        await a.streams.last.close();
        await t.pump();
        await t.pump();
        expect(find.textContaining('正在重连'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
        await settleLocalIo(t);
        final stream = a.requests
            .where((o) => o.path == '/notifications/stream')
            .last;
        expect(stream.headers['Last-Event-ID'], '5');
        expect(a.streams.length, 2);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
        await t.pump();
        expect(a.canceled, greaterThanOrEqualTo(2));
      },
    );
    testWidgets(
      'permanent format/403 stop and manual reconnect does not write messages',
      (t) async {
        final a = LiveAdapter()..jsonStream = true;
        final c = await launchLive(t, a);
        expect(find.text('重新连接消息'), findsOneWidget);
        expect(find.textContaining('格式无效'), findsOneWidget);
        a.jsonStream = false;
        await t.tap(find.text('重新连接消息'));
        await settleLocalIo(t);
        expect(find.text('消息实时更新中'), findsOneWidget);
        a.streams.last.addError(
          const ApiFailure(FailureKind.forbidden, '无权连接消息'),
        );
        await settleLocalIo(t);
        expect(find.text('重新连接消息'), findsOneWidget);
        expect(find.textContaining('无权连接消息'), findsOneWidget);
        expect(a.requests.where((o) => o.method != 'GET'), isEmpty);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
      },
    );
    testWidgets(
      'background closes stream and resumed confirmation precedes reconnect',
      (t) async {
        final a = LiveAdapter();
        final c = await launchLive(t, a);
        expect(a.streams.length, 1);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await settleLocalIo(t);
        expect(a.canceled, 1);
        a.meGate = Completer<void>();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settleLocalIo(t);
        expect(a.streams.length, 1);
        expect(c.read(sessionCheckProvider), isNotNull);
        a.meGate!.complete();
        await settleLocalIo(t);
        expect(a.streams.length, 2);
        expect(c.read(sessionCheckProvider), isNull);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
      },
    );
    testWidgets(
      'pending and old account/check disable stream and replay cursor resets',
      (t) async {
        final a = LiveAdapter();
        final c = await launchLive(t, a);
        a.send(event(9));
        await settleLocalIo(t);
        c.read(sessionProvider.notifier).state = const Session(
          id: 'u2',
          token: 'second-token',
        );
        await settleLocalIo(t);
        expect(a.canceled, 1);
        expect(
          a.requests
              .where((o) => o.path == '/notifications/stream')
              .last
              .headers['Last-Event-ID'],
          '0',
        );
        final count = a.requests
            .where((o) => o.path == '/notifications')
            .length;
        a.streams.first.add(Uint8List.fromList(utf8.encode(event(10))));
        await settleLocalIo(t);
        expect(
          a.requests.where((o) => o.path == '/notifications').length,
          count,
        );
        c.read(sessionCheckProvider.notifier).state = const AsyncLoading();
        await settleLocalIo(t);
        expect(a.canceled, 2);
        c.read(sessionCheckProvider.notifier).state = null;
        c.read(sessionProvider.notifier).state = const Session(
          id: 'u2',
          token: 'second-token',
          status: 'PENDING',
          active: false,
        );
        await settleLocalIo(t);
        expect(a.streams.length, 2);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
      },
    );
    testWidgets(
      'five transient failures stop with explicit retry and401 stops immediately',
      (t) async {
        final a = LiveAdapter();
        final c = await launchLive(t, a);
        for (var i = 0; i < 5; i++) {
          a.streams.last.addError(
            const ApiFailure(FailureKind.timeout, '连接超时'),
          );
          await t.pump();
          await t.pump();
          if (i < 4) {
            await t.pump(Duration(seconds: 1 << i));
            await settleLocalIo(t);
          }
        }
        await settleLocalIo(t);
        expect(
          c.read(liveNotificationsProvider).connection,
          NotificationConnection.stopped,
        );
        expect(a.streams.length, 5);
        await t.tap(find.text('重新连接消息'));
        await settleLocalIo(t);
        expect(a.streams.length, 6);
        a.streams.last.addError(
          const ApiFailure(FailureKind.unauthorized, '登录已失效'),
        );
        await settleLocalIo(t);
        expect(
          c.read(liveNotificationsProvider).connection,
          NotificationConnection.stopped,
        );
        await t.pump(const Duration(seconds: 31));
        expect(a.streams.length, 6);
        c.dispose();
        await t.pumpWidget(const SizedBox.shrink());
        await settleLocalIo(t);
      },
    );
    testWidgets('actual recovery inbox renders at360dp text1.5', (t) async {
      for (final (family, path) in [
        ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
            ))
            .load();
      }
      final a = LiveAdapter()
        ..jsonStream = true
        ..notices = 1;
      final c = await launchLive(t, a, scale: 1.5);
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
      expect(t.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/evidence/stage3-rebuild/52-notification-recovery-large.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
      c.dispose();
      await t.pumpWidget(const SizedBox.shrink());
      await settleLocalIo(t);
    });
  }
}
