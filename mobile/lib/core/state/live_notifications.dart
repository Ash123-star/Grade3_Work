import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../errors/api_failure.dart';
import '../../data/repositories/repository.dart';
import '../../data/repositories/notification_stream.dart';
import 'providers.dart';
import '../../data/models/notification_display.dart';

final notificationCursorProvider = StateProvider<int>((ref) {
  ref.watch(sessionEpochProvider);
  return 0;
});
final notificationStreamProvider = Provider<NotificationStream?>((ref) {
  final repository = ref.watch(repositoryProvider);
  return repository is HttpRepository
      ? NotificationStream(repository.dio)
      : null;
});

enum NotificationConnection {
  disabled,
  connecting,
  live,
  reconnecting,
  stopped,
}

class LiveNotificationState {
  const LiveNotificationState(this.connection, {this.sequence = 0, this.error});
  final NotificationConnection connection;
  final int sequence;
  final Object? error;
}

final liveNotificationsProvider =
    StateNotifierProvider.autoDispose<
      LiveNotifications,
      LiveNotificationState
    >((ref) {
      final session = ref.watch(sessionProvider);
      final enabled =
          !AppConfig.mock &&
          session.token != null &&
          session.canReadBusiness &&
          ref.watch(notificationForegroundProvider) &&
          ref.watch(sessionCheckProvider) == null;
      final gateway = enabled ? ref.watch(notificationStreamProvider) : null;
      final controller = LiveNotifications(
        gateway,
        (signals) {
          final current = ref.read(sessionProvider);
          if (current.id != session.id ||
              current.token != session.token ||
              !current.canReadBusiness ||
              !ref.read(notificationForegroundProvider) ||
              ref.read(sessionCheckProvider) != null) {
            return;
          }
          // Message lists are refreshed by their cached 30-second poller.
          final types = signals.map((signal) => signal.type ?? '').toSet();
          final reviewChanged = types.any((type) => type.startsWith('REVIEW_'));
          final taskChanged = types.any(
            (type) => type.startsWith('TASK_') || type == 'DELIVERY_CHECKED',
          );
          final logChanged = types.any((type) => type.startsWith('LOG_'));
          // A decision may apply a task/log/organization revision; a pending reminder does not.
          final decision = types.contains('REVIEW_APPROVED');
          if (reviewChanged) ref.invalidate(recordsProvider('reviews'));
          if (taskChanged || decision) {
            ref.invalidate(recordsProvider('tasks'));
            ref.invalidate(receivedTaskCardProvider);
            ref.invalidate(receivedTaskPageProvider);
            ref.invalidate(homePreviewProvider('tasks/received-card'));
            ref.invalidate(datedRecordsProvider('tasks'));
            ref.invalidate(calendarMonthTasksProvider);
          }
          if (logChanged || decision) {
            ref.invalidate(logDayRecordsProvider);
            ref.invalidate(recentDiaryRecordsProvider);
            ref.invalidate(datedRecordsProvider('logs'));
          }
          if (taskChanged || logChanged || decision) {
            ref.invalidate(memberRecordsProvider);
          }
          if (decision) {
            ref.invalidate(organizationTreeProvider);
            ref.invalidate(recordsProvider('organization'));
          }
          for (final signal in signals) {
            final resource = notificationResource(signal.type),
                id = signal.objectId;
            if (resource != null && id != null && id.isNotEmpty) {
              ref.invalidate(itemProvider((resource, id)));
              ref.invalidate(scopedItemProvider((resource, id, session.id)));
            }
          }
        },
        initialSequence: ref.read(notificationCursorProvider),
        onSequence: (sequence) {
          final current = ref.read(sessionProvider);
          if (current.id == session.id && current.token == session.token) {
            ref.read(notificationCursorProvider.notifier).state = sequence;
          }
        },
      );
      // Stop transport immediately when the last UI subscriber disappears,
      // rather than leaving timers alive until the auto-dispose frame.
      ref.onCancel(controller.suspend);
      ref.onResume(controller.resume);
      return controller;
    });

/// One transport per confirmed foreground session. No business payload is retained.
class LiveNotifications extends StateNotifier<LiveNotificationState> {
  LiveNotifications(
    this.gateway,
    this.refresh, {
    int initialSequence = 0,
    this.onSequence,
  }) : sequence = initialSequence,
       super(
         LiveNotificationState(
           gateway == null
               ? NotificationConnection.disabled
               : NotificationConnection.connecting,
           sequence: initialSequence,
         ),
       ) {
    if (gateway != null) scheduleMicrotask(connect);
  }
  final NotificationStream? gateway;
  final void Function(List<NotificationSignal>) refresh;
  final void Function(int)? onSequence;
  StreamSubscription<NotificationSignal>? subscription;
  CancelToken? cancel;
  Timer? reconnect, debounce;
  bool alive = true, subscribed = true;
  bool initialized = false;
  int generation = 0, sequence, failures = 0;
  final pending = <String, NotificationSignal>{};
  DateTime? lastRefresh, retryAt;

