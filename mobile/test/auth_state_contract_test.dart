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
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class AuthAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final user = <String, dynamic>{
    'id': 'account-1',
    'name': '小橙',
    'role': 'EMPLOYEE',
    'status': 'PENDING',
    'must_change_password': false,
    'dispatch_enabled': false,
    'department_id': 'dept-tech',
    'version': 1,
  };
  int loginStatus = 200,
      passwordStatus = 200,
      logoutStatus = 200,
      meStatus = 200;
  String protectedCode = 'FORBIDDEN';
  int protectedStatus = 403;
  Completer<void>? holdMe, holdProtected;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    var status = 200;
    dynamic data = {'items': [], 'total': 0};
    if (o.path == '/auth/login') {
      status = loginStatus;
      data = status == 200
          ? {
              'token': 'token-1',
              'expiresAt': DateTime.now()
                  .add(const Duration(hours: 2))
                  .toUtc()
                  .toIso8601String(),
              'user': {...user},
            }
          : {'code': 'INVALID_CREDENTIALS'};
    } else if (o.path == '/auth/me') {
      if (holdMe != null) await holdMe!.future;
      status = meStatus;
      data = status == 200
          ? {...user}
          : {'code': status == 401 ? 'SESSION_EXPIRED' : 'INTERNAL_ERROR'};
    } else if (o.path == '/auth/password') {
      status = passwordStatus;
      data = status == 200
          ? {'reloginRequired': true}
          : {'code': 'INVALID_CREDENTIALS'};
    } else if (o.path == '/auth/logout') {
      status = logoutStatus;
      data = {'ok': status == 200};
    } else if (o.path == '/tasks/protected') {
      if (holdProtected != null) await holdProtected!.future;
      status = protectedStatus;
      data = {'code': protectedCode};
    } else if (o.path == '/auth/departments') {
      data = [
        {'id': 'dept-tech', 'name': '技术部'},
      ];
    } else if (o.path == '/auth/register') {
      data = {'id': 'account-1', 'status': 'PENDING', 'role': 'EMPLOYEE'};
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

const signedOut = Session(
  id: '',
  name: '',
  active: false,
  role: UserRole.employee,
  dispatch: false,
);
const active = Session(
  id: 'account-1',
  name: '小橙',
  token: 'token-1',
  role: UserRole.employee,
  dispatch: false,
);

void main() {
  late AuthAdapter adapter;
  setUp(() => adapter = AuthAdapter());
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((e) => e.kind, 'kind', kind);

  test(
    'session identity fails closed and keeps actual password and expiry fields',
    () {
      final unknown = Session.fromRecord(
        const Record(id: 'x', title: '员工', fields: {'accessToken': 'token'}),
      );
      expect(unknown.canReadBusiness, isFalse);
      expect(unknown.role, UserRole.employee);
      final actual = Session.fromRecord(
        Record(
          id: 'account-1',
          title: '小橙',
          fields: {
            ...adapter.user,
            'status': 'ACTIVE',
            'must_change_password': true,
            'accessToken': 'token-1',
            'expiresAt': '2026-10-14T00:00:00Z',
          },
        ),
      );
      expect(actual.authenticated, isTrue);
      expect(actual.canReadBusiness, isFalse);
      expect(actual.departmentId, 'dept-tech');
      expect(actual.expiresAt!.isUtc, isTrue);
      expect(actual.restrict(expired: true).token, isNull);
    },
  );

  test(
    'HTTP distinguishes credentials/object403 from actual session errors and gates reads',
    () async {
      final events = <ApiFailure>[];
      final repo = HttpRepository(
        'http://localhost/api',
        'token-1',
        onSessionFailure: events.add,
      );
      repo.dio.httpClientAdapter = adapter;
      await expectLater(
        repo.detail('tasks', 'protected'),
        throwsA(failure(FailureKind.forbidden)),
      );
      expect(events, isEmpty);
      adapter.passwordStatus = 401;
      await expectLater(
        repo.execute(
          'auth',
          const Command('password', {
            '原密码': 'incorrect',
            '新密码': 'new-password-123',
          }),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            contains('原密码错误'),
          ),
        ),
      );
      expect(events, isEmpty);
      adapter.protectedCode = 'PASSWORD_CHANGE_REQUIRED';
      await expectLater(
        repo.detail('tasks', 'protected'),
        throwsA(failure(FailureKind.forbidden)),
      );
      expect(events.single.code, 'PASSWORD_CHANGE_REQUIRED');
      adapter.protectedStatus = 401;
      adapter.protectedCode = 'SESSION_EXPIRED';
      await expectLater(
        repo.detail('tasks', 'protected'),
        throwsA(failure(FailureKind.unauthorized)),
      );
      expect(events.last.code, 'SESSION_EXPIRED');
      final gated = HttpRepository(
        'http://localhost/api',
        'token-1',
        businessAllowed: false,
      );
      gated.dio.httpClientAdapter = adapter;
      adapter.requests.clear();
      await expectLater(
        gated.list('tasks', const Query()),
        throwsA(failure(FailureKind.forbidden)),
      );
      expect(adapter.requests, isEmpty);
      await gated.detail('auth', 'me');
      expect(adapter.requests.single.path, '/auth/me');
    },
  );

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
  }

  Future<ProviderContainer> launch(
    WidgetTester t, {
    String route = '/auth/login',
    Session session = signedOut,
    GlobalKey? boundary,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      'draft:account-1:2026-10-13:今日工作': '私有草稿',
    });
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
        fontScaleProvider.overrideWith((ref) => scale),
        repositoryProvider.overrideWith((ref) {
          final repo = ref.watch(httpRepositoryProvider);
          repo.dio.httpClientAdapter = adapter;
          return repo;
        }),
      ],
    );
    addTearDown(c.dispose);
    c.read(routerProvider).go(route);
    Widget app = UncontrolledProviderScope(
      container: c,
      child: const PandoraApp(),
    );
    if (boundary != null) app = RepaintBoundary(key: boundary, child: app);
    await t.pumpWidget(app);
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  Future<void> login(WidgetTester t) async {
    await t.enterText(find.byType(TextFormField).at(0), 'orange');
    await t.enterText(find.byType(TextFormField).at(1), 'password-1234');
    await t.tap(find.widgetWithText(FilledButton, '登录'));
    await settle(t);
  }

  testWidgets(
    'pending login and deep links never read business before me confirms active',
    (t) async {
      final c = await launch(t);
      await login(t);
      expect(find.text('你的员工申请已登记。管理员确认部门后，才能查看公司内部内容。'), findsOneWidget);
      expect(find.text('申请部门：技术部'), findsOneWidget);
      expect(c.read(sessionProvider).token, 'token-1');
      c.read(routerProvider).go('/item/tasks/protected');
      await settle(t);
      expect(find.text('你的员工申请已登记。管理员确认部门后，才能查看公司内部内容。'), findsOneWidget);
      expect(
        adapter.requests.every((r) => r.path.startsWith('/auth/')),
        isTrue,
      );
      adapter.meStatus = 503;
      await t.tap(find.text('刷新申请状态'));
      await settle(t);
      expect(find.text('服务暂时不可用，请稍后重试'), findsOneWidget);
      expect(c.read(sessionProvider).status, 'PENDING');
      adapter.meStatus = 200;
      adapter.user['status'] = 'ACTIVE';
      await t.tap(find.text('刷新申请状态'));
      await settle(t);
      expect(c.read(sessionProvider).canReadBusiness, isTrue);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/dashboard',
      );
      expect(
        adapter.requests.any((r) => r.path == '/dashboard/company'),
        isTrue,
      );
      await close(t);
    },
  );

  testWidgets(
    'mandatory password blocks routes, invalid old password stays editable, success revokes',
    (t) async {
      adapter.user['status'] = 'ACTIVE';
      adapter.user['must_change_password'] = true;
      final c = await launch(t);
      await login(t);
      expect(find.text('首次登录需要设置新密码，完成后请重新登录。'), findsOneWidget);
      c.read(routerProvider).go('/me');
      await settle(t);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/auth/password',
      );
      expect(
        adapter.requests.every((r) => r.path.startsWith('/auth/')),
        isTrue,
      );
      await t.enterText(find.byType(TextFormField).at(0), 'incorrect-old');
      await t.enterText(find.byType(TextFormField).at(1), 'new-password-123');
      await t.enterText(find.byType(TextFormField).at(2), 'different-password');
      await t.tap(find.byType(FilledButton).first);
      await settle(t);
      expect(adapter.requests.any((r) => r.path == '/auth/password'), isFalse);
      await t.enterText(find.byType(TextFormField).at(2), 'new-password-123');
      adapter.passwordStatus = 401;
      await t.tap(find.byType(FilledButton).first);
      await settle(t);
      expect(find.text('原密码错误，请重新填写'), findsOneWidget);
      expect(c.read(sessionProvider).expired, isFalse);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'new-password-123',
      );
      adapter.passwordStatus = 200;
      await t.tap(find.byType(FilledButton).first);
      await settle(t);
      expect(c.read(sessionProvider).token, isNull);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/auth/login',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'draft:account-1:2026-10-13:今日工作',
        ),
        '私有草稿',
      );
      await close(t);
    },
  );

  testWidgets('invalid login keeps fields and never claims expired session', (
    t,
  ) async {
    adapter.loginStatus = 401;
    final c = await launch(t);
    await login(t);
    expect(find.text('账号或密码错误，请重新填写'), findsOneWidget);
    expect(c.read(sessionProvider).expired, isFalse);
    expect(
      c.read(routerProvider).routeInformationProvider.value.uri.path,
      '/auth/login',
    );
    expect(
      t
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'orange',
    );
    await close(t);
  });

  testWidgets(
    'server logout failure retains session, retry clears token and business stack',
    (t) async {
      final c = await launch(t, route: '/me/settings', session: active);
      final button = find.widgetWithText(OutlinedButton, '退出登录');
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      adapter.logoutStatus = 503;
      await t.tap(find.widgetWithText(FilledButton, '退出'));
      await settle(t);
      expect(find.text('退出未完成：服务暂时不可用，请稍后重试'), findsOneWidget);
      expect(c.read(sessionProvider).token, 'token-1');
      adapter.logoutStatus = 200;
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '退出'));
      await settle(t);
      expect(c.read(sessionProvider).token, isNull);
      expect(
        adapter.requests
            .lastWhere((r) => r.path == '/auth/logout')
            .headers['Authorization'],
        'Bearer token-1',
      );
      c.read(routerProvider).go('/dashboard');
      await settle(t);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/auth/login',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'draft:account-1:2026-10-13:今日工作',
        ),
        '私有草稿',
      );
      await close(t);
    },
  );

  testWidgets(
    'protected401 expires globally but object403 does not, obsolete token cannot revoke successor',
    (t) async {
      final c = await launch(t, route: '/dashboard', session: active);
      final repo = c.read(repositoryProvider);
      await t.runAsync(() async {
        await expectLater(
          repo.detail('tasks', 'protected'),
          throwsA(failure(FailureKind.forbidden)),
        );
      });
      await settle(t);
      expect(c.read(sessionProvider).expired, isFalse);
      adapter.holdProtected = Completer<void>();
      adapter.protectedStatus = 401;
      adapter.protectedCode = 'SESSION_EXPIRED';
      late Future<void> oldRequest;
      await t.runAsync(() async {
        oldRequest = expectLater(
          repo.detail('tasks', 'protected'),
          throwsA(failure(FailureKind.unauthorized)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      c.read(sessionProvider.notifier).state = const Session(
        id: 'account-2',
        name: '新账号',
        token: 'token-2',
      );
      await settle(t);
      await t.runAsync(() async {
        adapter.holdProtected!.complete();
        await oldRequest;
      });
      await settle(t);
      expect(c.read(sessionProvider).token, 'token-2');
      adapter.holdProtected = null;
      await t.runAsync(() async {
        await expectLater(
          c.read(repositoryProvider).detail('tasks', 'protected'),
          throwsA(failure(FailureKind.unauthorized)),
        );
      });
      await settle(t);
      expect(c.read(sessionProvider).expired, isTrue);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/auth/expired',
      );
      expect(find.byType(NavigationBar), findsNothing);
      await close(t);
    },
  );

  testWidgets(
    'actual expiresAt timer blocks protected route and preserves private drafts',
    (t) async {
      final c = await launch(
        t,
        route: '/dashboard',
        session: Session(
          id: 'account-1',
          name: '小橙',
          token: 'token-1',
          expiresAt: DateTime.now().add(const Duration(seconds: 2)),
        ),
      );
      await t.pump(const Duration(seconds: 3));
      await settle(t);
      expect(c.read(sessionProvider).expired, isTrue);
      expect(find.text('请重新登录后继续。未提交的本地日志草稿会保留。'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await close(t);
    },
  );

  testWidgets(
    'foreground validation blocks stale content, retries failure and refreshes pending state',
    (t) async {
      final c = await launch(t, route: '/dashboard', session: active);
      adapter.holdMe = Completer<void>();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('正在确认登录状态'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      adapter.meStatus = 503;
      await t.runAsync(() async {
        adapter.holdMe!.complete();
      });
      await settle(t);
      expect(find.text('暂时无法确认登录状态'), findsOneWidget);
      expect(c.read(sessionProvider).token, 'token-1');
      adapter.holdMe = null;
      adapter.meStatus = 200;
      await t.tap(find.text('重新验证登录'));
      await settle(t);
      expect(find.text('你的员工申请已登记。管理员确认部门后，才能查看公司内部内容。'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      c.read(sessionProvider.notifier).state = active;
      c.read(routerProvider).go('/dashboard');
      await settle(t);
      adapter.holdMe = Completer<void>();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('正在确认登录状态'), findsOneWidget);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'account-2',
        name: '新账号',
        token: 'token-2',
      );
      await settle(t);
      expect(c.read(sessionCheckProvider), isNull);
      await t.runAsync(() async {
        adapter.holdMe!.complete();
      });
      await settle(t);
      expect(c.read(sessionProvider).id, 'account-2');
      expect(c.read(sessionProvider).status, 'ACTIVE');
      expect(c.read(sessionCheckProvider), isNull);
      await close(t);
    },
  );

  testWidgets(
    'render auth states with real HTTP adapter at enlarged text and narrow viewport',
    (t) async {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                materialIconsFontPath,
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
      final boundary = GlobalKey();
      final c = await launch(
        t,
        boundary: boundary,
        size: const Size(360, 720),
        scale: 1.5,
      );
      for (final (label, session, path) in [
        ('17-login', signedOut, '/auth/login'),
        ('18-pending', active.restrict(status: 'PENDING'), '/dashboard'),
        (
          '19-required-password',
          active.restrict(mustChangePassword: true),
          '/dashboard',
        ),
        ('20-expired', active.restrict(expired: true), '/dashboard'),
        ('21-disabled', active.restrict(status: 'DISABLED'), '/dashboard'),
      ]) {
        c.read(sessionProvider.notifier).state = session;
        c.read(routerProvider).go(path);
        await settle(t);
        expect(t.takeException(), isNull, reason: label);
        if (label != '17-login') {
          expect(find.byType(NavigationBar), findsNothing);
        }
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await render.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final output = File('docs/evidence/stage3-rebuild/$label.png');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
      c.read(sessionProvider.notifier).state = active;
      c.read(routerProvider).go('/dashboard');
      await settle(t);
      for (final (label, check) in <(String, AsyncValue<void>)>[
        ('22-session-check', const AsyncLoading<void>()),
        (
          '23-session-recovery',
          AsyncError<void>(
            const ApiFailure(FailureKind.timeout, '连接超时，请稍后重试'),
            StackTrace.current,
          ),
        ),
      ]) {
        c.read(sessionCheckProvider.notifier).state = check;
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byType(NavigationBar), findsNothing);
        expect(t.takeException(), isNull, reason: label);
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await render.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/evidence/stage3-rebuild/$label.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
      c.read(sessionCheckProvider.notifier).state = null;
      await close(t);
    },
  );
}
