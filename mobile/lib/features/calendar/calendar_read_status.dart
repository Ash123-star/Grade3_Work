import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/api_failure.dart';

/// A cooldown is explicit and user-driven; this widget never starts HTTP work.
class CalendarReadStatus extends StatefulWidget {
  const CalendarReadStatus({
    super.key,
    required this.failure,
    required this.onRetry,
    this.now,
  });
  final ApiFailure failure;
  final VoidCallback onRetry;
  final DateTime Function()? now;
  @override
  State<CalendarReadStatus> createState() => _CalendarReadStatusState();
}

class _CalendarReadStatusState extends State<CalendarReadStatus> {
  Timer? _timer;
  late DateTime _until;
  DateTime get _now => (widget.now ?? DateTime.now)();
  int get _seconds => (_until.difference(_now).inMilliseconds / 1000)
      .ceil()
      .clamp(0, 2147483647);
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    _until = _now.add(widget.failure.retryAfter ?? const Duration(seconds: 60));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds == 0) timer.cancel();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CalendarReadStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failure, widget.failure)) _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('calendar-read-cooldown'),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请求较多，月历暂停刷新'),
          Text(_seconds > 0 ? '$_seconds 秒后可重试，已有记录仅供查看' : '可以重新加载最新排期'),
          TextButton(
            onPressed: _seconds > 0 ? null : widget.onRetry,
            child: const Text('重新加载月历'),
          ),
        ],
      ),
    ),
  );
}
