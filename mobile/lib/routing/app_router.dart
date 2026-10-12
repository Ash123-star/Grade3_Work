import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/features/dashboard/dashboard_pages.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/features/settings/utility_pages.dart';
import 'package:pandora_mobile/features/common/catalog.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final active = ref.read(sessionProvider).active;
      if (!active &&
          ![
            '/auth/login',
            '/auth/register',
            '/auth/pending',
            '/auth/password',
            '/auth/expired',
            '/auth/disabled',
          ].contains(state.uri.path)) {
        return '/auth/login';
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
                path: '/view',
                builder: (_, _) => const CalendarPage(),
                routes: [
                  GoRoute(path: 'day', builder: (_, _) => const CalendarPage()),
                  GoRoute(path: 'week', builder: (_, _) => const CalendarPage()),
                  GoRoute(path: 'month', builder: (_, _) => const CalendarPage()),
                ],
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
              GoRoute(
                path: '/me',
                builder: (_, _) => const ProfilePage(),
                routes: [
                  GoRoute(
                    path: 'team',
                    builder: (_, _) => const ListPage('organization'),
                    routes: [
                      GoRoute(
                        path: ':memberId',
                        builder: (_, state) => DetailPage(
                          'organization',
                          state.pathParameters['memberId']!,
                          key: ValueKey(state.uri.toString()),
                        ),
                        routes: [
                          for (final category in [
                            'overview',
                            'profile',
                            'focus',
                            'logs',
                            'tasks',
                            'ai',
                          ])
                            GoRoute(
                              path: category,
                              builder: (_, state) => DetailPage(
                                'organization',
                                state.pathParameters['memberId']!,
                                key: ValueKey(state.uri.toString()),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
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
      GoRoute(path: '/auth/login', builder: (_, _) => const FormPage('login')),
      GoRoute(path: '/auth/register', builder: (_, _) => const FormPage('register')),
      GoRoute(path: '/auth/password', builder: (_, _) => const FormPage('password')),
      GoRoute(path: '/me/help', builder: (_, _) => const HelpPage()),
      GoRoute(path: '/guide', builder: (_, _) => const GuidePage()),
      GoRoute(path: '/me/statistics', builder: (_, _) => const AnalyticsPage()),
      GoRoute(path: '/me/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/auth/pending', builder: (_, _) => const UtilityPage('pending')),
      GoRoute(path: '/auth/disabled', builder: (_, _) => const UtilityPage('disabled')),
      GoRoute(path: '/auth/expired', builder: (_, _) => const UtilityPage('expired')),
      for (final path in [
        'privacy',
        'licenses',
        'history',
        'conflict',
        'report',
        'ai-usage',
        'export',
      ])
        GoRoute(path: '/$path', builder: (_, _) => UtilityPage(path)),
      GoRoute(path: '/me/admin', builder: (_, _) => const UtilityPage('admin')),
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
    theme: appTheme(),
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
