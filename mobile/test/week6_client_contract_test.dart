import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';

void main() {
  late HttpRepository repository;
  late List<RequestOptions> requests;
  late Object response;
  setUp(() {
    requests = [];
    response = {'id': 'comment-1'};
    repository = HttpRepository('http://contract.invalid/api', 'test-token');
    repository.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          requests.add(r);
          h.resolve(
            Response(requestOptions: r, statusCode: 200, data: response),
          );
        },
      ),
    );
  });
  tearDown(() => repository.dio.close(force: true));

  test('组合筛选分页保留部门、日期、人员及字面关键词，映射组织信息', () async {
    repository.dio.interceptors.clear();
    repository.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          requests.add(r);
          h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: {
                'items': [
                  {
                    'id': 'log-${requests.length}',
                    'author': {'id': 'u', 'name': '员工'},
                    'department': {'id': 'dept', 'name': '技术部'},
                  },
                ],
                'total': 2,
                'nextCursor': '30',
              },
            ),
          );
        },
      ),
    );
    final result = await readCompleteList(
      repository,
      'logs/subordinates',
      Query(
        departmentId: 'dept',
        ownerId: 'u',
        search: 'a&b',
        from: DateTime.utc(2026, 10, 21, 16),
      ),
    );
    expect(requests, hasLength(2));
    for (final r in requests) {
      expect(r.path, '/logs/subordinates');
      expect(r.queryParameters, containsPair('departmentId', 'dept'));
      expect(r.queryParameters, containsPair('search', 'a&b'));
      expect(r.queryParameters, containsPair('date', '2026-10-22'));
      expect(r.queryParameters, containsPair('ownerId', 'u'));
    }
    expect(requests.last.queryParameters['cursor'], '30');
    expect(result.items.first.fields['departmentName'], '技术部');
    expect(result.items.first.fields['authorName'], '员工');
  });

  test('HCJ回复映射parentId，撤回使用独立路径和版本', () async {
    await repository.execute(
      'logs/comments',
      const Command('comment', {
        'id': 'log-1',
        'text': '回复',
        'parentCommentId': 'comment-0',
      }),
    );
    expect(requests.single.data, {'text': '回复', 'parentId': 'comment-0'});
    await repository.execute(
      'logs',
      const Command('withdraw', {'id': 'log-1', 'reason': '补充'}, version: 3),
    );
    expect(requests.last.path, '/logs/log-1/withdraw');
    expect(requests.last.data, {'version': 3, 'reason': '补充'});
  });

  test('日志详情评论保留身份、作者及回复关系', () async {
    repository.dio.interceptors.clear();
    repository.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          final Object body = r.path.endsWith('/comments')
              ? [
                  {
                    'id': 'c',
                    'actor_id': 'u',
                    'author_name': '员工',
                    'parent_id': 'p',
                    'created_at': '2026-10-22T00:00:00Z',
                    'text': '回复',
                  },
                ]
              : r.path.endsWith('/versions')
              ? []
              : {'id': 'log', 'submitted': true};
          h.resolve(Response(requestOptions: r, statusCode: 200, data: body));
        },
      ),
    );
    final record = await repository.detail('logs', 'log');
    final comment = (record.fields['comments'] as List).single as Map;
    expect(comment['id'], 'c');
    expect(comment['parentCommentId'], 'p');
    expect(comment['authorName'], '员工');
  });

  test('评论写入失败不自动重试', () async {
    repository.dio.interceptors.clear();
    repository.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          requests.add(r);
          h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.receiveTimeout,
            ),
          );
        },
      ),
    );
    await expectLater(
      repository.execute(
        'logs/comments',
        const Command('comment', {'id': 'log', 'text': '回复'}),
      ),
      throwsA(
        isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.timeout),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('未支持任务字段不得被丢弃后创建旧任务', () async {
    for (final field in ['participantIds', 'startAt', 'tagId']) {
      await expectLater(
        repository.execute(
          'tasks',
          Command('create', {
            'title': '新任务',
            field: field == 'participantIds' ? ['u'] : 'value',
          }),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'CLIENT_CONTRACT_UNAVAILABLE',
          ),
        ),
      );
    }
    expect(requests, isEmpty);
  });

  test('精确24小时、服务端拒绝和撤回后重用原窗口', () {
    final until = DateTime.utc(2026, 10, 23);
    Record log({bool submitted = true, bool edit = true}) => Record(
      id: 'log',
      title: '日报',
      fields: {
        'submitted': submitted,
        'status': submitted ? '已提交' : '草稿',
        'submittedAt': '2026-10-22T00:00:00Z',
        'editableUntil': until.toIso8601String(),
        'canEdit': edit,
        'canWithdraw': true,
      },
    );
    expect(
      LogEditWindow(
        log(),
      ).canEditAt(until.subtract(const Duration(seconds: 1))),
      true,
    );
    expect(LogEditWindow(log()).canEditAt(until), false);
    expect(LogEditWindow(log()).canWithdrawAt(until), false);
    expect(LogEditWindow(log(submitted: false)).canEditAt(until), false);
    expect(
      LogEditWindow(
        log(edit: false),
      ).canEditAt(until.subtract(const Duration(hours: 1))),
      false,
    );
  });
}
