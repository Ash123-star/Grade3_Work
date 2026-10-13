import 'package:flutter/material.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

/// Shared geometry for the approved stage-3 reference, without business logic.
class PaperSurface extends StatelessWidget {
  const PaperSurface({
    super.key,
    required this.child,
    this.color,
    this.outlined = false,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final Color? color;
  final bool outlined;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final layout = SunnyPaperTokens.of(context);
    return Material(
      color: color ?? Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.cardRadius),
        side: outlined
            ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: SunnyPaperTokens.of(context).warm,
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: Semantics(
              selected: index == selected,
              child: Material(
                color: index == selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => onChanged(index),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class BottomActions extends StatelessWidget {
  const BottomActions({
    super.key,
    required this.primary,
    this.secondary,
    this.note,
  });
  final Widget primary;
  final Widget? secondary;
  final String? note;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (secondary != null) ...[
                  Flexible(flex: 2, child: secondary!),
                  const SizedBox(width: 12),
                ],
                Expanded(flex: 4, child: primary),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
