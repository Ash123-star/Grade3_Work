import 'support/workflow_fixture.dart';
import 'support/local_test_state.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_page.dart';

void main() {
  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    DateTime? logDate,
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [demoStoreProvider.overrideWithValue(workflowFixture())],
    );
    addTearDown(c.dispose);
    c.read(logDateProvider.notifier).state = logDate ?? DateTime(2025, 2, 3);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go(route);
    await t.pumpAndSettle();
    return c;
  }

  testWidgets(
    'diary composer autosaves one field and preserves it when submission fails',
    (t) async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final c = await launch(t, '/form/log-edit', logDate: day);
      expect(find.byType(BottomActions), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('工时'), findsNothing);
      await t.enterText(find.byType(TextField).first, '核对移动端验收范围');
      await t.pump(const Duration(milliseconds: 500));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final location = DraftLocation.diary('u1', day);
      final store = c.read(draftStoreProvider);
      expect(
        (await t.runAsync(() => store.read(location)))?.fields['今日工作'],
        '核对移动端验收范围',
      );
      c.read(scenarioProvider.notifier).state = DemoScenario.offline;
      await t.tap(find.text('提交'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        (await t.runAsync(() => store.read(location)))?.fields['今日工作'],
        '核对移动端验收范围',
      );
      c.read(scenarioProvider.notifier).state = DemoScenario.normal;
      await t.tap(find.text('提交'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final records = (await t.runAsync(
        () => c.read(repositoryProvider).list('logs', const Query()),
      ))!;
      expect(
        records.items
            .where((r) => r.fields['businessDate'] == day.toIso8601String().split('T').first)
            .single
            .fields['今日工作'],
        '核对移动端验收范围',
      );
      expect(await t.runAsync(() => store.read(location)), isNull);
    },
  );

  testWidgets(
    'review requires a rejection reason and does not show self decisions',
    (t) async {
      final c = await launch(t, '/me/reviews/1');
      expect(find.text('当前生效 · v1'), findsOneWidget);
      expect(find.text('候选版本 · v2'), findsOneWidget);
      expect(find.text('通过申请'), findsOneWidget);
      await t.tap(find.text('驳回'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '驳回申请'));
      await t.pumpAndSettle();
      expect(find.text('请填写驳回原因'), findsOneWidget);
      c.read(sessionProvider.notifier).state = const Session(
        id: 'u2',
        name: '陈一诺',
        role: UserRole.leader,
      );
      c.read(routerProvider).go('/me/reviews/1');
      await t.pumpAndSettle();
      expect(find.text('通过申请'), findsNothing);
      expect(find.text('驳回'), findsNothing);
      expect(find.text('这是你发起的申请，不能审核自己的修改'), findsOneWidget);
    },
  );

  testWidgets(
    'legacy revision link edits the submitted body directly without creating review',
    (t) async {
      final c = await launch(t, '/dashboard');
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      c.read(demoStoreProvider).records['logs'] = [
        Record(
          id: 'stale',
          title: '今日工作日志',
          ownerId: 'u1',
          version: 2,
          fields: {
            'businessDate': day.toIso8601String().split('T').first,
            '今日工作': '服务器最新内容',
            'status': '已提交',
            'submittedAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
          },
        ),
      ];
      c.read(logDateProvider.notifier).state = day;
      c.read(routerProvider).go('/form/log-revise?id=stale&version=2');
      await t.pumpAndSettle();
      await settleLocalIo(t);
      await t.enterText(find.byType(TextField).first, '直接修改后的工作');
      await t.tap(find.text('提交修改'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final updated = await t.runAsync(
        () => c.read(repositoryProvider).detail('logs', 'stale'),
      );
      expect(updated!.fields['今日工作'], '直接修改后的工作');
      expect(updated.version, 3);
      expect(
        c.read(demoStoreProvider).records['reviews']!.any(
          (review) => review.fields['targetId'] == 'stale',
        ),
        isFalse,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'task has one fixed primary action and more menu contains secondary actions',
    (t) async {
      final c = await launch(t, '/item/tasks/1');
      expect(find.text('接收任务'), findsOneWidget);
      expect(find.text('转派任务'), findsNothing);
      expect(find.byTooltip('更多操作'), findsNothing);
      await t.tap(find.text('接收任务'));
      await t.pumpAndSettle();
      expect(find.text('提交成果反馈'), findsOneWidget);
      final r = (await t.runAsync(
        () => c.read(repositoryProvider).detail('tasks', '1'),
      ))!;
      expect(r.fields['status'], '进行中');
    },
  );

  testWidgets('AI joins once then edits and completes account-scoped drafts', (
    t,
  ) async {
    final c = await launch(t, '/ai/directions');
    await t.ensureVisible(find.text('加入行动规划'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入行动规划'));
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).length, 2);
    await t.ensureVisible(find.text('发展分析'));
    await t.pumpAndSettle();
    await t.tap(find.text('发展分析'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('加入行动规划'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入行动规划'));
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).length, 2);
    await t.ensureVisible(find.text('编辑').first);
    await t.pumpAndSettle();
    await t.tap(find.text('编辑').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, '确认接口规则');
    await t.tap(find.text('保存草稿'));
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).first.title, '确认接口规则');
    await t.ensureVisible(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).first.done, true);
    c.read(sessionProvider.notifier).state = const Session(
      id: 'u2',
      role: UserRole.employee,
      dispatch: false,
    );
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u2')).length, 2);
    expect(c.read(aiActionDraftsProvider('u2')).first.title, isNot('确认接口规则'));
  });
}
