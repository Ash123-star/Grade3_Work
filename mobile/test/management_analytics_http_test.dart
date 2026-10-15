import 'support/flutter_sdk_assets.dart';
import 'support/local_test_state.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/dashboard/server_analytics_page.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class ManagementAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int mutationStatus = 200,
      summaryStatus = 200,
      profileStatus = 200,
      auditStatus = 200;
  final profile = <String, dynamic>{
    'id': 'staff',
    'name': '橙子',
    'role': 'EMPLOYEE',
    'status': 'PENDING',
    'department_id': 'dept',
    'team_id': 'team',
    'dispatch_enabled': true,
    'company_reviewer': false,
    'version': 7,
    'profile': {'introduction': '认真记录每天的进展'},
  };
  final summary = <String, dynamic>{
    'dispatched': 12,
    'overdue': 2,
    'onTimeAcceptance': {
      'numerator': 3,
      'denominator': 4,
      'rate': 0.75,
      'definition': '授权任务按期验收',
    },
    'dailySubmission': {
      'numerator': 0,
      'denominator': 0,
      'rate': 0,
      'definition': '成员自然日口径',
    },
    'departmentDistribution': [
      {'department_id': 'dept', 'dispatched': 12},
    ],
    'unreadLogs': 3,
    'updatedAt': '2026-10-13T08:00:00Z',
    'range': {'first': '2026-10-01', 'end': '2026-11-01'},
  };
  final csv = utf8.encode('\uFEFF姓名,内容\n橙子,完成验收\n');
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(o);
    var status = 200;
    dynamic data = {'items': [], 'total': 0};
    if (o.path == '/organization') {
      data = {
        'departments': [
          {'id': 'dept', 'name': '产品部', 'version': 4},
          {'id': 'empty', 'name': '空部门', 'version': 2},
        ],
        'teams': [
          {'id': 'team', 'name': '体验团队', 'department_id': 'dept', 'version': 3},
        ],
        'users': {'items': [], 'total': 2},
      };
    } else if (o.path == '/organization/people') {
      data = {
        'items': [
          o.queryParameters['cursor'] == '30'
              ? {
                  'id': 'later',
                  'name': '第二页成员',
                  'department_id': 'dept',
                  'team_id': 'team',
                  'version': 1,
                }
              : {...profile},
        ],
        'total': 2,
        'nextCursor': '30',
      };
    } else if (o.path == '/profiles/staff') {
      status = profileStatus;
      data = {...profile};
    } else if (o.path == '/organization/review-policy') {
      data = {
        'version': 9,
        'review_policy': {
          'taskTeamReview': true,
          'taskDepartmentReview': false,
        },
      };
    } else if (o.path.endsWith('/revisions')) {
      status = mutationStatus;
      data = status == 200
          ? {
              'id': 'request',
              'kind': 'USER',
              'applicant_id': 'admin',
              'target_id': 'staff',
              'status': 'PENDING',
              'version': 1,
            }
          : {'code': status == 409 ? 'CONFLICT' : 'FORBIDDEN'};
    } else if (o.path == '/analytics') {
      status = summaryStatus;
      data = summary;
    } else if (o.path == '/analytics/export') {
      return ResponseBody.fromBytes(
        csv,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/csv; charset=utf-8'],
        },
      );
    } else if (o.path == '/organization/audit') {
      status = auditStatus;
      data = {
        'items': [
          o.queryParameters['cursor'] == '30'
              ? {
                  'id': 99,
                  'type': 'USER_REVISED',
                  'actor_id': 'admin',
                  'object_id': 'staff',
                  'before_value': '{"role":"EMPLOYEE"}',
                  'after_value': {'role': 'LEADER'},
                  'reason': '组织调整',
                  'created_at': '2026-10-13T08:00:00Z',
                }
              : {
                  'id': 100,
                  'type': 'TASK_DISPATCHED',
                  'actor_id': 'admin',
                  'object_id': 'task',
                },
        ],
        'total': 2,
        'nextCursor': '30',
      };
    } else if (o.path == '/reviews/rejected') {
      data = {
        'id': 'rejected',
        'kind': 'USER',
        'target_id': 'staff',
        'applicant_id': 'admin',
        'status': 'REJECTED',
        'candidate': {'role': 'LEADER'},
        'before_value': {'role': 'EMPLOYEE'},
        'steps': [],
      };
    }
    if (status >= 400) {
      data = {'code': status == 409 ? 'CONFLICT' : 'FORBIDDEN'};
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const admin = Session(
  id: 'admin',
  name: '管理员',
  role: UserRole.admin,
  token: 'token',
);
void main() {
  late ManagementAdapter adapter;
  late HttpRepository repo;
  setUp(() {
    adapter = ManagementAdapter();
    repo = HttpRepository('http://localhost/api', 'token');
    repo.dio.httpClientAdapter = adapter;
  });
  Matcher failure(FailureKind kind) =>
      isA<ApiFailure>().having((e) => e.kind, 'kind', kind);
  test(
    'organization retains empty actual units, pages people, reads current profile permissions',
    () async {
      final tree = await repo.detail('organization/tree', 'tree');
      expect((tree.fields['departments'] as List).length, 2);
      expect((tree.fields['people'] as List<Record>).map((r) => r.id), [
        'staff',
        'later',
      ]);
      expect(
        adapter.requests
            .where((o) => o.path == '/organization/people')
            .last
            .queryParameters['cursor'],
        '30',
      );
      final profile = await repo.detail('organization/profile', 'staff');
      expect(profile.version, 7);
      expect(profile.fields['dispatch_enabled'], isTrue);
      expect(profile.fields['个人介绍'], '认真记录每天的进展');
      expect(adapter.requests.last.path, '/profiles/staff');
    },
  );
  test(
    'unit, user and policy submit candidate fields and versions; invalid input sends no request',
    () async {
      await repo.execute(
        'organization/admin',
        const Command('unit', {
          'kind': 'teams',
          'name': '新团队',
          'departmentId': 'dept',
          'reason': '扩充',
        }, version: 0),
      );
      expect(adapter.requests.last.path, '/organization/teams/revisions');
      expect(adapter.requests.last.data, {
        'id': '',
        'name': '新团队',
        'departmentId': 'dept',
        'version': 0,
        'reason': '扩充',
      });
      await repo.execute(
        'organization/admin',
        const Command('user', {
          'id': 'staff',
          'role': 'LEADER',
          'dispatchEnabled': false,
          'companyReviewer': true,
          'reason': '调整',
          'ignored': 'never',
        }, version: 7),
      );
      expect(adapter.requests.last.path, '/organization/users/staff/revisions');
      expect((adapter.requests.last.data as Map).keys.toSet(), {
        'role',
        'dispatchEnabled',
        'companyReviewer',
        'version',
        'reason',
      });
      await repo.execute(
        'organization/admin',
        const Command('policy', {
          'taskTeamReview': false,
          'taskDepartmentReview': true,
          'reason': '调整',
        }, version: 9),
      );
      expect(
        adapter.requests.last.path,
        '/organization/review-policy/revisions',
      );
      expect((adapter.requests.last.data as Map)['version'], 9);
      final count = adapter.requests.length;
      for (final c in [
        const Command('user', {
          'id': 'staff',
          'role': 'INVALID',
          'reason': 'x',
        }, version: 7),
        const Command('unit', {
          'kind': 'teams',
          'name': 'x',
          'reason': 'x',
        }, version: 0),
        const Command('policy', {
          'taskTeamReview': true,
          'taskDepartmentReview': false,
          'reason': '',
        }, version: 9),
      ]) {
        await expectLater(
          repo.execute('organization/admin', c),
          throwsA(failure(FailureKind.validation)),
        );
      }
      expect(adapter.requests.length, count);
      expect(adapter.profile['role'], 'EMPLOYEE');
    },
  );
  test(
    'analytics is a date/period object and CSV preserves exact bytes and query scope',
    () async {
      final summary = await repo.detail(
        'analytics',
        '2026-10-12',
        ownerId: 'month',
      );
      expect(summary.fields['dispatched'], 12);
      expect(adapter.requests.last.queryParameters, {
        'date': '2026-10-12',
        'period': 'month',
      });
      final export = await repo.execute(
        'analytics/export',
        const Command('export', {
          'date': '2026-10-12',
          'period': 'month',
          'resource': 'tasks',
        }),
      );
      expect(export.fields['bytes'], adapter.csv);
      expect(adapter.requests.last.queryParameters, {
        'date': '2026-10-12',
        'period': 'month',
        'resource': 'tasks',
      });
      await expectLater(
        repo.execute('analytics/export', const Command('export', {})),
        throwsA(failure(FailureKind.validation)),
      );
    },
  );
  test(
    'audit detail resolves later authorized page and fails safely when absent or denied',
    () async {
      final audit = await repo.detail('audit', '99');
      expect(audit.fields['auditType'], '组织');
      expect(audit.fields['before'], {'role': 'EMPLOYEE'});
      expect(audit.fields['after'], {'role': 'LEADER'});
      expect(
        adapter.requests.every((o) => o.path == '/organization/audit'),
        isTrue,
      );
      await expectLater(
        repo.detail('audit', 'missing'),
        throwsA(failure(FailureKind.notFound)),
      );
      adapter.auditStatus = 403;
      await expectLater(
        repo.detail('audit', '99'),
        throwsA(failure(FailureKind.forbidden)),
      );
    },
  );
  test(
    'mock organization creates review without mutating effective member',
    () async {
      final mock = MockRepository(admin);
      final before = await mock.detail('organization/profile', 'u2');
      final request = await mock.execute(
        'organization/admin',
        Command('user', {
          'id': 'u2',
          'role': 'LEADER',
          'reason': '调整',
        }, version: before.version),
      );
      expect(request.fields['reviewState'], '待审');
      expect(
        (await mock.detail('organization/profile', 'u2')).fields['role'],
        before.fields['role'],
      );
    },
  );
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
  }

  Future<ProviderContainer> launch(
    WidgetTester t,
    String route, {
    CsvSaver? saver,
    GlobalKey? boundary,
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = testContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => admin),
        fontScaleProvider.overrideWith((ref) => scale),
        selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 12)),
        periodProvider.overrideWith((ref) => '月'),
        repositoryProvider.overrideWith((ref) {
          final r = ref.watch(httpRepositoryProvider);
          r.dio.httpClientAdapter = adapter;
          return r;
        }),
        if (saver != null) csvSaverProvider.overrideWithValue(saver),
      ],
    );
    addTearDown(c.dispose);
    c.read(routerProvider).go(route);
    Widget app = UncontrolledProviderScope(
      container: c,
      child: const PandoraApp(),
    );
    if (boundary != null) app = RepaintBoundary(key: boundary, child: app);
    await t.pumpWidget(app);
    await settle(t);
    return c;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }

  Future<void> fillReason(WidgetTester t) async {
    final f = find.byType(TextFormField).last;
    await t.ensureVisible(f);
    await t.enterText(f, '保留组织调整理由');
    t.testTextInput.hide();
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t) async {
    await t.tap(find.widgetWithText(FilledButton, '提交候选修改'));
    await settle(t);
  }

  testWidgets(
    'role reads current version; conflict retains input; cancel reload preserves;403 clears',
    (t) async {
      final c = await launch(t, '/form/role?id=staff');
      expect(find.text('橙子 · v7'), findsOneWidget);
      await fillReason(t);
      adapter.mutationStatus = 409;
      await submit(t);
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        '保留组织调整理由',
      );
      await t.ensureVisible(find.text('重新读取当前配置').last);
      await t.pumpAndSettle();
      await t.tap(find.text('重新读取当前配置').last);
      await t.pumpAndSettle();
      expect(find.text('重新读取当前配置？'), findsOneWidget);
      await t.tap(find.text('保留输入'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        '保留组织调整理由',
      );
      adapter.profileStatus = 403;
      c.read(routerProvider).go('/form/role?id=staff&reload=1');
      await settle(t);
      expect(find.text('暂无管理权限'), findsOneWidget);
      expect(find.text('橙子 · v7'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await close(t);
    },
  );
  testWidgets(
    'membership uses actual organization IDs and keeps pending current config after candidate',
    (t) async {
      await launch(t, '/form/membership?id=staff');
      await submit(t);
      expect(find.text('请填写变更理由'), findsOneWidget);
      expect(adapter.requests.where((o) => o.method == 'POST'), isEmpty);
      await fillReason(t);
      await submit(t);
      final body =
          adapter.requests.lastWhere((o) => o.method == 'POST').data as Map;
      expect(body, {
        'departmentId': 'dept',
        'teamId': 'team',
        'status': 'ACTIVE',
        'version': 7,
        'reason': '保留组织调整理由',
      });
      expect(find.text('候选已提交'), findsOneWidget);
      expect(adapter.profile['status'], 'PENDING');
      await close(t);
    },
  );
  testWidgets(
    'policy loads actual switches and submits only supported routing flags',
    (t) async {
      await launch(t, '/form/policy');
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile).at(1)).value,
        isFalse,
      );
      await fillReason(t);
      await submit(t);
      expect(adapter.requests.lastWhere((o) => o.method == 'POST').data, {
        'taskTeamReview': true,
        'taskDepartmentReview': false,
        'version': 9,
        'reason': '保留组织调整理由',
      });
      await close(t);
    },
  );
  testWidgets(
    'statistics shows actual four metrics, zero denominator, definition and forbidden recovery',
    (t) async {
      final c = await launch(t, '/export');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: const ServerAnalyticsPage(),
          ),
        ),
      );
      await settle(t);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
      expect(find.text('暂无'), findsOneWidget);
      await t.ensureVisible(find.text('按期验收率'));
      await t.tap(find.text('按期验收率'));
      await t.pumpAndSettle();
      expect(find.textContaining('分子 3 / 分母 4'), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      adapter.summaryStatus = 403;
      await t.runAsync(() async {
        c.invalidate(analyticsSummaryProvider);
      });
      await settle(t);
      expect(find.text('75.0%'), findsNothing);
      expect(find.textContaining('没有访问'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets(
    'CSV saver gets selected date and bytes, canceled/save error never reports success',
    (t) async {
      String? filename;
      List<int>? saved;
      var mode = 0;
      await launch(
        t,
        '/export',
        saver: (name, bytes) async {
          filename = name;
          saved = bytes;
          if (mode == 2) throw const FileSystemException('write failed');
          return mode == 0 ? '/tmp/report.csv' : null;
        },
      );
      for (final i in [0, 1, 2]) {
        mode = i;
        await t.tap(find.text('导出并保存CSV'));
        await settle(t);
        if (i == 0) {
          expect(find.textContaining('报表已保存'), findsOneWidget);
        } else {
          expect(find.textContaining('报表已保存'), findsNothing);
          expect(
            find.textContaining(i == 1 ? '已取消保存' : '导出未完成'),
            findsOneWidget,
          );
        }
      }
      expect(filename, 'logs-2026-10-12-month.csv');
      expect(saved, adapter.csv);
      expect(adapter.requests.last.queryParameters, {
        'date': '2026-10-12',
        'period': 'month',
        'resource': 'logs',
      });
      await close(t);
    },
  );
  testWidgets(
    'organization preserves empty units and rejected management has no company resubmit',
    (t) async {
      final c = await launch(t, '/me/organization');
      expect(find.text('空部门'), findsOneWidget);
      expect(find.text('第二页成员'), findsOneWidget);
      c.read(routerProvider).go('/me/reviews/rejected');
      await settle(t);
      expect(find.text('修改后重新提交'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'management/statistics/audit renders use real-shaped responses at390dp and1.5 text',
    (t) async {
      final fonts = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync(),
            ),
          ),
        );
      await fonts.load();
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
      final key = GlobalKey();
      final c = await launch(t, '/form/department', boundary: key, scale: 1.5);
      for (final (label, path) in [
        ('24-unit', '/form/department'),
        ('25-membership', '/form/membership?id=staff'),
        ('26-role', '/form/role?id=staff'),
        ('27-policy', '/form/policy'),
        ('28-export', '/export'),
        ('29-audit', '/item/audit/99'),
      ]) {
        c.read(routerProvider).go(path);
        await settle(t);
        expect(t.takeException(), isNull, reason: label);
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final img = await render.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/evidence/stage3-rebuild/$label.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.5)),
                child: child!,
              ),
              home: const ServerAnalyticsPage(),
            ),
          ),
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await render.toImage(pixelRatio: 1);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          'docs/evidence/stage3-rebuild/30-server-statistics.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        img.dispose();
      });
      await close(t);
    },
  );
}
