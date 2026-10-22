import 'support/flutter_sdk_assets.dart';
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
import 'package:pandora_mobile/features/dashboard/dashboard_pages.dart';
import 'calendar_agenda_test.dart' show agendaStore;
import 'support/local_test_state.dart';

void main() {
  testWidgets('six-week task month fits the viewport without scrolling', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    for (final (family, path) in [
      ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
      ('MaterialIcons', materialIconsFontPath),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final (size, scale) in [
      (const Size(320, 640), 1.0),
      (const Size(360, 640), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(480, 960), 1.0),
      (const Size(320, 844), 1.5),
    ]) {
      t.view.physicalSize = size;
      final store = DemoStore();
      store.records['tasks'] = [
        const Record(
          id: 'training',
          title: '数据结构实训',
          fields: {
            'startAt': '2026-11-05T09:00:00+08:00',
            'deadline': '2026-11-10T18:00:00+08:00',
            'tagColor': '#BE8A68',
          },
        ),
        const Record(
          id: 'overlap',
          title: '需求评审会议',
          fields: {
            'startAt': '2026-11-04T09:00:00+08:00',
            'deadline': '2026-11-12T18:00:00+08:00',
            'tagColor': '#9EDCC3',
          },
        ),
        for (var i = 0; i < 4; i++)
          Record(
            id: 'single-$i',
            title: '计划核对事项$i',
            fields: {
              'deadline': '2026-11-05T18:00:00+08:00',
              'tagColor': '#B9DDF5',
            },
          ),
        const Record(
          id: 'last-day',
          title: '月底汇总验收',
          fields: {
            'deadline': '2026-11-30T18:00:00+08:00',
            'tagColor': '#FFB35C',
          },
        ),
      ];
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => const Session()),
          fontScaleProvider.overrideWith((ref) => scale),
          selectedDateProvider.overrideWith((ref) => DateTime(2026, 11, 5)),
          periodProvider.overrideWith((ref) => '月'),
          repositoryProvider.overrideWithValue(
            MockRepository(const Session(), store: store),
          ),
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
      c.read(routerProvider).go('/view');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final month = find.byKey(const ValueKey('calendar-month-grid'));
      final lastDay = find.byKey(const ValueKey('month-day:2026-11-30'));
      expect(
        find.descendant(
          of: find.byType(CalendarPage),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(find.text('数据结构'), findsOneWidget);
      expect(
        find.text('计划核对'),
        findsOneWidget,
        reason: 'two spans leave one of three lanes',
      );
      expect(find.text('月底汇总'), findsOneWidget);
      final navTop = t.getTopLeft(find.byType(NavigationBar)).dy;
      expect(t.getBottomRight(month).dy, lessThanOrEqualTo(navTop));
      expect(t.getBottomRight(lastDay).dy, lessThanOrEqualTo(navTop));
      final before = t.getRect(lastDay);
      await t.drag(month, const Offset(0, -100));
      await t.pumpAndSettle();
      expect(
        t.getRect(lastDay),
        before,
        reason: 'the complete month remains fixed',
      );
      expect(t.takeException(), isNull, reason: '$size scale=$scale');
      await t.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../output/flutter-evidence/week5/month-tasks-${size.width.toInt()}x${size.height.toInt()}-$scale.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(png!.buffer.asUint8List());
        picture.dispose();
      });
      await t.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  testWidgets(
    'render agenda at 360 and 390, large text, and scrolling AI actions',
    (t) async {
      final font = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(File(materialIconsFontPath).readAsBytesSync()),
          ),
        );
      await font.load();
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
            selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 13)),
            demoStoreProvider.overrideWithValue(agendaStore()),
            repositoryProvider.overrideWith(
              (ref) => MockRepository(
                const Session(),
                store: ref.watch(demoStoreProvider),
              ),
            ),
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
        Future<void> capture(String name) async {
          expect(t.takeException(), isNull, reason: name);
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await t.runAsync(() async {
            final picture = await render.toImage(pixelRatio: 1);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '${Directory.systemTemp.path}/pandora-ui-evidence/calendar-agenda/$name.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(data!.buffer.asUint8List());
            picture.dispose();
          });
        }

        c.read(routerProvider).go('/view');
        for (final (period, name) in [
          ('日', 'day'),
          ('周', 'week'),
          ('月', 'month'),
        ]) {
          c.read(periodProvider.notifier).state = period;
          await settleLocalIo(t);
          await capture('$name-${width.toInt()}');
        }
        c.read(routerProvider).go('/ai');
        await settleLocalIo(t);
        await capture('ai-top-${width.toInt()}');
        final list = find.byType(ListView);
        await t.drag(list.first, const Offset(0, -400));
        await t.pumpAndSettle();
        expect(find.text('建议草稿').hitTestable(), findsNothing);
        await capture('ai-scrolled-${width.toInt()}');
        await t.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    },
  );
}
