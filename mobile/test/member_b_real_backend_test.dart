import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

/// 显式启用的真实 HTTP 联调；仅使用独立 stage-demo 环境，不使用 Mock Adapter。
void main() {
  final enabled = Platform.environment['RUN_STAGE_INTEGRATION'] == '1';
  test(
    '真实 Flutter Repository 完成注册、独立确认、组织候选与审核生效',
    () async {
      HttpOverrides.global = null;
      final dir = Directory(Platform.environment['STAGE_DEMO_DIRECTORY']!);
      final settings = <String, String>{
        for (final line in File('${dir.path}/stage.env').readAsLinesSync())
          if (line.contains('='))
            line.split('=').first: line.substring(line.indexOf('=') + 1),
      };
      final saved = File('${dir.path}/demo-accounts.json');
      final prior = saved.existsSync()
          ? jsonDecode(saved.readAsStringSync()) as Map
          : <String, dynamic>{};
      final base = 'http://127.0.0.1:${settings['SERVER_PORT']}/api';
      final clients = <HttpRepository>[];
      HttpRepository client(String? token) {
        final value = HttpRepository(base, token);
        clients.add(value);
        return value;
      }

      final public = client(null);
      var adminPassword =
          prior['adminPassword'] as String? ?? settings['ADMIN_PASSWORD']!;
      final login = await public.execute(
        'auth',
        Command('login', {
          '账号': settings['ADMIN_ACCOUNT'],
          '密码': adminPassword,
        }),
      );
      final admin = client(login.fields['accessToken'] as String);
      if (login.fields['must_change_password'] == true) {
        final next = 'Changed!${adminPassword.substring(0, 48)}';
        await admin.execute(
          'auth',
          Command('password', {'原密码': adminPassword, '新密码': next}),
        );
        adminPassword = next;
        saved.writeAsStringSync(jsonEncode({'adminPassword': adminPassword}));
      }
      try {
        final departments = (await public.dio.get<List<dynamic>>(
          '/auth/departments',
        )).data!;
        final department = (departments.first as Map)['id'];
        final stamp = DateTime.now().millisecondsSinceEpoch.toString();
        final account = 'demo-b-$stamp', password = 'Demo-${stamp}Strong!';
        final registration = await public.execute(
          'auth',
          Command('register', {
            '账号': account,
            '密码': password,
            '手机号': '136${stamp.substring(stamp.length - 8)}',
            '姓名': 'B阶段演示员工',
            'departmentId': department,
          }),
        );
        expect(registration.fields['status'], 'PENDING');
        final employeeLogin = await public.execute(
          'auth',
          Command('login', {'账号': account, '密码': password}),
        );
        final employee = client(employeeLogin.fields['accessToken'] as String);
        await expectLater(
          employee.list('organization', const Query()),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.code,
              'code',
              'MEMBERSHIP_PENDING',
            ),
          ),
        );
        final membership = registration.fields['reviewId'] as String;
        await expectLater(
          employee.execute('reviews', Command('approve', {'id': membership})),
          throwsA(isA<ApiFailure>()),
        );
        await admin.execute('reviews', Command('approve', {'id': membership}));
        var me = await employee.detail('auth', 'me');
        expect(me.fields['status'], 'ACTIVE');
        // 复核职责申请尚无客户端表单，使用同一个真实客户端公开 HTTP 入口。
        final request = (await employee.dio.post<Map<String, dynamic>>(
          '/organization/reviewer-application',
          data: {'version': me.version, 'reason': '阶段展示独立审核'},
        )).data!;
        await admin.execute(
          'reviews',
          Command('approve', {'id': request['id']}),
        );
        me = await employee.detail('auth', 'me');
        expect(me.fields['company_reviewer'], true);
        final unit = await admin.execute(
          'organization/admin',
          Command('unit', {
            'kind': 'departments',
            'name': '阶段展示部门$stamp',
            'reason': '真实客户端组织审核',
          }, version: 0),
        );
        final candidate = await admin.detail('reviews', unit.id);
        expect(candidate.fields['reviewState'], '待审');
        await expectLater(
          admin.execute('reviews', Command('approve', {'id': unit.id})),
          throwsA(isA<ApiFailure>()),
        );
        await employee.execute('reviews', Command('approve', {'id': unit.id}));
        final approved = await admin.detail('reviews', unit.id);
        expect(approved.fields['reviewState'], '已通过');
        final units = (await admin.dio.get<List<dynamic>>(
          '/organization/departments',
        )).data!;
        expect(
          units.any((value) => (value as Map)['name'] == '阶段展示部门$stamp'),
          true,
        );
        await expectLater(
          employee.execute('reviews', Command('approve', {'id': unit.id})),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.conflict,
            ),
          ),
        );
        await employee.execute('auth', const Command('logout', {}));
        await expectLater(
          employee.detail('auth', 'me'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.unauthorized,
            ),
          ),
        );
        saved.writeAsStringSync(
          jsonEncode({
            'adminPassword': adminPassword,
            'employeeAccount': account,
            'employeePassword': password,
          }),
        );
        File('${dir.path}/flutter-integration-result.json').writeAsStringSync(
          jsonEncode({
            'passed': true,
            'time': DateTime.now().toIso8601String(),
            'reviewId': unit.id,
            'mock': false,
          }),
        );
      } finally {
        for (final repository in clients) {
          repository.dio.close(force: true);
        }
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
