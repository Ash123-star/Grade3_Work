import 'support/flutter_sdk_assets.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/pandora_splash.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

void main() {
  testWidgets('splash builds as the app root without inherited app theme', (
    t,
  ) async {
    await t.pumpWidget(const PandoraSplash(child: SizedBox.shrink()));
    expect(t.takeException(), isNull);
    await t.pump(const Duration(milliseconds: 1600));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'new local assets decode and invalid decoration preserves input',
    (t) async {
      final paths = Directory('assets/generated_ui/new_pack')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'));
      expect(paths.length, greaterThanOrEqualTo(82));
      final icon = File('assets/icon_desktop.png');
      final splashIcon = File('assets/icon_splash.png');
      expect(icon.existsSync(), isTrue);
      expect(splashIcon.existsSync(), isTrue);
      await t.runAsync(() async {
        for (final file in [icon, splashIcon]) {
          final iconCodec = await ui.instantiateImageCodec(
            file.readAsBytesSync(),
          );
          final iconFrame = await iconCodec.getNextFrame();
          expect(iconFrame.image.width, greaterThan(0), reason: file.path);
          iconFrame.image.dispose();
          iconCodec.dispose();
        }
        for (final file in paths) {
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0), reason: file.path);
          frame.image.dispose();
          codec.dispose();
        }
      });
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: PaperSurface(
              texture: 'assets/nonexistent-art.png',
              onTap: () => calls++,
              child: const Text('真实操作保留'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('真实操作保留'));
      expect(calls, 1);
      expect(t.takeException(), isNull);
    },
  );

  for (final config in [
    (360.0, 1.0),
    (390.0, 1.0),
    (412.0, 1.5),
    (360.0, 1.5),
  ]) {
    testWidgets(
      'screenshot repairs fit ${config.$1} scale ${config.$2} and navigate',
      (t) async {
        final font = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
              ),
            ),
          );
        await font.load();
        final displayFont = FontLoader('TuantuanDisplay')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/GenSenRoundedTW-B.ttf').readAsBytesSync(),
              ),
            ),
          );
        await displayFont.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  materialIconsFontPath,
                ).readAsBytesSync(),
              ),
            ),
          );
        await icons.load();
        t.view.physicalSize = Size(config.$1, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final store = DemoStore();
        store.records['tasks'] = [
          for (var i = 0; i < 3; i++)
            Record(
              id: '${i + 1}',
              title: '完成工作台交互稿与客户访谈记录$i',
              ownerId: 'u1',
              fields: {
                'deadline': '2026-10-14T09:05:00',
                'status': '待接收',
                '主负责人': '林小满',
                'dispatcherId': 'u1',
                '任务内容': '梳理首页信息层级，明确四大板块与常用入口。',
              },
            ),
        ];
        store.records['logs'] = [
          const Record(
            id: '1',
            title: '梳理工作台交互流程',
            ownerId: 'u1',
            fields: {
              'businessDate': '2026-10-13',
              'status': '已提交',
              '今日工作': '核对导航、摘要与详情交互。',
            },
          ),
        ];
        final c = testContainer(
          overrides: [
            sessionProvider.overrideWith((_) => const Session()),
            demoStoreProvider.overrideWithValue(store),
            repositoryProvider.overrideWithValue(
              MockRepository(const Session(), store: store),
            ),
            fontScaleProvider.overrideWith((_) => config.$2),
          ],
        );
        addTearDown(c.dispose);
        c.read(selectedDateProvider.notifier).state = DateTime(2026, 10, 14);
        final boundary = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: UncontrolledProviderScope(
              container: c,
              child: const PandoraApp(),
            ),
          ),
        );
        await settleLocalIo(t);
        Future<void> capture(String name) async {
          await t.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.diagnostics/ui-skin/${config.$1.toInt()}-${config.$2}/$name.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        final router = c.read(routerProvider);
        for (final (name, route) in [
          ('dashboard', '/dashboard'),
          ('profile', '/me'),
          ('ai', '/ai'),
          ('month', '/view/month'),
          ('task', '/item/tasks/1'),
          ('focus', '/item/dashboard%2Fcompany/1'),
          ('log', '/item/logs/1'),
          ('inbox', '/list/notifications'),
        ]) {
          router.go('/dashboard');
          await t.pumpAndSettle();
          if (['task', 'focus', 'log', 'inbox'].contains(name)) {
            router.push(route);
          } else {
            router.go(route);
          }
          await settleLocalIo(t);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$name $config');
          await capture(name);
          if (name == 'task') {
            final more = find.byTooltip('更多操作');
            expect(t.getCenter(more).dx, greaterThan(config.$1 * .7));
            expect(t.getSize(more).height, greaterThanOrEqualTo(48));
            await t.tap(more);
            await t.pumpAndSettle();
            expect(find.text('我的私人备注'), findsOneWidget);
          }
          if (name == 'inbox') {
            await t.tap(find.text('未读'));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await capture('inbox-unread');
          }
          if (name == 'month') {
            final day = find.byKey(const ValueKey('month-day:2026-10-14'));
            expect(
              find.byKey(const ValueKey('month-horizontal-scroll')),
              findsNothing,
            );
            final grid = t.getRect(
              find.byKey(const ValueKey('calendar-month-grid')),
            );
            for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
              final rect = t.getRect(
                find.byKey(ValueKey('month-weekday:$label')),
              );
              expect(rect.left, greaterThanOrEqualTo(grid.left));
              expect(rect.right, lessThanOrEqualTo(grid.right));
              expect(rect.right, lessThanOrEqualTo(config.$1));
            }
            expect(t.getSize(day).width, lessThan(config.$1 / 7));
            expect(t.getSize(day).height, greaterThanOrEqualTo(48));
            final previews = find.descendant(
              of: day,
              matching: find.textContaining('完成工作台'),
            );
            expect(previews, findsNWidgets(2));
            expect(
              find.descendant(of: day, matching: find.textContaining('任·')),
              findsNothing,
            );
            expect(find.text('任：任务 · 日：日志 · 点击日期查看全文'), findsNothing);
            expect(find.text('+1'), findsWidgets);
            await t.ensureVisible(day);
            await t.pumpAndSettle();
            await capture('month-selected');
            await t.tap(day);
            await t.pumpAndSettle();
            expect(find.byTooltip('关闭当天记录'), findsOneWidget);
            expect(
              find.descendant(of: day, matching: find.byType(TuantuanSkin)),
              findsNothing,
            );
            expect(t.takeException(), isNull);
            await capture('month-records');
          }
          if (name == 'profile') {
            await t.scrollUntilVisible(
              find.text('设置'),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await t.pumpAndSettle();
            await capture('profile-actions');
            await t.tap(find.text('设置'));
            await t.pumpAndSettle();
            expect(
              router
                  .routerDelegate
                  .currentConfiguration
                  .matches
                  .last
                  .matchedLocation,
              '/me/settings',
            );
          }
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
      },
    );
  }
}
