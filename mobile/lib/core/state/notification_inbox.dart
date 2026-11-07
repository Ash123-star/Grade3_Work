import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repository.dart';
import '../errors/api_failure.dart';

/// Session-owned stale-while-revalidate state. Never persists business data.
class NotificationInbox extends StateNotifier<AsyncValue<PageResult>> {
  NotificationInbox(
    this.repository,
    this.query, {
    required bool foreground,
    required bool authorized,
  }) : _foreground = foreground,
       super(const AsyncLoading()) {
    if (authorized) {
      unawaited(refresh());
    } else {
      state = const AsyncError(
        ApiFailure(FailureKind.forbidden, '请先确认账号业务访问权限'),
        StackTrace.empty,
      );
    }
    _schedule();
  }

  static const freshness = Duration(seconds: 30);
  final Repository repository;
  final Query query;
  Future<void>? _pending;
  Timer? _poll;
  DateTime? _checkedAt, _retryAt;
  PageResult? _firstPage;
  bool _foreground, _observed = true;

  Future<PageResult> get ready async {
    await refresh();
    return state.requireValue;
  }

  void observe(bool value) {
    _observed = value;
    _schedule();
    if (value) unawaited(refresh());
  }

  void foreground(bool value) {
    _foreground = value;
    _schedule();
    if (value && _observed) unawaited(refresh());
  }

  void _schedule() {
    _poll?.cancel();
    _poll = null;
    if (_foreground && _observed) {
      _poll = Timer.periodic(freshness, (_) => unawaited(refresh()));
    }
  }

  Duration get _cooldown {
    final repository = this.repository;
    final server = repository is HttpRepository
        ? repository.rateLimitRemaining
        : Duration.zero;
    final local = _retryAt?.difference(DateTime.now()) ?? Duration.zero;
    return server > local ? server : local;
  }

  Future<void> refresh({bool force = false, bool interactive = false}) {
    if (_pending != null) return _pending!;
    if (!mounted || !_foreground || !_observed) return Future.value();
    if (!interactive && _cooldown > Duration.zero) return Future.value();
    if (!force &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < freshness) {
      return Future.value();
    }
    return _pending = _readFirst(
      interactive,
    ).whenComplete(() => _pending = null);
  }

  Future<void> _readFirst(bool interactive) async {
    try {
      final page = await repository.list('notifications', query);
      if (!mounted) return;
      _checkedAt = DateTime.now();
      _retryAt = null;
      final previous = state.valueOrNull;
      final first = _firstPage;
      // Retain loaded history when the first-page boundary has not moved.
      final sameBoundary =
          first != null &&
          first.total == page.total &&
          first.items.length == page.items.length &&
          List.generate(
            first.items.length,
            (i) => i,
          ).every((i) => first.items[i].id == page.items[i].id);
      final combined = [...page.items];
      var next = page.nextCursor;
      if (sameBoundary && previous != null) {
        while (next != null && combined.length < previous.items.length) {
          final older = await repository.list(
            'notifications',
            Query(
              limit: query.limit,
              cursor: next,
              search: query.search,
              notificationCategory: query.notificationCategory,
              unreadOnly: query.unreadOnly,
            ),
          );
          if (!mounted) return;
          final ids = combined.map((r) => r.id).toSet();
          if (older.total != page.total ||
              older.items.isEmpty ||
              older.nextCursor == next ||
              older.items.any((r) => !ids.add(r.id))) {
            // Do not splice two offset snapshots together.
            combined.removeRange(page.items.length, combined.length);
            next = page.nextCursor;
            break;
          }
          combined.addAll(older.items);
          next = older.nextCursor;
        }
      }
      _firstPage = page;
      if (!state.hasError &&
          previous != null &&
          identical(page, first) &&
          previous.items.length == combined.length &&
          List.generate(
            combined.length,
            (i) => i,
          ).every((i) => identical(previous.items[i], combined[i])))
        return;
      state = AsyncData(
        PageResult(
          combined,
          total: page.total,
          unread: page.unread,
          nextCursor: next,
        ),
      );
    } catch (error, stack) {
      if (!mounted) return;
      _failed(error, stack, interactive: interactive);
    }
  }

  void _failed(Object error, StackTrace stack, {required bool interactive}) {
    if (error is ApiFailure &&
        [
          FailureKind.unauthorized,
          FailureKind.forbidden,
        ].contains(error.kind)) {
      _firstPage = null;
      state = AsyncError(error, stack);
      return;
    }
    _retryAt = DateTime.now().add(
      error is ApiFailure && error.statusCode == 429
          ? error.retryAfter ?? const Duration(seconds: 60)
          : freshness,
    );
    if (!state.hasValue) {
      state = AsyncError(error, stack);
    } else if (interactive) {
      state = AsyncError<PageResult>(error, stack).copyWithPrevious(state);
    }
    // Automatic revalidation must not replace an existing list with an error UI.
  }

  Future<void> loadMore() {
    if (_pending != null) return _pending!;
    final page = state.valueOrNull;
    if (!mounted || page == null || page.nextCursor == null)
      return Future.value();
    return _pending = _readMore(page).whenComplete(() => _pending = null);
  }

  Future<void> _readMore(PageResult previous) async {
    state = const AsyncLoading<PageResult>().copyWithPrevious(state);
    try {
      final page = await repository.list(
        'notifications',
        Query(
          limit: query.limit,
          cursor: previous.nextCursor,
          search: query.search,
          notificationCategory: query.notificationCategory,
          unreadOnly: query.unreadOnly,
        ),
      );
      if (!mounted) return;
      final ids = previous.items.map((r) => r.id).toSet();
      if (page.total != previous.total ||
          page.items.isEmpty ||
          page.nextCursor == previous.nextCursor ||
          page.items.any((r) => !ids.add(r.id))) {
        // Offset boundaries changed. Revalidate once; never loop through history.
        state = AsyncData(previous);
        _firstPage = null;
        await _readFirst(true);
        return;
      }
      state = AsyncData(
        PageResult(
          [...previous.items, ...page.items],
          total: page.total,
          nextCursor: page.nextCursor,
          unread: page.unread,
        ),
      );
    } catch (error, stack) {
      if (mounted) _failed(error, stack, interactive: true);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
