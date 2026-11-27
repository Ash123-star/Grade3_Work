import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/crm/crm_demo_store.dart';
import 'package:pandora_mobile/routing/app_router.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

import 'support/flutter_sdk_assets.dart';

void main() {
  testWidgets('正式构建注册客户目录，遵守登录和待确认限制，不解析本地客户数据', (tester) async {
    final container = ProviderContainer(
      overrides: [
        crmDemoProvider.overrideWith((ref) => throw StateError('正式入口不可加载本地数据')),
      ],
    );
    addTearDown(container.dispose);
    final session = container.read(sessionProvider.notifier);
    final router = container.read(routerProvider);
    void routeToDirectory(Session identity) {
      session.state = identity;
      router.go('/crm/customers');
    }

    routeToDirectory(const Session(active: false));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: appTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/auth/login');
    routeToDirectory(
      const Session(active: false, status: 'PENDING', token: 'fixture-token'),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/auth/pending');
    routeToDirectory(const Session(token: 'fixture-token'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/crm/customers');
    expect(find.text('无权访问客户目录'), findsOneWidget);
    expect(find.text('＋ 新增客户'), findsNothing);
    expect(find.text('林小满'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.mock);

  testWidgets('正式客户档案查重、保留重试键、处理冲突和服务端失权', (tester) async {
    final repository = HttpRepository('https://fixture.invalid/api', 'token');
    final fixture = _CustomerFixture();
    repository.dio.interceptors.add(
      InterceptorsWrapper(onRequest: fixture.handle),
    );
    final container = ProviderContainer(
      overrides: [httpRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).state = const Session(
      id: 'admin',
      role: UserRole.admin,
      token: 'token',
    );
    final router = container.read(routerProvider)..go('/crm/customers');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: appTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(String label) async {
      final finder = find.text(label);
      if (finder.hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(finder.last);
        await tester.pumpAndSettle();
      }
      await tester.tap(finder.hitTestable().last);
      await tester.pumpAndSettle();
    }

    await tap('新增客户');
    await tap('企业客户');
    await tester.enterText(find.widgetWithText(TextFormField, '客户名称'), '山海工作室');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tap('新增联系人');
    await tester.enterText(find.widgetWithText(TextFormField, '联系人姓名'), '王联系人');
    await tap('保存');
    await tap('保存档案');
    await tap('取消');
    expect(fixture.creates, hasLength(1));
    expect(find.text('王联系人'), findsOneWidget);
    await tap('保存档案');
    await tap('仍然建档');
    expect(find.text('新增客户'), findsOneWidget);
    await tap('保存档案');
    expect(fixture.creates, hasLength(4));
    expect(fixture.creates.take(2).toSet(), hasLength(1));
    expect(fixture.creates.skip(2).toSet(), hasLength(1));
    expect(fixture.creates.first, isNot(fixture.creates.last));
    expect(find.text('王联系人'), findsOneWidget);

    await tap('编辑档案');
    await tester.enterText(
      find.widgetWithText(TextFormField, '客户名称'),
      '未保存的名称',
    );
    await tap('保存档案');
    expect(find.text('这条记录已更新，请返回详情查看最新版本。'), findsOneWidget);
    expect(find.text('未保存的名称'), findsOneWidget);
    await tap('读取新版');
    await tap('读取新版');
    expect(find.text('新版工作室'), findsOneWidget);
    expect(fixture.versions, [1]);
    await tap('保存档案');
    expect(fixture.versions, [1, 2]);

    await tap('会员');
    await tap('体验权益');
    await tap('核销一次');
    await tester.enterText(find.widgetWithText(TextFormField, '核销说明'), '到店使用');
    await tap('确认核销');
    expect(find.text('到店使用'), findsOneWidget);
    expect(find.text('0 次'), findsOneWidget);
    expect(find.text('核销一次'), findsNothing);
    expect(fixture.redemptions, hasLength(1));
    router.pop();
    await tester.pumpAndSettle();

    await tap('业务');
    await tap('商城订单');
    await tap('订单 O-12');
    expect(find.text('CNY 50.00'), findsOneWidget);
    expect(fixture.orderScopes.last, containsPair('customerId', 'company'));
    expect(fixture.orderScopes.last, containsPair('externalOrderId', 'O-12'));
    router.pop();
    await tester.pumpAndSettle();
    fixture.denied = true;
    await tap('订单 O-12');
    expect(find.text('无权访问客户目录'), findsOneWidget);
    expect(find.text('CNY 50.00'), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.mock);

  testWidgets('正式管理员在小屏登记、申请、查看审批及从员工入口打开同一记录', (tester) async {
    const evidence = String.fromEnvironment('DELIVERY_SCREENSHOTS');
    const width = int.fromEnvironment('DELIVERY_TEST_WIDTH', defaultValue: 320);
    await tester.binding.setSurfaceSize(
      Size(width.toDouble(), evidence.isEmpty ? 650 : 880),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    if (evidence.isNotEmpty) {
      for (final (family, path) in [
        ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
        ('TuantuanDisplay', 'assets/fonts/GenSenRoundedTW-B.ttf'),
        ('MaterialIcons', materialIconsFontPath),
      ]) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
            ))
            .load();
      }
    }
    Future<void> capture(String name) async {
      if (evidence.isEmpty) return;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          Directory(evidence).createSync(recursive: true);
          File(
            '$evidence/$name.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    final repository = HttpRepository(
      'https://fixture.invalid/api',
      'fixture-token',
    );
    final fixture = _DeliveryFixture();
    repository.dio.interceptors.add(
      InterceptorsWrapper(onRequest: fixture.handle),
    );
    final container = ProviderContainer(
      overrides: [
        httpRepositoryProvider.overrideWithValue(repository),
        crmDemoProvider.overrideWith((ref) => throw StateError('不可读取演示数据')),
      ],
    );
    addTearDown(container.dispose);
    final session = container.read(sessionProvider.notifier);
    session.state = const Session(
      id: 'applicant',
      role: UserRole.admin,
      token: 'fixture-token',
    );
    final router = container.read(routerProvider)..go('/crm/customers');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: appTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(String text) async {
      final target = find.text(text).hitTestable();
      if (target.evaluate().isEmpty) {
        await tester.ensureVisible(find.text(text).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(target.last);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.text('‹').hitTestable().last);
      await tester.pumpAndSettle();
    }

    await tap('雁山客户');
    await tap('业务');
    await tap('线下业务');
    await tap('登记线下业务');
    await tester.enterText(find.widgetWithText(TextFormField, '业务标题'), '现场参访');
    await tester.enterText(
      find.widgetWithText(TextFormField, '业务日期（YYYY-MM-DD）'),
      '2026-11-26',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tap('选择业务负责人');
    await tap('王负责人');
    await tap('登记');
    expect(fixture.create?['customerId'], 'customer');
    expect(fixture.create?['ownerId'], 'employee');
    expect(fixture.create?['kind'], 'COMPANY_VISIT');
    expect(find.text('确认交付'), findsNothing);
    expect(find.text('活动待结束'), findsOneWidget);
    expect(find.text('服务待交付'), findsOneWidget);
    await capture('01-activity-pending');

    await tap('结束活动');
    await tester.enterText(find.widgetWithText(TextFormField, '申请理由'), '活动完成');
    await tap('提交审核');
    expect(find.text('已有待审申请，请刷新记录。'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '活动完成'), findsOneWidget);
    await tap('提交审核');
    expect(fixture.keys.take(2).toSet(), hasLength(1));
    expect(find.text('结束活动待审，正式记录尚未改变。'), findsOneWidget);
    await capture('02-review-pending');
    await tap('查看审核申请');
    expect(fixture.reviewReads, isPositive);
    final reviewScroll = find.byType(Scrollable).hitTestable().first;
    await tester.scrollUntilVisible(
      find.textContaining('申请操作：结束活动'),
      180,
      scrollable: reviewScroll,
    );
    await tester.scrollUntilVisible(
      find.text('重新分配审核人'),
      180,
      scrollable: reviewScroll,
    );
    expect(find.text('暂无符合条件的直属管理员，申请保持待审'), findsOneWidget);
    expect(find.text('重新分配审核人'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('线下业务详情'), findsOneWidget);
    await tap('撤回申请');
    expect(fixture.withdrawals, 1);
    expect(find.text('查看审核申请'), findsNothing);
    await tap('结束活动');
    await tester.enterText(find.widgetWithText(TextFormField, '申请理由'), '活动完成');
    await tap('提交审核');
    expect(find.text('结束活动待审，正式记录尚未改变。'), findsOneWidget);

    fixture.endApproved = true;
    await tap('刷新记录');
    expect(find.text('活动已结束'), findsOneWidget);
    expect(find.text('服务待交付'), findsOneWidget);
    await tap('确认交付');
    await tester.enterText(
      find.widgetWithText(TextFormField, '申请理由'),
      '已交付给客户',
    );
    fixture.stale = true;
    await tap('提交审核');
    expect(find.text('这条记录已更新，请返回详情查看最新版本。'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '已交付给客户'), findsOneWidget);
    await capture('03-version-conflict');
    await tap('返回详情并刷新');
    await tap('确认交付');
    await tester.enterText(
      find.widgetWithText(TextFormField, '申请理由'),
      '已交付给客户',
    );
    await tap('提交审核');
    expect(fixture.lastChange?['action'], 'CONFIRM_DELIVERY');
    expect(fixture.lastChange?['version'], 3);
    expect(find.text('服务待交付'), findsOneWidget);
    expect(find.text('确认交付待审，正式记录尚未改变。'), findsOneWidget);
    fixture.delivered = true;
    await tap('刷新记录');
    expect(find.text('服务已交付'), findsOneWidget);
    expect(find.text('确认交付'), findsNothing);
    await capture('04-delivered');

    await back();
    await tap('待交付');
    expect(fixture.filters.last['pendingOnly'], true);
    await back();
    await back();
    await tap('员工视角');
    await tap('王负责人');
    await tap('现场参访');
    expect(fixture.filters.last['employeeId'], 'employee');
    expect(fixture.details.toSet(), {'/offline-deliveries/delivery'});
    expect(find.text('现场参访'), findsOneWidget);
    session.state = const Session(
      id: 'replacement',
      role: UserRole.employee,
      token: 'other-token',
    );
    await tester.pumpAndSettle();
    expect(find.text('现场参访'), findsNothing);
    expect(find.text('无权访问客户目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.mock);
}

class _CustomerFixture {
  final creates = <String>[];
  final versions = <int>[];
  final orderScopes = <Map<String, dynamic>>[];
  final redemptions = <Map<String, dynamic>>[];
  Map<String, dynamic>? customer;
  bool denied = false;

  void handle(RequestOptions req, RequestInterceptorHandler handler) {
    void answer(Object data, [int status = 200]) => handler.resolve(
      Response(requestOptions: req, statusCode: status, data: data),
    );
    void fail(int status, String code) => handler.reject(
      DioException.badResponse(
        statusCode: status,
        requestOptions: req,
        response: Response(
          statusCode: status,
          requestOptions: req,
          data: {'code': code, 'message': '请求未完成'},
        ),
      ),
    );
    switch ((req.method, req.path)) {
      case ('GET', '/customers'):
        answer({
          'items': [?customer],
          'total': customer == null ? 0 : 1,
        });
      case ('POST', '/customers'):
        final body = req.data as Map<String, dynamic>;
        creates.add(req.headers['Idempotency-Key'] as String);
        if (body['confirmDuplicate'] != true) {
          fail(409, 'CUSTOMER_POSSIBLE_DUPLICATE');
        } else if (creates.length == 3) {
          fail(503, 'UNAVAILABLE');
        } else {
          customer = {
            ...body,
            'id': 'company',
            'status': 'ACTIVE',
            'version': 1,
          };
          answer(customer!, 201);
        }
      case ('GET', '/customers/company'):
        answer({
          'customer': customer,
          'membership': {'mallMemberId': 'member'},
          'benefits': [
            {
              'id': 'trial',
              'name': '体验权益',
              'kind': 'OTHER',
              'status': 'ACTIVE',
              'validFrom': '2000-01-01',
              'validTo': '2099-12-31',
              'maxUses': 1,
            },
          ],
          'progress': [],
        });
      case ('PUT', '/customers/company'):
        final body = req.data as Map<String, dynamic>;
        versions.add(body['version'] as int);
        if (versions.length == 1) {
          customer = {...customer!, 'name': '新版工作室', 'version': 2};
          fail(409, 'VERSION_CONFLICT');
        } else {
          customer = {...customer!, ...body, 'version': 3};
          answer(customer!);
        }
      case ('GET', '/customers/company/benefits/trial/redemptions'):
        answer(redemptions);
      case ('POST', '/customers/company/benefits/trial/redemptions'):
        if (req.headers['Idempotency-Key'] == null || redemptions.isNotEmpty) {
          fail(409, 'BENEFIT_UNAVAILABLE');
        } else {
          final row = {
            ...req.data as Map<String, dynamic>,
            'redeemedAt': '2026-11-27T03:00:00Z',
          };
          redemptions.add(row);
          answer(row, 201);
        }
      case ('GET', '/commerce/orders'):
        orderScopes.add(req.queryParameters);
        if (denied) {
          fail(403, 'FORBIDDEN');
        } else {
          answer({
            'total': 1,
            'items': [
              {
                'externalOrderId': 'O-12',
                'currency': 'CNY',
                'amount': '50.00',
                'status': 'PAID',
                'orderedAt': '2026-11-26T03:00:00Z',
              },
            ],
          });
        }
      default:
        fail(500, 'UNEXPECTED_FIXTURE_REQUEST');
    }
  }
}

class _DeliveryFixture {
  Map? create, lastChange;
  bool endApproved = false;
  bool stale = false, versionBumped = false, delivered = false;
  int reviewReads = 0, withdrawals = 0;
  final keys = <String>[];
  final filters = <Map<String, dynamic>>[];
  final details = <String>[];
  final employee = {'id': 'employee', 'name': '王负责人', 'status': 'ACTIVE'};

  Map<String, dynamic> get record => {
    'id': 'delivery',
    'customerId': 'customer',
    'customerName': '雁山客户',
    'title': '现场参访',
    'kind': 'COMPANY_VISIT',
    'businessDate': '2026-11-26',
    'ownerId': 'employee',
    'ownerName': '王负责人',
    'participants': [],
    'participantDetails': [],
    'activityStatus': endApproved ? 'ENDED' : 'SCHEDULED',
    'deliveryStatus': delivered ? 'DELIVERED' : 'PENDING',
    'version': delivered
        ? 4
        : versionBumped
        ? 3
        : endApproved
        ? 2
        : 1,
    if (!delivered &&
        lastChange != null &&
        (!endApproved || lastChange?['action'] == 'CONFIRM_DELIVERY'))
      'pendingReview': {
        'id': 'request',
        'action': lastChange?['action'],
        'canOpen': true,
        'canWithdraw': true,
      },
  };

  void handle(RequestOptions req, RequestInterceptorHandler handler) {
    void answer(Object data, [int status = 200]) => handler.resolve(
      Response(requestOptions: req, statusCode: status, data: data),
    );
    void page(List<Map<String, dynamic>> items) =>
        answer({'items': items, 'total': items.length, 'nextCursor': null});
    switch (req.path) {
      case '/customers':
        page([
          {
            'id': 'customer',
            'name': '雁山客户',
            'kind': 'ENTERPRISE',
            'status': 'ACTIVE',
          },
        ]);
      case '/offline-deliveries/employees':
        page([employee]);
      case '/customers/customer':
        answer({
          'customer': {
            'id': 'customer',
            'name': '雁山客户',
            'kind': 'ENTERPRISE',
            'status': 'ACTIVE',
            'version': 1,
          },
          'membership': null,
          'benefits': [],
          'progress': [],
        });
      case '/offline-deliveries':
        if (req.method == 'POST') {
          create = req.data as Map;
          answer({'id': 'delivery', 'version': 1}, 201);
        } else {
          filters.add(req.queryParameters);
          page([
            if (create != null &&
                !(delivered && req.queryParameters['pendingOnly'] == true))
              record,
          ]);
        }
      case '/offline-deliveries/delivery':
        details.add(req.path);
        answer(record);
      case '/offline-deliveries/delivery/changes':
        keys.add(req.headers['Idempotency-Key'] as String);
        if (keys.length == 1 || stale) {
          final conflict = stale;
          if (conflict) {
            stale = false;
            versionBumped = true;
          }
          handler.reject(
            DioException.badResponse(
              statusCode: 409,
              requestOptions: req,
              response: Response(
                requestOptions: req,
                statusCode: 409,
                data: {
                  'code': conflict
                      ? 'VERSION_CONFLICT'
                      : 'DELIVERY_REVIEW_PENDING',
                  'message': conflict ? '版本已变化' : '该记录已有待审申请',
                },
              ),
            ),
          );
        } else {
          lastChange = req.data as Map;
          answer({
            'id': 'delivery',
            'reviewId': 'request',
            'status': 'PENDING',
          }, 202);
        }
      case '/reviews/request':
        reviewReads++;
        answer({
          'id': 'request',
          'kind': 'OFFLINE_DELIVERY',
          'target_id': 'delivery',
          'applicant_id': 'applicant',
          'status': 'PENDING',
          'expected_version': 1,
          'reason': '活动完成',
          'reviewer_configured': false,
          'before_value': record,
          'candidate': {
            'title': '现场参访',
            'action': 'END_ACTIVITY',
            'activityStatus': 'ENDED',
            'deliveryStatus': 'PENDING',
          },
        });
      case '/reviews/request/withdraw-offline':
        withdrawals++;
        lastChange = null;
        answer({'id': 'request', 'status': 'WITHDRAWN'});
      default:
        handler.reject(
          DioException(
            requestOptions: req,
            message: 'Unexpected ${req.method} ${req.path}',
          ),
        );
    }
  }
}
