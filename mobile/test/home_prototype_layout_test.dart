import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/features/dashboard/dashboard_home.dart';
import 'package:pandora_mobile/features/home/home_summary_card.dart';
import 'package:pandora_mobile/features/personal_todos/application/todo_providers.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';
import 'package:pandora_mobile/shared/home_paper_navigation.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

Future<DemoTodoRepository> fixture() async {
  final repo = DemoTodoRepository(), date = civilDate(shanghaiToday());
  for (final item in [
    ('预约周末的牙齿检查', '确认医院的预约时间', false),
    ('整理这个月的个人账单', '', false),
    ('给阳台的绿植浇水', '', true),
  ]) {
    await repo.execute(
      TodoCommand('POST', null, {
        'title': item.$1,
        'note': item.$2,
        'date': date,
        'completed': item.$3,
      }),
    );
  }
  return repo;
}

Widget host(TodoRepository repo, double scale, {bool failSummary = false}) =>
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(
          (ref) => const Session(name: '小满', role: UserRole.leader),
        ),
        todoRepositoryProvider.overrideWithValue(repo),
        recordsProvider.overrideWith(
          (ref, key) async => const PageResult([
            Record(id: 'notification', title: '未读消息', fields: {'read': false}),
          ]),
        ),
        homePreviewProvider.overrideWith((ref, key) async {
          if (failSummary && key == 'tasks/received-card') {
            throw StateError('offline');
          }
          return PageResult([
            for (final title
                in key == 'dashboard/company'
                    ? ['本月产品交付安排', '周五下午全员例会']
                    : ['确认新版首页交互稿', '整理本周客户回访记录'])
              Record(id: title, title: title),
          ]);
        }),
      ],
      child: MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('home-capture'),
          child: Scaffold(
            body: const DashboardPage(),
            bottomNavigationBar: HomePaperNavigation(
              index: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    final font = FontLoader(AppTypography.displayFamily)
      ..addFont(rootBundle.load('assets/fonts/GenSenRoundedTW-B.ttf'));
    await font.load();
    if (const bool.fromEnvironment('HOME_VISUAL_CAPTURE')) {
      final body = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
            ),
          ),
        );
      await body.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        );
      await icons.load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('HOME_VISUAL_CAPTURE')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('home-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../output/home-prototype/flutter-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [320.0, 360.0, 390.0, 412.0, 480.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('home fits $width at $scale with every action reachable', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(host(await fixture(), scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(FloatingActionButton),
          findsNothing,
          reason:
              'dispatch-capable managers must also have no home dispatch control',
        );
        final events = tester.getRect(find.byType(HomeSummaryCard).first);
        final tasks = tester.getRect(find.byType(HomeSummaryCard).last);
        expect(
          tasks.left == events.left,
          width < 340 || scale > 1.3,
          reason: 'narrow or enlarged text uses a single column',
        );
        for (final title in ['事件纪', '任务看板']) {
          final rect = tester.getRect(find.text(title));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        for (final destination
            in find.byType(NavigationDestination).evaluate()) {
          final size = tester.getSize(find.byWidget(destination.widget));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        if (width == 390 && scale == 1) await capture(tester, '390-top');
        await tester.ensureVisible(find.text('新增事项').first);
        await tester.tap(find.text('新增事项').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('todo-title')),
          '布局验收新增事项',
        );
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        final todo = find.text('布局验收新增事项');
        await tester.scrollUntilVisible(
          todo,
          240,
          scrollable: find
              .descendant(
                of: find.byType(DashboardPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(todo, findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 390 && scale == 1) await capture(tester, '390-agenda');
      });
    }
  }

  testWidgets('summary failure leaves the private todo usable', (tester) async {
    await tester.pumpWidget(host(await fixture(), 1, failSummary: true));
    await tester.pumpAndSettle();
    expect(find.text('加载失败，重试'), findsOneWidget);
    expect(find.text('本月产品交付安排'), findsOneWidget);
    await tester.ensureVisible(find.text('新增事项').first);
    await tester.tap(find.text('新增事项').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请填写事项标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
