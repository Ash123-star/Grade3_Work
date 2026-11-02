import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/dashboard/task_management_table.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'support/local_test_state.dart';

void main() {
  testWidgets('profile has no task entry and view opens the task table', (
    tester,
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
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PandoraApp(),
      ),
    );
    container.read(routerProvider).go('/me');
    await settleLocalIo(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ProtectedAvatar), findsOneWidget);
    expect(find.text('任务管理'), findsNothing);
    container.read(routerProvider).go('/view');
    await settleLocalIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('任务管理'), findsOneWidget);
    await tester.tap(find.text('任务管理'));
    await settleLocalIo(tester);
    expect(find.byType(TaskManagementPage), findsOneWidget);
    expect(find.text('任务名称'), findsOneWidget);
    expect(find.text('搜索任务名称、标签、参与人或日期'), findsOneWidget);
    expect(find.byTooltip('新增任务'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
