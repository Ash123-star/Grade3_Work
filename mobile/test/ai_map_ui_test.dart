import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/providers.dart';
import 'package:pandora_mobile/data/models.dart';
import 'package:pandora_mobile/data/mock_repository.dart';
import 'package:pandora_mobile/features/ai_map_page.dart';

void main() {
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [fontScaleProvider.overrideWith((ref) => scale)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PandoraApp(),
      ),
    );
    container.read(routerProvider).go('/ai');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'development and risk actions join editable account-scoped drafts',
    (tester) async {
      final container = await launch(tester);
      expect(find.text('日'), findsNothing);
      expect(find.text('周'), findsNothing);
      expect(find.text('月'), findsNothing);
      await tester.tap(find.text('公司走向'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('加入行动规划').hitTestable(), 250);
      await tester.tap(find.text('加入行动规划'));
      await tester.pumpAndSettle();
      expect(container.read(aiActionDraftsProvider('u1')).length, 3);
      await tester.tap(find.text('发展分析'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('加入行动规划').hitTestable(), 250);
      await tester.tap(find.text('加入行动规划'));
      await tester.pumpAndSettle();
      expect(container.read(aiActionDraftsProvider('u1')).length, 3);
      await tester.scrollUntilVisible(find.text('编辑').first, 250);
      await tester.tap(find.text('编辑').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '确认接口规则');
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(
        container.read(aiActionDraftsProvider('u1')).first.title,
        '确认接口规则',
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 240));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(container.read(aiActionDraftsProvider('u1')).first.done, isTrue);
      container.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        role: UserRole.employee,
        dispatch: false,
      );
      await tester.pumpAndSettle();
      expect(container.read(aiActionDraftsProvider('u2')).length, 2);
      await tester.tap(find.text('发展分析'));
      await tester.pumpAndSettle();
      expect(find.text('公司走向'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all AI sections fit enlarged text and handle missing data', (
    tester,
  ) async {
    final container = await launch(tester, scale: 1.5);
    for (final title in ['发展分析', '堵点风险', '行动规划']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: title);
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$title scrolling');
      }
    }
    for (final scenario in [
      DemoScenario.empty,
      DemoScenario.offline,
      DemoScenario.forbidden,
    ]) {
      container.read(scenarioProvider.notifier).state = scenario;
      await tester.tap(find.text('发展分析'));
      await tester.pumpAndSettle();
      expect(find.text('从执行任务，走向独立推进'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
