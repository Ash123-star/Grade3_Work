import 'dart:async';
import 'package:flutter/material.dart';

enum NoticeTone { info, success, warning, error }

OverlayEntry? _activeNotice;

/// Root overlay: neither Scaffold layout nor its FAB is moved by a message.
void showAppNotice(
  BuildContext context,
  String text,
  NoticeTone tone, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeNotice?.remove();
  _activeNotice?.dispose();
  late final OverlayEntry entry;
  void close() {
    if (_activeNotice != entry) return;
    _activeNotice = null;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (context) {
      final media = MediaQuery.of(context);
      final (background, ink, icon) = switch (tone) {
        NoticeTone.success => (
          const Color(0xFFEAF6F0),
          const Color(0xFF246447),
          Icons.check_circle_outline,
        ),
        NoticeTone.error => (
          const Color(0xFFFBEFEC),
          const Color(0xFF963F38),
          Icons.error_outline,
        ),
        NoticeTone.warning => (
          const Color(0xFFFFF5E5),
          const Color(0xFF805B24),
          Icons.warning_amber_rounded,
        ),
        NoticeTone.info => (
          const Color(0xFFEDF3F8),
          const Color(0xFF365C78),
          Icons.info_outline,
        ),
      };
      return Positioned(
        top: media.padding.top + 12,
        left: 16,
        right: 16,
        child: _NoticeLifetime(
          duration: media.accessibleNavigation
              ? null
              : Duration(seconds: tone == NoticeTone.error ? 7 : 4),
          onTimeout: close,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight:
                    (media.size.height -
                            media.viewInsets.bottom -
                            media.padding.top -
                            24)
                        .clamp(48.0, 220.0)
                        .toDouble(),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: media.disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                builder: (_, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: background,
                    elevation: 5,
                    shadowColor: const Color(0x2232463E),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 2, 4),
                        child: Row(
                          children: [
                            Icon(icon, color: ink),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            if (onAction != null)
                              TextButton(
                                onPressed: () {
                                  close();
                                  onAction();
                                },
                                child: Text(
                                  actionLabel ?? '查看',
                                  style: TextStyle(color: ink),
                                ),
                              ),
                            IconButton(
                              tooltip: '关闭提示',
                              onPressed: close,
                              icon: Icon(Icons.close_rounded, color: ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  _activeNotice = entry;
  overlay.insert(entry);
}

class _NoticeLifetime extends StatefulWidget {
  const _NoticeLifetime({
    required this.duration,
    required this.onTimeout,
    required this.child,
  });
  final Duration? duration;
  final VoidCallback onTimeout;
  final Widget child;
  @override
  State<_NoticeLifetime> createState() => _NoticeLifetimeState();
}

class _NoticeLifetimeState extends State<_NoticeLifetime> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (widget.duration != null) {
      timer = Timer(widget.duration!, widget.onTimeout);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Persistent actionable errors float above content and can be dismissed.
class FloatingFeedback extends StatefulWidget {
  const FloatingFeedback({super.key, required this.child});
  final Widget child;
  @override
  State<FloatingFeedback> createState() => _FloatingFeedbackState();
}

class _FloatingFeedbackState extends State<FloatingFeedback> {
  bool dismissed = false;
  @override
  Widget build(BuildContext context) {
    if (dismissed) {
      return Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(24),
          child: TextButton.icon(
            onPressed: () => setState(() => dismissed = false),
            icon: const Icon(Icons.info_outline),
            label: const Text('查看操作提示'),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 5,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                ((MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom -
                            MediaQuery.paddingOf(context).vertical -
                            100) *
                        .5)
                    .clamp(48.0, 320.0)
                    .toDouble(),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        '操作提示',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭提示',
                      onPressed: () => setState(() => dismissed = true),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
