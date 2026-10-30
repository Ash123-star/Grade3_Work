import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/repositories/mock_repository.dart';
import 'package:pandora_mobile/data/repositories/repository.dart';
import 'package:pandora_mobile/data/repositories/complete_list.dart';
import 'package:pandora_mobile/core/config.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/data/local/draft_store.dart';
import 'local_state.dart';
import 'package:pandora_mobile/data/sse_client.dart';

final sseClientProvider = Provider<SseClient?>((ref) {
  final session = ref.watch(sessionProvider);
  if (AppConfig.mock || !session.canReadBusiness) return null;
  final client = SseClient(AppConfig.baseUrl, session.token);
  ref.onDispose(() => client.dio.close(force: true));
  return client;
});
final sseNotificationStreamProvider = StreamProvider.autoDispose<ServerEvent>((
  ref,
) {
  final client = ref.watch(sseClientProvider);
  return client == null
      ? const Stream<ServerEvent>.empty()
      : client.notifications();
});
final aiJobStreamProvider = StreamProvider.autoDispose
    .family<ServerEvent, String>((ref, jobId) {
      final client = ref.watch(sseClientProvider);
      return client == null
          ? const Stream<ServerEvent>.empty()
          : client.aiJob(jobId);
    });

final sessionProvider = StateProvider<Session>(
  (ref) => AppConfig.mock
      ? const Session()
      : const Session(active: false, role: UserRole.employee, dispatch: false),
);
final scenarioProvider = StateProvider<DemoScenario>(
  (ref) => DemoScenario.normal,
);
final fontScaleProvider = StateProvider<double>((ref) => 1);
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final periodProvider = StateProvider<String>((ref) => '月');
final demoStoreProvider = Provider<DemoStore>((ref) => DemoStore());
final httpRepositoryProvider = Provider<HttpRepository>((ref) {
  final session = ref.watch(sessionProvider);
  final sessionState = ref.read(sessionProvider.notifier);
  var alive = true;
  ref.onDispose(() => alive = false);
  return HttpRepository(
    AppConfig.baseUrl,
    session.token,
    businessAllowed: session.canReadBusiness,
    onSessionFailure: (failure) {
      if (!alive) return;
      final current = sessionState.state;
      // In-flight requests from a replaced account cannot revoke its successor.
      if (current.token != session.token || current.token == null) return;
      sessionState.state = switch (failure.code) {
        'PASSWORD_CHANGE_REQUIRED' => current.restrict(
          mustChangePassword: true,
        ),
        'MEMBERSHIP_PENDING' => current.restrict(status: 'PENDING'),
        _ => current.restrict(expired: true),
      };
    },
  );
});

final repositoryProvider = Provider<Repository>(
  (ref) => AppConfig.mock
      ? MockRepository(
          ref.watch(sessionProvider),
          scenario: ref.watch(scenarioProvider),
          store: ref.watch(demoStoreProvider),
        )
      : ref.watch(httpRepositoryProvider),
);

/// Null means no foreground validation. Credentials never use preferences.
final sessionCheckProvider = StateProvider<AsyncValue<void>?>((ref) => null);
final sessionStorageErrorProvider = StateProvider<String?>((ref) => null);

Future<void> refreshCurrentSession(
  WidgetRef ref, {
  bool blockBusiness = false,
}) async {
  final before = ref.read(sessionProvider);
  if (!before.authenticated || (!AppConfig.mock && before.token == null)) {
    return;
  }
  final repository = ref.read(repositoryProvider);
  if (blockBusiness) {
    ref.read(sessionCheckProvider.notifier).state = const AsyncLoading();
  }
  try {
    final user = await repository.detail('auth', 'me');
    if (!ref.context.mounted) return;
    final current = ref.read(sessionProvider);
    if (current.token != before.token ||
        current.id != before.id ||
        current.expired) {
      return;
    }
    final next = before.token == null
        ? current
        : Session.fromRecord(
            user,
            token: before.token,
            expiresAt: before.expiresAt,
          );
    if (next.id != before.id) {
      ref.read(sessionProvider.notifier).state = before.restrict(expired: true);
      ref.read(sessionCheckProvider.notifier).state = null;
      throw const ApiFailure(FailureKind.unauthorized, '账号身份已变化，请重新登录');
    }
    ref.read(sessionProvider.notifier).state = next;
    ref.read(sessionCheckProvider.notifier).state = null;
  } catch (error, stack) {
    if (ref.context.mounted &&
        ref.read(sessionProvider).token == before.token &&
        !ref.read(sessionProvider).expired &&
        blockBusiness) {
      ref.read(sessionCheckProvider.notifier).state = AsyncError(error, stack);
    }
    rethrow;
  }
}

