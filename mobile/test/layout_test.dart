import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/providers.dart';
import 'package:pandora_mobile/data/models.dart';
import 'package:pandora_mobile/features/catalog.dart';

void main() {
  for (final config in [
    (const Size(360, 640), 1.0),
    (const Size(412, 915), 1.5),
    (const Size(800, 1000), 1.0),
  ]) {
    testWidgets('all routes fit ${config.$1} at scale ${config.$2}', (
      tester,
    ) async {
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const Session(role: UserRole.admin),
          ),
          fontScaleProvider.overrideWith((ref) => config.$2),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PandoraApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      final routes = [
        '/dashboard',
        '/profile',
        '/ai',
        '/logs',
        '/calendar',
        '/settings',
        '/admin',
        '/help',
        '/guide',
        '/analytics',
        '/privacy',
        '/licenses',
        '/history',
        '/conflict',
        '/report',
        '/ai-usage',
        '/export',
        '/pending',
        '/disabled',
        '/expired',
        for (final resource in resourceTitles.keys)
          '/list/${Uri.encodeComponent(resource)}',
        for (final resource in resourceTitles.keys)
          '/item/${Uri.encodeComponent(resource)}/1',
        '/item/organization/u2',
        '/form/ai-draft?source=1',
        '/form/focus-edit?id=1',
        for (final form in screens.keys) '/form/$form',
      ];
      for (final route in routes) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -1600));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$route scrolled');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
