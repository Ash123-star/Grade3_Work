import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/local_state.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/local/calendar_command_store.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/calendar_tasks.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_schedule.dart';
import 'package:pandora_mobile/features/calendar/calendar_submission.dart';
import 'support/local_test_state.dart';

final constraints = CalendarConstraints(
  DateTime(2024),
  DateTime(2034),
  'calendar-v1-2026',
);
const task = Record(
  id: 'task',
  title: '跨周任务',
  version: 7,
  fields: {
    'startAt': '2026-11-02T09:00:00+08:00',
    'deadline': '2026-11-04T18:00:00+08:00',
    'capabilities': {'reschedule': true},
  },
);

class PageRepository extends MockRepository {
  PageRepository(this.fetch) : super(const Session());
  final Future<PageResult> Function(Query) fetch;
  @override
  Future<PageResult> list(String resource, Query query) => fetch(query);
}

class MoveAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'review',
        'status': 'PENDING',
        'kind': 'TASK_RESCHEDULE',
        'target_id': 'task',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SubmissionRepository extends MockRepository {
  SubmissionRepository() : super(const Session());
  int sends = 0;
  bool loseResponse = false;
  @override
  Future<Record> execute(String resource, Command command) async {
    sends++;
    if (loseResponse) throw const ApiFailure(FailureKind.timeout, '响应丢失');
    return const Record(
      id: 'review',
      title: '待审',
      fields: {'status': 'PENDING'},
    );
  }
}

class DeferredSubmissionRepository extends SubmissionRepository {
  final response = Completer<Record>();
  final sent = Completer<void>();
  @override
  Future<Record> execute(String resource, Command command) {
    sends++;
    if (!sent.isCompleted) sent.complete();
    return response.future;
  }
}

