import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';

void main() {
  DemoStore store(int count) => DemoStore()
    ..records['tasks'] = [
      for (var i = 0; i < count; i++)
        Record(id: 't$i', title: '任务$i', ownerId: 'u1', version: 2, fields: const {'participantIds': ['u1', 'u2']}),
    ];

  test('personal pin moves task first, is idempotent and invisible to others', () async {
    var tick = 0;
    final shared = store(3);
    DateTime clock() => DateTime(2026, 11, 1, 9, 0, tick++);
    final mine = MockRepository(const Session(id: 'u1', role: UserRole.leader), store: shared, clock: clock);
    final other = MockRepository(const Session(id: 'u2', role: UserRole.leader), store: shared, clock: clock);

    final first = await mine.execute('tasks/pin', const Command('pin', {'id': 't2'}));
    expect(first.fields['pinned'], isTrue);
    final again = await mine.execute('tasks/pin', const Command('pin', {'id': 't2'}));
    expect(again.fields['pinnedAt'], first.fields['pinnedAt']);
    await mine.execute('tasks/pin', const Command('pin', {'id': 't1'}));

    final page = await mine.list('tasks', const Query());
    expect(page.items.map((r) => r.id).take(3), ['t1', 't2', 't0']);
    expect(page.items.first.fields['pinned'], isTrue);
    expect(page.items.first.version, 2);
    final others = await other.list('tasks', const Query());
    expect(others.items.map((r) => r.id).take(3), ['t0', 't1', 't2']);
    expect(others.items.every((r) => r.fields['pinned'] == false), isTrue);

    final removed = await mine.execute('tasks/pin', const Command('unpin', {'id': 't1'}));
    expect(removed.fields['pinned'], isFalse);
    await mine.execute('tasks/pin', const Command('unpin', {'id': 't1'}));
    expect((await mine.list('tasks', const Query())).items.first.id, 't2');
  });

  test('pin limit and missing task are rejected', () async {
    final repo = MockRepository(const Session(id: 'u1', role: UserRole.leader), store: store(11));
    for (var i = 0; i < 10; i++) {
      await repo.execute('tasks/pin', Command('pin', {'id': 't$i'}));
    }
    await expectLater(
      repo.execute('tasks/pin', const Command('pin', {'id': 't10'})),
      throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'PIN_LIMIT')),
    );
    await expectLater(
      repo.execute('tasks/pin', const Command('pin', {'id': 'missing'})),
      throwsA(isA<ApiFailure>().having((e) => e.kind, 'kind', FailureKind.notFound)),
    );
  });
}
