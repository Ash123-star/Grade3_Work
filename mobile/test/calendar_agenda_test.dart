import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

DemoStore agendaStore() {
  final store = DemoStore();
  store.records['tasks'] = [
    for (var i = 0; i < 4; i++)
      Record(
        id: 't$i',
        title: '任务标题$i',
        fields: {
          'deadline': '2026-10-13T0${i + 1}:00:00Z',
          if (i == 0) 'startAt': '2026-10-13T01:00:00Z',
          if (i == 0) 'endAt': '2026-10-13T02:00:00Z',
        },
      ),
  ];
  store.records['logs'] = [
    const Record(
      id: 'l1',
      title: '日志标题',
      fields: {
        'businessDate': '2026-10-13',
        'status': '草稿',
        'submitted': false,
        '今日工作': '列表进入编辑验证',
      },
    ),
  ];
  return store;
}

void main() {
  testWidgets(
    'page chrome removes title and unused bar, preserves actions and back',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => PageFrame(
              title: '重复页名',
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const PageFrame(title: '二级页名', child: Text('正文')),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AppBar), findsNothing);
      await t.tap(find.text('打开'));
      await t.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('二级页名'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MaterialApp(
          home: PageFrame(
            title: '操作页名',
            actions: [TextButton(onPressed: () {}, child: const Text('消息'))],
            child: const Text('正文'),
          ),
        ),
      );
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('操作页名'), findsNothing);
    },
  );

  testWidgets('daily rows open log detail and existing draft editor', (
    t,
  ) async {
    final store = agendaStore();
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => const Session()),
        repositoryProvider.overrideWithValue(
          MockRepository(const Session(), store: store),
        ),
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
        periodProvider.overrideWith((ref) => '日'),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go('/view');
    await settleLocalIo(t);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('agenda:tasks:t$i')), findsOneWidget);
    }
    final row = find.byKey(const ValueKey('agenda:logs:l1'));
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await settleLocalIo(t);
    expect(t.widget<DetailPage>(find.byType(DetailPage)).id, 'l1');
    expect(find.text('继续编辑草稿'), findsOneWidget);
    await t.tap(find.text('继续编辑草稿'));
    await settleLocalIo(t);
    expect(find.byType(FormPage), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('top actions scroll with content and stay reachable on return', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: PageFrame(
          title: 'AI地图',
          actions: [TextButton(onPressed: () {}, child: const Text('建议草稿'))],
          child: PageBody(
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 80, child: Text('内容$i')),
            ],
          ),
        ),
      ),
    );
    final button = find.text('建议草稿');
    final before = t.getTopLeft(button).dy;
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(before, greaterThanOrEqualTo(0));
    expect(button.hitTestable(), findsNothing);
    await t.drag(find.byType(ListView), const Offset(0, 500));
    await t.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets(
    'bounded month cells open all records and revoke stale sheet data',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), store: agendaStore()),
          ),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
          periodProvider.overrideWith((ref) => '月'),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: appTheme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: const Scaffold(
                body: SingleChildScrollView(child: CalendarContent()),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cell = find.byKey(const ValueKey('month-day:2026-10-13'));
      expect(
        find.descendant(of: cell, matching: find.text('+3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cell, matching: find.textContaining('任·')),
        findsNothing,
      );
      expect(
        find.descendant(of: cell, matching: find.textContaining('任务标题')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: cell, matching: find.textContaining('日志标题')),
        findsNothing,
      );
      await t.ensureVisible(cell);
      await t.tap(cell);
      await t.pumpAndSettle();
      expect(find.text('5 条记录'), findsOneWidget);
      c.read(sessionProvider.notifier).state = const Session(active: false);
      await t.pump();
      expect(find.text('账号权限已变化，请关闭后重新查看'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('任务标题0'),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );

  for (final scenario in [
    DemoScenario.empty,
    DemoScenario.forbidden,
    DemoScenario.offline,
  ]) {
    testWidgets('agenda preserves $scenario feedback', (t) async {
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), scenario: scenario),
          ),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
          periodProvider.overrideWith((ref) => '日'),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: const Scaffold(
              body: SingleChildScrollView(child: CalendarContent()),
            ),
          ),
        ),
      );
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      await t.pumpAndSettle();
      expect(
        find.byType(ErrorPanel),
        scenario == DemoScenario.empty ? findsNothing : findsOneWidget,
      );
      if (scenario == DemoScenario.empty) {
        expect(find.text('这一天没有任务或日志，可选择其他日期'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
}