  void connect() async {
    if (!alive || !subscribed || gateway == null) return;
    reconnect?.cancel();
    final remaining = retryAt?.difference(DateTime.now()) ?? Duration.zero;
    if (remaining > Duration.zero) {
      reconnect = Timer(remaining, connect);
      return;
    }
    final attempt = ++generation;
    state = LiveNotificationState(
      NotificationConnection.connecting,
      sequence: sequence,
    );
    cancel = CancelToken();
    if (!initialized && sequence == 0) {
      try {
        final head = await gateway!.latestSequence(cancel!);
        if (!alive || attempt != generation) return;
        sequence = head;
        initialized = true;
        onSequence?.call(sequence);
      } catch (error) {
        if (alive && attempt == generation) disconnected(error);
        return;
      }
    }
    subscription = gateway!
        .connect(sequence, cancel!)
        .listen(
          (signal) {
            if (!alive || attempt != generation) return;
            if (signal.sequence == null) {
              state = LiveNotificationState(
                NotificationConnection.live,
                sequence: sequence,
              );
              // Transport establishment/reconnection is not a business change.
              if (pending.isNotEmpty) scheduleRefresh();
            } else if (signal.sequence! > sequence) {
              sequence = signal.sequence!;
              failures = 0;
              pending['${signal.type}:${signal.objectId}'] = signal;
              state = LiveNotificationState(
                NotificationConnection.live,
                sequence: sequence,
              );
              scheduleRefresh();
            }
          },
          onError: (Object error) {
            if (alive && attempt == generation) disconnected(error);
          },
          onDone: () {
            if (alive && attempt == generation) disconnected(null);
          },
          cancelOnError: true,
        );
  }

  void scheduleRefresh() {
    if (debounce != null) return;
    final since = lastRefresh == null
        ? const Duration(seconds: 5)
        : DateTime.now().difference(lastRefresh!);
    var wait = since < const Duration(seconds: 5)
        ? const Duration(seconds: 5) - since
        : const Duration(seconds: 2);
    // HTTP requests are stopped by the shared repository interceptor during 429.
    final backoff = retryAt?.difference(DateTime.now()) ?? Duration.zero;
    if (backoff > wait) wait = backoff;
    if (gateway!.cooldown > wait) wait = gateway!.cooldown;
    debounce = Timer(wait, () {
      debounce = null;
      if (!alive || !subscribed || pending.isEmpty) return;
      if (gateway!.cooldown > Duration.zero) {
        scheduleRefresh();
        return;
      }
      final signals = pending.values.toList();
      pending.clear();
      lastRefresh = DateTime.now();
      refresh(signals);
      // A background transition before this point must replay the unrefreshed batch.
      onSequence?.call(sequence);
    });
  }

  void disconnected(Object? error) {
    generation++;
    cancel?.cancel();
    unawaited(subscription?.cancel());
    subscription = null;
    final permanent =
        error is ApiFailure &&
        [
          FailureKind.validation,
          FailureKind.forbidden,
          FailureKind.unauthorized,
        ].contains(error.kind);
    if (error != null) failures++;
    if (permanent || failures >= 5) {
      debounce?.cancel();
      debounce = null;
      state = LiveNotificationState(
        NotificationConnection.stopped,
        sequence: sequence,
        error:
            error ?? const ApiFailure(FailureKind.unavailable, '消息连接中断，请重新连接'),
      );
      if (error is ApiFailure &&
          [
            FailureKind.forbidden,
            FailureKind.unauthorized,
          ].contains(error.kind)) {
        refresh(const []);
      }
      return;
    }
    state = LiveNotificationState(
      NotificationConnection.reconnecting,
      sequence: sequence,
      error: error,
    );
    final delay = error is ApiFailure && error.statusCode == 429
        ? error.retryAfter ?? const Duration(seconds: 60)
        : Duration(
            seconds: failures == 0 ? 1 : (1 << (failures - 1)).clamp(1, 30),
          );
    retryAt = DateTime.now().add(delay);
    reconnect = Timer(delay, connect);
  }

  void retry() {
    if (!alive ||
        gateway == null ||
        state.connection != NotificationConnection.stopped) {
      return;
    }
    if (retryAt != null && retryAt!.isAfter(DateTime.now())) return;
    failures = 0;
    connect();
  }

  void suspend() {
    subscribed = false;
    generation++;
    reconnect?.cancel();
    debounce?.cancel();
    debounce = null;
    cancel?.cancel();
    unawaited(subscription?.cancel());
    subscription = null;
  }

  void resume() {
    subscribed = true;
    connect();
  }

  @override
  void dispose() {
    alive = false;
    suspend();
    super.dispose();
  }
}
