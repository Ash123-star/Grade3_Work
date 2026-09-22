import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import 'core/providers.dart';
import 'features/home_pages.dart';
import 'features/detail_pages.dart';
import 'features/form_page.dart';
import 'features/utility_pages.dart';
import 'features/catalog.dart';
import 'features/demo_pages.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final active = ref.read(sessionProvider).active;
      if (!active &&
          ![
            '/form/login',
            '/form/register',
            '/pending',
            '/expired',
            '/disabled',
          ].contains(state.uri.path)) {
        return '/form/login';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: '导图',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: '视图',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_note_outlined),
                selectedIcon: Icon(Icons.edit_note),
                label: '日志',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: 'AI地图',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, _) => const CalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/logs', builder: (_, _) => const LogsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/ai', builder: (_, _) => const AiPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/list/:resource',
        builder: (_, s) => ListPage(
          s.pathParameters['resource']!,
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/item/:resource/:id',
        builder: (_, s) => DetailPage(
          s.pathParameters['resource']!,
          s.pathParameters['id']!,
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/form/:kind',
        builder: (_, s) => screens.containsKey(s.pathParameters['kind'])
            ? FormPage(
                s.pathParameters['kind']!,
                key: ValueKey(s.uri.toString()),
                id: s.uri.queryParameters['id'],
                source: s.uri.queryParameters['source'],
                version:
                    int.tryParse(s.uri.queryParameters['version'] ?? '') ?? 1,
              )
            : const UtilityPage('not-found'),
      ),
      GoRoute(path: '/help', builder: (_, _) => const HelpPage()),
      GoRoute(path: '/guide', builder: (_, _) => const GuidePage()),
      GoRoute(path: '/analytics', builder: (_, _) => const AnalyticsPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      for (final path in [
        'pending',
        'disabled',
        'expired',
        'privacy',
        'licenses',
        'history',
        'conflict',
        'report',
        'ai-usage',
        'export',
        'admin',
      ])
        GoRoute(path: '/$path', builder: (_, _) => UtilityPage(path)),
    ],
    errorBuilder: (_, _) => const UtilityPage('not-found'),
  );
  ref.listen(sessionProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

class PandoraApp extends ConsumerWidget {
  const PandoraApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: '潘多拉工作台',
    debugShowCheckedModeBanner: false,
    theme: cuteTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(routerProvider),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(ref.watch(fontScaleProvider))),
      child: child!,
    ),
  );
}
