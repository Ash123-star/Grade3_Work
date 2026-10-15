import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/providers.dart';
import 'package:pandora_mobile/data/mock_repository.dart';

void main() {
  testWidgets(
    'single development map removes old actions and never invents demo conclusions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [fontScaleProvider.overrideWith((ref) => 1.5)],
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
      expect(find.text('成长与发展地图'), findsOneWidget);
      expect(find.text('堵点风险'), findsNothing);
      expect(find.text('行动规划'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('从执行任务，走向独立推进'), findsNothing);
      for (final scenario in [
        DemoScenario.empty,
        DemoScenario.offline,
        DemoScenario.forbidden,
      ]) {
        container.read(scenarioProvider.notifier).state = scenario;
        await tester.pumpAndSettle();
        expect(find.text('成长与发展地图'), findsOneWidget);
        expect(find.text('加入行动规划'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 250));
    },
  );
}
