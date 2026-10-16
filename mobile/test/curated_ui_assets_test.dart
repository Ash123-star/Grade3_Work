import 'support/flutter_sdk_assets.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/local_test_state.dart';

void main() {
  testWidgets('generated UI assets keep sizing and decorative semantics local', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: Color(0xFFC45E14), size: 30),
          child: Row(
            children: [
              TuantuanIcon('task', size: 30),
              TuantuanMascot('welcome', size: 48),
            ],
          ),
        ),
      ),
    );
    await settleLocalIo(t);
    final artwork = t.widget<Image>(
      find.descendant(
        of: find.byType(TuantuanIcon),
        matching: find.byType(Image),
      ),
    );
    expect(artwork.width, 30);
    expect(
      find.descendant(
        of: find.byType(TuantuanMascot),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TuantuanMascot),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    for (final name in ['phosphor', 'forui']) {
      expect(
        await rootBundle.loadString('assets/licenses/$name-LICENSE.txt'),
        contains('Permission'),
      );
    }
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'all pinned local icons and pets decode without remote requests',
    (t) async {
      final files = [
        ...Directory('assets/phosphor').listSync(),
        ...Directory('assets/companions').listSync(),
      ].where((f) => f.path.endsWith('.svg'));
      expect(files.length, 26);
      for (final file in files) {
        final path = file.path.replaceAll('\\', '/');
        await t.pumpWidget(MaterialApp(home: SvgPicture.asset(path)));
        await settleLocalIo(t);
        expect(t.takeException(), isNull, reason: path);
      }
    },
  );

  testWidgets(
    'semantic badges and mascot decoration preserve narrow and scaled navigation',
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
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final width in [360.0, 390.0]) {
        t.view.physicalSize = Size(width, 844);
        final c = testContainer(
          overrides: [
            sessionProvider.overrideWith((ref) => const Session()),
            fontScaleProvider.overrideWith((ref) => width == 360 ? 1.5 : 1),
          ],
        );
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
        Future<void> capture(String captureName) async {
          await t.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await render.toImage();
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '${Directory.systemTemp.path}/pandora-ui-evidence/restored-icons/$captureName-${width.toInt()}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
            picture.dispose();
          });
        }

        for (final (route, name) in [
          ('/dashboard', 'dashboard'),
          ('/me', 'profile'),
          ('/view/day', 'day'),
          ('/view/week', 'week'),
          ('/view/month', 'month'),
          ('/logs', 'report'),
        ]) {
          c.read(routerProvider).go(route);
          await settleLocalIo(t);
          if (name == 'report') {
            await t.tap(find.text('周报'));
            await settleLocalIo(t);
            expect(find.text('工作回顾'), findsOneWidget);
          }
          expect(t.takeException(), isNull, reason: '$name $width');
          if (name == 'dashboard') {
            expect(find.byType(TuantuanMascot), findsOneWidget);
            expect(
              find.byType(TuantuanIcon).evaluate().length,
              greaterThanOrEqualTo(2),
            );
            expect(
              t
                  .widgetList<NavigationDestination>(
                    find.byType(NavigationDestination),
                  )
                  .map((d) => d.label),
              ['导图', '视图', '日志', 'AI地图', '我的'],
            );
          }
          if (name == 'profile') {
            expect(find.byType(FBadge), findsOneWidget);
            final badge = t.widget<FBadge>(find.byType(FBadge));
            final style =
                badge.style(
                      FTheme.of(
                        t.element(find.byType(FBadge)),
                      ).badgeStyles.primary,
                    )
                    as FBadgeStyle;
            expect(style.decoration.color, SunnyPalette.orange);
            expect(
              find.ancestor(
                of: find.byType(TuantuanDecoration),
                matching: find.byType(Row),
              ),
              findsWidgets,
            );
          }
          await capture(name);
          if (name == 'report') {
            await t.drag(find.byType(Scrollable).first, const Offset(0, -420));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await capture('report-scrolled');
          }
        }
        await t.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    },
  );
}
