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
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'support/local_test_state.dart';

class MemberAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool forbidden = false, lateForbidden = false, empty = false;
  Completer<void>? profileWait;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    var status = 200;
    dynamic body = {'items': [], 'total': 0};
    final cursor = int.tryParse('${o.queryParameters['cursor'] ?? 0}') ?? 0;
    if (o.path.startsWith('/profiles/')) {
      final gate = profileWait;
      if (gate != null) await gate.future;
      status = forbidden ? 403 : 200;
      final id = o.path.split('/').last;
      body = {
        'id': id,
        'name': id == 'u2' ? '陈一诺' : '林小满',
        'version': 3,
        'profile': {'introduction': '认真记录与协作'},
      };
    } else if (o.path == '/logs/subordinates' || o.path == '/logs') {
      status = forbidden || lateForbidden && cursor > 0 ? 403 : 200;
      final date = o.queryParameters['date'];
      final total = empty
          ? 0
          : date == null
          ? 31
          : 1;
      body = {
        'items': [
          for (
            var i = cursor;
            i < (total == 31 && cursor == 0 ? 30 : total);
            i++
          )
            {
              'id': 'log-$i',
              'title': i == 30 ? '最后一页正式日志' : '工作记录$i',
              'owner_id': o.queryParameters['ownerId'] ?? 'u2',
              'business_date':
                  date ?? '2026-01-${(i + 1).toString().padLeft(2, '0')}',
              if (date != null || i != 1) 'submitted': date != null || i != 0,
              'body': {'work': i < 2 ? '禁止公开的草稿或未知正文' : '正式记录$i'},
            },
        ],
        'total': total,
        'nextCursor': '30',
      };
    } else if (o.path == '/dashboard/personal') {
      body = {
        'items': [
          for (var i = 0; i < 5; i++)
            {
              'id': 'focus-$i',
              'title': '成员重点$i',
              'owner_id': o.queryParameters['ownerId'],
              'body': {'text': '真实重点内容'},
            },
        ],
        'total': 5,
      };
    } else if (o.path == '/tasks') {
      body = {'items': [], 'total': 0};
    } else if (o.path == '/organization/people') {
      body = {
        'items': [
          {'id': 'u2', 'name': '陈一诺', 'status': 'ACTIVE'},
        ],
        'total': 1,
      };
    } else if (o.path == '/logs/log-30') {
      body = {
        'id': 'log-30',
        'business_date': '2026-01-31',
        'owner_id': 'u2',
        'submitted': true,
        'version': 7,
        'body': {'work': '第31条真正正文'},
      };
    } else if (o.path == '/logs/log-30/versions' ||
        o.path == '/logs/log-30/comments') {
      body = [];
    }
    if (status == 403) body = {'code': 'FORBIDDEN'};
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

HttpRepository repo(MemberAdapter adapter) {
  final r = HttpRepository('http://members.test', 'test-token');
  r.dio.httpClientAdapter = adapter;
  return r;
}

Future<ProviderContainer> launch(
  WidgetTester t,
  MemberAdapter adapter,
  String route, {
  double scale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final c = testContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => const Session()),
      repositoryProvider.overrideWithValue(repo(adapter)),
      fontScaleProvider.overrideWith((ref) => scale),
      selectedDateProvider.overrideWith((ref) => DateTime(2027, 2, 3)),
      reportDateProvider.overrideWith((ref) => DateTime(2025, 3, 4)),
      logFilterDateProvider.overrideWith((ref) => DateTime(2026, 1, 31)),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(container: c, child: const PandoraApp()),
  );
  c.read(routerProvider).go(route);
  await settleLocalIo(t);
  return c;
}

