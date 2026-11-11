import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/dashboard/task_management_table.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

import 'support/local_test_state.dart';

Future<ProviderContainer> _mount(
  WidgetTester tester,
  List<Record> tasks, {
  bool largeText = false,
}) async {
  tester.view.physicalSize = Size(largeText ? 360 : 1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = testContainer(
    overrides: [
      sessionProvider.overrideWith(
        (_) => const Session(role: UserRole.employee, dispatch: false),
      ),
      recordsProvider.overrideWith(
        (_, _) async => PageResult(tasks, total: tasks.length),
      ),
    ],
  );
  await tester.pumpWidget(
    OwnedTestProviderScope(
      container: container,
      child: MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(largeText ? 1.5 : 1)),
          child: child!,
        ),
        home: const TaskManagementPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'completion precedes start, uses real dispatch instant and refreshes',
    (tester) async {
      Record task(String phase) => Record(
        id: 'task',
        title: '验收任务',
        fields: {
          'phase': phase,
          'status': '已验收',
          'startAt': '2026-11-05T01:00:00Z',
          'deadline': '2026-11-06T10:00:00Z',
          'createdAt': '2026-11-01T01:00:00Z',
          'dispatchAt': '2026-11-04T02:00:00Z',
        },
      );
      final tasks = [task('FEEDBACK')];
      final container = await _mount(tester, tasks);
      expect(find.text('任务管理'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('完成情况')).dx,
        lessThan(tester.getTopLeft(find.text('开始时间')).dx),
      );
      expect(find.text('待验收'), findsOneWidget);
      expect(find.text('已验收'), findsNothing);
      expect(find.text('2026-11-04 10:00'), findsOneWidget);
      expect(find.text('2026-11-01 09:00'), findsNothing);

      tasks[0] = task('RECEIVED');
      container.invalidate(recordsProvider('tasks'));
      await tester.pumpAndSettle();
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('待验收'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing dispatch date remains empty, not a creation date', (
    tester,
  ) async {
    await _mount(tester, const [
      Record(
        id: 'task',
        title: '未知阶段任务',
        fields: {
          'phase': 'FUTURE_PHASE',
          'status': '已验收',
          'createdAt': '2026-11-01T01:00:00Z',
        },
      ),
    ]);
    expect(find.text('情况未知'), findsOneWidget);
    expect(find.text('已验收'), findsNothing);
    expect(find.text('2026-11-01 09:00'), findsNothing);
    final dispatchCell = find.byKey(const ValueKey('task-cell:task:派发时间'));
    expect(
      find.descendant(of: dispatchCell, matching: find.text('—')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '360dp at 1.5 text scale keeps complete people and labels expandable',
    (tester) async {
      const names = ['张小明一号', '张小明二号', '张小明三号', '张小明四号'];
      const labels = ['非常长的客户需求标签', '研发质量', '交付保障', '沟通记录'];
      await _mount(tester, [
        Record(
          id: 'task',
          title: '这是一个非常长的任务名称用于移动端展示验收',
          fields: {
            'phase': 'DISPATCHED',
            'participantNames': names,
            'labels': [
              for (var i = 0; i < labels.length; i++)
                {
                  'id': 'l$i',
                  'name': labels[i],
                  'color': i == 0 ? '#FF0000' : '#00FF00',
                },
            ],
          },
        ),
      ], largeText: true);
      expect(tester.takeException(), isNull);
      expect(find.text(labels[2]), findsNothing);
      expect(find.byKey(const ValueKey('task-expand:task:标签')), findsOneWidget);
      final badges = tester
          .widgetList<AppLabelBadge>(find.byType(AppLabelBadge))
          .toList();
      expect(badges.take(2).map((badge) => badge.color), [
        const Color(0xFFFF0000),
        const Color(0xFF00FF00),
      ]);
      final peopleBadges = badges.where((badge) => names.contains(badge.label));
      expect(peopleBadges.map((badge) => badge.label), names.take(2));
      expect(
        peopleBadges.every((badge) => badge.color == const Color(0xFFF5EDDA)),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('task-expand:task:标签')));
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(find.widgetWithText(SelectableText, label), findsOneWidget);
      }
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      expect(find.text(labels[2]), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('task-table-horizontal-scroll')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('task-expand:task:参与人')));
      await tester.pumpAndSettle();
      for (final name in names) {
        expect(find.widgetWithText(SelectableText, name), findsOneWidget);
      }
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
