import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

/// Reuses explicitly supplied isolated-stage accounts; does not bypass rate limits.
void main() {
  test(
    '真实Repository日志提交、筛选、回复、直接编辑及权限拒绝',
    () async {
      HttpOverrides.global = null;
      final dir = Platform.environment['STAGE_DEMO_DIRECTORY']!;
      final config = <String, String>{
        for (final line in File('$dir/stage.env').readAsLinesSync())
          if (line.contains('='))
            line.split('=').first: line.substring(line.indexOf('=') + 1),
      };
      final accounts =
          jsonDecode(File('$dir/demo-accounts.json').readAsStringSync()) as Map;
      final clients = <HttpRepository>[];
      HttpRepository client(String? token) {
        final r = HttpRepository(
          'http://127.0.0.1:${config['SERVER_PORT']}/api',
          token,
        );
        clients.add(r);
        return r;
      }

      final public = client(null);
      try {
        Future<HttpRepository> login(String account, String password) async {
          final r = await public.execute(
            'auth',
            Command('login', {'账号': account, '密码': password}),
          );
          return client(r.fields['accessToken'] as String);
        }

        final admin = await login(
          config['ADMIN_ACCOUNT']!,
          accounts['adminPassword'] as String,
        );
        final employee = await login(
          accounts['employeeAccount'] as String,
          accounts['employeePassword'] as String,
        );
        final me = await employee.detail('auth', 'me');
        expect(me.fields['status'], 'ACTIVE');
        final instant = DateTime.now();
        final day = shanghaiWallTime(
          instant,
        ).toIso8601String().split('T').first;
        final diary = await employee.execute(
          'logs',
          Command('submit', {
            'businessDate': day,
            '今日工作': 'week6 real repository',
          }),
        );
        final first = diary.fields['submittedAt'];
        expect(diary.fields['canEdit'], true);
        expect(diary.fields['canWithdraw'], false);
        expect(
          DateTime.parse(
            '${diary.fields['editableUntil']}',
          ).difference(DateTime.parse('$first')).inHours,
          24,
        );
        final list = await admin.list(
          'logs/subordinates',
          Query(
            departmentId: '${me.fields['department_id']}',
            search: 'week6 real repository',
            from: instant,
          ),
        );
        expect(list.items.any((r) => r.id == diary.id), true);
        final comment = await admin.execute(
          'logs/comments',
          Command('comment', {'id': diary.id, 'text': 'review comment'}),
        );
        final reply = await employee.execute(
          'logs/comments',
          Command('comment', {
            'id': diary.id,
            'text': 'reply',
            'parentCommentId': comment.id,
          }),
        );
        final detail = await employee.detail('logs', diary.id);
        expect(
          (detail.fields['comments'] as List).whereType<Map>().any(
            (r) => r['id'] == reply.id && r['parentCommentId'] == comment.id,
          ),
          true,
        );
        await expectLater(
          employee.execute(
            'logs/comments',
            Command('comment', {'id': diary.id, 'text': ''}),
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.validation,
            ),
          ),
        );
        await expectLater(
          employee.list('logs/subordinates', const Query()),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.forbidden,
            ),
          ),
        );
        final edited = await employee.execute(
          'logs',
          Command('update-content', {
            'id': diary.id,
            'work': 'integration direct edit',
          }, version: diary.version),
        );
        expect(edited.fields['submittedAt'], first);
        expect(edited.fields['canWithdraw'], false);
        expect(edited.fields['今日工作'], 'integration direct edit');
      } finally {
        for (final r in clients) {
          r.dio.close(force: true);
        }
      }
    },
    skip: Platform.environment['RUN_STAGE_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
