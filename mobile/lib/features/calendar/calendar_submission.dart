import 'dart:async';
import 'dart:math';
import '../../core/errors/api_failure.dart';
import '../../data/local/calendar_command_store.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repository.dart';

class CalendarSubmission {
  CalendarSubmission(this.repository, this.store, this.session);
  final Repository repository;
  final CalendarCommandStore store;
  final Session session;

  /// Persist before first send. A late response never creates a new command/key.
  Future<Record?> confirm(
    CalendarMoveCommand command, {
    required bool Function() sameSession,
    required bool Function() foreground,
  }) async {
    await store.save(session, command);
    final watch = Stopwatch()..start();
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!sameSession() || !foreground()) return null;
      try {
        final remaining = const Duration(seconds: 45) - watch.elapsed;
        if (remaining <= Duration.zero) return null;
        final result = command.reviewId == null
            ? await repository
                  .execute('tasks', command.command)
                  .timeout(
                    remaining < const Duration(seconds: 15)
                        ? remaining
                        : const Duration(seconds: 15),
                  )
            : await repository
                  .detail('reviews', command.reviewId!)
                  .timeout(
                    remaining < const Duration(seconds: 15)
                        ? remaining
                        : const Duration(seconds: 15),
                  );
        if (!sameSession()) return null;
        if (result.id.isEmpty || result.fields['status'] == null) {
          throw const ApiFailure(FailureKind.server, '审核响应不完整，提交结果待确认');
        }
        await store.save(session, command.reviewed(result.id));
        return result;
      } catch (error) {
        if (!sameSession()) return null;
        if (error is ApiFailure &&
            error.statusCode != 429 &&
            [
              FailureKind.validation,
              FailureKind.unauthorized,
              FailureKind.forbidden,
              FailureKind.notFound,
              FailureKind.conflict,
            ].contains(error.kind)) {
          await store.clear(session);
          rethrow;
        }
        if (!foreground() || attempt == 2) return null;
        var delay = Duration(
          milliseconds: (attempt + 1) * 500 + Random().nextInt(250),
        );
        if (error is ApiFailure &&
            error.retryAfter != null &&
            error.retryAfter! > delay) {
          delay = error.retryAfter!;
        }
        if (watch.elapsed + delay >= const Duration(seconds: 45)) return null;
        await Future<void>.delayed(delay);
      }
    }
    return null;
  }
}
