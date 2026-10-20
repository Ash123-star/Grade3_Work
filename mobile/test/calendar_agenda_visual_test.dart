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
import 'package:pandora_mobile/shared/widgets.dart';
import 'calendar_agenda_test.dart' show agendaStore;
import 'support/local_test_state.dart';

void main() {
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
            ByteData.sublistView(
              File(
                materialIconsFontPath,
              ).readAsBytesSync(),
            ),
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
        final list = find.descendant(
          of: find.byType(PageFrame).last,
          matching: find.byType(ListView),
        );
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
