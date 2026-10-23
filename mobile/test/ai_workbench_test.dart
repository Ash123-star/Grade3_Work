import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/ai_work.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/ai_work_repository.dart';
import 'package:pandora_mobile/features/ai_map/workbench_page.dart';
import 'package:pandora_mobile/features/ai_map/work_management_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/flutter_sdk_assets.dart';
import 'support/local_test_state.dart';

class WorkFixture extends AiWorkRepository {
  WorkFixture() : super(Dio());
  static const longTaskTitle = '核对华东区域第四季度全部项目成本明细并提交更新后的完整报价材料';
  int confirmations = 0;
  bool completed = false;
  bool similar = false;
  WorkItem get value => WorkItem({
    'id': 'work',
    'title': '交付成本明细',
    'version': completed ? 4 : 2,
    'planVersion': 1,
    'planValid': true,
    'state': completed ? 'SUCCEEDED' : 'WAITING_CONFIRMATION',
    'messages': <Object>[],
    'plan': {
      'summary': '任务要求已整理',
      'actions': [
        {
          'type': 'CREATE_TASK',
          'label': '给周宁创建「交付成本明细」',
          'payload': {'deadline': '2026-12-24T17:00:00+08:00'},
          if (similar)
            'similarTasks': [
              {'id': 'existing-task', 'title': '已有的成本明细任务'},
            ],
        },
      ],
    },
    'receipts': completed
        ? [
            {
              'step_key': 'action-1',
              'result': {'summary': '任务已创建', 'taskId': 'task'},
            },
          ]
        : [],
    'result': {'summary': completed ? '任务已创建' : '请核对负责人和截止时间'},
  });
  @override
  Future<WorkItem> get(String id) async => value;
  @override
  Future<List<WorkItem>> list() async => [];
  @override
  Future<WorkListPage> page(int cursor) async => WorkListPage(await list(), -1);
  @override
  Future<List<Map<String, dynamic>>> authorizations() async => [];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    if (path.startsWith('/ai/work-authorization-options')) {
      return {
        'items': [
          {'id': 'long-task', 'label': longTaskTitle},
        ],
      };
    }
    if (path == '/tasks/long-task') {
      return {'id': 'long-task', 'title': longTaskTitle, 'version': 1};
    }
    if (path == '/ai/work-authorizations') return {'items': []};
    if (path == '/ai/work-authorization-policy') {
      return {
        'canCreate': false,
        'canSubmit': false,
        'maxDays': 1,
        'maxObjects': 1,
        'maxActions': 1,
      };
    }
    throw StateError('Unexpected fixture request: $method $path');
  }

  @override
  Future<WorkItem> confirm(WorkItem item, String key) async {
    confirmations++;
    completed = true;
    return value;
  }
}

class PagedWorkFixture extends WorkFixture {
  bool secondAccount = false;
  final requested = <int>[];
  @override
  Future<List<WorkItem>> list() async => secondAccount
      ? []
      : List.generate(
          30,
          (i) => WorkItem({
            'id': 'work-$i',
            'title': '事项 $i',
            'state': 'SUCCEEDED',
            'version': 1,
          }),
        );
  @override
  Future<WorkListPage> page(int cursor) async {
    if (cursor == 0) {
      final items = await list();
      return WorkListPage(items, items.length == 30 ? 30 : -1);
    }
    requested.add(cursor);
    return const WorkListPage([
      WorkItem({
        'id': 'work-29',
        'title': '重复事项',
        'state': 'SUCCEEDED',
        'version': 2,
      }),
      WorkItem({'id': 'work-30', 'title': '历史事项', 'state': 'SUCCEEDED'}),
    ], -1);
  }
}

class StaleReportFixture extends WorkFixture {
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async => {
    'id': 'check',
    'state': 'STALE',
    'snapshotValid': false,
    'summary': '交付要求或材料已更新，请重新检查',
    'findings': [],
  };
}

class ProcedureFixture extends WorkFixture {
  final paths = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    paths.add(path);
    if (fail) throw StateError('offline');
    return {
      'items': path.contains('drafts=true')
          ? [
              {
                'id': 'procedure',
                'title': '差旅报销办法',
                'version': 1,
                'review_status': 'PENDING',
                'pending_review_id': 'review',
              },
            ]
          : [],
      'nextCursor': -1,
    };
  }
}

