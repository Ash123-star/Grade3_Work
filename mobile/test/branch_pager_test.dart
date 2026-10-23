import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/routing/branch_pager.dart';

void main() {
  testWidgets(
    'logs drags translate adjacent branches and never open subordinates',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/logs',
        routes: [
          GoRoute(
            path: '/logs/subordinates',
            builder: (_, _) => const Scaffold(body: Text('subordinates')),
          ),
          StatefulShellRoute(
            navigatorContainerBuilder: (_, shell, children) =>
                BranchPager(shell: shell, children: children),
            builder: (context, state, shell) => Scaffold(
              body: shell,
              bottomNavigationBar: NavigationBar(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: shell.goBranch,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home),
                    label: 'dashboard',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month),
                    label: 'view',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.article),
                    label: 'logs',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome),
                    label: 'ai',
                  ),
                  NavigationDestination(icon: Icon(Icons.person), label: 'me'),
                ],
              ),
            ),
            branches: [
              for (final name in ['dashboard', 'view', 'logs', 'ai', 'me'])
                StatefulShellBranch(
                  preload: true,
                  routes: [
                    GoRoute(
                      path: '/$name',
                      builder: (context, _) => Scaffold(
                        body: Center(
                          child: name == 'logs'
                              ? TextButton(
                                  onPressed: () =>
                                      context.push('/logs/subordinates'),
                                  child: const Text('logs content'),
                                )
                              : Text('$name content'),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(const Offset(600, 250));
      await drag.moveBy(const Offset(-100, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-350, 0));
      await tester.pump();
      expect(tester.getCenter(find.text('logs content')).dx, lessThan(400));
      expect(find.text('ai content'), findsOneWidget);
      await drag.up();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/ai');
      expect(find.text('subordinates'), findsNothing);
      await tester.dragFrom(const Offset(200, 250), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/logs');
      await tester.dragFrom(const Offset(200, 250), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/view');
      await tester.tap(find.text('me').last);
      await tester.pump(const Duration(milliseconds: 80));
      final pager = tester.widget<PageView>(
        find.byKey(const ValueKey('bottom-branch-pager')),
      );
      expect(pager.controller!.page, greaterThan(1));
      expect(pager.controller!.page, lessThan(4));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/me');
      expect(pager.controller!.page, closeTo(4, .001));
      expect(tester.takeException(), isNull);
    },
  );
}
