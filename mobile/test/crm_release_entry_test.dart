import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/crm/crm_demo_store.dart';
import 'package:pandora_mobile/routing/app_router.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

void main() {
  testWidgets('正式构建注册客户目录，遵守登录和待确认限制，不解析本地客户数据', (tester) async {
    final container = ProviderContainer(
      overrides: [
        crmDemoProvider.overrideWith((ref) => throw StateError('正式入口不可加载本地数据')),
      ],
    );
    addTearDown(container.dispose);
    final session = container.read(sessionProvider.notifier);
    final router = container.read(routerProvider);
    void routeToDirectory(Session identity) {
      session.state = identity;
      router.go('/crm/customers');
    }

    routeToDirectory(const Session(active: false));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: appTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/auth/login');
    routeToDirectory(
      const Session(active: false, status: 'PENDING', token: 'fixture-token'),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/auth/pending');
    routeToDirectory(const Session(token: 'fixture-token'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/crm/customers');
    expect(find.text('客户目录暂不可用'), findsOneWidget);
    expect(find.text('＋ 新增客户'), findsNothing);
    expect(find.text('林小满'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.mock);
}
