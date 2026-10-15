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
import 'package:pandora_mobile/data/models/diary_task_links.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/shared/diary_task_links.dart';
import 'package:pandora_mobile/shared/sunny_button.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'read_http_contract_test.dart' show ReadAdapter;
import 'support/local_test_state.dart';

class AssociationAdapter extends ReadAdapter {
  int laterStatus = 200;
  dynamic links = ['task-0', 'task-30'];
  ResponseBody json(dynamic body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    if (o.path == '/tasks') {
      requests.add(o);
      final cursor = int.tryParse('${o.queryParameters['cursor'] ?? 0}') ?? 0;
      if (cursor > 0 && laterStatus != 200) {
        return json({
          'code': 'FORBIDDEN',
          'message': 'scope lost',
        }, laterStatus);
      }
      return json({
        'items': [
          for (var i = cursor; i < (cursor == 0 ? 30 : 31); i++)
            {
              'id': 'task-$i',
              'title': i == 30 ? '最后一页的关联任务' : '授权任务$i',
              'owner_id': 'u1',
              'fields': {'content': '实际任务正文$i'},
            },
        ],
        'total': 31,
        'nextCursor': cursor == 0 ? '30' : null,
      });
    }
    if (o.path == '/logs/log-1') {
      requests.add(o);
      return json({
        'id': 'log-1',
        'owner_id': 'u1',
        'business_date': '2026-10-12',
        'submitted': submitted,
        'version': 3,
        'body': {'work': '多任务日报正文', 'taskIds': links},
      });
    }
    if (o.path.startsWith('/tasks/task-')) {
      requests.add(o);
      return json({
        'id': o.path.split('/').last,
        'title': '打开实际任务',
        'owner_id': 'u1',
        'version': 1,
        'events': [],
        'fields': {'content': '实际任务详情正文'},
      });
    }
    if (o.path == '/logs/log-1/revisions' || o.path == '/logs/draft') {
      requests.add(o);
      return json({'id': 'log-1', 'version': 4, 'title': '日志已保存'});
    }
    return super.fetch(o, body, cancelFuture);
  }
}

