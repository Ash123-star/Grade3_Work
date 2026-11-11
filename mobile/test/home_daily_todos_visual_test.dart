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
import 'package:pandora_mobile/features/personal_todos/application/todo_providers.dart';
import 'package:pandora_mobile/features/personal_todos/data/personal_todo.dart';
import 'package:pandora_mobile/features/personal_todos/data/todo_repository.dart';
import 'package:pandora_mobile/shared/calendar/civil_date.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'support/flutter_sdk_assets.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0, 480.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('home real widgets fit $width / $scale', (t) async {
        for (final entry in {
          'Roboto': 'assets/fonts/GenSenRoundedTW-B.ttf',
          'TuantuanDisplay': 'assets/fonts/GenSenRoundedTW-B.ttf',
          'MaterialIcons': materialIconsFontPath,
        }.entries) {
          await (FontLoader(entry.key)..addFont(
                Future.value(
                  ByteData.sublistView(File(entry.value).readAsBytesSync()),
                ),
              ))
              .load();
        }
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final repo = DemoTodoRepository();
        for (final title in ['整理本周的阅读笔记', '晚饭后散步二十分钟']) {
          await repo.execute(
            TodoCommand('POST', null, {
              'title': title,
              'date': civilDate(shanghaiToday()),
            }),
          );
        }
        final boundary = GlobalKey();
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => const Session(name: '小满')),
              todoRepositoryProvider.overrideWithValue(repo),
              homePreviewProvider.overrideWith(
                (ref, resource) async => PageResult([
                  Record(
                    id: '1',
                    title: resource == 'dashboard/company'
                        ? '本周产品交流会'
                        : '确认活动页面的最终方案',
                  ),
                  Record(
                    id: '2',
                    title: resource == 'dashboard/company'
                        ? '十一月团队共创计划'
                        : '整理客户访谈记录',
                  ),
                ], total: 12),
              ),
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
                key: boundary,
                child: const DashboardPage(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (Platform.environment['CAPTURE_HOME'] == '1' &&
            width == 390 &&
            scale == 1) {
          await t.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('docs/screenshots/home-daily-todos.png');
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
        await t.pumpAndSettle();
        expect(find.text('整理本周的阅读笔记'), findsNWidgets(2));
        expect(t.takeException(), isNull);
      });
    }
  }
}
