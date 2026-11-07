import 'package:flutter/material.dart';
import 'calendar_drag_controller.dart';
import 'calendar_schedule.dart';

/// Date feedback only. Candidate bars are laid out in the month's free lanes.
class CalendarDragPreview extends StatelessWidget {
  const CalendarDragPreview({
    super.key,
    required this.drag,
    required this.overlayOrigin,
  });
  final CalendarDragController drag;
  final Offset overlayOrigin;

  @override
  Widget build(BuildContext context) {
    final area = drag.bounds!;
    final colors = Theme.of(context).colorScheme;
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
