import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/data/models/models.dart';

void main() {
  test(
    'direct edits preserve first submission and retired actions cannot mutate logs',
    () async {
      var now = DateTime.utc(2026, 10, 21, 8);
      final store = DemoStore()
        ..records['logs'] = []
        ..records['reviews'] = [];
      final reviewCount = (store.records['reviews'] ?? []).length;
      final author = MockRepository(
        const Session(id: 'u2', role: UserRole.employee),
        store: store,
        clock: () => now,
      );
      final log = await author.execute(
        'logs',
        const Command('submit', {
          'title': '窗口验证',
          'businessDate': '2026-10-21',
          '今日工作': '原文',
        }),
      );
      final edited = await author.execute(
        'logs',
        Command('update-content', {
          'id': log.id,
          'work': '补充正文',
        }, version: log.version),
      );
      expect(edited.fields['submittedAt'], log.fields['submittedAt']);
      expect(isSubmittedDiary(edited), isTrue);
      for (final action in ['withdraw', 'request-review', 'unknown']) {
        await expectLater(
          author.execute(
            'logs',
            Command(action, {
              'id': log.id,
              '今日工作': '不得写入',
            }, version: edited.version),
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.unavailable,
            ),
          ),
        );
      }
      expect((store.records['reviews'] ?? []).length, reviewCount);
      now = now.add(const Duration(hours: 24));
      expect((await author.detail('logs', log.id)).fields['canEdit'], isFalse);
      await expectLater(
        author.execute(
          'logs',
          Command('update-content', {
            'id': log.id,
            'work': '超时覆盖',
          }, version: edited.version),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect((await author.detail('logs', log.id)).fields['今日工作'], '补充正文');
    },
  );
  test(
    'one shared demo preserves dispatch receive feedback return acceptance archive across users',
    () async {
      final store = DemoStore();
      final manager = MockRepository(const Session(), store: store);
      final employee = MockRepository(
        const Session(
          id: 'u2',
          name: '陈一诺',
          role: UserRole.employee,
          dispatch: false,
        ),
        store: store,
      );
      var task = await manager.execute(
        'tasks',
        Command('create', {
          'title': '演示闭环任务',
          '任务内容': '完成一个可以验收的交互稿',
          'ownerId': 'u2',
          '主负责人': '陈一诺',
          'deadline': DateTime.now()
              .add(const Duration(days: 2))
              .toIso8601String(),
        }),
      );
      expect(
        (await employee.detail('tasks', task.id)).fields['任务内容'],
        '完成一个可以验收的交互稿',
      );
      task = await employee.execute(
        'tasks',
        Command('receive', {'id': task.id}, version: task.version),
      );
      expect(task.fields['status'], '进行中');
      task = await employee.execute(
        'tasks',
        Command('feedback', {
          'id': task.id,
          '成果说明': '初稿已完成',
        }, version: task.version),
      );
      expect(task.fields['status'], '待验收');
      task = await manager.execute(
        'tasks',
        Command('return', {
          'id': task.id,
          '验收意见': '补充空状态',
        }, version: task.version),
      );
      expect(task.fields['status'], '需补充');
      task = await employee.execute(
        'tasks',
        Command('feedback', {
          'id': task.id,
          '成果说明': '已补充空状态',
        }, version: task.version),
      );
      task = await manager.execute(
        'tasks',
        Command('accept', {'id': task.id, '验收意见': '通过'}, version: task.version),
      );
      expect(task.fields['status'], '已验收');
      expect(task.fields['acceptedAt'], isNotNull);
      task = await manager.execute(
        'tasks',
        Command('archive', {'id': task.id}, version: task.version),
      );
      expect(task.fields['status'], '已归档');
      expect(task.title, '演示闭环任务');
      final notifications = (await employee.list(
        'notifications',
        const Query(),
      )).items;
      expect(notifications.any((n) => n.fields['targetId'] == task.id), isTrue);
      await employee.execute('notifications', const Command('read-all', {}));
      expect(
        (await employee.list(
          'notifications',
          const Query(),
        )).items.every((n) => n.fields['read'] == true),
        isTrue,
      );
    },
  );
  test(
    'daily log is unique and in-window edits apply without review',
    () async {
      final store = DemoStore()..records['reviews'] = [];
      final now = DateTime.utc(2026, 9, 23, 4);
      final employee = MockRepository(
        const Session(
          id: 'u2',
          name: '陈一诺',
          role: UserRole.employee,
          dispatch: false,
        ),
        store: store,
        clock: () => now,
      );
      final manager = MockRepository(
        const Session(),
        store: store,
        clock: () => now,
      );
      const date = '2026-09-23';
      final first = await employee.execute(
        'logs',
        const Command('submit', {
          'title': '日报',
          'businessDate': date,
          '今日工作': '原始内容',
        }),
      );
      await expectLater(
        employee.execute(
          'logs',
          const Command('submit', {
            'title': '日报',
            'businessDate': date,
            '今日工作': '第二次内容',
          }),
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.conflict),
        ),
      );
      final edited = await employee.execute(
        'logs',
        Command('update-content', {
          'id': first.id,
          'work': '修订内容',
        }, version: first.version),
      );
      expect((await employee.detail('logs', first.id)).fields['今日工作'], '修订内容');
      expect(edited.fields['submittedAt'], first.fields['submittedAt']);
      expect((await manager.list('reviews', const Query())).items, isEmpty);
      final subordinate = (await manager.list(
        'logs/subordinates',
        const Query(ownerId: 'u2'),
      )).items;
      expect(subordinate.every((r) => r.ownerId == 'u2'), isTrue);
    },
  );
  test('logged out user can log in but cannot read work records', () async {
    final repo = MockRepository(const Session(active: false));
    expect(
      (await repo.execute(
        'auth',
        const Command('login', {'账号': 'demo', '密码': '12345678'}),
      )).id,
      'auth',
    );
    await expectLater(repo.list('tasks', const Query()), throwsException);
  });
}
