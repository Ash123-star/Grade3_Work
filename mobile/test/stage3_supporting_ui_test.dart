import 'support/local_test_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

class FailedActionRepository extends MockRepository {
  FailedActionRepository(super.session, {required super.store});
  @override
  Future<Record> execute(String resource, Command command) async =>
      throw const ApiFailure(FailureKind.timeout, '本次操作连接超时，记录未变更');
}

void main() {
  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    DemoStore? store,
    bool failedAction = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        if (store != null) demoStoreProvider.overrideWithValue(store),
        if (failedAction)
          repositoryProvider.overrideWith(
            (ref) => FailedActionRepository(
              ref.watch(sessionProvider),
              store: ref.watch(demoStoreProvider),
            ),
          ),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PandoraApp()),
    );
    c.read(routerProvider).go(route);
    await t.pumpAndSettle();
    return c;
  }

  testWidgets(
    'acceptance reads actual results and transfer keeps current context',
    (t) async {
      final store = DemoStore();
      store.records['tasks'] = [
        const Record(
          id: 'accept',
          title: '交付验收',
          ownerId: 'u2',
          fields: {
            'status': '待验收',
            '成果说明': '已核对交付文件',
            '遇到的阻碍': '需核实版权',
            '主负责人': '陈一诺',
            'deadline': '2026-10-14T18:00:00',
            'dispatcherId': 'u1',
          },
        ),
      ];
      final c = await launch(
        t,
        '/form/acceptance?id=accept&version=1',
        store: store,
      );
      expect(find.text('本次成果 · 只读'), findsOneWidget);
      expect(find.text('已核对交付文件'), findsOneWidget);
      expect(find.text('需核实版权'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('已核对交付文件')).dy,
        lessThan(t.getTopLeft(find.byType(TextFormField)).dy),
      );
      await t.tap(find.widgetWithText(FilledButton, '任务验收'));
      await t.pumpAndSettle();
      expect(find.text('请填写验收意见'), findsOneWidget);
      c.read(routerProvider).go('/form/transfer?id=accept&version=1');
      await t.pumpAndSettle();
      expect(find.text('当前生效 · v1'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '陈一诺'),
        findsOneWidget,
      );
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '陈一诺',
      );
      expect(find.text('2026-10-14T18:00:00'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'history uses requested version and profile excludes unsubmitted diaries',
    (t) async {
      final store = DemoStore();
      store.records['logs'] = [
        const Record(
          id: 'history',
          title: '验收工作日报',
          version: 3,
          fields: {
            'businessDate': '2026-10-12',
            'status': '已提交',
            '今日工作': '当前正式工作',
            'versions': [
              {
                'version': 2,
                'body': '历史工作正文',
                'reason': '补充说明',
                'time': '2026-10-11 17:00',
              },
              {'version': 1, 'body': '更早版本正文', 'time': '2026-10-10 17:00'},
            ],
          },
        ),
        const Record(
          id: 'private',
          title: '不应出现在公开时间线',
          fields: {'status': '草稿', 'businessDate': '2026-10-13'},
        ),
      ];
      final c = await launch(t, '/history/history/version/2', store: store);
      expect(find.text('历史工作正文'), findsOneWidget);
      expect(find.text('当前正式工作'), findsNothing);
      expect(find.text('变更理由：补充说明'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      c.read(routerProvider).go('/history/history/version/99');
      await t.pumpAndSettle();
      expect(find.text('该版本正文不可用'), findsOneWidget);
      expect(find.text('当前正式工作'), findsNothing);
      c.read(routerProvider).go('/me/profile');
      await t.pumpAndSettle();
      expect(find.text('日志时间线'), findsOneWidget);
      expect(find.text('不应出现在公开时间线'), findsNothing);
      expect(find.text('验收工作日报'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'new own private note saves and remains hidden on another member focus',
    (t) async {
      const noteId = 'dashboard/company:1:u1';
      final c = await launch(t, '/form/note?id=${Uri.encodeComponent(noteId)}');
      final save = find.widgetWithText(FilledButton, '私人备注');
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      await t.enterText(find.byType(TextFormField).first, '仅本人使用的备忘');
      await t.tap(save);
      await t.pumpAndSettle();
      final note = (await t.runAsync(
        () => c.read(repositoryProvider).detail('private-notes', noteId),
      ))!;
      expect(note.fields['备注'], '仅本人使用的备忘');
      c.read(routerProvider).go('/item/dashboard%2Fcompany/1');
      await t.pumpAndSettle();
      expect(find.text('仅本人使用的备忘'), findsOneWidget);
      c.read(demoStoreProvider).records['dashboard/personal'] = [
        const Record(id: 'other', title: '他人公开重点', ownerId: 'u2'),
      ];
      c.read(routerProvider).go('/item/dashboard%2Fpersonal/other');
      await t.pumpAndSettle();
      expect(find.text('我的私人备注'), findsNothing);
      expect(find.text('仅本人使用的备忘'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'failed detail action stays visible by fixed action and missing record recovers safely',
    (t) async {
      final c = await launch(t, '/item/tasks/1', failedAction: true);
      await t.tap(find.text('接收任务'));
      await t.pumpAndSettle();
      expect(find.text('本次操作连接超时，记录未变更'), findsOneWidget);
      expect(
        t.getBottomRight(find.text('本次操作连接超时，记录未变更')).dy,
        lessThan(t.getTopLeft(find.text('接收任务')).dy),
      );
      c.read(routerProvider).go('/item/tasks/missing');
      await t.pumpAndSettle();
      expect(find.text('内容不可用'), findsOneWidget);
      expect(find.text('安全返回'), findsOneWidget);
      expect(find.text('接收任务'), findsNothing);
      await t.tap(find.text('安全返回'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '导图'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
