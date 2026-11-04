import 'dart:async';

/// Keeps a small, short-lived set of successful month providers alive.
/// Stores disposal handles only; task data and identity stay in their provider.
class CalendarMonthRetention {
  CalendarMonthRetention({
    this.capacity = 6,
    this.ttl = const Duration(seconds: 30),
  });
  final int capacity;
  final Duration ttl;
  final _entries = <Object, ({Timer timer, void Function() close})>{};

  void Function() retain(Object key, void Function() close) {
    _evict(key);
    final timer = Timer(ttl, () => _evict(key));
    _entries[key] = (timer: timer, close: close);
    while (_entries.length > capacity) {
      _evict(_entries.keys.first);
    }
    return () {
      if (identical(_entries[key]?.timer, timer)) {
        _entries.remove(key);
        timer.cancel();
      }
    };
  }

  void _evict(Object key) {
    final entry = _entries.remove(key);
    entry?.timer.cancel();
    entry?.close();
  }

  void dispose() {
    for (final key in _entries.keys.toList()) {
      _evict(key);
    }
  }
}
