import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/data/mock_repository.dart';
import 'package:pandora_mobile/data/models.dart';

void main() {
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
    'daily log is unique and revisions only apply after full review',
    () async {
      final store = DemoStore();
      final employee = MockRepository(
        const Session(
          id: 'u2',
          name: '陈一诺',
          role: UserRole.employee,
          dispatch: false,
        ),
        store: store,
      );
      final manager = MockRepository(const Session(), store: store);
      const date = '2026-09-23';
      final first = await employee.execute(
        'logs',
        const Command('submit', {
          'title': '日报',
          'businessDate': date,
          '今日工作': '原始内容',
        }),
      );
      final second = await employee.execute(
        'logs',
        const Command('submit', {
          'title': '日报',
          'businessDate': date,
          '今日工作': '第二次内容',
        }),
      );
      expect(first.id, second.id);
      var request = await employee.execute(
        'logs',
        Command('request-review', {
          'id': second.id,
          '今日工作': '修订内容',
          '修改理由': '补充记录',
        }, version: second.version),
      );
      expect(
        (await employee.detail('logs', second.id)).fields['今日工作'],
        '第二次内容',
      );
      for (var i = 0; i < 3; i++) {
        request = await manager.execute(
          'reviews',
          Command('approve', {'id': request.id}, version: request.version),
        );
      }
      expect(request.fields['reviewState'], '已通过');
      expect((await employee.detail('logs', second.id)).fields['今日工作'], '修订内容');
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
