import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../errors/api_failure.dart';
import '../../data/repositories/repository.dart';
import '../../data/repositories/notification_stream.dart';
import 'providers.dart';

final notificationForegroundProvider = StateProvider<bool>((ref) => true);
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
    StateNotifierProvider.autoDispose<LiveNotifications, LiveNotificationState>(
      (ref) {
        final session = ref.watch(sessionProvider);
        final enabled =
            !AppConfig.mock &&
            session.token != null &&
            session.canReadBusiness &&
            ref.watch(notificationForegroundProvider) &&
            ref.watch(sessionCheckProvider) == null;
        final gateway = enabled ? ref.watch(notificationStreamProvider) : null;
        final controller = LiveNotifications(gateway, () {
          final current = ref.read(sessionProvider);
          if (current.id != session.id ||
              current.token != session.token ||
              !current.canReadBusiness ||
              !ref.read(notificationForegroundProvider) ||
              ref.read(sessionCheckProvider) != null) {
            return;
          }
          ref.invalidate(recordsProvider('notifications'));
          ref.invalidate(recordsProvider('reviews'));
          ref.invalidate(recordsProvider('tasks'));
          ref.invalidate(datedRecordsProvider);
          ref.invalidate(logDayRecordsProvider);
          ref.invalidate(memberRecordsProvider);
        });
        // Stop transport immediately when the last UI subscriber disappears,
        // rather than leaving timers alive until the auto-dispose frame.
        ref.onCancel(controller.suspend);
        ref.onResume(controller.resume);
        return controller;
      },
    );

/// One transport per confirmed foreground session. No business payload is retained.
class LiveNotifications extends StateNotifier<LiveNotificationState> {
  LiveNotifications(this.gateway, this.refresh)
    : super(
        LiveNotificationState(
          gateway == null
              ? NotificationConnection.disabled
              : NotificationConnection.connecting,
        ),
      ) {
    if (gateway != null) scheduleMicrotask(connect);
  }
  final NotificationStream? gateway;
  final void Function() refresh;
  StreamSubscription<NotificationSignal>? subscription;
  CancelToken? cancel;
  Timer? reconnect, debounce;
  bool alive = true, subscribed = true;
  int generation = 0, sequence = 0, failures = 0;

  void connect() {
    if (!alive || !subscribed || gateway == null) return;
    reconnect?.cancel();
    final attempt = ++generation;
    state = LiveNotificationState(
      NotificationConnection.connecting,
      sequence: sequence,
    );
    cancel = CancelToken();
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
              scheduleRefresh();
            } else if (signal.sequence! > sequence) {
              sequence = signal.sequence!;
              failures = 0;
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
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), () {
      if (alive && state.connection == NotificationConnection.live) refresh();
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
        refresh();
      }
      return;
    }
    state = LiveNotificationState(
      NotificationConnection.reconnecting,
      sequence: sequence,
      error: error,
    );
    final seconds = failures == 0 ? 1 : (1 << (failures - 1)).clamp(1, 30);
    reconnect = Timer(Duration(seconds: seconds), connect);
  }

  void retry() {
    if (!alive ||
        gateway == null ||
        state.connection != NotificationConnection.stopped) {
      return;
    }
    failures = 0;
    connect();
  }

  void suspend() {
    subscribed = false;
    generation++;
    reconnect?.cancel();
    debounce?.cancel();
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
