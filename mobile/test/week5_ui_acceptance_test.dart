import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/dashboard/task_management_table.dart';
import 'package:pandora_mobile/shared/public_comments.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'support/flutter_sdk_assets.dart';
import 'support/local_test_state.dart';
import 'support/workflow_fixture.dart';

Future<void> fonts() async {
  for (final entry in {
    'Roboto': 'C:/Windows/Fonts/msyh.ttc',
    'TuantuanDisplay': 'assets/fonts/GenSenRoundedTW-B.ttf',
    'MaterialIcons': materialIconsFontPath,
  }.entries) {
    final font = FontLoader(entry.key)
      ..addFont(
        Future.value(ByteData.sublistView(File(entry.value).readAsBytesSync())),
      );
    await font.load();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'nine annotated screens have reproducible renders and responsive geometry',
    (t) async {
      await fonts();
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final width in [390.0, 320.0, 480.0]) {
        t.view.physicalSize = Size(width, width == 480 ? 960 : 844);
        final c = testContainer(
          overrides: [
            sessionProvider.overrideWith((ref) => const Session()),
            demoStoreProvider.overrideWithValue(workflowFixture()),
            fontScaleProvider.overrideWith((ref) => width == 320 ? 1.5 : 1),
          ],
        );
        final boundary = GlobalKey();
        c.read(logFilterDateProvider.notifier).state = null;
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: UncontrolledProviderScope(
              container: c,
              child: const PandoraApp(),
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 1700));
        await settleLocalIo(t);
        Future<void> settle() async {
          await t.pump();
          await t.pump(const Duration(milliseconds: 180));
          await settleLocalIo(t);
          await t.pumpAndSettle();
        }

        Future<void> capture(String name) async {
          expect(t.takeException(), isNull, reason: '$name width=$width');
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await t.runAsync(() async {
            final picture = await render.toImage(pixelRatio: 1);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../output/flutter-evidence/week5/$name-${width.toInt()}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
            picture.dispose();
          });
        }

        final a = t.getRect(find.byKey(const ValueKey('dashboard-tile:0')));
        final b = t.getRect(find.byKey(const ValueKey('dashboard-tile:1')));
        final d = t.getRect(find.byKey(const ValueKey('dashboard-tile:2')));
        expect(a.top, b.top);
        expect(b.left, greaterThan(a.right));
        expect(d.top, greaterThan(a.bottom));
        await capture('01-dashboard');
        final router = c.read(routerProvider);
        router.push('/tasks/received');
        await settle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('筛选字段'), findsNothing);
        expect(find.text('任务工作台'), findsNothing);
        await capture('02-company-tasks');
        router.go('/view');
        c.read(periodProvider.notifier).state = '月';
        await settle();
        expect(
          find.byKey(const ValueKey('calendar-month-grid')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('agenda:logs:1')), findsNothing);
        final grid = t.getSize(
          find.byKey(const ValueKey('calendar-month-grid')),
        );
        expect(grid.height, greaterThan(grid.width));
        if (width != 320) {
          expect(
            t
                .getBottomRight(
                  find.byKey(const ValueKey('calendar-month-grid')),
                )
                .dy,
            lessThan(t.view.physicalSize.height - 60),
          );
        }
        await capture('03-month');
        c.read(periodProvider.notifier).state = '周';
        await settle();
        for (var day = 1; day <= 7; day++) {
          expect(
            find
                .descendant(
                  of: find.byKey(ValueKey('week-day:$day')),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w.key is ValueKey<String> &&
                        (w.key! as ValueKey<String>).value.startsWith(
                          'week-pill:',
                        ),
                  ),
                )
                .evaluate()
                .length,
            lessThanOrEqualTo(2),
          );
        }
        expect(
          t
              .getSize(find.byKey(const ValueKey('calendar-week-overview')))
              .height,
          greaterThan(500),
        );
        await capture('04-week');
        router.go('/logs');
        await settle();
        expect(find.byTooltip('创建日志'), findsOneWidget);
        expect(find.byType(BottomActions), findsNothing);
        await capture('06-logs');
        router.push('/logs/subordinates');
        await settle();
        expect(
          find.byKey(const ValueKey('subordinate-log-search')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('log-department:全部部门')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('log-date:all')), findsOneWidget);
        expect(find.text('陈一诺'), findsWidgets);
        await capture('05-subordinate-logs');
        router.go('/item/logs/1');
        await settle();
        await t.scrollUntilVisible(
          find.byType(PublicComments),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await settle();
        expect(find.byType(PublicComments), findsOneWidget);
        expect(find.text('申请修订日志'), findsNothing);
        expect(find.text('提交修订申请'), findsNothing);
        await capture('07-log-detail');
        router.go('/me');
        await settle();
        final list = find
            .descendant(
              of: find.byType(PageFrame).last,
              matching: find.byType(ListView),
            )
            .first;
        await t.drag(list, const Offset(0, -330));
        await settle();
        expect(find.text('下属工作台'), findsNothing);
        expect(find.text('组织与成员'), findsNothing);
        await capture('08-profile');
        router.push('/me/people');
        await settle();
        expect(
          find.byKey(const ValueKey('personnel-department:全部部门')),
          findsOneWidget,
        );
        await capture('09-personnel');
        router.go('/me/tasks');
        await settle();
        expect(find.byType(TaskManagementPage), findsOneWidget);
        expect(find.text('本人及下属的全部任务'), findsOneWidget);
        await capture('10-task-management');
        router.go('/item/logs/7');
        await settle();
        final locked = t.widget<SunnyPrimaryButton>(
          find.widgetWithText(SunnyPrimaryButton, '已满24小时 · 日志已锁定'),
        );
        expect(locked.onPressed, isNull);
        await capture('11-locked-log');
        await t.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    },
  );

  testWidgets(
    'diary detail edits directly within the window; comments can post and reply',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = testContainer(
        overrides: [demoStoreProvider.overrideWithValue(workflowFixture())],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      await t.pump(const Duration(milliseconds: 1700));
      await settleLocalIo(t);
      final router = c.read(routerProvider);
      router.go('/logs');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('diary-row:1')));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('今日工作'), findsOneWidget);
      expect(find.text('评论'), findsOneWidget);
      expect(find.textContaining('等待独立审核'), findsNothing);
      router.go('/item/logs/1');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('public-comment-input')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('public-comment-input')),
        '前端验收评论',
      );
      await t.ensureVisible(find.text('发布评论'));
      await t.tap(find.text('发布评论'));
      await t.pumpAndSettle();
      expect(find.text('前端验收评论', findRichText: true), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('reply-comment:0')));
      await t.tap(find.byKey(const ValueKey('reply-comment:0')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('public-comment-input')),
        '回复验收',
      );
      await t.ensureVisible(find.text('发布评论'));
      await t.tap(find.text('发布评论'));
      await t.pumpAndSettle();
      final record = await t.runAsync(
        () => c.read(repositoryProvider).detail('logs', '1'),
      );
      expect(
        (record!.fields['comments'] as List).last['parentCommentId'],
        isNotNull,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('small screen task filters scroll and empty search recovers', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [fontScaleProvider.overrideWith((ref) => 1.5)],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go('/me/tasks');
    await settleLocalIo(t);
    await t.pumpAndSettle();
    await t.tap(find.text('筛选字段'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('应用'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.enterText(find.byType(TextField), '不存在的任务');
    await t.pumpAndSettle();
    expect(find.text('暂无任务记录'), findsOneWidget);
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.byTooltip('紧凑列表视图'));
    await t.pumpAndSettle();
    expect(find.byTooltip('字段卡片视图'), findsOneWidget);
    expect(find.text('暂无任务记录'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'department and author filters combine; calendar opens all daily records',
    (t) async {
      final c = testContainer(
        overrides: [demoStoreProvider.overrideWithValue(workflowFixture())],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      final router = c.read(routerProvider);
      router.go('/logs/subordinates');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('log-department:全部部门')));
      await t.pumpAndSettle();
      await t.tap(find.text('产品部').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('subordinate-log-search')),
        '许知远',
      );
      await t.pumpAndSettle();
      expect(find.text('暂无日志'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('log-department:产品部')));
      await t.pumpAndSettle();
      await t.tap(find.text('技术部').last);
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '许知远'),
        findsOneWidget,
      );
      expect(find.text('陈一诺'), findsNothing);
      router.go('/view');
      c.read(periodProvider.notifier).state = '月';
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final now = c.read(selectedDateProvider);
      await t.tap(
        find.byKey(ValueKey('month-day:${now.year}-${now.month}-${now.day}')),
      );
      await t.pumpAndSettle();
      expect(find.byTooltip('关闭当天记录'), findsOneWidget);
      expect(find.textContaining('条记录'), findsWidgets);
      await t.tap(find.byTooltip('关闭当天记录'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'create diary with autosaved draft and edit submitted work directly',
    (t) async {
      final repo = MockRepository(
        const Session(),
        store: DemoStore()..records['logs'] = [],
      );
      final c = testContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      final router = c.read(routerProvider);
      router.go('/logs');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byTooltip('创建日志'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final work = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '写下今天完成的工作',
      );
      await t.enterText(work, '从页面创建的草稿');
      await t.pump(const Duration(milliseconds: 500));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      router.pop();
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('创建日志'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(work).controller!.text, '从页面创建的草稿');
      await t.tap(find.text('提交'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final draft = (await t.runAsync(
        () => repo.list('logs', const Query()),
      ))!.items.single;
      final submitted = await t.runAsync(() => repo.detail('logs', draft.id));
      expect(isSubmittedDiary(submitted!), isTrue);
      expect(submitted.fields['submittedAt'], isNotNull);
      await t.tap(find.byKey(ValueKey('diary-row:${draft.id}')));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.textContaining('等待独立审核'), findsNothing);
      await t.enterText(work, '24小时内直接修改的正文');
      await t.tap(find.text('提交修改'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final changed = await t.runAsync(() => repo.detail('logs', draft.id));
      expect(changed!.fields['今日工作'], '24小时内直接修改的正文');
      expect((await t.runAsync(() => repo.list('reviews', const Query())))!.items, isEmpty);
      expect(changed.fields['submittedAt'], submitted.fields['submittedAt']);

      t.testTextInput.hide();
      router.go('/logs');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      while (find.byType(SnackBar).evaluate().isNotEmpty) {
        await t.tap(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(IconButton),
              )
              .last,
        );
        await t.pumpAndSettle();
      }
      await t.tap(find.byTooltip('创建日志'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('今日工作'), findsOneWidget);
      expect(find.text('自动保存到此设备'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'view opens task management; failures and empty data are explicit',
    (t) async {
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const Session(role: UserRole.employee, dispatch: false),
          ),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PandoraApp()),
      );
      final router = c.read(routerProvider);
      router.go('/me');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('任务管理'), findsNothing);
      router.go('/view');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.text('任务管理'), findsOneWidget);
      await t.tap(find.text('任务管理'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(find.byType(TaskManagementPage), findsOneWidget);
      expect(find.text('任务名称'), findsOneWidget);
      expect(find.byTooltip('新增任务'), findsNothing);
      c.read(scenarioProvider.notifier).state = DemoScenario.offline;
      c.invalidate(recordsProvider('tasks'));
      await t.pumpAndSettle();
      expect(find.textContaining('网络连接超时'), findsOneWidget);
      c.read(scenarioProvider.notifier).state = DemoScenario.empty;
      c.invalidate(recordsProvider('tasks'));
      await t.pumpAndSettle();
      expect(find.text('暂无任务记录'), findsOneWidget);
      c.read(scenarioProvider.notifier).state = DemoScenario.normal;
      c.invalidate(recordsProvider('tasks'));
      await t.pumpAndSettle();
      expect(find.text('暂无任务记录'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}
