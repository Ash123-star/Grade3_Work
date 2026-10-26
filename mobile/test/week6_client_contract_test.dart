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

  test('主线新任务契约将HCJ字段映射为participants和labelId并保留审核响应', () async {
    response = {
      'id': 'review-1',
      'status': 'PENDING',
      'applicant_id': 'u',
      'kind': 'TASK_CREATE',
      'target_id': 'task-1',
    };
    final result = await repository.execute(
      'tasks',
      const Command('create', {
        'title': '新任务',
        'participantIds': ['u', 'v'],
        'tagId': 'label-1',
        'startAt': '2026-10-23T09:00:00+08:00',
        'deadline': '2026-10-24T18:00:00+08:00',
        'content': '完整说明',
      }, idempotencyKey: 'create-key'),
    );
    final body = requests.single.data as Map;
    expect(body['participants'], ['u', 'v']);
    expect(body['labelId'], 'label-1');
    expect(body['startAt'], '2026-10-23T09:00:00+08:00');
    expect(body.containsKey('participantIds'), false);
    expect(body.containsKey('ownerId'), false);
    expect(body.containsKey('tagId'), false);
    expect(requests.single.headers['Idempotency-Key'], 'create-key');
    expect(result.id, 'review-1');
    expect(result.fields['reviewState'], '待审');
  });

  test('新任务评论需要幂等键并保留回复关系', () async {
    await expectLater(
      repository.execute(
        'tasks/comments',
        const Command('comment', {'id': 'task', 'text': '回复'}),
      ),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'IDEMPOTENCY_REQUIRED'),
      ),
    );
    expect(requests, isEmpty);
    await repository.execute(
      'tasks/comments',
      const Command('comment', {
        'id': 'task',
        'text': '回复',
        'parentCommentId': 'parent',
      }, idempotencyKey: 'reply-key'),
    );
    expect(requests.single.path, '/tasks/task/comments');
    expect(requests.single.headers['Idempotency-Key'], 'reply-key');
    expect(requests.single.data, {'text': '回复', 'parentId': 'parent'});
  });

  test('服务端标签元数据和任务评论保持真实姓名颜色', () async {
    response = {
      'id': 'task',
      'participants': [
        {'id': 'u', 'name': '员工'},
      ],
      'label': {
        'id': 'label',
        'name': '自定义标签',
        'color': '#123456',
        'category': '公司',
      },
    };
    final task = await repository.detail('tasks', 'task');
    expect(task.fields['participantIds'], ['u']);
    expect(task.fields['participantNames'], ['员工']);
    expect(task.fields['tagName'], '自定义标签');
    expect(task.fields['tagColor'], '#123456');
    response = {
      'items': [
        {'id': 'label', 'name': '自定义标签', 'color': '#123456', 'version': 2},
      ],
    };
    final labels = await repository.list('task-labels', const Query());
    expect(requests.last.path, '/task-labels');
    expect(labels.items.single.fields['color'], '#123456');
    expect(labels.items.single.version, 2);
    response = {
      'items': [
        {
          'id': 'comment',
          'body': '正文',
          'author_id': 'u',
          'nickname': '员工',
          'parent_id': 'parent',
          'avatar_id': 'avatar',
        },
      ],
    };
    final comments = await repository.list(
      'tasks/task/comments',
      const Query(),
    );
    expect(comments.items.single.fields['text'], '正文');
    expect(comments.items.single.fields['actorName'], '员工');
    expect(comments.items.single.fields['parentCommentId'], 'parent');
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
