import 'package:flutter/material.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'generated_assets.dart';

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
      elevation: onTap == null ? 0 : 1,
      shadowColor: const Color(0x183E6654),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.cardRadius),
        side: BorderSide(
          color: outlined
              ? Theme.of(context).colorScheme.outline
              : const Color(0xFFE1EEE7),
          width: outlined ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class TuantuanIconTile extends StatelessWidget {
  const TuantuanIconTile({super.key, required this.icon, this.color});
  final String icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD6E9DE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x143E6654),
          offset: Offset(0, 3),
          blurRadius: 8,
        ),
      ],
    ),
    child: TuantuanIcon(icon, size: 40),
  );
}

class TuantuanRecordCard extends StatelessWidget {
  const TuantuanRecordCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.accent = SunnyPalette.mint,
    this.onTap,
  });
  final String icon, title, subtitle;
  final Widget? trailing;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PaperSurface(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        TuantuanIconTile(icon: icon, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing ??
            const Icon(Icons.chevron_right_rounded, color: SunnyPalette.muted),
      ],
    ),
  );
}

class TuantuanStatusPill extends StatelessWidget {
  const TuantuanStatusPill(
    this.label, {
    super.key,
    this.color = SunnyPalette.mint,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
        color: Color.alphaBlend(
          SunnyPalette.primaryStrong.withValues(alpha: .12),
          color,
        ),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: SunnyPalette.ink),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: SunnyPalette.ink,
          ),
        ),
      ],
    ),
  );
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
