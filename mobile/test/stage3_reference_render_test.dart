import 'support/local_test_state.dart';
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

// Actual Flutter rendering with isolated reference fixture data. No prototype SVG used.
void main() {
  testWidgets('render sixteen reference screens with Chinese system font', (
    tester,
  ) async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (!font.existsSync()) {
      fail('Screenshot evidence needs a readable CJK font.');
    }
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 10, 12),
        today = DateTime.now().toIso8601String().split('T').first;
    SharedPreferences.setMockInitialValues({
      'draft:u1:$today:今日工作': '梳理五个主页面的信息结构',
      'draft:u1:$today:savedAt': '${today}T09:20:00',
      'draft:u1:2026-10-12:今日工作': '梳理了五个主页面的信息结构，完成月历和日志编辑页面设计。',
      'draft:u1:2026-10-12:关联任务': '1',
      'draft:u1:2026-10-12:遇到的阻碍': '附件上传接口需要确认。',
      'draft:u1:2026-10-12:明日计划': '继续整理任务详情与审批流程。',
      'draft:u1:2026-10-12:工时': '7.5',
      'draft:u1:2026-10-12:savedAt': '2026-10-12T09:20:00',
    });
    final store = DemoStore();
    store.records['dashboard/company'] = [
      const Record(id: '1', title: '秋季产品发布', subtitle: '10月的共同方向'),
      const Record(id: '2', title: '本周客户拜访', subtitle: '重点客户沟通'),
    ];
    store.records['dashboard/personal'] = [
      const Record(id: '1', title: '做好前端交互', subtitle: '梳理员工常用路径'),
      const Record(id: '2', title: '完善设计文档', subtitle: '整理页面与组件'),
    ];
    store.records['tasks'] = [
      Record(
        id: '1',
        title: '上线前验收清单',
        fields: {
          'deadline': '2026-10-14T18:00:00',
          '所属分组': '产品发布',
          '紧急程度': '紧急',
          '主负责人': '陈一诺',
          'dispatcherId': 'u1',
          'status': '待验收',
          '协作人': '许知远',
          '任务内容': '核对发布资料、接口失败场景与移动端验收项，补充遗漏的说明。',
          '附件': '验收清单.pdf',
          '成果说明': '已补齐接口失败场景，待独立验收。',
          'events': [
            '林小满派发任务 · 10月10日 09:30',
            '陈一诺接收任务 · 10月10日 10:05',
            '陈一诺提交成果反馈 · 10月12日 14:20',
          ],
        },
      ),
      const Record(
        id: '2',
        title: '发布素材校对',
        fields: {
          'deadline': '2026-10-12T14:00:00',
          '主负责人': '陈一诺',
          '所属分组': '产品发布',
          '紧急程度': '普通',
        },
      ),
    ];
    store.records['logs'] = [
      for (final (i, title) in [
        '上线前验收与文档整理',
        '移动端组件与交互梳理',
        '日历联动与页面走查',
      ].indexed)
        Record(
          id: '${i + 1}',
          title: title,
          fields: {
            'businessDate': '2026-10-${(11 - i).toString().padLeft(2, '0')}',
            '今日工作': title,
            'status': '已提交',
          },
        ),
    ];
    store.records['reviews'] = [
      const Record(
        id: '1',
        title: '陈一诺申请修订工作日志',
        ownerId: 'u2',
        fields: {
          'createdAt': '2026-10-12T08:40:00',
          'applicantName': '陈一诺',
          'reviewState': '待审',
          'step': 0,
          'reason': '补充遗漏的接口验收工作记录。',
          'before': '完成页面布局与组件梳理。',
          'after': '完成页面布局与组件梳理。\n新增：补充接口失败场景验收。',
        },
      ),
    ];
    store.records['organization/profile'] = [
      const Record(
        id: 'u1',
        title: '林小满',
        subtitle: '技术部 · 移动端团队',
        fields: {'个人介绍': '把复杂的工作，做得清楚一点。'},
      ),
    ];
    store.records['notifications'] = [
      for (var i = 0; i < 3; i++)
        Record(id: '${i + 1}', title: '消息', fields: {'read': false}),
    ];
    store.records['ai-maps'] = [
      for (final (i, title, body) in [
        (0, '先确认发布依赖', '验收资料需要在明天下午前汇齐'),
        (1, '补充接口边界说明', '缺少附件失败场景，建议补充核对'),
        (2, '预留联调与缓冲时间', '时间安排建议，需人工判断'),
      ])
        Record(
          id: '${i + 1}',
          title: title,
          fields: {
            'body': body,
            'createdAt': '2026-10-12T09:30:00',
            'sources': i == 0
                ? ['/item/tasks/1', '/item/logs/1']
                : ['/item/tasks/1'],
          },
        ),
    ];
    final c = testContainer(
      overrides: [demoStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    c.read(selectedDateProvider.notifier).state = day;
    c.read(logDateProvider.notifier).state = day;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: UncontrolledProviderScope(
          container: c,
          child: const PandoraApp(),
        ),
      ),
    );
    final screens = [
      ('01-dashboard', '/dashboard'),
      ('02-calendar', '/view'),
      ('03-logs', '/logs'),
      ('04-ai', '/ai'),
      ('05-profile', '/me'),
      ('06-editor', '/form/log-edit'),
      ('07-task', '/item/tasks/1'),
      ('08-review', '/me/reviews/1'),
      ('09-acceptance', '/form/acceptance?id=1&version=1'),
      ('10-transfer', '/form/transfer?id=1&version=1'),
      ('11-profile-document', '/me/profile'),
      ('12-history-document', '/history/1/version/1'),
      ('13-organization', '/me/organization'),
      ('14-settings', '/me/settings'),
      ('15-help', '/me/help'),
      ('16-log-reader', '/item/logs/1'),
    ];
    for (final screen in screens) {
      if (screens.indexOf(screen) < 5) {
        c.read(routerProvider).go(screen.$2);
      } else {
        final router = c.read(routerProvider);
        final fromLogs = [
          '06-editor',
          '12-history-document',
          '16-log-reader',
        ].contains(screen.$1);
        final fromTask = [
          '07-task',
          '09-acceptance',
          '10-transfer',
        ].contains(screen.$1);
        router.go(fromLogs ? '/logs' : (fromTask ? '/dashboard' : '/me'));
        await tester.pumpAndSettle();
        if (screen.$1 == '09-acceptance' || screen.$1 == '10-transfer') {
          router.push('/item/tasks/1');
          await tester.pumpAndSettle();
        } else if (screen.$1 == '12-history-document') {
          router.push('/item/logs/1');
          await tester.pumpAndSettle();
          router.push('/history/1');
          await tester.pumpAndSettle();
        }
        router.push(screen.$2);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: screen.$2);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await render.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        final output = File('docs/evidence/stage3-rebuild/${screen.$1}.png');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes!.buffer.asUint8List());
        img.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
