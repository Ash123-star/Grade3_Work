import 'support/local_test_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_page.dart';

void main() {
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [fontScaleProvider.overrideWith((ref) => scale)],
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
    'AI first screen prioritizes sources and account-scoped action drafts',
    (tester) async {
      final c = await launch(tester);
      expect(find.text('今天优先处理的三件事'), findsOneWidget);
      expect(find.textContaining('来源'), findsWidgets);
      expect(find.text('打开工作关系图'), findsOneWidget);
      await tester.ensureVisible(find.text('行动规划'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('行动规划'));
      await tester.pumpAndSettle();
      expect(find.text('个人行动草稿'), findsOneWidget);
      expect(find.text('编辑'), findsWidgets);
      final before = c.read(aiActionDraftsProvider('u1')).length;
      await tester.tap(find.text('编辑').first);
      await tester.pumpAndSettle();
      expect(find.text('保存草稿'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.read(aiActionDraftsProvider('u1')).length, before);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        role: UserRole.employee,
        dispatch: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('团队走向'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
  testWidgets('AI enlarged text and unavailable states stay explicit', (
    tester,
  ) async {
    final c = await launch(tester, scale: 1.5);
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    for (final scenario in [
      DemoScenario.empty,
      DemoScenario.offline,
      DemoScenario.forbidden,
    ]) {
      c.read(scenarioProvider.notifier).state = scenario;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('今天优先处理的三件事'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
