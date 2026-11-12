import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/home/home_summary_card.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

void main() {
  for (final resource in ['dashboard/company', 'tasks/received-card']) {
    testWidgets('$resource summary and record have independent destinations', (
      tester,
    ) async {
      var all = 0;
      final details = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homePreviewProvider.overrideWith(
              (ref, key) async =>
                  PageResult([Record(id: 'entry-1', title: '真实摘要记录')]),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: HomeSummaryCard(
                  title: '摘要标题',
                  resource: resource,
                  onAll: () => all++,
                  onItem: (record) => details.add(record.id),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('真实摘要记录'));
      await tester.pumpAndSettle();
      expect(details, ['entry-1']);
      expect(
        all,
        0,
        reason: 'record tap must not also open the full collection',
      );
      await tester.tap(find.text('摘要标题'));
      await tester.pumpAndSettle();
      expect(all, 1);
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();
      expect(all, 2);
      expect(details, ['entry-1']);
    });
  }

  for (final count in [0, 1, 2, 3, 4]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('task preview $count records at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opened = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homePreviewProvider.overrideWith(
                (ref, key) async => PageResult(
                  List.generate(
                    count,
                    (i) => Record(id: '$i', title: '真实任务$i'),
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: HomeSummaryCard(
                      title: '任务看板',
                      resource: 'tasks/received-card',
                      onAll: () {},
                      onItem: (record) => opened.add(record.id),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < count; i++) {
          expect(find.text('真实任务$i'), i < 3 ? findsOneWidget : findsNothing);
        }
        if (count >= 3) {
          await tester.tap(find.text('真实任务2'));
          expect(opened, ['2']);
        }
        if (count == 0) expect(find.text('暂无参与任务'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('empty summary remains an entry to its full list', (
    tester,
  ) async {
    var all = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homePreviewProvider.overrideWith((ref, key) async => PageResult([])),
        ],
        child: MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: HomeSummaryCard(
              title: '事件纪',
              resource: 'dashboard/company',
              onAll: () => all++,
              onItem: (_) => fail('empty summary has no detail'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂无公司事项'));
    await tester.pumpAndSettle();
    expect(all, 1);
  });
}
