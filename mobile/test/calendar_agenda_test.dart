import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/features/dashboard/dashboard_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

DemoStore agendaStore() {
  final store = DemoStore();
  store.records['tasks'] = [
    for (var i = 0; i < 7; i++)
      Record(
        id: 't$i',
        title: i == 6 ? '数据结构实训' : '任务标题$i',
        fields: {
          'tagColor': '#BE8A68',
          'deadline': '2026-10-13T0${i + 1}:00:00Z',
          if (i == 0) 'startAt': '2026-10-12T01:00:00Z',
          if (i == 0) 'endAt': '2026-10-12T02:00:00Z',
          if (i == 4) ...{
            'startAt': '2026-09-30T08:00:00+08:00',
            'deadline': '2026-10-02T18:00:00+08:00',
          },
          if (i == 5) ...{
            'startAt': '2026-10-13T08:00:00+08:00',
            'deadline': '2026-10-13T18:00:00+08:00',
          },
          if (i == 6) ...{
            'startAt': '2026-10-16T08:00:00+08:00',
            'deadline': '2026-10-20T18:00:00+08:00',
          },
        },
      ),
    const Record(
      id: 'earlier-span',
      title: '跨周任务测试完整名称',
      fields: {
        'startAt': '2026-10-15T08:00:00+08:00',
        'deadline': '2026-10-22T18:00:00+08:00',
        'tagColor': '#9EDCC3',
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

class TaskViewRepository extends MockRepository {
  TaskViewRepository({DemoStore? store}) : super(const Session(), store: store);
  final requests = <String>[];

  @override
  Future<PageResult> list(String resource, Query query) {
    requests.add(resource);
    if (resource == 'logs') throw StateError('视图不得查询日志');
    return super.list(resource, query);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final period in ['日', '周', '月']) {
    testWidgets('$period view queries only tasks and removes type hints', (
      t,
    ) async {
      final repo = TaskViewRepository(store: agendaStore());
      final c = testContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
          periodProvider.overrideWith((ref) => period),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: CalendarPage()),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.requests, isNotEmpty);
      expect(repo.requests.toSet(), {'tasks'});
      expect(find.textContaining('日志'), findsNothing);
      expect(find.textContaining('任务·'), findsNothing);
      expect(find.textContaining('任务 ·'), findsNothing);
      expect(find.byType(ErrorPanel), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('cross-week continuation repeats its task title on Monday', (
    t,
  ) async {
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
          home: const Scaffold(body: CalendarContent()),
        ),
      ),
    );
    await t.pumpAndSettle();

    final mondayContinuation = find.byKey(
      const ValueKey(
        'month-span-label:tasks:earlier-span:2026-10-19T00:00:00.000',
      ),
    );
    expect(mondayContinuation, findsOneWidget);
    expect(t.widget<Text>(mondayContinuation).data, '跨周任务测试完整名称');
    expect(t.takeException(), isNull);
  });

  testWidgets('date control opens a cancellable date wheel', (t) async {
    final c = testContainer(
      overrides: [
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: DateControls())),
      ),
    );
    await t.tap(find.text('2026年10月'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-date-wheel')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('calendar-date-cancel')));
    await t.pumpAndSettle();
    expect(c.read(selectedDateProvider), DateTime(2026, 10, 13));
    await t.tap(find.text('2026年10月'));
    await t.pumpAndSettle();
    await t.drag(find.byType(CupertinoPicker).first, const Offset(0, -96));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('calendar-date-confirm')));
    await t.pumpAndSettle();
    expect(c.read(selectedDateProvider), isNot(DateTime(2026, 10, 13)));
    expect(t.takeException(), isNull);
    c.dispose();
  });

  testWidgets(
    'page chrome removes title and unused bar, preserves actions and back',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => PageFrame(
              title: '重复页名',
              showTitle: false,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PageFrame(
                      title: '二级页名',
                      showTitle: false,
                      child: Text('正文'),
                    ),
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
            showTitle: false,
            actions: [TextButton(onPressed: () {}, child: const Text('消息'))],
            child: const Text('正文'),
          ),
        ),
      );
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('操作页名'), findsNothing);
    },
  );

  testWidgets('daily rows open task detail without log records', (t) async {
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
    expect(find.byKey(const ValueKey('agenda:logs:l1')), findsNothing);
    expect(find.text('日志标题'), findsNothing);
    final row = find.byKey(const ValueKey('agenda:tasks:t1'));
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    await t.tap(row);
    await settleLocalIo(t);
    expect(t.widget<DetailPage>(find.byType(DetailPage)).id, 't1');
    expect(t.widget<DetailPage>(find.byType(DetailPage)).resource, 'tasks');
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
                body: SizedBox.expand(child: CalendarContent()),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cell = find.byKey(const ValueKey('month-day:2026-10-13'));
      expect(
        find.byKey(
          const ValueKey('month-span:tasks:t4:2026-09-28T00:00:00.000'),
        ),
        findsOneWidget,
        reason: 'cross-month task overlaps the visible October grid',
      );
      expect(
        find.byKey(
          const ValueKey('month-span:tasks:t5:2026-10-12T00:00:00.000'),
        ),
        findsNothing,
        reason: 'overflow records are represented by the day counter',
      );
      expect(
        find.byKey(const ValueKey('month-overflow:2026-10-13')),
        findsOneWidget,
      );
      expect(find.textContaining('+'), findsWidgets);
      final firstWeekSegment = find.byKey(
        const ValueKey('month-span:tasks:t6:2026-10-12T00:00:00.000'),
      );
      final nextWeekSegment = find.byKey(
        const ValueKey('month-span:tasks:t6:2026-10-19T00:00:00.000'),
      );
      expect(firstWeekSegment, findsOneWidget);
      expect(nextWeekSegment, findsOneWidget);
      expect(
        t.getTopLeft(firstWeekSegment).dy -
            t.getTopLeft(find.byKey(const ValueKey('month-day:2026-10-16'))).dy,
        t.getTopLeft(nextWeekSegment).dy -
            t.getTopLeft(find.byKey(const ValueKey('month-day:2026-10-19'))).dy,
        reason: 'continuation across weeks keeps one horizontal lane',
      );
      expect(
        find.descendant(of: firstWeekSegment, matching: find.text('数据结构实训')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nextWeekSegment, matching: find.text('数据结构实训')),
        findsOneWidget,
        reason: 'the next week repeats the task name at its continuation start',
      );
      final previewTitles = t.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('calendar-month-grid')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data?.startsWith('任务标题') == true,
          ),
        ),
      );
      expect(previewTitles, isNotEmpty);
      for (final title in previewTitles) {
        expect(title.style?.fontSize, inInclusiveRange(6, 10));
        expect(title.overflow, TextOverflow.ellipsis);
        expect(title.maxLines, 1);
        expect(title.data, isNot('任务标题'));
      }
      final segmentRect = t.getRect(firstWeekSegment);
      final startCell = t.getRect(
        find.byKey(const ValueKey('month-day:2026-10-16')),
      );
      final endCell = t.getRect(
        find.byKey(const ValueKey('month-day:2026-10-18')),
      );
      expect(segmentRect.left, startCell.left);
      expect(segmentRect.right, closeTo(endCell.right - 2, .01));
      expect(
        t.getRect(find.descendant(of: firstWeekSegment, matching: find.text('数据结构实训'))).right,
        closeTo(segmentRect.right - 10, .01),
      );
      final material = t.widget<Material>(
        find.descendant(of: firstWeekSegment, matching: find.byType(Material)),
      );
      expect(material.color, const Color(0xFFBE8A68));
      expect(
        find.descendant(of: cell, matching: find.text('13')),
        findsOneWidget,
      );
      await t.ensureVisible(cell);
      await t.tapAt(t.getTopLeft(cell) + const Offset(8, 8));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('5 条记录'), findsOneWidget);
      expect(find.text('任务标题5'), findsOneWidget);
      expect(find.text('日志标题'), findsNothing);
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
        expect(find.text('暂无记录，可选择其他日期'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
}
