import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

import 'support/local_test_state.dart';

class _MemberAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int profileStatus = 200;
  bool emptyLogs = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(request);
    var status = 200;
    dynamic body = {'items': [], 'total': 0};
    if (request.path == '/profiles/u2') {
      status = profileStatus;
      body = {
        'id': 'u2',
        'name': '陈一诺',
        'version': 3,
        'role': 'EMPLOYEE',
        'status': 'ACTIVE',
        'department_name': '产品部',
        'position': '产品专员',
        'phone': '13800138002',
        'email': 'chen@example.invalid',
        'profile': {'introduction': '认真记录与协作'},
      };
    } else if (request.path == '/logs/subordinates/calendar') {
      body = {
        'ownerId': request.queryParameters['ownerId'],
        'month': request.queryParameters['month'],
        'employmentStartDate': '2025-01-01',
        'days': {'30': 'MISSING', '31': 'SUBMITTED'},
      };
    } else if (request.path == '/logs/subordinates') {
      final date = request.queryParameters['date'];
      final hasLog = !emptyLogs && date == '2026-01-31';
      body = {
        'items': [
          if (hasLog)
            {
              'id': 'log-31',
              'title': '陈一诺的工作日志',
              'owner_id': 'u2',
              'business_date': date,
              'submitted': true,
              'version': 4,
              'body': {'work': '已完成的真实工作'},
            },
        ],
        'total': hasLog ? 1 : 0,
      };
    } else if (request.path == '/logs/log-31') {
      body = {
        'id': 'log-31',
        'title': '陈一诺的工作日志',
        'owner_id': 'u2',
        'business_date': '2026-01-31',
        'submitted': true,
        'version': 4,
        'body': {'work': '已完成的真实工作'},
      };
    } else if (request.path == '/tasks') {
      body = {
        'items': [
          {
            'id': 'task-31',
            'title': '成员日历任务',
            'owner_id': 'u2',
            'deadline': '2026-01-31T18:00:00+08:00',
            'start_at': '2026-01-29T09:00:00+08:00',
            'fields': {'content': '成员任务内容'},
          },
        ],
        'total': 1,
      };
    }
    if (status == 403) body = {'code': 'FORBIDDEN'};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> _launch(
  WidgetTester tester,
  _MemberAdapter adapter,
  String route, {
  Session session = const Session(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = HttpRepository('http://members.test/api', 'test-token')
    ..dio.httpClientAdapter = adapter;
  final container = testContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => session),
      repositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const PandoraApp()),
  );
  container.read(routerProvider).go(route);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('member workspace shows contact card and only logs/tasks filters', (tester) async {
    final adapter = _MemberAdapter();
    await _launch(tester, adapter, '/me/team/u2/logs?date=2026-01-31');

    expect(find.text('陈一诺'), findsOneWidget);
    expect(find.text('产品专员'), findsOneWidget);
    expect(find.text('产品部'), findsOneWidget);
    expect(find.text('13800138002'), findsOneWidget);
    await tester.ensureVisible(find.text('chen@example.invalid'));
    expect(find.text('chen@example.invalid'), findsOneWidget);
    expect(find.text('正在查看：陈一诺'), findsNothing);
    expect(find.text('返回本人面板'), findsNothing);
    expect(find.text('个人重点'), findsNothing);
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('重点'), findsNothing);
    expect(find.text('消息'), findsNothing);
    expect(
      adapter.requests.any(
        (request) => request.path == '/logs/subordinates/calendar' &&
            request.queryParameters['ownerId'] == 'u2' &&
            request.queryParameters['month'] == '2026-01',
      ),
      isTrue,
    );
  });

  testWidgets('submitted dates open matching log and missing dates show an empty state', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final adapter = _MemberAdapter();
    await _launch(tester, adapter, '/me/team/u2/logs?date=2026-01-31');

    await tester.tap(find.bySemanticsLabel('2026年1月31日，已提交日志'));
    await tester.pumpAndSettle();
    expect(find.text('已完成的真实工作'), findsOneWidget);
    expect(adapter.requests.any((request) => request.path == '/logs/log-31'), isTrue);

    final container = ProviderScope.containerOf(tester.element(find.text('已完成的真实工作')));
    container.read(routerProvider).go('/me/team/u2/logs?date=2026-01-31');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('2026年1月30日，未提交日志'));
    await tester.pumpAndSettle();
    expect(find.text('当日未提交日志'), findsOneWidget);
  });

  testWidgets('task calendar queries the selected member and displays their task', (tester) async {
    final adapter = _MemberAdapter();
    await _launch(tester, adapter, '/me/team/u2/tasks?date=2026-01-31');

    expect(find.text('成员日历任务'), findsOneWidget);
    final request = adapter.requests.lastWhere((item) => item.path == '/tasks');
    expect(request.queryParameters['ownerId'], 'u2');
    expect(request.queryParameters['from'], isNotNull);
    expect(request.queryParameters['to'], isNotNull);
  });

  testWidgets('revoked member scope clears protected contact details', (tester) async {
    final adapter = _MemberAdapter();
    final container = await _launch(tester, adapter, '/me/team/u2/logs');
    await tester.ensureVisible(find.text('chen@example.invalid'));
    expect(find.text('chen@example.invalid'), findsOneWidget);
    adapter.profileStatus = 403;
    container.invalidate(itemProvider(('organization/profile', 'u2')));
    await tester.pumpAndSettle();
    expect(find.text('chen@example.invalid'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