Future<void> logoutCurrentSession(WidgetRef ref) async {
  final before = ref.read(sessionProvider);
  if (before.authenticated) {
    try {
      await ref
          .read(repositoryProvider)
          .execute('auth', const Command('logout', {}));
    } on ApiFailure catch (failure) {
      if (failure.kind != FailureKind.unauthorized) rethrow;
    }
  }
  if (!ref.context.mounted) return;
  final current = ref.read(sessionProvider);
  if ((current.token != before.token || current.id != before.id) &&
      !current.expired) {
    return;
  }
  if (!AppConfig.mock) {
    await ref.read(sessionStoreProvider).clear(token: before.token);
    if (!ref.context.mounted ||
        ref.read(sessionProvider).id != before.id ||
        ref.read(sessionProvider).token != current.token) {
      return;
    }
  }
  ref.read(sessionStorageErrorProvider.notifier).state = null;
  ref.read(sessionCheckProvider.notifier).state = null;
  ref.read(sessionProvider.notifier).state = const Session(
    id: '',
    name: '',
    active: false,
    dispatch: false,
    role: UserRole.employee,
  );
}

final recordsProvider = FutureProvider.autoDispose.family<PageResult, String>((
  ref,
  resource,
) {
  final session = ref.watch(sessionProvider);
  if (!session.canReadBusiness) {
    throw const ApiFailure(FailureKind.forbidden, '请先确认账号业务访问权限');
  }
  var active = true;
  ref.onDispose(() => active = false);
  return readCompleteList(
    ref.watch(repositoryProvider),
    resource,
    const Query(),
    isActive: () => active,
  );
});
final receivedTaskCardProvider = FutureProvider.autoDispose<PageResult>((ref) {
  final session = ref.watch(sessionProvider);
  if (!session.canReadBusiness) {
    throw const ApiFailure(FailureKind.forbidden, '请先确认账号业务访问权限');
  }
  var active = true;
  ref.onDispose(() => active = false);
  return readCompleteList(
    ref.watch(repositoryProvider),
    'tasks/received-card',
    const Query(),
    isActive: () => active,
  );
});
final itemProvider = FutureProvider.autoDispose
    .family<Record, (String, String)>(
      (ref, key) => ref.watch(repositoryProvider).detail(key.$1, key.$2),
    );
final scopedItemProvider = FutureProvider.autoDispose
    .family<Record, (String, String, String)>(
      (ref, key) =>
          ref.watch(repositoryProvider).detail(key.$1, key.$2, ownerId: key.$3),
    );

final organizationTreeProvider = FutureProvider.autoDispose<Record>((ref) {
  final user = ref.watch(sessionProvider);
  if (!user.canReadBusiness || !user.manager) {
    throw const ApiFailure(FailureKind.forbidden, '无权查看组织成员');
  }
  return ref.watch(repositoryProvider).detail('organization/tree', 'tree');
});
final auditRecordsProvider = FutureProvider.autoDispose<PageResult>(
  (ref) => ref.watch(recordsProvider('audit').future),
);
final analyticsFiltersProvider = StateProvider.family<AnalyticsFilters, String>(
  (ref, accountId) => const AnalyticsFilters(),
);
final analyticsSummaryProvider = FutureProvider.autoDispose<Record>((ref) {
  final accountId = ref.watch(sessionProvider).id;
  final filters = ref.watch(analyticsFiltersProvider(accountId));
  return ref.watch(repositoryProvider).analytics(
    AnalyticsQuery(
      date: ref.watch(selectedDateProvider),
      period: switch (ref.watch(periodProvider)) {
        '日' => 'day',
        '周' => 'week',
        _ => 'month',
      },
      groupBy: filters.groupBy,
      departmentId: filters.departmentId.isEmpty ? null : filters.departmentId,
      teamId: filters.teamId.isEmpty ? null : filters.teamId,
      ownerId: filters.ownerId.isEmpty ? null : filters.ownerId,
    ),
  );
});
final datedRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, String>((ref, resource) {
      var active = true;
      ref.onDispose(() => active = false);
      final date = ref.watch(selectedDateProvider);
      final period = ref.watch(periodProvider);
      final DateTime from, to;
      if (period == '月' && resource == 'tasks') {
        final range = _calendarMonthRange(date);
        from = range.from;
        to = range.to;
      } else {
        final range = BusinessRange(date, period);
        from = range.from;
        to = range.to;
      }
      return readCompleteList(
        ref.watch(repositoryProvider),
        resource,
        Query(
          ownerId: resource == 'tasks' ? ref.watch(sessionProvider).id : null,
          from: from,
          to: to,
        ),
        isActive: () => active,
      );
    });

final calendarMonthTasksProvider = FutureProvider.autoDispose
    .family<PageResult, (String?, int)>((ref, key) {
      var active = true;
      ref.onDispose(() => active = false);
      final monthIndex = key.$2;
      final year = monthIndex >= 0
          ? monthIndex ~/ 12
          : (monthIndex - 11) ~/ 12;
      final first = DateTime(year, monthIndex - year * 12 + 1);
      final range = _calendarMonthRange(first);
      return readCompleteList(
        ref.watch(repositoryProvider),
        'tasks',
        Query(
          ownerId: key.$1,
          from: range.from,
          to: range.to,
        ),
        isActive: () => active,
      );
    });

