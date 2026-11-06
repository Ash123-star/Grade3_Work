import 'dart:async';
import 'package:flutter/material.dart';
import 'generated_assets.dart';
import '../theme/sunshine_palette.dart';

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
      final (ink, asset, status) = switch (tone) {
        NoticeTone.success => (SunshinePalette.ink, 'success', '成功'),
        NoticeTone.error => (SunshinePalette.error, 'error', '错误'),
        NoticeTone.warning => (SunshinePalette.accentInk, 'notification', '注意'),
        NoticeTone.info => (SunshinePalette.ink, 'help', '提示'),
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
                    color: const Color(0xFFFFFAF0),
                    elevation: 4,
                    shadowColor: const Color(0x335F471B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFFEADBB9)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: SunshinePalette.butter,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Image.asset(
                                TuantuanAssets.icons[asset]!,
                                width: 28,
                                height: 28,
                                excludeFromSemantics: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Semantics(
                                    label: '$status：$text',
                                    excludeSemantics: true,
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        color: ink,
                                        fontSize: 14,
                                        height: 1.45,
                                        fontWeight: FontWeight.w600,
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
                                        style: const TextStyle(
                                          color: SunshinePalette.accentInk,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭提示',
                              onPressed: close,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: SunshinePalette.muted,
                                size: 18,
                              ),
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
          color: const Color(0xFFFFFAF0),
          elevation: 2,
          borderRadius: BorderRadius.circular(24),
          child: TextButton.icon(
            onPressed: () => setState(() => dismissed = false),
            icon: Image.asset(
              TuantuanAssets.icons['help']!,
              width: 24,
              height: 24,
              excludeFromSemantics: true,
            ),
            label: const Text('查看操作提示'),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Material(
        color: const Color(0xFFFFFAF0),
        elevation: 4,
        shadowColor: const Color(0x335F471B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEADBB9)),
        ),
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
                    const SunshineMascot(size: 28),
                    const SizedBox(width: 8),
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
