import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'support/local_test_state.dart';
import 'support/flutter_sdk_assets.dart';

/// Opt-in: business data always uses real HTTP/PostgreSQL. Only device secure
/// storage is in memory. Never point this fixture at a shared/production DB.
void main() {
  testWidgets(
    '真实日志页面：账号部门搜索、分页、修订审核、评论和撤回重提',
    (t) async {
      HttpOverrides.global = null;
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
      final directory = Directory(
        Platform.environment['STAGE_DEMO_DIRECTORY']!,
      );
      final settings = <String, String>{
        for (final line in File(
          '${directory.path}/stage.env',
        ).readAsLinesSync())
          if (line.contains('='))
            line.split('=').first: line.substring(line.indexOf('=') + 1),
      };
      final clients = <HttpRepository>[];
      HttpRepository client(String? token) {
        final r = HttpRepository(
          'http://127.0.0.1:${settings['SERVER_PORT']}/api',
          token,
        );
        clients.add(r);
        return r;
      }

      addTearDown(() {
        for (final r in clients) {
          r.dio.close(force: true);
        }
      });
      late HttpRepository admin, employee;
      final reviewers = <String, HttpRepository>{};
      late Session adminSession, employeeSession;
      late String department, account, logId;
      late Record submitted;
      await t.runAsync(() async {
        final public = client(null);
        final saved = File('${directory.path}/demo-accounts.json');
        final prior = saved.existsSync()
            ? jsonDecode(saved.readAsStringSync()) as Map
            : {};
        final login = await public.execute(
          'auth',
          Command('login', {
            '账号': settings['ADMIN_ACCOUNT'],
            '密码': prior['adminPassword'] ?? settings['ADMIN_PASSWORD'],
          }),
        );
        admin = client(login.fields['accessToken'] as String);
        adminSession = Session.fromRecord(
          await admin.detail('auth', 'me'),
          token: login.fields['accessToken'] as String,
        );
        reviewers[adminSession.id] = admin;
        if (prior['employeeAccount'] != null) {
          final reviewerLogin = await public.execute(
            'auth',
            Command('login', {
              '账号': prior['employeeAccount'],
              '密码': prior['employeePassword'],
            }),
          );
          final reviewer = client(
            reviewerLogin.fields['accessToken'] as String,
          );
          reviewers[(await reviewer.detail('auth', 'me')).id] = reviewer;
        }
        expect(
          adminSession.mustChangePassword,
          false,
          reason: 'Run member_b_real_backend_test first',
        );
        final departments = (await public.dio.get<List<dynamic>>(
          '/auth/departments',
        )).data!;
        department = '${(departments.first as Map)['id']}';
        final stamp = DateTime.now().millisecondsSinceEpoch.toString();
        account = 'log-b-$stamp';
        final password = 'Log-$stamp-Strong!';
        final registered = await public.execute(
          'auth',
          Command('register', {
            '账号': account,
            '密码': password,
            '手机号': '137${stamp.substring(stamp.length - 8)}',
            '姓名': '日志联调员工',
            'departmentId': department,
          }),
        );
        await admin.execute(
          'reviews',
          Command('approve', {'id': registered.fields['reviewId']}),
        );
        final employeeLogin = await public.execute(
          'auth',
          Command('login', {'账号': account, '密码': password}),
        );
        employee = client(employeeLogin.fields['accessToken'] as String);
        employeeSession = Session.fromRecord(
          await employee.detail('auth', 'me'),
          token: employeeLogin.fields['accessToken'] as String,
        );
        final today = DateTime.now();
        for (var i = 0; i < 31; i++) {
          final date = today
              .subtract(Duration(days: i))
              .toIso8601String()
              .split('T')
              .first;
          final value = await employee.execute(
            'logs',
            Command('submit', {
              'businessDate': date,
              '今日工作': '真实日志内容$i',
              '工时': '1',
            }),
          );
          if (i == 0) {
            logId = value.id;
            submitted = await employee.detail('logs', logId);
          }
        }
        final all = await readCompleteList(
          admin,
          'logs/subordinates',
          Query(departmentId: department, search: account),
        );
        expect(all.items.length, 31);
        expect(all.items.every((r) => r.ownerId == employeeSession.id), true);
        expect(
          (await admin.list(
            'logs/subordinates',
            Query(departmentId: 'unknown', search: account),
          )).items,
          isEmpty,
        );
        await expectLater(
          employee.list('logs/subordinates', const Query()),
          throwsA(isA<ApiFailure>()),
        );
        final comment = await admin.execute(
          'logs/comments',
          Command('comment', {'id': logId, 'text': '真实评论'}),
        );
        await employee.execute(
          'logs/comments',
          Command('comment', {
            'id': logId,
            'text': '真实回复',
            'parentCommentId': comment.id,
          }),
        );
        final detail = await employee.detail('logs', logId);
        expect(
          (detail.fields['comments'] as List).any(
            (c) => c['parentId'] == comment.id,
          ),
          true,
        );
      });

      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final container = testContainer(
        overrides: [
          repositoryProvider.overrideWith(
            (ref) => ref.watch(sessionProvider).id == employeeSession.id
                ? employee
                : admin,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).state = adminSession;
      container.read(logFilterDateProvider.notifier).state = null;
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: UncontrolledProviderScope(
            container: container,
            child: const PandoraApp(),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      container.read(routerProvider).go('/logs/subordinates');
      await settle();
      await t.enterText(find.byType(TextField).first, account);
      await settle();
      expect(find.byKey(ValueKey('diary-row:$logId')), findsOneWidget);
      final filter = find.byKey(const ValueKey('log-department:全部部门'));
      await t.tap(filter);
      await settle();
      final departmentName = await t.runAsync(
        () async =>
            (await admin.list(
                  'logs/subordinates',
                  Query(search: account),
                )).items.first.fields['departmentName']
                as String,
      );
      await t.tap(find.text(departmentName!).last);
      await settle();
      expect(container.read(subordinateLogFilterProvider).$1, department);
      expect(find.byKey(ValueKey('diary-row:$logId')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 1);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/subordinate-logs-live.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });

      container.read(sessionProvider.notifier).state = employeeSession;
      container
          .read(routerProvider)
          .go('/form/log-revise?id=$logId&version=${submitted.version}');
      await settle();
      await t.enterText(find.byType(TextFormField).first, '修订后的真实工作');
      final reason = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '填写修改理由',
      );
      await t.scrollUntilVisible(
        reason,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(reason, '补充验收情况');
      await t.tap(find.text('提交修订申请'));
      await settle();
      await t.runAsync(() async {
        expect(
          (await employee.detail('logs', logId)).fields['今日工作'],
          '真实日志内容0',
        );
        final reviews = await readCompleteList(
          employee,
          'reviews',
          const Query(),
        );
        final pending = reviews.items.singleWhere(
          (r) =>
              r.fields['targetId'] == logId && r.fields['reviewState'] == '待审',
        );
        await expectLater(
          employee.execute('reviews', Command('approve', {'id': pending.id})),
          throwsA(isA<ApiFailure>()),
        );
        final review = await employee.detail('reviews', pending.id);
        for (final step in review.fields['steps'] as List) {
          final reviewer = reviewers['${step['reviewer_id']}'];
          expect(
            reviewer,
            isNotNull,
            reason: 'Use a fresh isolated fixture database',
          );
          await reviewer!.execute(
            'reviews',
            Command('approve', {'id': pending.id}),
          );
        }
        expect(
          (await employee.detail('logs', logId)).fields['今日工作'],
          '修订后的真实工作',
        );
      });
      container.invalidate(itemProvider);
      container.read(routerProvider).go('/item/logs/$logId');
      await settle();
      final withdraw = find.text('撤回日志');
      await t.ensureVisible(withdraw);
      await t.tap(withdraw);
      await settle();
      await t.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText?.startsWith('撤回原因') ?? false),
        ),
        '补充附件',
      );
      await t.tap(find.text('撤回日志').last);
      await settle();
      await t.runAsync(() async {
        final draft = await employee.detail('logs', logId);
        expect(draft.fields['submitted'], false);
        expect(draft.fields['submittedAt'], submitted.fields['submittedAt']);
        expect(
          (await admin.list('logs/subordinates', Query(search: account))).total,
          30,
        );
        await employee.execute(
          'logs',
          Command('submit', {'id': logId}, version: draft.version),
        );
        expect(
          (await employee.detail('logs', logId)).fields['submittedAt'],
          submitted.fields['submittedAt'],
        );
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
    skip: Platform.environment['RUN_STAGE_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