void main() {
  testWidgets(
    'overview previews are compact, total truthful and final category source opens',
    (t) async {
      final adapter = MemberAdapter();
      final c = await launch(t, adapter, '/me/team/u2');
      expect(find.text('正在查看：陈一诺'), findsOneWidget);
      expect(find.text('成员重点0'), findsOneWidget);
      expect(find.text('成员重点3'), findsNothing);
      expect(find.text('查看全部 5 条公开个人重点 →'), findsOneWidget);
      expect(find.text('查看全部 29 条已提交日志 →'), findsOneWidget);
      expect(find.text('工作记录0'), findsNothing);
      expect(find.text('工作记录1'), findsNothing);
      expect(find.text('最后一页正式日志'), findsNothing);
      await t.ensureVisible(find.text('查看全部 29 条已提交日志 →'));
      await t.pumpAndSettle();
      await t.tap(find.text('查看全部 29 条已提交日志 →'));
      await settleLocalIo(t);
      expect(find.text('最后一页正式日志'), findsOneWidget);
      await t.ensureVisible(find.text('最后一页正式日志'));
      await t.pumpAndSettle();
      await t.tap(find.text('最后一页正式日志'));
      await settleLocalIo(t);
      expect(find.text('第31条真正正文'), findsOneWidget);
      expect(adapter.requests.any((r) => r.path == '/logs/log-30'), isTrue);
      expect(c.read(selectedDateProvider), DateTime(2027, 2, 3));
    },
  );

  testWidgets(
    'carried date, clear, picker and category changes remain member scoped',
    (t) async {
      final adapter = MemberAdapter();
      final c = await launch(t, adapter, '/me/team/u2/logs?date=2026-01-31');
      expect(c.read(memberLogDateProvider('u2')), DateTime(2026, 1, 31));
      final request = adapter.requests.lastWhere(
        (r) => r.path == '/logs/subordinates',
      );
      expect(request.queryParameters['ownerId'], 'u2');
      expect(request.queryParameters['date'], '2026-01-31');
      expect(request.queryParameters['period'], 'day');
      await t.tap(find.text('清除日期'));
      await settleLocalIo(t);
      expect(find.text('全部日期'), findsOneWidget);
      expect(find.text('最后一页正式日志'), findsOneWidget);
      expect(adapter.requests.last.queryParameters['date'], isNull);
      await t.tap(find.text('全部日期'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('确定'));
      await settleLocalIo(t);
      expect(c.read(memberLogDateProvider('u2')), isNotNull);
      expect(c.read(logFilterDateProvider), DateTime(2026, 1, 31));
      expect(c.read(selectedDateProvider), DateTime(2027, 2, 3));
      expect(c.read(reportDateProvider), DateTime(2025, 3, 4));
      c.read(routerProvider).go('/me/team/u3/logs');
      await settleLocalIo(t);
      expect(c.read(memberLogDateProvider('u3')), isNull);
      expect(adapter.requests.last.queryParameters['ownerId'], 'u3');
    },
  );

  testWidgets(
    'subordinate diary member entry carries its active business date',
    (t) async {
      final adapter = MemberAdapter();
      final c = await launch(t, adapter, '/logs/subordinates');
      expect(find.text('查看 u2 的工作台'), findsOneWidget);
      await t.ensureVisible(find.text('查看 u2 的工作台'));
      await t.pumpAndSettle();
      await t.tap(find.text('查看 u2 的工作台'));
      await settleLocalIo(t);
      expect(c.read(memberLogDateProvider('u2')), DateTime(2026, 1, 31));
      expect(find.text('正在查看：陈一诺'), findsOneWidget);
      expect(
        adapter.requests
            .lastWhere((r) => r.path == '/logs/subordinates')
            .queryParameters['date'],
        '2026-01-31',
      );
    },
  );

  for (final route in [
    '/me/team/u2/logs?date=2026-02-30',
    '/me/team/u2/logs?date=abc',
    '/me/team/u2/wrong',
  ]) {
    testWidgets('invalid link $route never reads member business data', (
      t,
    ) async {
      final adapter = MemberAdapter();
      await launch(t, adapter, route);
      expect(find.text('工作台链接无效'), findsOneWidget);
      expect(
        adapter.requests.where(
          (r) => r.path == '/profiles/u2' || r.path == '/logs/subordinates',
        ),
        isEmpty,
      );
    });
  }

  testWidgets(
    'later page403 removes entire identity, retry recovers real data',
    (t) async {
      final adapter = MemberAdapter();
      final c = await launch(t, adapter, '/me/team/u2/logs');
      expect(find.text('正在查看：陈一诺'), findsOneWidget);
      adapter.lateForbidden = true;
      c.invalidate(memberRecordsProvider(('logs/subordinates', 'u2')));
      await settleLocalIo(t);
      expect(find.text('正在查看：陈一诺'), findsNothing);
      expect(find.text('最后一页正式日志'), findsNothing);
      expect(find.text('成员范围已不可访问，受保护资料与记录已清除。'), findsOneWidget);
      expect(find.text('返回本人面板'), findsOneWidget);
      adapter.lateForbidden = false;
      await t.tap(find.text('重新检查访问权限'));
      await settleLocalIo(t);
      expect(find.text('正在查看：陈一诺'), findsOneWidget);
      expect(find.text('最后一页正式日志'), findsOneWidget);
    },
  );

  testWidgets('empty submitted records are distinct from permission refusal', (
    t,
  ) async {
    final adapter = MemberAdapter()..empty = true;
    final c = await launch(t, adapter, '/me/team/u2/logs');
    expect(find.text('正在查看：陈一诺'), findsOneWidget);
    expect(find.text('暂无记录'), findsOneWidget);
    adapter.forbidden = true;
    c.invalidate(itemProvider(('organization', 'u2')));
    await settleLocalIo(t);
    expect(find.text('正在查看：陈一诺'), findsNothing);
    expect(find.text('暂无记录'), findsNothing);
  });

  testWidgets(
    'account replacement rejects delayed member identity and resets member date',
    (t) async {
      final adapter = MemberAdapter()..profileWait = Completer<void>();
      final c = await launch(t, adapter, '/me/team/u2/logs?date=2026-01-31');
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u3',
        role: UserRole.employee,
        dispatch: false,
      );
      await t.pump();
      adapter.profileWait!.complete();
      await settleLocalIo(t);
      expect(find.text('正在查看：陈一诺'), findsNothing);
      expect(find.text('无权访问'), findsOneWidget);
      expect(c.read(memberLogDateProvider('u2')), isNull);
      expect(
        adapter.requests.where((r) => r.path == '/logs/subordinates'),
        isEmpty,
      );
      expect(t.takeException(), isNull);
    },
  );

  if (!AppConfig.mock) {
    testWidgets(
      'formal help does not send unsupported feedback or navigate to a fake list',
      (t) async {
        final adapter = MemberAdapter();
        final c = await launch(t, adapter, '/me/help');
        final count = adapter.requests.length;
        await t.ensureVisible(find.text('查看问题反馈说明'));
        await t.pumpAndSettle();
        await t.tap(find.text('查看问题反馈说明'));
        await t.pumpAndSettle();
        expect(
          c.read(routerProvider).routeInformationProvider.value.uri.path,
          '/me/help',
        );
        expect(adapter.requests.length, count);
        expect(find.textContaining('当前不能发送反馈'), findsOneWidget);
      },
    );
  }

  testWidgets('public own profile also hides unknown and draft diaries', (
    t,
  ) async {
    final adapter = MemberAdapter();
    await launch(t, adapter, '/me/profile');
    expect(find.text('工作记录0'), findsNothing);
    expect(find.text('工作记录1'), findsNothing);
    expect(find.text('最后一页正式日志'), findsOneWidget);
  });

  testWidgets(
    'help zero-match clears text and explains actual supported behavior',
    (t) async {
      final adapter = MemberAdapter();
      await launch(t, adapter, '/me/help');
      await t.enterText(find.byType(TextField), '不存在的随机搜索');
      await t.pumpAndSettle();
      expect(find.text('没有找到相关说明'), findsOneWidget);
      await t.tap(find.text('清除搜索'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
      await t.tap(find.text('员工 · 如何处理任务'));
      await t.pumpAndSettle();
      expect(find.textContaining('正式服务目前不支持退回补充'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('actual router member and help screens render at360dp large text', (
    t,
  ) async {
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
    for (final (route, name) in [
      ('/me/team/u2', '47-member-overview-large'),
      ('/me/team/u2/logs?date=2026-01-31', '48-member-logs-large'),
      ('/me/help', '49-help-large'),
    ]) {
      final adapter = MemberAdapter();
      final c = await launch(t, adapter, route, scale: 1.5);
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
        await File(
          'docs/evidence/stage3-rebuild/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
}
