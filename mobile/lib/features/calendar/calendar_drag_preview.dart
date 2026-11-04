import 'package:flutter/material.dart';
import 'calendar_drag_controller.dart';
import 'calendar_schedule.dart';

/// A visual snapshot of the picked-up segment. The domain intent stays in the
/// controller; neither this replica nor its position can modify task data.
class CalendarDragAppearance {
  const CalendarDragAppearance({
    required this.rect,
    required this.grabOffset,
    required this.child,
  });
  final Rect rect;
  final Offset grabOffset;
  final Widget child;
}

class CalendarDragPreview extends StatelessWidget {
  const CalendarDragPreview({
    super.key,
    required this.drag,
    required this.appearance,
    required this.overlayOrigin,
  });
  final CalendarDragController drag;
  final CalendarDragAppearance appearance;
  final Offset overlayOrigin;

  @override
  Widget build(BuildContext context) {
    final area = drag.bounds!;
    final colors = Theme.of(context).colorScheme;
    final position = drag.pointer - appearance.grabOffset - overlayOrigin;
    final width = (area.width - 16).clamp(0.0, 320.0);
    final hintLeft = (drag.pointer.dx - width / 2).clamp(
      area.left + 8,
      area.right - width - 8,
    );
    final shown = drag.present();
    final target = drag.target;
    final preview = shown?.schedule;
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: position.dx,
                top: position.dy - 8,
                width: appearance.rect.width,
                height: appearance.rect.height,
                child: RepaintBoundary(
                  child: Material(
                    key: const ValueKey('calendar-drag-bar'),
                    elevation: 8,
                    shadowColor: colors.shadow.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(4),
                    child: appearance.child,
                  ),
                ),
              ),
              Positioned(
                left: hintLeft - overlayOrigin.dx,
                top:
                    (drag.pointer.dy > area.center.dy
                        ? drag.pointer.dy - 108
                        : drag.pointer.dy + 28) -
                    overlayOrigin.dy,
                width: width,
                child: Material(
                  elevation: 3,
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          target == null
                              ? '移到已加载日期内'
                              : '抓取处 ${businessDateText(drag.intent!.anchor)} → ${businessDateText(target.day)}',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: preview == null
                                    ? colors.error
                                    : colors.primary,
                              ),
                        ),
                        Text(
                          preview?.description ?? '此落点不可移动，松手将恢复原位',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
