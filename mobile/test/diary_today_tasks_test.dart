import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'support/local_test_state.dart';
import 'support/workflow_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/diary_task_links.dart';
import 'package:pandora_mobile/shared/diary_task_links.dart';

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('HOME_VISUAL_CAPTURE')) return;
    final display = FontLoader('TuantuanDisplay')
      ..addFont(rootBundle.load('assets/fonts/GenSenRoundedTW-B.ttf'));
    await display.load();
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
    await font.load();
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
  });
  const first = Record(
    id: 'first',
    title: '项目需求梳理',
    fields: {
      'phase': 'RECEIVED',
      'labels': [
        {'name': '研发', 'color': '#226633'},
      ],
    },
  );
  const second = Record(
    id: 'second',
    title: '接口联调',
    fields: {'phase': 'RECEIVED', 'tagColor': '#F3A45D'},
  );
  test('pending tasks require an explicit received lifecycle', () {
    expect(diaryTaskIsPending(first), isTrue);
    expect(diaryTaskIsPending(second), isTrue);
    for (final phase in [
      'FEEDBACK',
      'DISPATCHED',
      'ACCEPTED',
      'ARCHIVED',
      'WITHDRAWN',
      'UNKNOWN',
    ]) {
      expect(
        diaryTaskIsPending(
          Record(id: phase, title: phase, fields: {'phase': phase}),
        ),
        isFalse,
      );
    }
    expect(diaryTaskColor(first.fields), const Color(0xFF226633));
  });

  testWidgets('compact dropdown supports independent multiple selections', (
    t,
  ) async {
    var links = '';
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          receivedTaskCardProvider.overrideWith(
            (ref) async => PageResult([
              first,
              second,
              const Record(
                id: 'feedback',
                title: '待验收任务',
                fields: {'phase': 'FEEDBACK'},
              ),
              const Record(
                id: 'done',
                title: '已完成任务',
                fields: {'phase': 'ACCEPTED'},
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DiaryTaskLinksEditor(
                value: links,
                enabled: true,
                onChanged: (v) => setState(() => links = v),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text(first.title), findsNothing);
    expect(
      t.getSize(find.byType(DiaryTaskLinksEditor)).height,
      lessThanOrEqualTo(56),
    );
    await t.tap(find.byKey(const ValueKey('diary-task-dropdown')));
    await t.pumpAndSettle();
    expect(find.text('已完成任务'), findsNothing);
    expect(find.text('待验收任务'), findsNothing);
    await t.tap(find.text(first.title));
    await t.pumpAndSettle();
    await t.tap(find.text(second.title));
    await t.pumpAndSettle();
    expect(DiaryTaskLinks.parse(links), ['first', 'second']);
    final pill = t.widget<DiaryTaskPill>(
      find.byKey(const ValueKey('diary-task-first')),
    );
    expect(pill.color, const Color(0xFF226633));
    expect(pill.selected, isTrue);
    await t.tap(find.text(first.title));
    await t.pumpAndSettle();
    expect(DiaryTaskLinks.parse(links), ['second']);
  });

  testWidgets(
    'reader resolves a completed saved task directly with its original colour',
    (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            itemProvider.overrideWith(
              (ref, key) async => const Record(
                id: 'old',
                title: '已验收历史任务',
                fields: {'phase': 'ACCEPTED', 'tagColor': '#F3A45D'},
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DiaryTaskLinksReader(['old'])),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('已验收历史任务'), findsOneWidget);
      expect(
        t.widget<DiaryTaskPill>(find.byType(DiaryTaskPill)).color,
        const Color(0xFFF3A45D),
      );
    },
  );
  testWidgets(
    'composer saves selections in encrypted draft and submits them with the diary',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final date =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final fixture = workflowFixture();
      fixture.records['logs']!.removeWhere(
        (r) => r.ownerId == 'u1' && r.fields['businessDate'] == date,
      );
      final c = testContainer(
        overrides: [
          demoStoreProvider.overrideWithValue(fixture),
          diaryAvailableTasksProvider.overrideWith(
            (ref) async => [first, second],
          ),
        ],
      );
      await t.pumpWidget(
        OwnedTestProviderScope(
          container: c,
          child: const RepaintBoundary(
            key: ValueKey('diary-capture'),
            child: PandoraApp(),
          ),
        ),
      );
      c.read(logDateProvider.notifier).state = day;
      c.read(routerProvider).go('/form/log-edit');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '记录今日任务完成内容');
      await t.tap(find.byKey(const ValueKey('diary-task-dropdown')));
      await t.pumpAndSettle();
      await t.tap(find.text(first.title));
      await t.pump();
      await t.tap(find.text(second.title));
      await t.pump(const Duration(milliseconds: 500));
      await settleLocalIo(t);
      final store = c.read(draftStoreProvider);
      final local = await t.runAsync(
        () => store.read(DraftLocation.diary('u1', day)),
      );
      expect(DiaryTaskLinks.parse(local!.fields['关联任务']), ['first', 'second']);
      if (const bool.fromEnvironment('HOME_VISUAL_CAPTURE')) {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('diary-capture')),
        );
        await t.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../output/home-log-verification/diary-today-tasks.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.tap(find.byKey(const ValueKey('diary-task-dropdown')));
      await t.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      await t.tap(find.byTooltip('关闭'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      c.read(routerProvider).go('/form/log-edit');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('diary-task-dropdown')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<DiaryTaskPill>(
              find.byKey(const ValueKey('diary-task-first')),
            )
            .selected,
        isTrue,
      );
      expect(
        t
            .widget<DiaryTaskPill>(
              find.byKey(const ValueKey('diary-task-second')),
            )
            .selected,
        isTrue,
      );
      await t.tap(find.byKey(const ValueKey('diary-task-dropdown')));
      await t.pumpAndSettle();
      await t.tap(find.text('提交'));
      await settleLocalIo(t);
      await t.pumpAndSettle();
      final page = (await t.runAsync(
        () => c.read(repositoryProvider).list('logs', const Query()),
      ))!;
      final log = page.items.singleWhere(
        (r) => r.ownerId == 'u1' && r.fields['businessDate'] == date,
      );
      expect(log.fields['taskIds'], ['first', 'second']);
      expect(
        await t.runAsync(() => store.read(DraftLocation.diary('u1', day))),
        isNull,
      );
    },
  );
}
