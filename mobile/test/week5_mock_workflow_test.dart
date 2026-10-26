import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/log_edit_window.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

Record diary(String id, DateTime submitted, {String owner = 'u1'}) => Record(
  id: id,
  title: '日报$id',
  ownerId: owner,
  fields: {
    'status': '已提交',
    '今日工作': '完成需求核对',
    'businessDate': '2026-10-17',
    'submittedAt': submitted.toIso8601String(),
    'comments': <Map<String, dynamic>>[],
  },
);

void main() {
  test(
    'Shanghai week includes Sunday and mock business day follows Shanghai across UTC midnight',
    () async {
      final repo = MockRepository(
        const Session(),
        clock: () => DateTime.utc(2026, 10, 17, 20),
        store: DemoStore()
          ..records['tasks'] = [
            const Record(
              id: 'sunday',
              title: '周日任务',
              ownerId: 'u1',
              fields: {'deadline': '2026-10-18T23:59:00+08:00'},
            ),
            const Record(
              id: 'monday',
              title: '下周任务',
              ownerId: 'u1',
              fields: {'deadline': '2026-10-19T00:00:00+08:00'},
            ),
          ],
      );
      final range = BusinessRange(DateTime(2026, 10, 18), '周');
      final tasks = (await repo.list(
        'tasks',
        Query(from: range.from, to: range.to),
      )).items;
      expect(tasks.map((r) => r.id), ['sunday']);
      final today = (await repo.list('logs', const Query())).items.first;
      expect(today.fields['businessDate'], '2026-10-18');
      expect(businessEventTime(today.fields['submittedAt'])?.day, 18);
    },
  );
  test(
    'first submission opens a direct 24h edit window and preserves its start',
    () async {
      var now = DateTime.utc(2026, 10, 17, 4);
      final store = DemoStore()..records['logs'] = [];
      final repo = MockRepository(
        const Session(),
        store: store,
        clock: () => now,
      );
      final draft = await repo.execute(
        'logs',
        const Command('save-draft', {
          'title': '日志草稿',
          '今日工作': '初稿',
          'businessDate': '2026-10-17',
        }),
      );
      expect(draft.fields['status'], '草稿');
      final submitted = await repo.execute(
        'logs',
        Command('submit', {'id': draft.id}, version: draft.version),
      );
      expect(submitted.fields['submittedAt'], now.toIso8601String());
      now = now.add(const Duration(hours: 23, minutes: 59));
      final edited = await repo.execute(
        'logs',
        Command('update-content', {
          'id': submitted.id,
          'work': '窗口内直接修订',
        }, version: submitted.version),
      );
      expect(edited.fields['今日工作'], '窗口内直接修订');
      expect(edited.fields['submittedAt'], submitted.fields['submittedAt']);
      expect(edited.fields['versions'], hasLength(1));
      expect(store.records['reviews'], isEmpty);
      now = now.add(const Duration(minutes: 1));
      for (final action in ['update-content', 'request-review', 'withdraw']) {
        await expectLater(
          repo.execute(
            'logs',
            Command(action, {
              'id': edited.id,
              'work': '越过窗口',
              '今日工作': '越过窗口',
              'reason': '边界验证',
            }, version: edited.version),
          ),
          throwsA(isA<ApiFailure>()),
        );
      }
      expect((await repo.detail('logs', edited.id)).fields['canEdit'], isFalse);
      now = now.add(const Duration(hours: 1));
      expect(LogEditWindow(edited).canEditAt(now), isFalse);
    },
  );

  test(
    'other author and invalid body cannot change a diary; original content survives',
    () async {
      final now = DateTime.utc(2026, 10, 17);
      final repo = MockRepository(
        const Session(),
        clock: () => now,
        store: DemoStore()
          ..records['logs'] = [
            diary('own', now),
            diary('other', now, owner: 'u2'),
          ],
      );
      await expectLater(
        repo.execute(
          'logs',
          const Command('update', {'id': 'other', '今日工作': '越权'}),
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        repo.execute(
          'logs',
          const Command('update', {'id': 'own', '今日工作': '  '}),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect((await repo.detail('logs', 'own')).fields['今日工作'], '完成需求核对');
    },
  );

  test(
    'public task and log comments support replies; empty, invalid parent and mutations fail',
    () async {
      final repo = MockRepository(const Session(), store: DemoStore());
      for (final target in ['tasks', 'logs']) {
        final id = (await repo.list(target, const Query())).items.first.id;
        final before =
            ((await repo.detail(target, id)).fields['comments'] as List?)
                ?.length ??
            0;
        final first = await repo.execute(
          '$target/comments',
          Command('comment', {'id': id, 'text': '这是一条公开评论'}),
        );
        await repo.execute(
          '$target/comments',
          Command('comment', {
            'id': id,
            'text': '回复内容',
            'parentCommentId': first.id,
          }),
        );
        final detail = await repo.detail(target, id);
        final comments = detail.fields['comments'] as List;
        expect(comments.length, before + 2);
        expect(comments.last['parentCommentId'], first.id);
        expect(comments[before]['actorName'], '林小满');
        expect(comments[before]['createdAt'], isNotNull);
        for (final command in [
          Command('comment', {'id': id, 'text': ' '}),
          Command('comment', {
            'id': id,
            'text': '回复',
            'parentCommentId': 'missing',
          }),
          Command('delete', {'id': id, 'text': '删除'}),
        ]) {
          await expectLater(
            repo.execute('$target/comments', command),
            throwsA(isA<ApiFailure>()),
          );
        }
      }
    },
  );

  test(
    'management includes subordinate-only tasks and excludes unrelated people; employee sees own',
    () async {
      final store = DemoStore()
        ..records['organization'] = [
          const Record(id: 'u1', title: '本人'),
          const Record(id: 'u2', title: '下属', fields: {'managerId': 'u1'}),
          const Record(id: 'u3', title: '下属的下属', fields: {'managerId': 'u2'}),
          const Record(id: 'u4', title: '其他团队'),
        ]
        ..records['tasks'] = [
          for (var i = 1; i <= 4; i++)
            Record(
              id: '$i',
              title: '任务$i',
              ownerId: 'u$i',
              fields: {
                'participantIds': ['u$i'],
                'dispatcherId': 'boss',
              },
            ),
        ];
      final manager = MockRepository(const Session(), store: store);
      expect(
        (await manager.list('tasks', const Query())).items.map((r) => r.id),
        ['1', '2', '3'],
      );
      final employee = MockRepository(
        const Session(id: 'u2', role: UserRole.employee, dispatch: false),
        store: store,
      );
      expect(
        (await employee.list('tasks', const Query())).items.map((r) => r.id),
        ['2'],
      );
      await expectLater(
        employee.detail('tasks', '4'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'subordinates contain only submitted scoped logs and seeded task times are valid',
    () async {
      final repo = MockRepository(const Session());
      final tasks = (await repo.list('tasks', const Query())).items;
      for (final task in tasks) {
        final start = DateTime.parse('${task.fields['startAt']}');
        final end = DateTime.parse('${task.fields['deadline']}');
        expect(start.isAfter(end), isFalse, reason: task.id);
      }
      final logs = (await repo.list('logs/subordinates', const Query())).items;
      expect(
        logs.every((r) => r.ownerId != 'u1' && isSubmittedDiary(r)),
        isTrue,
      );
      final keys = logs
          .map((r) => '${r.ownerId}:${r.fields['businessDate']}')
          .toList();
      expect(keys.toSet().length, keys.length);
    },
  );
}
