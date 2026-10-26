import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/dashboard/task_management_table.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

import 'support/local_test_state.dart';

void main() {
  final tasks = [
    const Record(
      id: 'task-a',
      title: '设计主页',
      fields: {
        'tagName': '研发',
        'participantNames': ['Alice'],
        'startAt': '2026-10-20T09:00:00+08:00',
        'deadline': '2026-10-24T18:00:00+08:00',
        'createdAt': '2026-10-19T10:00:00+08:00',
      },
    ),
    const Record(
      id: 'task-b',
      title: '交付日志',
      fields: {
        'tagName': '设计',
        'participantNames': ['Bob'],
        'startAt': '2026-10-21T09:00:00+08:00',
        'deadline': '2026-10-25T18:00:00+08:00',
        'createdAt': '2026-10-20T10:00:00+08:00',
      },
    ),
    const Record(
      id: 'task-c',
      title: '研发测试',
      fields: {
        'tagName': '研发',
        'participantNames': ['Bob'],
        'startAt': '2026-10-21T09:00:00+08:00',
        'deadline': '2026-10-26T18:00:00+08:00',
        'createdAt': '2026-10-20T11:00:00+08:00',
      },
    ),
  ];

  Future<({ProviderContainer container, GoRouter router})> mount(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith(
          (ref) => const Session(role: UserRole.employee, dispatch: false),
        ),
        recordsProvider.overrideWith(
          (ref, resource) async => PageResult(tasks, total: tasks.length),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/tasks',
      routes: [
        GoRoute(path: '/tasks', builder: (_, _) => const TaskManagementPage()),
      ],
    );
    addTearDown(() {
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: appTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (container: container, router: router);
  }

  testWidgets('field filter searches and selects candidate values', (
    tester,
  ) async {
    await mount(tester);

    await tester.tap(find.byKey(const ValueKey('task-filter-header:标签')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-filter-option:研发')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-filter-option:设计')), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '研');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-filter-option:研发')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-filter-option:设计')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-filter-option:研发')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('设计主页'), findsOneWidget);
    expect(find.text('研发测试'), findsOneWidget);
    expect(find.text('交付日志'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'candidate conditions combine across fields and cancel is inert',
    (tester) async {
      await mount(tester);

      await tester.tap(find.byKey(const ValueKey('task-filter-header:标签')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-filter-option:研发')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-filter-apply')));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('task-table-horizontal-scroll')),
        const Offset(-260, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-filter-header:参与人')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-filter-option:Alice')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-filter-apply')));
      await tester.pumpAndSettle();
      expect(find.text('设计主页'), findsOneWidget);
      expect(find.text('研发测试'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('task-filter-header:参与人')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-filter-option:Bob')));
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(find.text('设计主页'), findsOneWidget);
      expect(find.text('交付日志'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('date columns use a date picker instead of value candidates', (
    tester,
  ) async {
    await mount(tester);

    await tester.drag(
      find.byKey(const ValueKey('task-table-horizontal-scroll')),
      const Offset(-560, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-filter-header:截止时间')));
    await tester.pumpAndSettle();
    expect(find.text('选择截止时间日期'), findsNothing);
    expect(
      find.byKey(const ValueKey('task-date-filter-picker')),
      findsOneWidget,
    );
    expect(find.text('搜索候选值'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task-date-filter-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-date-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('交付日志'), findsOneWidget);
    expect(find.text('设计主页'), findsOneWidget);
    expect(find.text('研发测试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start date filter includes tasks starting on or after date', (
    tester,
  ) async {
    await mount(tester);

    await tester.drag(
      find.byKey(const ValueKey('task-table-horizontal-scroll')),
      const Offset(-560, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-filter-header:开始时间')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-date-filter-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21').last);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-date-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('设计主页'), findsNothing);
    expect(find.text('交付日志'), findsOneWidget);
    expect(find.text('研发测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
