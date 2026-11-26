import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/features/crm/crm_demo_store.dart';
import 'package:pandora_mobile/features/crm/crm_workspace.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

Future<void> tap(WidgetTester t, String text) async {
  final target = find.text(text).hitTestable().last;
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> show(
  WidgetTester t,
  CrmDemoStore store, {
  double width = 390,
  double height = 844,
  double scale = 1,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, height);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    ProviderScope(
      overrides: [crmDemoProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: appTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const CrmWorkspacePage(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('公司双按钮排和顶部今天沿真实入口返回保留日期与视图', (t) async {
    final container = ProviderContainer();
    final date = container.read(selectedDateProvider.notifier);
    final period = container.read(periodProvider.notifier);
    date.state = DateTime(2026, 10, 11);
    period.state = '月';
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SafeArea(
              child: DateControls(
                showTaskManagement: true,
                showCustomerDirectory: true,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/crm/customers',
          builder: (_, _) => const CrmWorkspacePage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: appTheme(), routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.getCenter(find.text('客户目录')).dy,
      t.getCenter(find.text('派发任务')).dy,
    );
    expect(
      t.getCenter(find.text('今天')).dy,
      lessThan(t.getCenter(find.text('客户目录')).dy),
    );
    await tap(t, '周');
    await tap(t, '客户目录');
    expect(find.text('客户手帐'), findsOneWidget);
    await tap(t, '‹');
    expect(date.state, DateTime(2026, 10, 11));
    expect(period.state, '周');
    await tap(t, '今天');
    expect(date.state, shanghaiToday());
    expect(period.state, '周');
  });

  test('临时样例在账号切换时隔离且旧实例拒绝写入', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final old = container.read(crmDemoProvider);
    final (status, customer) = old.save(
      type: '个人',
      name: '隔离测试客户',
      owner: '陈晨',
      phone: '',
      note: '',
      contactName: '',
      since: '2026.11.26',
    );
    expect(status, CrmSaveResult.success);
    container.read(sessionProvider.notifier).state = const Session(
      id: 'another',
      companyId: 'another-company',
    );
    final current = container.read(crmDemoProvider);
    expect(current.customers.any((c) => c.name == '隔离测试客户'), isFalse);
    expect(
      old
          .save(
            customer: customer,
            version: customer!.version,
            type: '个人',
            name: '越界编辑',
            owner: '陈晨',
            phone: '',
            note: '',
            contactName: '',
            since: '2026.11.26',
          )
          .$1,
      CrmSaveResult.denied,
    );
  });

  testWidgets('客户目录搜索、翻页与详情返回保留状态', (t) async {
    await show(t, CrmDemoStore());
    expect(find.text('1 / 2'), findsOneWidget);
    await tap(t, '下一页 ›');
    await tap(t, '沈予安');
    await tap(t, '‹');
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('沈予安'), findsOneWidget);
    await t.enterText(find.byType(TextField), '林小满');
    await tap(t, '搜索');
    expect(find.text('1 / 1'), findsOneWidget);
    await tap(t, '林小满');
    await tap(t, '会员');
    expect(find.text('‹ 返回客户目录'), findsNothing);
    expect(find.bySemanticsLabel('返回客户目录'), findsOneWidget);
    expect(t.getRect(find.text('会员')).bottom, greaterThan(800));
    await tap(t, '演出年卡');
    expect(find.text('余 2 次'), findsOneWidget);
    await tap(t, '权益使用记录 · 4 条');
    expect(find.text('秋日音乐现场 · 入场核销 1 次'), findsOneWidget);
    await tap(t, '业务');
    await tap(t, '订单');
    await tap(t, '下一页 ›');
    await tap(t, '夏日会员礼包');
    expect(find.text('原实付金额'), findsOneWidget);
    await tap(t, '‹ 返回客户详情');
    expect(find.text('2 / 2'), findsOneWidget);
    await tap(t, '‹');
    expect(t.widget<TextField>(find.byType(TextField)).controller?.text, '林小满');
  });

  testWidgets('新增校验、重复核对、保存重试及遗留草稿保护', (t) async {
    final store = CrmDemoStore();
    await show(t, store);
    await tap(t, '＋ 新增客户');
    await tap(t, '保存客户');
    expect(find.text('请输入客户姓名'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '林小满');
    await tap(t, '保存客户');
    expect(find.text('先核对，避免重复建档'), findsOneWidget);
    await tap(t, '林小满');
    expect(find.text('已有客户 · 核对资料'), findsOneWidget);
    await tap(t, '返回核对选择');
    await tap(t, '返回修改');
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller?.text,
      '林小满',
    );
    await t.enterText(find.byType(TextField).first, '示例新客户');
    await tap(t, '取消');
    await tap(t, '继续编辑');
    store.nextSave = CrmSaveResult.failed;
    await tap(t, '保存客户');
    expect(find.textContaining('填写内容已保留'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller?.text,
      '示例新客户',
    );
    await tap(t, '保存客户');
    expect(find.text('客户详情'), findsOneWidget);
    expect(store.customers.first.name, '示例新客户');
    await tap(t, '编辑资料');
    await t.enterText(find.byType(TextField).first, '冲突资料');
    store.nextSave = CrmSaveResult.conflict;
    await tap(t, '保存修改');
    expect(find.textContaining('资料已有更新'), findsOneWidget);
    await tap(t, '重新载入资料');
    await tap(t, '放弃修改');
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller?.text,
      '示例新客户',
    );
    await t.enterText(find.byType(TextField).first, '确认后的客户');
    await tap(t, '保存修改');
    expect(store.customers.first.name, '确认后的客户');
    expect(t.takeException(), isNull);
  });

  testWidgets('企业联系人从档案弹层保存且不替换脱敏电话', (t) async {
    final store = CrmDemoStore();
    await show(t, store);
    await tap(t, '禾屿设计工作室');
    await tap(t, '＋ 添加');
    await tap(t, '保存联系人');
    expect(find.text('请输入联系人姓名'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '样例联系人');
    await tap(t, '取消');
    await tap(t, '继续编辑');
    await tap(t, '保存联系人');
    expect(store.customers[1].contacts.last.name, '样例联系人');
    final edit = find.bySemanticsLabel('编辑联系人顾言').hitTestable().first;
    await t.tap(edit);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField).last).controller?.text,
      '',
    );
    await t.enterText(find.byType(TextField).at(1), '资料对接');
    await tap(t, '保存联系人');
    expect(store.customers[1].contacts.first.phone, '021 **** 0620');
    expect(store.customers[1].contacts.first.role, '资料对接');
  });

  testWidgets('仅查看、受限字段、错误重试和失权不显示样例', (t) async {
    final store = CrmDemoStore(
      canManage: false,
      contactAllowed: false,
      amountAllowed: false,
      readState: CrmReadState.failed,
    );
    await show(t, store);
    expect(find.text('林小满'), findsNothing);
    await tap(t, '重新加载');
    expect(find.text('＋ 新增客户'), findsNothing);
    await tap(t, '林小满');
    expect(find.text('138 **** 0268'), findsNothing);
    expect(find.text('编辑资料'), findsNothing);
    await tap(t, '业务');
    await tap(t, '订单');
    expect(find.textContaining('金额未授权'), findsWidgets);
    await tap(t, '‹');
    store.readState = CrmReadState.forbidden;
    await tap(t, '搜索');
    expect(find.text('暂时无法访问'), findsOneWidget);
    expect(find.text('林小满'), findsNothing);
  });

  for (final width in [320.0, 390.0, 412.0]) {
    testWidgets('${width.toInt()}dp 大字：目录、详情、表单底栏可达', (t) async {
      final height = width == 320 ? 568.0 : 844.0;
      await show(t, CrmDemoStore(), width: width, height: height, scale: 1.5);
      final save = find.text('保存客户');
      await tap(t, '＋ 新增客户');
      expect(save.hitTestable(), findsOneWidget);
      expect(t.getRect(save).bottom, lessThan(height));
      await tap(t, '企业客户');
      expect(save.hitTestable(), findsOneWidget);
      await tap(t, '取消');
      await tap(t, '放弃修改');
      await tap(t, '林小满');
      await tap(t, '会员');
      await tap(t, '业务');
      expect(find.bySemanticsLabel('返回客户目录').hitTestable(), findsOneWidget);
      expect(find.text('‹ 返回客户目录'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
