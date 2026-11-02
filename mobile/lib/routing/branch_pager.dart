import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/shared/sibling_swipe.dart';

/// Keeps go_router's branch Navigators mounted while PageView translates them.
class BranchPager extends StatefulWidget {
  const BranchPager({super.key, required this.shell, required this.children});
  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  State<BranchPager> createState() => _BranchPagerState();
}

class _BranchPagerState extends State<BranchPager> {
  late final PageController _controller = PageController(
    initialPage: widget.shell.currentIndex,
  );
  Drag? _drag;
  bool _reverting = false;

  @override
  void didUpdateWidget(covariant BranchPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shell.currentIndex != oldWidget.shell.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients && _drag == null) {
          _moveTo(widget.shell.currentIndex);
        }
      });
    }
  }

  void _moveTo(int index) {
    if (!_controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
    } else if (((_controller.page ?? index) - index).abs() > .001) {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _cancel() {
    if (_drag == null) return;
    _reverting = true;
    _drag?.cancel();
    _drag = null;
    _moveTo(widget.shell.currentIndex);
  }

  @override
  void dispose() {
    _drag?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GuardedHorizontalDrag(
    canDrag: (step) {
      final next = widget.shell.currentIndex + step;
      return next >= 0 && next < widget.children.length;
    },
    onStart: (details) {
      if (!_controller.hasClients) return;
      _reverting = false;
      _drag = _controller.position.drag(details, () => _drag = null);
    },
    onUpdate: (details) => _drag?.update(details),
    onEnd: (details) {
      final drag = _drag;
      _drag = null;
      drag?.end(details);
    },
    onCancel: _cancel,
    child: NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 || !_controller.hasClients) return false;
        final index = _controller.page?.round() ?? widget.shell.currentIndex;
        if (!_reverting && index != widget.shell.currentIndex) {
          widget.shell.goBranch(index);
        }
        _reverting = false;
        return false;
      },
      child: PageView(
        key: const ValueKey('bottom-branch-pager'),
        controller: _controller,
        // The guarded recognizer drives the native ScrollPosition, retaining
        // PageView's drag, snapping and ballistic motion without edge conflicts.
        physics: const NeverScrollableScrollPhysics(),
        allowImplicitScrolling: true,
        children: [
          for (final (index, child) in widget.children.indexed)
            _KeptBranch(
              key: ValueKey(index),
              active: index == widget.shell.currentIndex,
              child: child,
            ),
        ],
      ),
    ),
  );
}

class _KeptBranch extends StatefulWidget {
  const _KeptBranch({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<_KeptBranch> createState() => _KeptBranchState();
}

class _KeptBranchState extends State<_KeptBranch>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      enabled: widget.active,
      child: ExcludeFocus(excluding: !widget.active, child: widget.child),
    );
  }
}
