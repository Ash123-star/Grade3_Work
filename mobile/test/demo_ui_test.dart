import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/providers.dart';

void main() {
  testWidgets('logs use a single independent date and allow member selection', (tester) async {
    final container=ProviderContainer();
    addTearDown(container.dispose);
    container.read(periodProvider.notifier).state='月';
    await tester.pumpWidget(UncontrolledProviderScope(container:container,child:const PandoraApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日志').last);
    await tester.pumpAndSettle();
    expect(find.text('日'),findsNothing);
    expect(find.text('周'),findsNothing);
    expect(find.text('月'),findsNothing);
    expect(find.text('编辑已提交日志'),findsOneWidget);
    expect(find.text('全部日期 · 按日期筛选'),findsOneWidget);
    expect(container.read(logDayRecordsProvider(('logs','u1'))).valueOrNull!.items.length,3);
    await tester.tap(find.text('下属日志'));
    await tester.pumpAndSettle();
    expect(find.text('选择下属'),findsOneWidget);
    expect(find.text('编辑已提交日志'),findsNothing);
    container.read(logFilterDateProvider.notifier).state=DateTime.now().subtract(const Duration(days:1));
    await tester.pumpAndSettle();
    expect(find.text('完成客户访谈与结论整理'),findsWidgets);
    await tester.tap(find.text('全部日期'));
    await tester.pumpAndSettle();
    expect(container.read(logFilterDateProvider),isNull);
    expect(container.read(logDayRecordsProvider(('logs/subordinates',null))).valueOrNull!.items.length,9);
    expect(container.read(periodProvider),'月');
    expect(tester.takeException(),isNull);
  });

  testWidgets(
    'navigation ordering, calendar periods and AI sections fit small screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PandoraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((w) => w.label)
            .toList(),
        ['导图', '视图', '日志', 'AI地图', '我的'],
      );
      await tester.tap(find.text('视图').last);
      await tester.pumpAndSettle();
      for (final period in ['周', '月']) {
        await tester.tap(find.text(period));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(container.read(periodProvider), period);
      }
      await tester.tap(find.text('AI地图').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('堵点风险'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('日'), findsNothing);
      expect(find.text('行动规划'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('AI task draft and existing focus editor are prefilled', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PandoraApp(),
      ),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/form/ai-draft?source=1');
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields.first.controller!.text, '确认交互稿中的关键依赖');
    expect(fields[1].controller!.text, isNotEmpty);
    container.read(routerProvider).go('/form/focus-edit?id=1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .first
          .controller!
          .text,
      '梳理工作台体验',
    );
    expect(tester.takeException(), isNull);
  });
}
