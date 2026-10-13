import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/features/dashboard/dashboard_pages.dart';
import 'package:pandora_mobile/features/common/detail_pages.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/features/settings/utility_pages.dart';
import 'package:pandora_mobile/features/settings/diary_sync_page.dart';
import 'package:pandora_mobile/features/common/catalog.dart';
import 'package:pandora_mobile/features/common/demo_pages.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/features/dashboard/member_workspace.dart';
import 'package:pandora_mobile/features/dashboard/organization_browser.dart';
import 'package:pandora_mobile/features/dashboard/own_profile_page.dart';
import 'package:pandora_mobile/core/state/session_lifecycle.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/features/dashboard/management_page.dart';
import 'package:pandora_mobile/features/dashboard/server_analytics_page.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/features/ai_map/ai_job_pages.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_tools.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      final public = [
        '/auth/login',
        '/auth/register',
        '/auth/pending',
        '/auth/disabled',
        '/auth/expired',
      ].contains(path);
      if (session.expired && !public) return '/auth/expired';
      if (session.status == 'DISABLED' &&
          path != '/auth/disabled' &&
          path != '/auth/login') {
        return '/auth/disabled';
      }
      if (!session.authenticated) return public ? null : '/auth/login';
      if (session.mustChangePassword) {
        return path == '/auth/password' ? null : '/auth/password';
      }
      if (!session.canReadBusiness) {
        return [
              '/auth/pending',
              '/auth/password',
              '/form/password',
            ].contains(path)
            ? null
            : '/auth/pending';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/logs/subordinates',
        builder: (_, _) => const LogsPage(subordinates: true),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: NavigationBar(
              animationDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) => shell.goBranch(i),
              destinations: const [
                NavigationDestination(
                  icon: AppArtworkIcon('squares-four'),
                  selectedIcon: AppArtworkIcon('squares-four', filled: true),
                  label: '导图',
                ),
                NavigationDestination(
                  icon: AppArtworkIcon('calendar-dots'),
                  selectedIcon: AppArtworkIcon('calendar-dots', filled: true),
                  label: '视图',
                ),
                NavigationDestination(
                  icon: AppArtworkIcon('notebook'),
                  selectedIcon: AppArtworkIcon('notebook', filled: true),
                  label: '日志',
                ),
                NavigationDestination(
                  icon: AppArtworkIcon('graph'),
                  selectedIcon: AppArtworkIcon('graph', filled: true),
                  label: 'AI地图',
                ),
                NavigationDestination(
                  icon: AppArtworkIcon('user-circle'),
                  selectedIcon: AppArtworkIcon('user-circle', filled: true),
                  label: '我的',
                ),
              ],
            ),
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
                  GoRoute(
                    path: 'day',
                    builder: (_, _) => const CalendarPage(initialPeriod: '日'),
                  ),
                  GoRoute(
                    path: 'week',
                    builder: (_, _) => const CalendarPage(initialPeriod: '周'),
                  ),
                  GoRoute(
                    path: 'month',
                    builder: (_, _) => const CalendarPage(initialPeriod: '月'),
                  ),
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
              GoRoute(path: '/me', builder: (_, _) => const ProfilePage()),
            ],
          ),
        ],
      ),
      GoRoute(path: '/me/profile', builder: (_, _) => const OwnProfilePage()),
      GoRoute(
        path: '/attachments/:id',
        builder: (_, s) => AttachmentDownloadPage(
          s.pathParameters['id']!,
          key: ValueKey('${s.uri}:${ref.read(sessionProvider).id}'),
        ),
      ),
      GoRoute(
        path: '/history/:id/version/:version',
        builder: (_, s) => DiaryVersionPage(
          logId: s.pathParameters['id']!,
          version: int.tryParse(s.pathParameters['version']!) ?? -1,
        ),
      ),
      GoRoute(
        path: '/me/organization',
        builder: (_, _) => const OrganizationBrowser(),
      ),
      GoRoute(
        path: '/me/team',
        builder: (_, _) => const ListPage('organization'),
      ),
      GoRoute(
        path: '/me/team/:memberId',
        builder: (_, s) => MemberWorkspace(
          s.pathParameters['memberId']!,
          businessDate: s.uri.queryParameters['date'],
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/me/team/:memberId/:category',
        builder: (_, s) => MemberWorkspace(
          s.pathParameters['memberId']!,
          category: s.pathParameters['category']!,
          businessDate: s.uri.queryParameters['date'],
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/me/reviews',
        builder: (_, _) => const ListPage('reviews'),
      ),
      GoRoute(
        path: '/me/reviews/:id',
        builder: (_, s) => DetailPage(
          'reviews',
          s.pathParameters['id']!,
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/ai/graph',
        builder: (_, _) => AppConfig.mock
            ? const PageFrame(
                title: '工作关系图',
                child: PageBody(children: [AiGraph()]),
              )
            : const ServerAiGraphPage(),
      ),
      GoRoute(path: '/ai/usage', builder: (_, _) => const ServerAiUsagePage()),
      GoRoute(
        path: '/ai/jobs/:id/edit',
        builder: (_, s) => AiJobPage(
          s.pathParameters['id']!,
          edit: true,
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/ai/jobs/:id/actions/:index',
        builder: (_, s) => AiJobPage(
          s.pathParameters['id']!,
          actionIndex: int.tryParse(s.pathParameters['index']!),
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/ai/jobs/:id/confirm/:index',
        builder: (_, s) => AiConfirmPage(
          s.pathParameters['id']!,
          int.tryParse(s.pathParameters['index']!) ?? -1,
          key: ValueKey(s.uri.toString()),
        ),
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
          ownerId: s.uri.queryParameters['ownerId'],
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/form/:kind',
        builder: (_, s) => managementKinds.contains(s.pathParameters['kind'])
            ? ManagementPage(
                s.pathParameters['kind']!,
                memberId: s.uri.queryParameters['id'],
                key: ValueKey('${s.uri}:${ref.read(sessionProvider).id}'),
              )
            : screens.containsKey(s.pathParameters['kind'])
            ? FormPage(
                s.pathParameters['kind']!,
                key: ValueKey(s.uri.toString()),
                id: s.uri.queryParameters['id'],
                source: s.uri.queryParameters['source'],
                version:
                    int.tryParse(s.uri.queryParameters['version'] ?? '') ?? 1,
                restoreDiaryDraft:
                    s.uri.queryParameters['draftSource'] == 'diary',
              )
            : const UtilityPage('not-found'),
      ),
      GoRoute(path: '/auth/login', builder: (_, _) => const FormPage('login')),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const FormPage('register'),
      ),
      GoRoute(
        path: '/auth/password',
        builder: (_, _) => const FormPage('password'),
      ),
      GoRoute(path: '/me/help', builder: (_, _) => const HelpPage()),
      GoRoute(path: '/guide', builder: (_, _) => const GuidePage()),
      GoRoute(
        path: '/me/statistics',
        builder: (_, _) => AppConfig.mock
            ? const AnalyticsPage()
            : const ServerAnalyticsPage(),
      ),
      GoRoute(path: '/export', builder: (_, _) => const AnalyticsExportPage()),
      GoRoute(path: '/me/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/conflict',
        builder: (_, s) => DiarySyncPage(
          date: s.uri.queryParameters['date'],
          id: s.uri.queryParameters['id'],
          version: s.uri.queryParameters['version'],
          key: ValueKey(s.uri.toString()),
        ),
      ),
      GoRoute(
        path: '/auth/pending',
        builder: (_, _) => const UtilityPage('pending'),
      ),
      GoRoute(
        path: '/auth/disabled',
        builder: (_, _) => const UtilityPage('disabled'),
      ),
      GoRoute(
        path: '/auth/expired',
        builder: (_, _) => const UtilityPage('expired'),
      ),
      for (final path in [
        'privacy',
        'licenses',
        'history',
        'report',
        'ai-usage',
      ])
        GoRoute(
          path: '/$path',
          builder: (_, _) => path == 'ai-usage' && !AppConfig.mock
              ? const ServerAiUsagePage()
              : UtilityPage(path),
        ),
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
      child: SessionLifecycle(child: child!),
    ),
  );
}
