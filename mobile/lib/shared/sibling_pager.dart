import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'generated_assets.dart' show TuantuanPaperBackdrop;
import 'sibling_swipe.dart';

/// Lays out adjacent pages together; routing changes only after drag settling.
class SiblingPager extends StatefulWidget {
  const SiblingPager({
    super.key,
    required this.index,
    required this.itemCount,
    required this.onSelected,
    required this.itemBuilder,
  });

  final int index, itemCount;
  final ValueChanged<int> onSelected;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<SiblingPager> createState() => _SiblingPagerState();
}

class _SiblingPagerState extends State<SiblingPager> {
  late final PageController _controller = PageController(
    initialPage: widget.index,
  );
  Drag? _drag;
  bool _gesturePending = false, _syncing = false;
  int _motionVersion = 0;

  @override
  void didUpdateWidget(covariant SiblingPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveTo(widget.index);
      });
    }
  }

  Future<void> _moveTo(int index) async {
    if (!_controller.hasClients) return;
    _gesturePending = false;
    _drag?.cancel();
    _drag = null;
    final version = ++_motionVersion;
    _syncing = true;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(index);
      } else if (((_controller.page ?? index) - index).abs() > .001) {
        await _controller.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      if (version == _motionVersion) _syncing = false;
    }
  }

  void _cancel() {
    if (_drag == null) return;
    _gesturePending = false;
    _drag?.cancel();
    _drag = null;
    _moveTo(widget.index);
  }

  @override
  void dispose() {
    _motionVersion++;
    _gesturePending = false;
    _drag?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: TuantuanPaperBackdrop(
      child: GuardedHorizontalDrag(
        canDrag: (step) =>
            widget.index + step >= 0 && widget.index + step < widget.itemCount,
        onStart: (details) {
          if (!_controller.hasClients) return;
          _motionVersion++;
          _syncing = false;
          _gesturePending = false;
          _drag = _controller.position.drag(details, () => _drag = null);
        },
        onUpdate: (details) => _drag?.update(details),
        onEnd: (details) {
          final drag = _drag;
          _drag = null;
          _gesturePending = drag != null;
          drag?.end(details);
        },
        onCancel: _cancel,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.depth != 0 ||
                !_controller.hasClients ||
                !_gesturePending ||
                _syncing) {
              return false;
            }
            _gesturePending = false;
            if (MediaQuery.viewInsetsOf(context).bottom > 0 ||
                ModalRoute.of(context)?.isCurrent == false) {
              _moveTo(widget.index);
              return false;
            }
            final index = _controller.page?.round() ?? widget.index;
            if (index != widget.index) widget.onSelected(index);
            return false;
          },
          child: PageView.builder(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => _KeptSibling(
              key: ValueKey(index),
              active: index == widget.index,
              child: widget.itemBuilder(context, index),
            ),
          ),
        ),
      ),
    ),
  );
}

class _KeptSibling extends StatefulWidget {
  const _KeptSibling({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_KeptSibling> createState() => _KeptSiblingState();
}

class _KeptSiblingState extends State<_KeptSibling>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      enabled: widget.active,
      child: ExcludeSemantics(
        excluding: !widget.active,
        child: ExcludeFocus(excluding: !widget.active, child: widget.child),
      ),
    );
  }
}
