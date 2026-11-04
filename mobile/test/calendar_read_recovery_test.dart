import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/calendar_month_retention.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/calendar_tasks.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/features/calendar/calendar_content.dart';
import 'package:pandora_mobile/features/calendar/calendar_interaction.dart';
import 'package:pandora_mobile/features/calendar/calendar_read_status.dart';
import 'calendar_movement_test.dart' show PageRepository;
import 'calendar_drag_widget_test.dart' show dragStore, readyInteraction;
import 'support/local_test_state.dart';

const limited = ApiFailure(
  FailureKind.unavailable,
  '请求过于频繁',
  statusCode: 429,
  code: 'RATE_LIMITED',
  retryAfter: Duration(seconds: 3),
);
const empty = PageResult([], total: 0, snapshotToken: 'stable');
const month = (null, 2026 * 12 + 10);

class CountingCalendarRepository extends MockRepository {
  CountingCalendarRepository()
    : super(
        const Session(),
        store: dragStore(),
        clock: () => DateTime(2026, 11, 2),
      );
  int reads = 0, details = 0;
  ApiFailure? failure;
  ApiFailure? detailFailure;
  @override
  Future<PageResult> list(String resource, Query query) async {
    if (resource == 'tasks') {
      reads++;
      if (failure != null) throw failure!;
    }
    return super.list(resource, query);
  }

  @override
  Future<Record> detail(String resource, String id, {String? ownerId}) async {
    details++;
    if (detailFailure != null) throw detailFailure!;
    return super.detail(resource, id, ownerId: ownerId);
  }
}

