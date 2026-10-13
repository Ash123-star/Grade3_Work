import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/state/session_bootstrap.dart';
import 'package:pandora_mobile/data/local/draft_database.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'package:pandora_mobile/data/local/secure_values.dart';
import 'package:pandora_mobile/data/local/session_store.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'auth_state_contract_test.dart' show AuthAdapter;
import 'support/local_test_state.dart';

const server = 'http://localhost:8080/api';
Session session({
  String account = 'private-account',
  String token = 'private-token',
}) => Session(
  id: account,
  token: token,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);
Record identity(String id, {String status = 'ACTIVE', bool password = false}) =>
    Record(
      id: id,
      title: '员工',
      fields: {
        'status': status,
        'role': 'EMPLOYEE',
        'must_change_password': password,
        'dispatch_enabled': false,
      },
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  (DraftDatabase, MemorySecureValues, DraftStore) create() {
    final db = DraftDatabase(NativeDatabase.memory());
    final secure = MemorySecureValues();
    final store = DraftStore(db, secure, namespace: server);
    addTearDown(db.close);
    return (db, secure, store);
  }

  test(
    'real SQL stores only opaque lookup/ciphertext; random nonce and full restart restore',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pandora-draft-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/drafts.sqlite');
      final secure = MemorySecureValues();
      var db = DraftDatabase(NativeDatabase(file));
      var store = DraftStore(db, secure, namespace: server);
      final location = DraftLocation.diary(
        'private-account',
        DateTime(2026, 10, 13),
      );
      final draft = LocalDraft(
        fields: {'今日工作': '私人工作正文', '工时': '7.5'},
        savedAt: DateTime(2026, 10, 13, 10),
        serverId: 'server-draft-9',
        serverVersion: 10,
      );
      await store.write(location, draft);
      final first =
          (await db.customSelect('SELECT * FROM drafts').getSingle()).data;
      await store.write(location, draft);
      final second =
          (await db.customSelect('SELECT * FROM drafts').getSingle()).data;
      expect(
        second.keys,
        unorderedEquals(['lookup_id', 'ciphertext', 'nonce', 'mac']),
      );
      expect(second['nonce'], isNot(equals(first['nonce'])));
      expect(second['ciphertext'], isNot(equals(first['ciphertext'])));
      await db.close();
      final bytes = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      for (final text in [
        'private-account',
        '2026-10-13',
        'server-draft-9',
        '今日工作',
      ]) {
        expect(bytes, isNot(contains(text)));
      }
      db = DraftDatabase(NativeDatabase(file));
      store = DraftStore(db, secure, namespace: server);
      final restored = (await store.read(location))!;
      expect(restored.fields, draft.fields);
      expect(restored.savedAt, draft.savedAt);
      expect(restored.serverId, 'server-draft-9');
      expect(restored.serverVersion, 10);
      await db.close();
    },
  );

  test(
    'account/date/server/revision isolation and only exact submitted draft removed',
    () async {
      final (db, secure, store) = create();
      final day = DateTime(2026, 10, 13);
      final a = DraftLocation.diary('a', day),
          b = DraftLocation.diary('b', day);
      final v1 = DraftLocation.revision('a', 'log9', 1),
          v2 = DraftLocation.revision('a', 'log9', 2);
      final draft = LocalDraft(fields: {'今日工作': '仅本人'}, savedAt: day);
      await store.write(a, draft);
      await store.write(b, draft);
      await store.write(v1, draft);
      expect(
        await store.read(
          DraftLocation.diary('a', day.add(const Duration(days: 1))),
        ),
        isNull,
      );
      expect(await store.read(v2), isNull);
      final other = DraftStore(
        db,
        secure,
        namespace: 'https://different-server/api',
      );
      expect(await other.read(a), isNull);
      await other.write(a, draft);
      await store.remove(a);
      expect(await store.read(a), isNull);
      expect((await store.read(b))!.fields, draft.fields);
      expect((await store.read(v1))!.fields, draft.fields);
      expect((await other.read(a))!.fields, draft.fields);
    },
  );

  test(
    'swapped ciphertext and missing key reject without deleting data or resetting key',
    () async {
      final (db, secure, store) = create();
      final a = DraftLocation.diary('a', DateTime(2026, 10, 13));
      final b = DraftLocation.diary('b', DateTime(2026, 10, 13));
      await store.write(
        a,
        LocalDraft(fields: {'今日工作': 'A'}, savedAt: DateTime.now()),
      );
      await store.write(
        b,
        LocalDraft(fields: {'今日工作': 'B'}, savedAt: DateTime.now()),
      );
      final rows = await db.customSelect('SELECT * FROM drafts').get();
      await db.customStatement(
        'UPDATE drafts SET ciphertext=?, nonce=?, mac=? WHERE lookup_id=?',
        [
          rows[1].data['ciphertext'],
          rows[1].data['nonce'],
          rows[1].data['mac'],
          rows[0].data['lookup_id'],
        ],
      );
      await expectLater(store.read(a), throwsA(isA<LocalStorageFailure>()));
      secure.values.clear();
      final reopened = DraftStore(db, secure, namespace: server);
      await expectLater(reopened.read(b), throwsA(isA<LocalStorageFailure>()));
      expect(secure.values, isEmpty);
      expect(
        (await db.customSelect('SELECT COUNT(*) AS n FROM drafts').getSingle())
            .read<int>('n'),
        2,
      );
    },
  );

  test(
    'legacy migration removes only exact keys after real encrypted readback',
    () async {
      final (_, _, store) = create();
      SharedPreferences.setMockInitialValues({
        'draft:a:2026-10-13:今日工作': '迁移正文',
        'draft:a:2026-10-13:工时': '8',
        'draft:a:2026-10-13:savedAt': '2026-10-13T10:00:00',
        'draft:b:2026-10-13:今日工作': '其他账号',
        'revision:a:log9:1:修改理由': '修订说明',
      });
      final a = DraftLocation.diary('a', DateTime(2026, 10, 13));
      expect((await store.read(a))!.fields['今日工作'], '迁移正文');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('draft:a:2026-10-13:今日工作'), isNull);
      expect(prefs.getString('draft:b:2026-10-13:今日工作'), '其他账号');
      expect(
        (await store.read(
          DraftLocation.revision('a', 'log9', 1),
        ))!.fields['修改理由'],
        '修订说明',
      );
      expect(prefs.getString('revision:a:log9:1:修改理由'), isNull);
    },
  );

  test(
    'failed secure key write retains legacy input; retry migrates without plaintext writes',
    () async {
      final (_, secure, store) = create();
      SharedPreferences.setMockInitialValues({
        'draft:a:2026-10-13:今日工作': '失败保留',
      });
      secure.failWrite = true;
      final location = DraftLocation.diary('a', DateTime(2026, 10, 13));
      await expectLater(
        store.read(location),
        throwsA(isA<LocalStorageFailure>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('draft:a:2026-10-13:今日工作'), '失败保留');
      secure.failWrite = false;
      expect((await store.read(location))!.fields['今日工作'], '失败保留');
      expect(prefs.getString('draft:a:2026-10-13:今日工作'), isNull);
    },
  );

  test(
    'credentials contain no cached role/body/password; expire/malformed removed',
    () async {
      final secure = MemorySecureValues();
      final actual = SessionStore(secure, server: server);
      await actual.save(session());
      final data = jsonDecode(secure.values[actual.key]!) as Map;
      expect(
        data.keys,
        unorderedEquals(['schema', 'server', 'account', 'token', 'expiresAt']),
      );
      expect((await actual.read())!.account, 'private-account');
      secure.values[actual.key] = '{broken';
      expect(await actual.read(), isNull);
      expect(secure.values, isEmpty);
      await actual.save(
        Session(id: 'a', token: 'old', expiresAt: DateTime(2000)),
      );
      expect(await actual.read(), isNull);
    },
  );

  test(
    'serialized late old-token clear cannot revoke replacement credentials',
    () async {
      final secure = MemorySecureValues(), first = session();
      final store = SessionStore(secure, server: server);
      await store.save(first);
      final saving = store.save(session(account: 'new', token: 'new-token'));
      final clearing = store.clear(token: first.token);
      await Future.wait([saving, clearing]);
      expect((await store.read())!.token, 'new-token');
      await store.clear(token: 'new-token');
      expect(await store.read(), isNull);
    },
  );

  test(
    'recovery requires server identity; pending/password routes retain true state',
    () async {
      final store = SessionStore(MemorySecureValues(), server: server);
      for (final status in ['ACTIVE', 'PENDING']) {
        await store.save(session());
        var reads = 0;
        final recovered = await recoverSession(store, (credential) async {
          reads++;
          expect(credential.token, 'private-token');
          return identity(
            'private-account',
            status: status,
            password: status == 'ACTIVE',
          );
        });
        expect(reads, 1);
        expect(recovered.status, status);
        expect(recovered.canReadBusiness, isFalse);
        expect(recovered.mustChangePassword, status == 'ACTIVE');
      }
    },
  );

  test(
    'recovery401/identity mismatch removes material; network retains explicit retry',
    () async {
      final store = SessionStore(MemorySecureValues(), server: server);
      await store.save(session());
      await expectLater(
        recoverSession(
          store,
          (_) async => throw const ApiFailure(FailureKind.timeout, 'timeout'),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(await store.read(), isNotNull);
      final revoked = await recoverSession(
        store,
        (_) async =>
            throw const ApiFailure(FailureKind.unauthorized, 'revoked'),
      );
      expect(revoked.canReadBusiness, isFalse);
      expect(await store.read(), isNull);
      await store.save(session());
      final changed = await recoverSession(
        store,
        (_) async => identity('different'),
      );
      expect(changed.authenticated, isFalse);
      expect(await store.read(), isNull);
    },
  );

  testWidgets(
    'editor restores encrypted draft across disposal; account/date not leaked',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = testContainer();
      addTearDown(c.dispose);
      final day = DateTime(2026, 10, 13);
      c.read(logDateProvider.notifier).state = day;
      c.read(sessionProvider.notifier).state = const Session();
      final store = c.read(draftStoreProvider);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      c.read(routerProvider).go('/form/log-edit');
      await t.pumpAndSettle();
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '真实加密编辑链路');
      await t.tap(find.text('保存草稿'));
      await t.pumpAndSettle();
      final saved = await t.runAsync(
        () => store.read(DraftLocation.diary('u1', day)),
      );
      expect(saved!.fields['今日工作'], '真实加密编辑链路');
      c.read(routerProvider).go('/logs');
      await t.pumpAndSettle();
      c.read(routerProvider).go('/form/log-edit');
      await t.pumpAndSettle();
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '真实加密编辑链路',
      );
      c.read(sessionProvider.notifier).state = const Session(id: 'u2');
      await t.pumpAndSettle();
      expect(find.text('真实加密编辑链路'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'bootstrap mounts no business page while held and on network error',
    (t) async {
      final c = testContainer();
      addTearDown(c.dispose);
      final store = c.read(sessionStoreProvider);
      await store.save(session());
      final hold = Completer<Record>();
      final child = ProviderScope(
        overrides: [
          ...localTestOverrides(),
          sessionStoreProvider.overrideWithValue(store),
          recoveryIdentityProvider.overrideWithValue((_) => hold.future),
          sessionRecoveryEnabledProvider.overrideWithValue(true),
        ],
        child: const SessionBootstrap(
          child: MaterialApp(home: Text('BUSINESS MOUNTED')),
        ),
      );
      await t.pumpWidget(child);
      await t.pump();
      await settleLocalIo(t);
      await t.pump();
      expect(find.text('BUSINESS MOUNTED'), findsNothing);
      hold.completeError(const ApiFailure(FailureKind.timeout, 'timeout'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('BUSINESS MOUNTED'), findsNothing);
      expect(find.text('重新验证登录'), findsOneWidget);
      expect(await t.runAsync(store.read), isNotNull);
      await t.tap(find.text('清除本机登录信息'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('BUSINESS MOUNTED'), findsOneWidget);
      expect(await t.runAsync(store.read), isNull);
    },
  );

  testWidgets(
    'startup existing HTTP me restores pending without business reads and keeps server identity',
    (t) async {
      final c = testContainer();
      addTearDown(c.dispose);
      final store = c.read(sessionStoreProvider);
      await store.save(session(account: 'account-1', token: 'token-1'));
      final adapter = AuthAdapter();
      final repo = HttpRepository(server, 'token-1', businessAllowed: false)
        ..dio.httpClientAdapter = adapter;
      final widget = ProviderScope(
        overrides: [
          ...localTestOverrides(),
          sessionStoreProvider.overrideWithValue(store),
          sessionRecoveryEnabledProvider.overrideWithValue(true),
          recoveryIdentityProvider.overrideWithValue(
            (_) => repo.detail('auth', 'me'),
          ),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: const SessionBootstrap(child: PandoraApp()),
      );
      await t.pumpWidget(widget);
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('你的员工申请已登记。管理员确认部门后，才能查看公司内部内容。'), findsWidgets);
      expect(find.byType(NavigationBar), findsNothing);
      expect(adapter.requests.map((r) => r.path), [
        '/auth/me',
        '/auth/departments',
      ]);
      expect(adapter.requests.first.headers['Authorization'], 'Bearer token-1');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 300));
      repo.dio.close();
    },
  );

  testWidgets(
    'failed encryption keeps editor input and recovers with explicit save',
    (t) async {
      final c = testContainer();
      addTearDown(c.dispose);
      final secure = c.read(secureValuesProvider) as MemorySecureValues;
      secure.failRead = true;
      c.read(sessionProvider.notifier).state = const Session();
      c.read(logDateProvider.notifier).state = DateTime(2026, 10, 13);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      c.read(routerProvider).go('/form/log-edit');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.textContaining('草稿读取失败'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).first, '本机失败仍保留');
      await t.tap(find.text('保存草稿'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.textContaining('草稿保存失败'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '本机失败仍保留',
      );
      secure.failRead = false;
      await t.tap(find.text('保存草稿'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final draft = await t.runAsync(
        () => c
            .read(draftStoreProvider)
            .read(DraftLocation.diary('u1', DateTime(2026, 10, 13))),
      );
      expect(draft!.fields['今日工作'], '本机失败仍保留');
      expect(find.textContaining('草稿保存失败'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets('late recovery cannot replace new in-memory or secure account', (
    t,
  ) async {
    final hold = Completer<Record>();
    final c = testContainer(
      overrides: [
        sessionRecoveryEnabledProvider.overrideWithValue(true),
        recoveryIdentityProvider.overrideWithValue((_) => hold.future),
      ],
    );
    addTearDown(c.dispose);
    final store = c.read(sessionStoreProvider);
    await store.save(session());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const SessionBootstrap(
          child: MaterialApp(home: Text('SAFE NEW ACCOUNT')),
        ),
      ),
    );
    await settleLocalIo(t);
    c.read(sessionProvider.notifier).state = session(
      account: 'new',
      token: 'new-token',
    );
    await t.runAsync(
      () => store.save(session(account: 'new', token: 'new-token')),
    );
    hold.complete(identity('private-account'));
    await settleLocalIo(t);
    expect(c.read(sessionProvider).id, 'new');
    expect((await t.runAsync(store.read))!.token, 'new-token');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });

  testWidgets('render safe restart recovery at360dp and1.5 text', (t) async {
    for (final item in [
      ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final loader = FontLoader(item.$1)
        ..addFont(
          Future.value(ByteData.sublistView(File(item.$2).readAsBytesSync())),
        );
      await loader.load();
    }
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer();
    addTearDown(c.dispose);
    final store = c.read(sessionStoreProvider);
    await store.save(session());
    final key = GlobalKey();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...localTestOverrides(),
          fontScaleProvider.overrideWith((_) => 1.5),
          sessionStoreProvider.overrideWithValue(store),
          sessionRecoveryEnabledProvider.overrideWithValue(true),
          recoveryIdentityProvider.overrideWithValue(
            (_) async => throw const ApiFailure(FailureKind.timeout, 'timeout'),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: SessionBootstrap(child: PandoraApp()),
          ),
        ),
      ),
    );
    await settleLocalIo(t);
    await t.pumpAndSettle();
    expect(find.text('暂时无法恢复登录'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/evidence/stage3-rebuild/40-session-recovery.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });
}
