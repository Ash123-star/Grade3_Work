import 'dart:async';
import '../../core/errors/api_failure.dart';
import '../models/models.dart';
import 'repository.dart';

final sharedCalendarTaskReader = CalendarTaskReader();

/// Task-only bounded reader. Partial data is never returned as success.
class CalendarTaskReader {
  int _running = 0;
  final _queue = <Completer<void>>[];
  Future<void> _acquire() async {
    if (_running < 2) {
      _running++;
      return;
    }
    final waiter = Completer<void>();
    _queue.add(waiter);
    await waiter.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _queue.remove(waiter);
        throw const ApiFailure(FailureKind.timeout, '日历读取等待超出时间预算');
      },
    );
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  Future<PageResult> read(
    Repository repository,
    Query query, {
    required bool Function() isActive,
  }) async {
    final clock = Stopwatch()..start();
    await _acquire();
    try {
      for (var restart = 0; restart < 2; restart++) {
        final items = <Record>[], ids = <String>{}, cursors = <String>{};
        String? cursor, token;
        Map<String, dynamic>? constraints;
        int? total;
        try {
          for (var page = 0; page < 200; page++) {
            if (!isActive()) {
              throw const ApiFailure(FailureKind.unavailable, '日历读取已停止');
            }
            final remaining = const Duration(seconds: 45) - clock.elapsed;
            if (remaining <= Duration.zero) {
              throw const ApiFailure(FailureKind.timeout, '日历读取超出时间预算');
            }
            final result = await repository
                .list(
                  'tasks',
                  Query(
                    search: query.search,
                    ownerId: query.ownerId,
                    from: query.from,
                    to: query.to,
                    cursor: cursor,
                    snapshotToken: token,
                    requestTimeout: remaining < const Duration(seconds: 15)
                        ? remaining
                        : const Duration(seconds: 15),
                  ),
                )
                .timeout(remaining);
            if (!isActive()) {
              throw const ApiFailure(FailureKind.unavailable, '日历读取已停止');
            }
            if (result.snapshotToken == null ||
                result.snapshotToken!.isEmpty ||
                result.total < 0 ||
                result.total > 5000 ||
                total != null && result.total != total ||
                token != null && token != result.snapshotToken) {
              _invalid();
            }
            token = result.snapshotToken;
            total = result.total;
            constraints ??= result.scheduleConstraints;
            for (final item in result.items) {
              if (item.id.isEmpty || item.version < 1 || !ids.add(item.id)) {
                _invalid();
              }
              items.add(item);
            }
            final next = result.nextCursor;
            if (items.length > total || result.items.isEmpty && next != null) {
              _invalid();
            }
            if (next == null) {
              if (items.length != total) _invalid();
              return PageResult(
                List.unmodifiable(items),
                total: total,
                snapshotToken: token,
                scheduleConstraints: constraints,
              );
            }
            if (next.isEmpty ||
                items.length >= total ||
                !cursors.add(next) ||
                next == cursor) {
              _invalid();
            }
            cursor = next;
          }
          throw const ApiFailure(
            FailureKind.validation,
            '日历超过 200 页，请缩小范围或打开任务列表',
          );
        } on ApiFailure catch (e) {
          if (e.code != 'CALENDAR_SNAPSHOT_CHANGED' || restart == 1) rethrow;
        }
      }
      throw StateError('Unreachable calendar read');
    } on TimeoutException {
      throw const ApiFailure(FailureKind.timeout, '日历读取超出时间预算');
    } finally {
      _release();
    }
  }

  Never _invalid() =>
      throw const ApiFailure(FailureKind.server, '日历分页不完整，请重试；可先查看任务列表');
}
