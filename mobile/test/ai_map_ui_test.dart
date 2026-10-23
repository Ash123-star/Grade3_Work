import 'support/local_test_state.dart';
import 'ai_work_repository_test.dart' show record, capabilities;
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

class WorkAdapter implements HttpClientAdapter {
  bool failCreate = false;
  final List<RequestOptions> calls = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<dynamic>? cancel,
  ) async {
    calls.add(options);
    Object body = {'items': [], 'nextCursor': -1, 'contractVersion': 1};
    var status = 200;
    final detail = {
      ...record(version: 2),
      'id': 'work-1',
      'title': '整理成本表',
      'result': {'summary': '补充信息后就能继续'},
      'messages': [
        {
          'body': {'text': '请整理成本表', 'attachmentIds': []},
        },
      ],
    };
    if (options.path == '/ai/work-capabilities') {
      body = capabilities;
    } else if (options.method == 'POST') {
      status = failCreate ? 503 : 202;
      body = failCreate ? {'code': 'AI_PROVIDER_FAILED'} : detail;
    } else if (options.path.contains('/work-items/')) {
      body = detail;
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<ProviderContainer> launch(
    WidgetTester tester,
    WorkAdapter adapter, {
    double width = 360,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => const Session()),
        sseClientProvider.overrideWithValue(null),
        fontScaleProvider.overrideWith((ref) => scale),
        httpRepositoryProvider.overrideWith((ref) {
          final s = ref.watch(sessionProvider);
          final repo = HttpRepository('http://localhost/api', s.token);
          repo.dio.httpClientAdapter = adapter;
          return repo;
        }),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go('/ai');
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets(
    'new workbench keeps composer above five tabs and removes analysis decoration',
    (tester) async {
      await launch(tester, WorkAdapter());
      expect(find.text('把事情交给我'), findsOneWidget);
      expect(find.text('发展分析'), findsNothing);
      expect(find.text('开始分析'), findsNothing);
      expect(find.text('把下一步想清楚'), findsNothing);
      expect(
        tester.getBottomLeft(find.text('发送')).dy,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      for (final name in ['导图', '视图', '日志', 'AI地图', '我的']) {
        expect(find.text(name), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('failed send keeps input and reuses request key', (tester) async {
    final adapter = WorkAdapter()..failCreate = true;
    await launch(tester, adapter);
    await tester.enterText(find.byType(TextField), '请整理成本表');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('请整理成本表'), findsOneWidget);
    expect(find.textContaining('暂时没能处理'), findsOneWidget);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    final writes = adapter.calls.where((e) => e.method == 'POST').toList();
    expect(writes.length, 2);
    expect(
      writes[0].headers['Idempotency-Key'],
      writes[1].headers['Idempotency-Key'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'submitted request shows clarification and no fake task success',
    (tester) async {
      final adapter = WorkAdapter();
      await launch(tester, adapter);
      await tester.enterText(find.byType(TextField), '请整理成本表');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('办理详情'), findsOneWidget);
      expect(find.text('这项任务什么时候交？'), findsOneWidget);
      expect(find.text('任务已创建'), findsNothing);
      expect(find.text('已提交，等待验收'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('workbench fits $width dp at 1.5 font scale', (tester) async {
      final c = await launch(tester, WorkAdapter(), width: width, scale: 1.5);
      await tester.tap(find.text('截图建任务'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'other',
        role: UserRole.employee,
        dispatch: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('任务已创建'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
