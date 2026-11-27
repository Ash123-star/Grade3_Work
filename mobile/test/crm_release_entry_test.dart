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
