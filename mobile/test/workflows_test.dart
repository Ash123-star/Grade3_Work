import 'support/local_test_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/common/form_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

void main() {
  test('Shanghai week range begins Monday and survives year boundary', () {
    final range = BusinessRange(DateTime(2027, 1, 1), '周');
    expect(range.from, DateTime.utc(2026, 12, 27, 16));
    expect(range.to.difference(range.from).inDays, 7);
  });
  test(
    'employee cannot bypass dispatch guard or request subordinate logs',
    () async {
      final repo = MockRepository(
        const Session(role: UserRole.employee, dispatch: false),
      );
      await expectLater(
        repo.execute('tasks', const Command('create', {})),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        repo.list('logs/subordinates', const Query()),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('self review fails and outdated versions are rejected', () async {
    final repo = MockRepository(
      const Session(),
      store: DemoStore()
        ..records['reviews'] = [
          const Record(
            id: '1',
            title: '他人申请',
            ownerId: 'u2',
            fields: {
              'reviewState': '待审',
              'step': 0,
              'approvalMode': 'DIRECT_MANAGER',
              'reviewerId': 'u1',
            },
          ),
          const Record(
            id: '2',
            title: '本人申请',
            ownerId: 'u1',
            fields: {'reviewState': '待审', 'step': 0},
          ),
        ],
    );
    await expectLater(
      repo.execute(
        'reviews',
        const Command('approve', {'id': '2'}, version: 1),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      repo.execute(
        'reviews',
        const Command('approve', {'id': '1'}, version: 0),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await repo.execute(
      'reviews',
      const Command('approve', {'id': '1'}, version: 1),
    );
    await expectLater(
      repo.execute(
        'reviews',
        const Command('approve', {'id': '1'}, version: 1),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('idempotency does not create duplicate tasks', () async {
    final repo = MockRepository(const Session());
    const command = Command('create', {
      'title': '验证任务',
    }, idempotencyKey: 'stable-key');
    final a = await repo.execute('tasks', command),
        b = await repo.execute('tasks', command);
    expect(a.id, b.id);
    expect(
      (await repo.list('tasks', const Query(search: '验证任务'))).items.length,
      1,
    );
  });
  test('HTTP forbidden response is a typed failure', () {
    final request = RequestOptions(path: '/tasks');
    final failure = ApiFailure.fromDio(
      DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 403),
      ),
    );
    expect(failure.kind, FailureKind.forbidden);
  });
  testWidgets('five destinations default to dashboard, no employee dispatch', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...localTestOverrides(),
          sessionProvider.overrideWith(
            (ref) => const Session(role: UserRole.employee, dispatch: false),
          ),
        ],
        child: const PandoraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '导图'), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.byTooltip('派发任务'), findsNothing);
    await tester.tap(find.text('日志').last);
    await tester.pumpAndSettle();
    expect(find.text('下属日志'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dispatch fields validate without a completion field', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: appTheme(), home: const FormPage('dispatch')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('完成情况'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '派发任务'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '派发任务'));
    await tester.pumpAndSettle();
    expect(find.text('至少选择一名参与人'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
