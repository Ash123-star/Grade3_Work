import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A single-content sibling transition. Inner boundaries reject the drag so
/// the enclosing branch pager can handle it in the gesture arena.
class SiblingSwipe extends StatefulWidget {
  const SiblingSwipe({
    super.key,
    required this.index,
    required this.itemCount,
    required this.onStep,
    required this.child,
  });

  final int index, itemCount;
  final bool Function(int step) onStep;
  final Widget child;

  @override
  State<SiblingSwipe> createState() => _SiblingSwipeState();
}

class _SiblingSwipeState extends State<SiblingSwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);
  double _offset = 0, _width = 1, _from = 0, _to = 0;
  bool _switching = false;

  bool _canStep(int step) =>
      widget.index + step >= 0 && widget.index + step < widget.itemCount;

  @override
  void initState() {
    super.initState();
    _motion.addListener(() {
      setState(
        () => _offset =
            _from +
            (_to - _from) * Curves.easeOutCubic.transform(_motion.value),
      );
    });
  }

  Future<void> _settle(double target, {int milliseconds = 180}) async {
    if (!mounted) return;
    _from = _offset;
    _to = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _offset = target);
      return;
    }
    _motion.duration = Duration(milliseconds: milliseconds);
    await _motion.forward(from: 0).orCancel;
  }

  @override
  void didUpdateWidget(covariant SiblingSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index && !_switching) {
      _motion.stop();
      _offset = widget.index > oldWidget.index ? _width : -_width;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settle(0).ignore();
      });
    }
  }

  Future<void> _end(DragEndDetails details) async {
    if (_switching) return;
    final velocity = details.primaryVelocity ?? 0;
    final step = _offset < 0 ? 1 : -1;
    final commit =
        _canStep(step) &&
        (_offset.abs() >= _width * .22 ||
            (_offset.abs() >= 20 &&
                velocity.abs() >= 500 &&
                velocity.sign == _offset.sign));
    _switching = true;
    try {
      if (!commit) {
        await _settle(0);
        return;
      }
      await _settle(-step * _width, milliseconds: 120);
      if (!mounted) return;
      if (!widget.onStep(step)) {
        await _settle(0);
        return;
      }
      // Wait for the new provider/state/route content before sliding it in.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      setState(() => _offset = step * _width);
      await _settle(0, milliseconds: 160);
    } on TickerCanceled {
      // Disposed or replaced by a newer transition.
    } finally {
      _switching = false;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      return GuardedHorizontalDrag(
        canDrag: (step) => _switching || _canStep(step),
        onStart: (_) {
          if (!_switching) _motion.stop();
        },
        onUpdate: (details) {
          if (_switching) return;
          final next = _offset + (details.primaryDelta ?? 0);
          final step = next < 0 ? 1 : -1;
          setState(
            () => _offset = _canStep(step) ? next.clamp(-_width, _width) : 0,
          );
        },
        onEnd: (details) => _end(details),
        onCancel: () {
          if (!_switching && mounted) _settle(0).ignore();
        },
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(_offset, 0),
            child: IgnorePointer(ignoring: _switching, child: widget.child),
          ),
        ),
      );
    },
  );
}

/// Shared gesture boundary for both the native branch PageView and siblings.
/// Direction is rejected before the horizontal drag wins, allowing an outer
/// pager to take over without calling navigation twice.
class GuardedHorizontalDrag extends StatefulWidget {
  const GuardedHorizontalDrag({
    super.key,
    required this.canDrag,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.child,
  });
  final bool Function(int step) canDrag;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final VoidCallback onCancel;
  final Widget child;

  @override
  State<GuardedHorizontalDrag> createState() => _GuardedHorizontalDragState();
}

class _GuardedHorizontalDragState extends State<GuardedHorizontalDrag> {
  final _pointers = <int>{};
  bool _cancelled = false;

  bool _allowed(PointerEvent event) {
    final media = MediaQuery.of(context);
    return media.viewInsets.bottom == 0 &&
        ModalRoute.of(context)?.isCurrent != false &&
        event.position.dx >= 24 &&
        event.position.dx <= media.size.width - 24;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_pointers.isEmpty) _cancelled = false;
      _pointers.add(event.pointer);
      if (_pointers.length > 1) {
        _cancelled = true;
        widget.onCancel();
      }
    },
    onPointerUp: (event) => _pointers.remove(event.pointer),
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _cancelled = true;
      widget.onCancel();
    },
    child: RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _NavigationDrag: GestureRecognizerFactoryWithHandlers<_NavigationDrag>(
          _NavigationDrag.new,
          (gesture) {
            gesture
              ..allowed = _allowed
              ..canDrag = widget.canDrag
              ..onStart = (details) {
                if (!_cancelled) widget.onStart(details);
              }
              ..onUpdate = (details) {
                if (!_cancelled) widget.onUpdate(details);
              }
              ..onEnd = (details) {
                if (_cancelled ||
                    MediaQuery.viewInsetsOf(context).bottom > 0 ||
                    ModalRoute.of(context)?.isCurrent == false) {
                  widget.onCancel();
                } else {
                  widget.onEnd(details);
                }
              }
              ..onCancel = () {
                widget.onCancel();
              };
          },
        ),
      },
      child: widget.child,
    ),
  );
}

class _NavigationDrag extends HorizontalDragGestureRecognizer {
  bool Function(PointerEvent)? allowed;
  bool Function(int)? canDrag;
  Offset? _origin;
  int? _pointer;
  bool _directionChecked = false;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (allowed?.call(event) ?? false) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer == null) {
      _pointer = event.pointer;
      _origin = event.position;
      _directionChecked = false;
    }
    super.addAllowedPointer(event);
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) {
      _pointer = null;
      _origin = null;
    }
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer == _pointer &&
        event is PointerMoveEvent &&
        !_directionChecked &&
        _origin != null) {
      final delta = event.position - _origin!;
      if (delta.dx.abs() > 4 && delta.dx.abs() > delta.dy.abs()) {
        _directionChecked = true;
        if (!(canDrag?.call(delta.dx < 0 ? 1 : -1) ?? false)) {
          resolve(GestureDisposition.rejected);
          _pointer = null;
          _origin = null;
          return;
        }
      }
    }
    super.handleEvent(event);
    if (event.pointer == _pointer &&
        (event is PointerUpEvent || event is PointerCancelEvent)) {
      _pointer = null;
      _origin = null;
    }
  }
}