Future<ProviderContainer> mount(
  WidgetTester t,
  CountingCalendarRepository repo,
  CalendarTaskReader reader,
) async {
  final c = testContainer(
    overrides: [
      sessionProvider.overrideWith((_) => const Session()),
      repositoryProvider.overrideWithValue(repo),
      calendarTaskReaderProvider.overrideWithValue(reader),
      selectedDateProvider.overrideWith((_) => DateTime(2026, 11, 2)),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    OwnedTestProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: CalendarContent(availableHeight: 650)),
      ),
    ),
  );
  await settleLocalIo(t);
  await t.pumpAndSettle();
  await readyInteraction(t);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    '429 on another active month stops remaining pages already in flight',
    () async {
      final started = Completer<void>(), response = Completer<PageResult>();
      var calls = 0;
      final repo = PageRepository((query) async {
        calls++;
        if (query.search == 'limited') throw limited;
        if (!started.isCompleted) started.complete();
        return response.future;
      });
      final reader = CalendarTaskReader();
      final pending = reader.read(
        repo,
        const Query(search: 'slow'),
        isActive: () => true,
      );
      await started.future;
      await expectLater(
        reader.read(repo, const Query(search: 'limited'), isActive: () => true),
        throwsA(isA<ApiFailure>()),
      );
      final stopped = expectLater(
        pending,
        throwsA(isA<ApiFailure>().having((e) => e.statusCode, 'status', 429)),
      );
      response.complete(
        const PageResult(
          [Record(id: 'first', title: 'first page')],
          total: 2,
          nextCursor: '2',
          snapshotToken: 'same',
        ),
      );
      await stopped;
      expect(calls, 2);
    },
  );

  test(
    'pagination uses 100 rows and cooldown blocks all months without extending deadline',
    () async {
      var now = DateTime.utc(2026, 11, 4), calls = 0;
      final reader = CalendarTaskReader(now: () => now);
      final repo = PageRepository((q) async {
        calls++;
        expect(q.limit, 100);
        if (calls == 1) throw limited;
        return empty;
      });
      Future<PageResult> read() =>
          reader.read(repo, const Query(), isActive: () => true);
      await expectLater(read(), throwsA(isA<ApiFailure>()));
      now = now.add(const Duration(seconds: 2));
      for (var i = 0; i < 10; i++) {
        await expectLater(
          read(),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.retryAfter,
              'remaining',
              const Duration(seconds: 1),
            ),
          ),
        );
      }
      expect(calls, 1);
      expect(
        (await reader.read(
          PageRepository((_) async => empty),
          const Query(),
          isActive: () => true,
        )).items,
        isEmpty,
      );
      now = now.add(const Duration(seconds: 1));
      expect((await read()).items, isEmpty);
      expect(calls, 2);
    },
  );

  test(
    'successful months are reused, bounded and invalidated across sessions',
    () async {
      var reads = 0;
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith((_) => const Session()),
          calendarMonthRetentionProvider.overrideWith((ref) {
            ref.watch(sessionEpochProvider);
            final retention = CalendarMonthRetention(
              ttl: const Duration(seconds: 1),
            );
            ref.onDispose(retention.dispose);
            return retention;
          }),
          repositoryProvider.overrideWithValue(
            PageRepository((_) async {
              reads++;
              return empty;
            }),
          ),
        ],
      );
      addTearDown(c.dispose);
      Future<void> visit(int index) async {
        final provider = calendarMonthTasksProvider((null, index));
        final sub = c.listen(provider, (_, _) {});
        await c.read(provider.future);
        sub.close();
        await c.pump();
      }

      await visit(month.$2);
      await visit(month.$2);
      expect(reads, 1);
      for (var i = 1; i <= 6; i++) {
        await visit(month.$2 + i);
      }
      await visit(month.$2);
      expect(
        reads,
        8,
        reason: 'only six successful month handles are retained',
      );
      c.invalidate(calendarMonthTasksProvider);
      await visit(month.$2);
      expect(reads, 9);
      c.read(sessionProvider.notifier).state = const Session(id: 'other');
      await visit(month.$2);
      expect(reads, 10);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await c.pump();
      await visit(month.$2);
      expect(reads, 11);
      c.dispose();
    },
  );

  testWidgets(
    'retention expiration closes handles and cleanup cannot evict replacement',
    (t) async {
      var closed = 0;
      final pool = CalendarMonthRetention(ttl: const Duration(seconds: 2));
      final oldCleanup = pool.retain('same', () => closed++);
      pool.retain('same', () => closed++);
      oldCleanup();
      expect(closed, 1);
      await t.pump(const Duration(seconds: 2));
      expect(closed, 2);
      pool.dispose();
    },
  );

  testWidgets(
    'cooldown retry is disabled until expiry and never automatically fetches',
    (t) async {
      var now = DateTime.utc(2026), retries = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarReadStatus(
              failure: limited,
              onRetry: () => retries++,
              now: () => now,
            ),
          ),
        ),
      );
      await t.tap(find.text('重新加载月历'));
      expect(retries, 0);
      now = now.add(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(retries, 0);
      await t.tap(find.text('重新加载月历'));
      expect(retries, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '429 retains the last complete month read-only then recovers; 403 clears it',
    (t) async {
      var now = DateTime.utc(2026);
      final repo = CountingCalendarRepository();
      final c = await mount(t, repo, CalendarTaskReader(now: () => now));
      expect(find.byType(CalendarTaskHandle).hitTestable(), findsWidgets);
      repo.failure = limited;
      c.invalidate(calendarMonthTasksProvider);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-read-cooldown')),
        findsWidgets,
      );
      expect(find.byType(CalendarTaskHandle).hitTestable(), findsWidgets);
      expect(
        t
            .widgetList<CalendarTaskHandle>(find.byType(CalendarTaskHandle))
            .every((w) => w.constraints == null),
        isTrue,
      );
      final calls = repo.reads;
      for (var i = 0; i < 5; i++) {
        c.invalidate(calendarMonthTasksProvider);
        await t.pumpAndSettle();
      }
      expect(repo.reads, calls);
      repo.failure = null;
      now = now.add(const Duration(seconds: 4));
      c.invalidate(calendarMonthTasksProvider);
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-read-cooldown')),
        findsNothing,
      );
      expect(
        t
            .widgetList<CalendarTaskHandle>(find.byType(CalendarTaskHandle))
            .every((w) => w.constraints != null),
        isTrue,
      );
      repo.failure = const ApiFailure(
        FailureKind.forbidden,
        '权限失效',
        statusCode: 403,
      );
      c.invalidate(calendarMonthTasksProvider);
      await t.pumpAndSettle();
      expect(find.byType(CalendarTaskHandle), findsNothing);
    },
  );

  testWidgets(
    'a new account hitting 429 never sees the previous account month',
    (t) async {
      final repo = CountingCalendarRepository();
      final c = await mount(t, repo, CalendarTaskReader());
      expect(find.byType(CalendarTaskHandle).hitTestable(), findsWidgets);
      repo.failure = limited;
      c.read(sessionProvider.notifier).state = const Session(id: 'other');
      await settleLocalIo(t);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-read-cooldown')),
        findsWidgets,
      );
      expect(find.byType(CalendarTaskHandle), findsNothing);
    },
  );

  testWidgets(
    'detail 429 does not refresh all months and blocks repeated move attempts',
    (t) async {
      final repo = CountingCalendarRepository();
      await mount(t, repo, CalendarTaskReader());
      final state = await readyInteraction(t);
      final handle = t.widget<CalendarTaskHandle>(
        find.byType(CalendarTaskHandle).first,
      );
      final calls = repo.reads;
      repo.detailFailure = limited;
      for (var i = 0; i < 6; i++) {
        await state.move(handle.record, 7, handle.constraints!);
        await t.pumpAndSettle();
      }
      expect(repo.details, 1);
      expect(repo.reads, calls);
      expect(find.text('确认移动排期'), findsNothing);
    },
  );
}