class RetrySubmissionRepository extends SubmissionRepository {
  final keys = <String?>[];
  ApiFailure? failure;
  bool recover = false;
  @override
  Future<Record> execute(String resource, Command command) async {
    sends++;
    keys.add(command.idempotencyKey);
    if (recover && sends > 1) {
      return const Record(
        id: 'same-review',
        title: '待审',
        fields: {'status': 'PENDING'},
      );
    }
    throw failure ?? const ApiFailure(FailureKind.timeout, '已提交但响应丢失');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'lost response confirms same key; retries and Retry-After stay bounded',
    () async {
      final container = testContainer();
      addTearDown(container.dispose);
      final store = container.read(calendarCommandStoreProvider);
      const session = Session();
      const command = CalendarMoveCommand(
        taskId: 'task',
        version: 7,
        days: 1,
        reason: '排期',
        key: 'durable-key',
        revision: 'calendar-v1-2026',
      );
      final recovered = RetrySubmissionRepository()..recover = true;
      final result = await CalendarSubmission(
        recovered,
        store,
        session,
      ).confirm(command, sameSession: () => true, foreground: () => true);
      expect(result!.id, 'same-review');
      expect(recovered.keys, ['durable-key', 'durable-key']);
      expect((await store.read(session))!.reviewId, 'same-review');
      final exhausted = RetrySubmissionRepository();
      expect(
        await CalendarSubmission(
          exhausted,
          store,
          session,
        ).confirm(command, sameSession: () => true, foreground: () => true),
        isNull,
      );
      expect(exhausted.keys, ['durable-key', 'durable-key', 'durable-key']);
      expect((await store.read(session))!.key, 'durable-key');
      final limited = RetrySubmissionRepository()
        ..failure = const ApiFailure(
          FailureKind.server,
          '限流',
          statusCode: 429,
          retryAfter: Duration(seconds: 60),
        );
      expect(
        await CalendarSubmission(
          limited,
          store,
          session,
        ).confirm(command, sameSession: () => true, foreground: () => true),
        isNull,
      );
      expect(limited.sends, 1);
    },
  );
  test(
    'late response cannot restore a command after A to B to A or relogin',
    () async {
      final container = testContainer();
      addTearDown(container.dispose);
      final store = container.read(calendarCommandStoreProvider);
      const session = Session();
      const command = CalendarMoveCommand(
        taskId: 'task',
        version: 7,
        days: 1,
        reason: '排期',
        key: 'old-session-key',
        revision: 'calendar-v1-2026',
      );
      final epoch = container.read(sessionEpochProvider);
      final repository = DeferredSubmissionRepository();
      final future = CalendarSubmission(repository, store, session).confirm(
        command,
        sameSession: () => container.read(sessionEpochProvider) == epoch,
        foreground: () => true,
      );
      await repository.sent.future;
      container.read(sessionProvider.notifier).state = const Session(id: 'B');
      expect(container.read(sessionEpochProvider), isNot(epoch));
      container.read(sessionProvider.notifier).state = const Session();
      expect(container.read(sessionEpochProvider), isNot(epoch));
      await store.clear(session);
      repository.response.complete(
        const Record(
          id: 'late-review',
          title: '旧响应',
          fields: {'status': 'PENDING'},
        ),
      );
      expect(await future, isNull);
      expect(await store.read(session), isNull);
      expect(repository.sends, 1);
    },
  );
  test(
    'review decisions follow the deployed strict request contract',
    () async {
      final repository = HttpRepository('https://example.invalid/api', 'token');
      final adapter = MoveAdapter();
      repository.dio.httpClientAdapter = adapter;
      await repository.execute(
        'reviews',
        const Command('approve', {
          'id': 'review',
          'reason': '独立审核',
        }, version: 7),
      );
      expect(adapter.requests.single.path, '/reviews/review/decision');
      expect(adapter.requests.single.data, {'approve': true, 'reason': '独立审核', 'expectedVersion': 7});
      repository.dio.close(force: true);
    },
  );
  test('middle-day anchor preserves both instants and duration', () {
    final days = businessDayDelta(DateTime(2026, 11, 3), DateTime(2026, 11, 5));
    final original = CalendarSchedule.fromRecord(task),
        moved = CalendarSchedule.fromRecord(task).move(days, constraints);
    expect(moved.start, DateTime.parse('2026-11-04T09:00:00+08:00'));
    expect(moved.end, DateTime.parse('2026-11-06T18:00:00+08:00'));
    expect(
      moved.end.difference(moved.start!),
      original.end.difference(original.start!),
    );
    expect(businessDayDelta(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2);
    expect(businessDayDelta(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
  });
  test('null start, leap day, invalid interval and date window', () {
    final schedule = CalendarSchedule.fromRecord(
      const Record(
        id: 'd',
        title: '截止',
        fields: {'deadline': '2028-02-28T18:00:00+08:00'},
      ),
    );
    expect(schedule.move(1, constraints).start, isNull);
    expect(
      businessDateText(shanghaiWallTime(schedule.move(1, constraints).end)),
      '2028-02-29',
    );
    expect(() => parseBusinessDate('2026-02-29'), throwsFormatException);
    expect(() => parseBusinessDate('2026-13-01'), throwsFormatException);
    expect(() => schedule.move(0, constraints), throwsFormatException);
    expect(() => schedule.move(4000, constraints), throwsFormatException);
    expect(
      () => CalendarSchedule.fromRecord(
        const Record(
          id: 'd',
          title: '无效',
          fields: {
            'startAt': '2026-11-02T18:00Z',
            'deadline': '2026-11-02T18:00Z',
          },
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'move HTTP sends only integer delta, version, reason and original headers',
    () async {
      final repository = HttpRepository('https://example.invalid/api', 'token'),
          adapter = MoveAdapter();
      repository.dio.httpClientAdapter = adapter;
      final result = await repository.execute(
        'tasks',
        const Command(
          'move-schedule',
          {'id': 'task', 'moveDays': 2, 'reason': '排期调整'},
          version: 7,
          idempotencyKey: 'key',
          scheduleRevision: 'calendar-v1-2026',
        ),
      );
      expect(result.id, 'review');
      expect(result.fields['status'], 'PENDING');
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.path, '/tasks/task/reschedules');
      expect(request.data, {'version': 7, 'moveDays': 2, 'reason': '排期调整'});
      expect(request.headers['Idempotency-Key'], 'key');
      expect(
        request.headers['If-Schedule-Constraints-Match'],
        'calendar-v1-2026',
      );
      expect(request.receiveTimeout, const Duration(seconds: 15));
    },
  );
  test(
    'reader binds token and requires terminal cursor with exact total',
    () async {
      final queries = <Query>[];
      final repository = PageRepository((q) async {
        queries.add(q);
        return q.cursor == null
            ? PageResult(
                [task],
                total: 2,
                nextCursor: '1',
                snapshotToken: 'token',
              )
            : const PageResult(
                [Record(id: 'second', title: '下一任务')],
                total: 2,
                snapshotToken: 'token',
              );
      });
      final page = await CalendarTaskReader().read(
        repository,
        Query(from: DateTime.utc(2026, 11), to: DateTime.utc(2026, 12)),
        isActive: () => true,
      );
      expect(page.items, hasLength(2));
      expect(queries.last.snapshotToken, 'token');
      final bad = PageRepository(
        (_) async => const PageResult(
          [],
          total: 0,
          nextCursor: '1',
          snapshotToken: 'token',
        ),
      );
      await expectLater(
        CalendarTaskReader().read(bad, const Query(), isActive: () => true),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'snapshot changes discard whole first attempt and restart once',
    () async {
      var attempts = 0, calls = 0;
      final repository = PageRepository((q) async {
        calls++;
        if (q.cursor == null) {
          attempts++;
          return PageResult(
            [task],
            total: 2,
            nextCursor: '1',
            snapshotToken: 't$attempts',
          );
        }
        throw const ApiFailure(
          FailureKind.conflict,
          '变更',
          code: 'CALENDAR_SNAPSHOT_CHANGED',
        );
      });
      await expectLater(
        CalendarTaskReader().read(
          repository,
          const Query(),
          isActive: () => true,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(attempts, 2);
      expect(calls, 4);
    },
  );
  test(
    'reader rejects duplicates, missing token, extra page and incomplete final',
    () async {
      for (final page in [
        PageResult([task, task], total: 2, snapshotToken: 't'),
        PageResult([task], total: 1),
        PageResult([task], total: 1, nextCursor: '1', snapshotToken: 't'),
        PageResult([task], total: 2, snapshotToken: 't'),
      ]) {
        await expectLater(
          CalendarTaskReader().read(
            PageRepository((_) async => page),
            const Query(),
            isActive: () => true,
          ),
          throwsA(isA<ApiFailure>()),
        );
      }
    },
  );
  test(
    'reader accepts 5000 records and exactly 200 pages, rejects excess',
    () async {
      final reader = CalendarTaskReader();
      var calls = 0;
      final repository = PageRepository((q) async {
        calls++;
        final offset = int.parse(q.cursor ?? '0');
        return PageResult(
          List.generate(25, (i) => Record(id: 'r${offset + i}', title: '任务')),
          total: 5000,
          nextCursor: offset + 25 == 5000 ? null : '${offset + 25}',
          snapshotToken: 'stable',
        );
      });
      expect(
        (await reader.read(
          repository,
          const Query(),
          isActive: () => true,
        )).items.length,
        5000,
      );
      expect(calls, 200);
      await expectLater(
        reader.read(
          PageRepository(
            (_) async => const PageResult([], total: 5001, snapshotToken: 't'),
          ),
          const Query(),
          isActive: () => true,
        ),
        throwsA(isA<ApiFailure>()),
      );
      calls = 0;
      await expectLater(
        reader.read(
          PageRepository((q) async {
            final offset = calls++;
            return PageResult(
              [Record(id: 'r$offset', title: '任务')],
              total: 201,
              nextCursor: '${offset + 1}',
              snapshotToken: 't',
            );
          }),
          const Query(),
          isActive: () => true,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 200);
    },
  );
  test(
    'reader accepts empty snapshot and rejects repeated cursor or lost scope',
    () async {
      final empty = await CalendarTaskReader().read(
        PageRepository(
          (_) async => const PageResult([], total: 0, snapshotToken: 'empty'),
        ),
        const Query(),
        isActive: () => true,
      );
      expect(empty.items, isEmpty);
      var calls = 0;
      await expectLater(
        CalendarTaskReader().read(
          PageRepository((q) async {
            calls++;
            return PageResult(
              [Record(id: 'r$calls', title: '任务')],
              total: 4,
              nextCursor: 'same',
              snapshotToken: 't',
            );
          }),
          const Query(),
          isActive: () => true,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 2);
      var active = true;
      await expectLater(
        CalendarTaskReader().read(
          PageRepository((_) async {
            active = false;
            return PageResult([task], total: 1, snapshotToken: 't');
          }),
          const Query(),
          isActive: () => active,
        ),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('shared reader limits requests to two concurrent reads', () async {
    final reader = CalendarTaskReader();
    final release = Completer<void>();
    var running = 0, peak = 0, calls = 0;
    final repository = PageRepository((_) async {
      running++;
      calls++;
      if (running > peak) peak = running;
      await release.future;
      running--;
      return const PageResult([], total: 0, snapshotToken: 't');
    });
    final reads = List.generate(
      5,
      (_) => reader.read(repository, const Query(), isActive: () => true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    release.complete();
    await Future.wait(reads);
    expect(peak, 2);
    expect(calls, 5);
  });
  test(
    'command storage is protected and separated by company/account',
    () async {
      final container = testContainer();
      addTearDown(container.dispose);
      final store = container.read(calendarCommandStoreProvider);
      const session = Session(companyId: 'company-a');
      final command = CalendarMoveCommand(
        taskId: 'task',
        version: 7,
        days: 2,
        reason: '私密原因',
        key: newCalendarCommandKey(),
        revision: 'calendar-v1-2026',
      );
      await store.save(session, command);
      expect((await store.read(session))!.key, command.key);
      expect(await store.read(const Session(companyId: 'company-b')), isNull);
      expect(
        await store.read(const Session(id: 'other', companyId: 'company-a')),
        isNull,
      );
      await store.clear(session);
      expect(await store.read(session), isNull);
    },
  );
  test(
    'secure persistence failure prevents sending; background prevents retries',
    () async {
      final secure = MemorySecureValues()..failWrite = true;
      final container = testContainer(
        overrides: [secureValuesProvider.overrideWithValue(secure)],
      );
      addTearDown(container.dispose);
      final store = container.read(calendarCommandStoreProvider),
          repo = SubmissionRepository();
      const command = CalendarMoveCommand(
        taskId: 'task',
        version: 7,
        days: 1,
        reason: '排期',
        key: 'key',
        revision: 'calendar-v1-2026',
      );
      await expectLater(
        CalendarSubmission(
          repo,
          store,
          const Session(),
        ).confirm(command, sameSession: () => true, foreground: () => true),
        throwsA(anything),
      );
      expect(repo.sends, 0);
      secure.failWrite = false;
      repo.loseResponse = true;
      var foreground = true;
      final result = await CalendarSubmission(repo, store, const Session())
          .confirm(
            command,
            sameSession: () => true,
            foreground: () {
              final value = foreground;
              foreground = false;
              return value;
            },
          );
      expect(result, isNull);
      expect(repo.sends, 1);
      expect((await store.read(const Session()))!.key, 'key');
    },
  );
}