void main() {
  late AssociationAdapter adapter;
  late HttpRepository repo;
  late GlobalKey captureKey;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = AssociationAdapter();
    repo = HttpRepository('http://localhost/api', 'links-token');
    repo.dio.httpClientAdapter = adapter;
    captureKey = GlobalKey();
  });
  const account = Session(id: 'u1', name: '日志作者', token: 'links-token');

  Future<ProviderContainer> launch(
    WidgetTester t, {
    String? route,
    double scale = 1,
  }) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => account),
        repositoryProvider.overrideWithValue(repo),
        fontScaleProvider.overrideWith((ref) => scale),
      ],
    );
    addTearDown(c.dispose);
    if (route != null) {
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
    } else {
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: DiaryTaskPicker(
                initial: const ['task-0', 'unavailable'],
                account: account,
              ),
            ),
          ),
        ),
      );
    }
    await settleLocalIo(t);
    await t.pumpAndSettle();
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await settleLocalIo(t);
  }

  test(
    'codec preserves arrays and legacy singleton, normalizes duplicates, rejects invalid IDs',
    () {
      expect(DiaryTaskLinks.parse('old-task'), ['old-task']);
      expect(DiaryTaskLinks.parse(''), isEmpty);
      expect(DiaryTaskLinks.parse(DiaryTaskLinks.encode(['a', 'b', 'a'])), [
        'a',
        'b',
      ]);
      for (final bad in [
        42,
        ['a', null],
        [''],
        '[broken',
        ['a\n'],
      ]) {
        expect(() => DiaryTaskLinks.parse(bad), throwsA(isA<ApiFailure>()));
      }
    },
  );
  test(
    'GET and draft/revision commands retain all task IDs and preserve current version',
    () async {
      final record = await repo.detail('logs', 'log-1');
      expect(DiaryTaskLinks.parse(record.fields['关联任务']), [
        'task-0',
        'task-30',
      ]);
      for (final action in ['save', 'request-review']) {
        await repo.execute(
          'logs',
          Command(action, {
            'id': 'log-1',
            'businessDate': '2026-10-12',
            '今日工作': '保持全部关联',
            '关联任务': record.fields['关联任务'],
            '修改理由': '补充说明',
          }, version: 3),
        );
        final request = adapter.requests.last;
        expect(request.data['body']['taskIds'], ['task-0', 'task-30']);
        expect(request.data['version'], 3);
      }
      adapter.links = ['task-0', 42];
      await expectLater(
        repo.detail('logs', 'log-1'),
        throwsA(isA<ApiFailure>()),
      );
      final before = adapter.requests.length;
      await expectLater(
        repo.execute('logs', const Command('save', {'关联任务': '[bad'})),
        throwsA(isA<ApiFailure>()),
      );
      expect(adapter.requests.length, before);
    },
  );
  testWidgets(
    'picker searches last complete page and retains other selections across filter',
    (t) async {
      await launch(t);
      expect(find.text('已选 2 项 · 筛选不会移除已有选择'), findsOneWidget);
      await t.enterText(find.byType(TextField), '最后一页');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('diary-task-task-30')));
      await t.pumpAndSettle();
      expect(find.text('已选 3 项 · 筛选不会移除已有选择'), findsOneWidget);
      await t.enterText(find.byType(TextField), '不存在的搜索');
      await t.pumpAndSettle();
      expect(find.text('没有匹配的授权任务'), findsOneWidget);
      expect(find.text('已选 3 项 · 筛选不会移除已有选择'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'late-page403 clears picker titles and blocks confirmation without deleting selections',
    (t) async {
      final c = await launch(t);
      adapter.laterStatus = 403;
      c.invalidate(recordsProvider('tasks'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('授权任务0'), findsNothing);
      expect(find.text('无权访问'), findsOneWidget);
      final button = t.widget<SunnyPrimaryButton>(
        find.widgetWithText(SunnyPrimaryButton, '确认关联'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('已选 2 项 · 筛选不会移除已有选择'), findsOneWidget);
      await close(t);
    },
  );
  for (final replacement in [
    const Session(id: 'other', token: 'other-token'),
    const Session(id: 'u1', token: 'replacement-token'),
  ]) {
    testWidgets(
      'picker hides old session on ${replacement.id}:${replacement.token}',
      (t) async {
        final c = await launch(t);
        c.read(sessionProvider.notifier).state = replacement;
        await t.pumpAndSettle();
        expect(find.text('任务选择已停止，请重新确认账号与权限'), findsOneWidget);
        expect(find.text('授权任务0'), findsNothing);
        expect(find.text('确认关联'), findsNothing);
        await close(t);
      },
    );
  }
  testWidgets(
    'real revision editor cancel preserves links; delete and encrypted reopen preserve remaining array',
    (t) async {
      final c = await launch(t, route: '/form/log-revise?id=log-1&version=3');
      final editor = find.byType(DiaryTaskLinksEditor);
      await t.ensureVisible(editor);
      await t.pumpAndSettle();
      expect(
        DiaryTaskLinks.parse(t.widget<DiaryTaskLinksEditor>(editor).value),
        ['task-0', 'task-30'],
      );
      await t.tap(find.text('添加'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消').last);
      await t.pumpAndSettle();
      expect(
        DiaryTaskLinks.parse(t.widget<DiaryTaskLinksEditor>(editor).value),
        ['task-0', 'task-30'],
      );
      await t.tap(find.text('添加'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '实际任务正文1');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('diary-task-task-1')));
      await t.tap(find.text('确认关联'));
      await t.pumpAndSettle();
      expect(
        DiaryTaskLinks.parse(t.widget<DiaryTaskLinksEditor>(editor).value),
        ['task-0', 'task-30', 'task-1'],
      );
      final chip = find.widgetWithText(InputChip, '授权任务0');
      t.widget<InputChip>(chip).onDeleted!();
      await t.pump(const Duration(milliseconds: 700));
      await settleLocalIo(t);
      final draft = await t.runAsync(
        () => c
            .read(draftStoreProvider)
            .read(DraftLocation.revision('u1', 'log-1', 3)),
      );
      expect(DiaryTaskLinks.parse(draft!.fields['关联任务']), [
        'task-30',
        'task-1',
      ]);
      c.read(routerProvider).go('/logs');
      await settleLocalIo(t);
      c.read(routerProvider).go('/form/log-revise?id=log-1&version=3');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        DiaryTaskLinks.parse(t.widget<DiaryTaskLinksEditor>(editor).value),
        ['task-30', 'task-1'],
      );
      final reason = find.widgetWithText(TextFormField, '填写修改理由');
      await t.ensureVisible(reason);
      await t.enterText(reason, '保留两个任务关系');
      await t.tap(find.text('提交修订申请'));
      await settleLocalIo(t);
      final revision = adapter.requests.lastWhere(
        (o) => o.path == '/logs/log-1/revisions',
      );
      expect(revision.data['body']['taskIds'], ['task-30', 'task-1']);
      expect(revision.data['version'], 3);
      await close(t);
    },
  );
  testWidgets(
    'reader opens each actual association and does not navigate unavailable link',
    (t) async {
      adapter.links = ['task-0', 'task-30', 'missing'];
      final c = await launch(t, route: '/item/logs/log-1');
      final reader = find.byType(DiaryTaskLinksReader);
      await t.ensureVisible(reader);
      await t.pumpAndSettle();
      expect(find.text('授权任务0'), findsOneWidget);
      expect(find.text('最后一页的关联任务'), findsOneWidget);
      expect(find.text('关联任务 3 暂不可查看 · 已保留原关联'), findsOneWidget);
      await t.tap(find.text('最后一页的关联任务'));
      await settleLocalIo(t);
      expect(adapter.requests.any((o) => o.path == '/tasks/task-30'), isTrue);
      expect(adapter.requests.any((o) => o.path == '/tasks/missing'), isFalse);
      c.read(routerProvider).go('/item/logs/log-1');
      await settleLocalIo(t);
      adapter.laterStatus = 403;
      c.invalidate(recordsProvider('tasks'));
      await settleLocalIo(t);
      expect(find.text('最后一页的关联任务'), findsNothing);
      await close(t);
    },
  );
  testWidgets('actual multiple association picker renders at360dp text1.5', (
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
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
    final c = await launch(
      t,
      route: '/form/log-revise?id=log-1&version=3',
      scale: 1.5,
    );
    await t.ensureVisible(find.byType(DiaryTaskLinksEditor));
    await t.pumpAndSettle();
    await t.tap(find.text('添加'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '最后一页');
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(t.getBottomRight(find.text('确认关联')).dy, lessThanOrEqualTo(500));
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final bitmap = await boundary.toImage(pixelRatio: 1);
      final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'docs/evidence/stage3-rebuild/53-diary-task-picker-large.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
      bitmap.dispose();
    });
    expect(c.read(sessionProvider).id, 'u1');
    await close(t);
  });
}
