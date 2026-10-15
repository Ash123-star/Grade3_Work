import 'support/flutter_sdk_assets.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_tools.dart';
import 'package:pandora_mobile/features/ai_map/ai_job_pages.dart';
import 'package:pandora_mobile/features/ai_map/graph_layout.dart';
import 'ai_http_workflow_test.dart' show AiAdapter, buildHttp;
import 'support/local_test_state.dart';

Map<String, dynamic> node(String id, {String type = 'RESULT'}) => {
  'id': id,
  'owner_id': 'u1',
  'job_id': 'job',
  'body': {
    'title': '真实节点 $id',
    'type': type,
    'sourceIds': ['task:task-1'],
  },
};
Map<String, dynamic> edge(String from, String to) => {
  'source_id': from,
  'target_id': to,
  'body': {'label': '真实前置'},
};

class GraphAdapter extends AiAdapter {
  List<Map<String, dynamic>> mapNodes = [
    node('source'),
    node('goal', type: 'GOAL'),
    node('risk', type: 'RISK'),
    node('detached', type: 'BLOCKER'),
  ];
  List<Map<String, dynamic>> mapEdges = [
    edge('source', 'goal'),
    edge('goal', 'risk'),
  ];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    if (o.path == '/ai-maps') {
      requests.add(o);
      return ResponseBody.fromString(
        jsonEncode({'nodes': mapNodes, 'edges': mapEdges}),
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
  void verifyBounds(RelationshipLayout value) {
    final rects = [
      for (final point in value.points.values) point & value.nodeSize,
    ];
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].left, greaterThanOrEqualTo(0));
      expect(rects[i].right, lessThanOrEqualTo(value.size.width));
      expect(rects[i].bottom, lessThanOrEqualTo(value.size.height));
      expect(rects[i].top.isFinite, true);
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), false);
      }
    }
  }

  test(
    'actual branches and merges determine ranks; disconnected nodes stay explicit',
    () {
      final value = RelationshipLayout.build(
        [
          node('a'),
          node('b'),
          node('c', type: 'GOAL'),
          node('d'),
          node('alone'),
        ],
        [edge('a', 'b'), edge('a', 'c'), edge('b', 'd'), edge('c', 'd')],
      );
      expect(value.points['a']!.dy, lessThan(value.points['b']!.dy));
      expect(value.points['b']!.dy, value.points['c']!.dy);
      expect(value.points['c']!.dy, lessThan(value.points['d']!.dy));
      expect(value.isolated, {'alone'});
      expect(value.cyclic, isEmpty);
      verifyBounds(value);
    },
  );
  test(
    'goals center within equal dependency level, input order does not move nodes',
    () {
      final nodes = [node('a'), node('b', type: 'GOAL'), node('c')];
      final value = RelationshipLayout.build(nodes, []);
      expect(value.points['b']!.dx, greaterThan(value.points['a']!.dx));
      expect(value.points['b']!.dx, lessThan(value.points['c']!.dx));
      expect(
        RelationshipLayout.build(nodes.reversed.toList(), []).points,
        value.points,
      );
      verifyBounds(value);
    },
  );
  test(
    'cycles are condensed, self edges marked, downstream follows whole component',
    () {
      final value = RelationshipLayout.build(
        [node('a'), node('b'), node('c'), node('self')],
        [edge('a', 'b'), edge('b', 'a'), edge('b', 'c'), edge('self', 'self')],
      );
      expect(value.cyclic, {'a', 'b', 'self'});
      expect(value.points['a']!.dy, value.points['b']!.dy);
      expect(value.points['b']!.dy, lessThan(value.points['c']!.dy));
      verifyBounds(value);
    },
  );
  test(
    '100 node deep map and large text stays finite, complete and nonoverlapping',
    () {
      final value = RelationshipLayout.build(
        [
          for (var i = 0; i < 100; i++)
            node('n$i', type: i % 4 == 0 ? 'GOAL' : 'RESULT'),
        ],
        [for (var i = 0; i < 99; i++) edge('n$i', 'n${i + 1}')],
        textScale: 1.5,
      );
      expect(value.points.length, 100);
      expect(value.size.height, greaterThan(5000));
      expect(value.points['n99']!.dy, greaterThan(value.points['n98']!.dy));
      verifyBounds(value);
    },
  );
  test(
    'empty, detached and missing-endpoint edges do not invent relations',
    () {
      expect(RelationshipLayout.build([], []).points, isEmpty);
      final nodes = [for (var i = 0; i < 100; i++) node('n$i')];
      final value = RelationshipLayout.build(nodes, [edge('unknown', 'n0')]);
      expect(value.isolated.length, 100);
      verifyBounds(value);
    },
  );

  late GraphAdapter adapter;
  late GlobalKey capture;
  setUp(() {
    adapter = GraphAdapter();
    capture = GlobalKey();
  });
  const session = Session(id: 'u1', token: 'graph-token', role: UserRole.admin);
  Future<ProviderContainer> launch(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => session),
        fontScaleProvider.overrideWith((ref) => scale),
        httpRepositoryProvider.overrideWith(
          (ref) => buildHttp(ref.watch(sessionProvider), adapter),
        ),
        repositoryProvider.overrideWith(
          (ref) => ref.watch(httpRepositoryProvider),
        ),
        routerProvider.overrideWith((ref) {
          final router = GoRouter(
            initialLocation: '/ai/graph',
            routes: [
              GoRoute(
                path: '/ai/graph',
                builder: (_, _) => const ServerAiGraphPage(),
              ),
              GoRoute(
                path: '/ai/jobs/:id/actions/:index',
                builder: (_, s) => AiJobPage(
                  s.pathParameters['id']!,
                  actionIndex: int.parse(s.pathParameters['index']!),
                ),
              ),
              GoRoute(
                path: '/item/tasks/:id',
                builder: (_, s) =>
                    Scaffold(body: Text('原始任务 ${s.pathParameters['id']}')),
              ),
            ],
          );
          ref.onDispose(router.dispose);
          return router;
        }),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      RepaintBoundary(
        key: capture,
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

  Future<void> openNode(WidgetTester t, String title) async {
    await t.scrollUntilVisible(
      find.text(title).last,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text(title).last);
    await t.pumpAndSettle();
    await t.tap(find.text(title).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'HTTP graph legend and same filtered edge list, no match explicit reset',
    (t) async {
      await launch(t);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('目标'), findsWidgets);
      expect(find.textContaining('未关联节点独立展示'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
      await t.enterText(find.byType(TextField).first, 'risk');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('筛选内暂无依赖关系'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('真实节点 source →'), findsNothing);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '不存在');
      await t.pumpAndSettle();
      expect(find.text('没有匹配的节点，请调整搜索或类型。'), findsOneWidget);
      await t.tap(find.text('清除地图筛选'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'actual source and matching action modal navigates without any write',
    (t) async {
      await launch(t);
      await openNode(t, '真实节点 goal');
      expect(find.text('原始依据'), findsOneWidget);
      expect(find.text('相关下一步'), findsOneWidget);
      expect(find.text('发布依赖清单'), findsOneWidget);
      await t.ensureVisible(find.text('先核对发布依赖'));
      await t.pumpAndSettle();
      await t.tap(find.text('先核对发布依赖'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.byType(AiJobPage), findsOneWidget);
      expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
      await close(t);
    },
  );
  testWidgets(
    'cycle message, duplicate or invalid node fail safely with recovery',
    (t) async {
      adapter.mapEdges.add(edge('risk', 'goal'));
      final c = await launch(t);
      expect(find.textContaining('存在循环依赖'), findsOneWidget);
      adapter.mapNodes.add(node('goal'));
      await t.tap(find.byTooltip('刷新地图'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.textContaining('地图节点格式未确认'), findsWidgets);
      adapter.mapNodes = [node('invalid', type: 'UNKNOWN')];
      await t.tap(find.byTooltip('刷新地图'));
      await settleLocalIo(t);
      expect(find.textContaining('地图节点格式未确认'), findsWidgets);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        token: 'new',
      );
      await t.pumpAndSettle();
      expect(find.text('真实节点 goal'), findsNothing);
      await close(t);
    },
  );
  testWidgets('100 actual nodes have last list entry reachable at large text', (
    t,
  ) async {
    adapter.mapNodes = [for (var i = 0; i < 100; i++) node('n$i')];
    adapter.mapEdges = [for (var i = 0; i < 99; i++) edge('n$i', 'n${i + 1}')];
    await launch(t, scale: 1.5);
    await t.scrollUntilVisible(
      find.text('真实节点 n99').last,
      600,
      maxScrolls: 100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('真实节点 n99'), findsWidgets);
    expect(t.takeException(), isNull);
    await close(t);
  });
  testWidgets(
    'actual hierarchical graph renders at360dp text1.5 with complete list',
    (t) async {
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
      await t.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final bitmap = await boundary.toImage(pixelRatio: 1);
        final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../output/flutter-evidence/55-ai-hierarchy-large.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        bitmap.dispose();
      });
      await close(t);
    },
  );
}