void main() {
  testWidgets(
    'procedure maintenance shows pending review and clears after account switch',
    (t) async {
      final repo = ProcedureFixture();
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith(
            (_) => const Session(role: UserRole.admin),
          ),
          workRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: appTheme(), home: const ProcedurePage()),
        ),
      );
      await settleLocalIo(t);
      await t.tap(find.text('维护草稿'));
      await settleLocalIo(t);
      expect(find.text('差旅报销办法'), findsOneWidget);
      expect(find.text('等待复核 · 查看申请'), findsOneWidget);
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '申请发布')).onPressed,
        isNull,
      );
      container.read(sessionProvider.notifier).state = const Session(
        id: 'other',
      );
      await t.pumpAndSettle();
      expect(find.text('差旅报销办法'), findsNothing);
      expect(find.text('账号已切换，请重新打开公司资料'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets(
    'employee sees procedure search with failure recovery and no maintenance controls',
    (t) async {
      final repo = ProcedureFixture()..fail = true;
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith(
            (_) => const Session(role: UserRole.employee),
          ),
          workRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: appTheme(), home: const ProcedurePage()),
        ),
      );
      await settleLocalIo(t);
      expect(find.text('维护草稿'), findsNothing);
      expect(find.byTooltip('新增资料'), findsNothing);
      expect(find.text('重新加载'), findsOneWidget);
      repo.fail = false;
      await t.tap(find.text('重新加载'));
      await settleLocalIo(t);
      expect(find.text('还没有可用的公司资料'), findsOneWidget);
      expect(find.text('重新加载'), findsNothing);
      await t.enterText(find.byType(TextField), '差旅');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settleLocalIo(t);
      expect(
        repo.paths.last,
        contains('search=${Uri.encodeQueryComponent('差旅')}'),
      );
      expect(repo.paths.every((p) => p.contains('drafts=false')), isTrue);
      await t.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets('sending keeps keyboard focus and input until acknowledged', (
    t,
  ) async {
    final pending = Completer<void>();
    final focus = FocusNode();
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: WorkComposer(
              focus: focus,
              onSend: (_, _, _) => pending.future,
            ),
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextField), '请核对材料');
    expect(focus.hasFocus, isTrue);
    await t.tap(find.text('发送'));
    await t.pump();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(field.readOnly, isTrue);
    expect(focus.hasFocus, isTrue);
    pending.completeError(StateError('offline'));
    await t.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      '请核对材料',
    );
    await t.pumpWidget(const SizedBox.shrink());
    focus.dispose();
  });
  testWidgets('motion pauses in background, offscreen and reduced motion', (
    t,
  ) async {
    bool? active;
    Future<void> render({bool reduced = false, bool visible = true}) async {
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: visible,
              child: WorkMotionScope(
                child: Builder(
                  builder: (context) {
                    active = TickerMode.of(context);
                    return Text(
                      WorkMotion.duration(context).inMilliseconds.toString(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
    }

    await render();
    expect(active, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(active, isFalse);
    expect(find.text('0'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await render(reduced: true);
    expect(active, isFalse);
    await render(visible: false);
    expect(active, isFalse);
    await render();
    expect(active, isTrue);
    await t.pumpWidget(const SizedBox.shrink());
  });
  test('paged list deduplicates and resets after account switch', () async {
    final repo = PagedWorkFixture();
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith((_) => const Session()),
        workRepositoryProvider.overrideWithValue(repo),
      ],
    );
    final keep = container.listen(workListProvider, (_, _) {});
    try {
      expect(
        (await container.read(workListProvider.future)).items,
        hasLength(30),
      );
      container.read(workPageCountProvider.notifier).state = 2;
      final result = await container.read(workListProvider.future);
      expect(result.items, hasLength(31));
      expect(
        result.items.singleWhere((item) => item.id == 'work-29').title,
        '重复事项',
      );
      expect(result.nextCursor, -1);
      expect(repo.requested, [30]);
      repo.secondAccount = true;
      container.read(sessionProvider.notifier).state = const Session(
        id: 'other',
      );
      expect((await container.read(workListProvider.future)).items, isEmpty);
      expect(container.read(workPageCountProvider), 1);
    } finally {
      keep.close();
      container.dispose();
    }
  });

  testWidgets('stale report blocks submission and hides on account switch', (
    t,
  ) async {
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith((_) => const Session()),
        workRepositoryProvider.overrideWithValue(StaleReportFixture()),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appTheme(),
          home: const DeliveryCheckPage('task', 1),
        ),
      ),
    );
    await settleLocalIo(t);
    expect(find.text('交付要求或材料已更新，请重新检查'), findsOneWidget);
    final submit = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交人工核对'),
    );
    expect(submit.onPressed, isNull);
    container.read(sessionProvider.notifier).state = const Session(id: 'other');
    await t.pumpAndSettle();
    expect(find.text('交付要求或材料已更新，请重新检查'), findsNothing);
    expect(find.text('账号已切换，请重新打开任务'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  testWidgets('company restriction disables grants with useful copy', (
    t,
  ) async {
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith((_) => const Session()),
        workRepositoryProvider.overrideWithValue(WorkFixture()),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: appTheme(), home: const WorkSettingsPage()),
      ),
    );
    await settleLocalIo(t);
    expect(find.text('公司暂未开放自动授权，你仍可逐次交代办理。'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '添加授权'))
          .onPressed,
      isNull,
    );
    await t.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  testWidgets(
    'failed send keeps input and idempotency key until acknowledged',
    (t) async {
      final keys = <String>[];
      var fail = true;
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: WorkComposer(
                onSend: (text, files, key) async {
                  keys.add(key);
                  if (fail) throw StateError('offline');
                },
              ),
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField), '请帮我整理交付材料');
      await t.tap(find.text('发送'));
      await t.pumpAndSettle();
      expect(find.text('请帮我整理交付材料'), findsOneWidget);
      expect(find.textContaining('内容已保留'), findsOneWidget);
      fail = false;
      await t.tap(find.text('发送'));
      await t.pumpAndSettle();
      expect(keys, hasLength(2));
      expect(keys[0], keys[1]);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('workbench navigation, large text confirmation and real receipt', (
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(File(materialIconsFontPath).readAsBytesSync()),
        ),
      );
    await font.load();
    final display = FontLoader(AppTypography.displayFamily)
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    await display.load();
    await icons.load();
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final width in [360.0, 390.0, 412.0]) {
      t.view.physicalSize = Size(width, 844);
      final repo = WorkFixture();
      final container = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          fontScaleProvider.overrideWith((_) => width == 360 ? 1.5 : 1),
          workRepositoryProvider.overrideWithValue(repo),
          workCapabilitiesProvider.overrideWith(
            (_) async =>
                const WorkCapabilities(enabled: true, configured: true),
          ),
          workEventsProvider('work').overrideWith((_) => const Stream.empty()),
        ],
      );
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: UncontrolledProviderScope(
            container: container,
            child: const PandoraApp(),
          ),
        ),
      );
      container.read(routerProvider).go('/ai');
      await settleLocalIo(t);
      expect(find.text('把事情交给我'), findsOneWidget);
      for (final label in ['导图', '视图', '日志', 'AI地图', '我的']) {
        expect(find.text(label), findsWidgets);
      }
      Future<void> capture(String phase) async {
        expect(t.takeException(), isNull, reason: '$phase at $width');
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await t.runAsync(() async {
          final picture = await render.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File(
            '${Directory.systemTemp.path}/pandora-ui-evidence/ai-workbench/$phase-${width.toInt()}.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await capture('home');
      container.read(routerProvider).go('/ai/work/work');
      await settleLocalIo(t);
      expect(find.text('创建任务'), findsOneWidget);
      await capture('confirmation');
      await t.ensureVisible(find.text('创建任务'));
      await t.tap(find.text('创建任务'));
      await settleLocalIo(t);
      expect(repo.confirmations, 1);
      expect(find.text('任务已创建'), findsWidgets);
      expect(find.text('查看任务'), findsOneWidget);
      expect(find.text('已验收'), findsNothing);
      await capture('receipt');
      await t.ensureVisible(find.text('选择任务'));
      await t.tap(find.text('选择任务'));
      await settleLocalIo(t);
      await t.tap(find.text(WorkFixture.longTaskTitle));
      await settleLocalIo(t);
      final taskButton = find.ancestor(
        of: find.text(WorkFixture.longTaskTitle),
        matching: find.byType(OutlinedButton),
      );
      expect(taskButton, findsOneWidget);
      expect(t.getSize(taskButton).height, greaterThanOrEqualTo(48));
      await capture('selected-task');
      repo.completed = false;
      repo.similar = true;
      container.read(routerProvider).go('/ai');
      await settleLocalIo(t);
      container.read(routerProvider).go('/ai/work/work');
      await settleLocalIo(t);
      expect(find.text('已有相似任务，要继续处理原任务吗？'), findsOneWidget);
      expect(find.text('已有的成本明细任务'), findsOneWidget);
      expect(find.text('仍然创建任务'), findsOneWidget);
      await capture('similar-task');
      await t.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
