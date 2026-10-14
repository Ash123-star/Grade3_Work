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
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/features/ai_map/ai_map_page.dart';

void main() {
  Future<ProviderContainer> launch(WidgetTester t, String route) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer();
    addTearDown(c.dispose);
    c.read(logDateProvider.notifier).state = DateTime(2025, 2, 3);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go(route);
    await t.pumpAndSettle();
    return c;
  }

  testWidgets(
    'diary save, invalid hours, offline retry and keyboard preserve dated content',
    (t) async {
      final c = await launch(t, '/form/log-edit');
      expect(find.byType(BottomActions), findsOneWidget);
      expect(t.getTopLeft(find.text('保存草稿')).dy, greaterThan(700));
      await t.enterText(find.byType(TextFormField).first, '核对移动端验收范围');
      await t.pump(const Duration(milliseconds: 700));
      await t.tap(find.text('保存草稿'));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final location = DraftLocation.diary('u1', DateTime(2025, 2, 3));
      final store = c.read(draftStoreProvider);
      expect(
        (await t.runAsync(() => store.read(location)))?.fields['今日工作'],
        '核对移动端验收范围',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is TuantuanMascot && w.pose == 'success',
        ),
        findsOneWidget,
      );
      expect(prefs.getString('draft:u1:2025-02-03:今日工作'), isNull);
      c.read(selectedDateProvider.notifier).state = DateTime(2027, 1, 1);
      c.read(logFilterDateProvider.notifier).state = DateTime(2024, 1, 1);
      await t.scrollUntilVisible(
        find.text('工时（选填）'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final hours = find.byType(TextFormField).last;
      await t.enterText(hours, 'NaN');
      await t.tap(find.text('提交日志'));
      await t.pumpAndSettle();
      expect(find.text('工时应在0到24之间'), findsOneWidget);
      await t.enterText(hours, '7.5');
      c.read(scenarioProvider.notifier).state = DemoScenario.offline;
      await t.tap(find.text('提交日志'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('提交失败，内容已保留'), findsOneWidget);
      expect(
        (await t.runAsync(() => store.read(location)))?.fields['今日工作'],
        '核对移动端验收范围',
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      expect(t.getBottomRight(find.text('重试提交')).dy, lessThan(544));
      t.view.resetViewInsets();
      c.read(scenarioProvider.notifier).state = DemoScenario.normal;
      await t.pumpAndSettle();
      await t.tap(find.text('重试提交'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final records = (await t.runAsync(
        () => c.read(repositoryProvider).list('logs', const Query()),
      ))!;
      expect(
        records.items
            .where((r) => r.fields['businessDate'] == '2025-02-03')
            .single
            .fields['今日工作'],
        '核对移动端验收范围',
      );
      expect(prefs.getString('draft:u1:2025-02-03:今日工作'), isNull);
      expect(await t.runAsync(() => store.read(location)), isNull);
    },
  );

  testWidgets(
    'review requires a rejection reason and does not show self decisions',
    (t) async {
      final c = await launch(t, '/me/reviews/1');
      expect(find.text('当前生效 · v1'), findsOneWidget);
      expect(find.text('候选版本 · v2 · 待审核'), findsOneWidget);
      expect(find.text('通过本级审核'), findsOneWidget);
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
      expect(find.text('通过本级审核'), findsNothing);
      expect(find.text('驳回'), findsNothing);
      expect(find.text('这是你发起的申请，不能审核自己的修改'), findsOneWidget);
    },
  );

  testWidgets(
    'stale diary editor requires explicit reload without losing its draft',
    (t) async {
      final c = await launch(t, '/dashboard');
      c.read(demoStoreProvider).records['logs'] = [
        const Record(
          id: 'stale',
          title: '最新日报',
          ownerId: 'u1',
          version: 2,
          fields: {
            'businessDate': '2025-02-03',
            '今日工作': '服务器最新内容',
            'status': '已提交',
          },
        ),
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('revision:u1:stale:1:今日工作', '旧版本的本机输入');
      c.read(routerProvider).go('/form/log-revise?id=stale&version=1');
      await t.pumpAndSettle();
      expect(find.textContaining('版本已更新'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '重试提交'))
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.text('重新读取最新版本'));
      await t.pumpAndSettle();
      await t.tap(find.text('重新读取最新版本'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '重新读取'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '服务器最新内容',
      );
      expect(prefs.getString('revision:u1:stale:1:今日工作'), '旧版本的本机输入');
      expect(find.textContaining('版本已更新'), findsNothing);
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
      await t.tap(find.byTooltip('更多操作'));
      await t.pumpAndSettle();
      expect(find.text('转派任务'), findsOneWidget);
      await t.tapAt(const Offset(10, 350));
      await t.pumpAndSettle();
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
    final c = await launch(t, '/ai');
    await t.tap(find.text('团队走向'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('加入行动规划'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入行动规划'));
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).length, 3);
    await t.ensureVisible(find.text('发展分析'));
    await t.pumpAndSettle();
    await t.tap(find.text('发展分析'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('加入行动规划'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入行动规划'));
    await t.pumpAndSettle();
    expect(c.read(aiActionDraftsProvider('u1')).length, 3);
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