final memberCalendarDateProvider = StateProvider.family<DateTime, String>((
  ref,
  ownerId,
) {
  ref.watch(sessionProvider.select((session) => (session.id, session.token)));
  return shanghaiWallTime(DateTime.now());
});

final memberWorkspaceRevokedProvider = StateProvider.family<bool, String>((
  ref,
  ownerId,
) {
  ref.watch(sessionProvider.select((session) => (session.id, session.token)));
  return false;
});

final memberLogMonthProvider = FutureProvider.autoDispose
    .family<MemberLogMonth, (String, int)>((ref, key) {
      final session = ref.watch(sessionProvider);
      if (!session.manager || !session.canReadBusiness) {
        throw const ApiFailure(FailureKind.forbidden, '无权查看成员日志日历');
      }
      final month = DateTime(key.$2 ~/ 12, key.$2 % 12 + 1);
      return ref.watch(repositoryProvider).memberLogMonth(key.$1, month);
    });

({DateTime from, DateTime to}) _calendarMonthRange(DateTime date) {
  final first = DateTime(date.year, date.month);
  final gridStart = first.subtract(Duration(days: first.weekday - 1));
  final weeks =
      ((first.weekday - 1 + DateTime(date.year, date.month + 1, 0).day) / 7)
          .ceil();
  final gridEnd = gridStart.add(Duration(days: weeks * 7));
  return (
    from: DateTime.utc(
      gridStart.year,
      gridStart.month,
      gridStart.day,
    ).subtract(const Duration(hours: 8)),
    to: DateTime.utc(
      gridEnd.year,
      gridEnd.month,
      gridEnd.day,
    ).subtract(const Duration(hours: 8)),
  );
}

void refreshBusiness(WidgetRef ref) {
  ref.invalidate(recordsProvider);
  ref.invalidate(receivedTaskCardProvider);
  ref.invalidate(datedRecordsProvider);
  ref.invalidate(itemProvider);
  ref.invalidate(scopedItemProvider);
  ref.invalidate(organizationTreeProvider);
  ref.invalidate(auditRecordsProvider);
  ref.invalidate(analyticsSummaryProvider);
  ref.invalidate(memberRecordsProvider);
  ref.invalidate(logDayRecordsProvider);
}

/// Each member date belongs to the current account, independent of own diary/calendar.
final memberLogDateProvider = StateProvider.family<DateTime?, String>((
  ref,
  id,
) {
  ref.watch(sessionProvider.select((session) => (session.id, session.token)));
  return null;
});
final memberRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, (String, String)>((ref, key) {
      var active = true;
      ref.onDispose(() => active = false);
      final date = key.$1 == 'logs/subordinates'
          ? ref.watch(memberLogDateProvider(key.$2))
          : null;
      final range = date == null ? null : BusinessRange(date, '日');
      return readCompleteList(
        ref.watch(repositoryProvider),
        key.$1,
        Query(ownerId: key.$2, from: range?.from, to: range?.to),
        isActive: () => active,
      );
    });

final logDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
final logDayRecordsProvider = FutureProvider.autoDispose
    .family<PageResult, (String, String?)>((ref, key) {
      var active = true;
      ref.onDispose(() => active = false);
      final date = ref.watch(logFilterDateProvider);
      final range = date == null ? null : BusinessRange(date, '日');
      return readCompleteList(
        ref.watch(repositoryProvider),
        key.$1,
        Query(
          ownerId: key.$2,
          from: range?.from,
          to: range?.to,
          departmentId: key.$1 == 'logs/subordinates'
              ? ref.watch(subordinateLogFilterProvider).$1
              : null,
          search: key.$1 == 'logs/subordinates'
              ? ref.watch(subordinateLogFilterProvider).$2
              : '',
        ),
        isActive: () => active,
      );
    });

final subordinateLogFilterProvider = StateProvider<(String?, String)>((ref) {
  ref.watch(sessionProvider.select((s) => (s.id, s.token)));
  return (null, '');
});

final logFilterDateProvider = StateProvider<DateTime?>((ref) => DateTime.now());

/// Public registration choices use server IDs; names never substitute for IDs.
final registrationDepartmentsProvider = FutureProvider.autoDispose<PageResult>(
  (ref) =>
      ref.watch(repositoryProvider).list('auth/departments', const Query()),
);

final todayDraftProvider = FutureProvider.autoDispose.family<DateTime?, String>(
  (ref, account) async {
    final current = ref.watch(sessionProvider);
    if (current.id != account || !current.canReadBusiness) return null;
    final draft = await ref
        .read(draftStoreProvider)
        .read(DraftLocation.diary(account, DateTime.now()));
    if ((draft?.fields['今日工作'] ?? '').isEmpty) return null;
    return draft?.savedAt;
  },
);
