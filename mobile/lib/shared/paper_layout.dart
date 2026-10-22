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
    this.texture,
    this.cornerDecoration,
    this.textureOpacity = .16,
    this.skin,
    this.decorated = false,
    this.borderColor,
  });
  final Widget child;
  final Color? color;
  final bool outlined;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? texture;
  final String? cornerDecoration;
  final double textureOpacity;
  final String? skin;
  final bool decorated;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final layout = SunnyPaperTokens.of(context);
    final base = color ?? Theme.of(context).colorScheme.surface;
    final paper =
        texture ??
        TuantuanAssets.textures[base == SunnyPalette.purple
            ? 'lavenderCloud'
            : base == SunnyPalette.coral
            ? 'coralDots'
            : base == SunnyPalette.mint
            ? 'mintGrid'
            : 'paper'];
    final surfaceSkin =
        skin ?? TuantuanAssets.detailSections[TuantuanAssets.tone(base)]!;
    final surface = Material(
      color: base,
      elevation: onTap == null ? 0 : 1,
      shadowColor: const Color(0x183E6654),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.cardRadius),
        side: BorderSide(
          color: borderColor ?? (outlined
              ? Theme.of(context).colorScheme.outline
              : const Color(0xFFE1EEE7)),
          width: outlined ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (decorated) ...[
            Positioned.fill(child: TuantuanSkin(surfaceSkin)),
            if (paper != null)
              Positioned.fill(
                child: TuantuanArt(
                  paper,
                  fit: BoxFit.cover,
                  opacity: textureOpacity,
                ),
              ),
            if (cornerDecoration != null)
              Positioned(
                right: 10,
                bottom: 8,
                child: TuantuanArt(
                  cornerDecoration!,
                  width: 42,
                  height: 42,
                  opacity: .8,
                ),
              ),
          ],
          InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
    return surface;
  }
}

class TuantuanIconTile extends StatelessWidget {
  const TuantuanIconTile({
    super.key,
    required this.icon,
    this.color,
    this.skin = 'cream',
    this.size = 48,
  });
  final String icon;
  final Color? color;
  final String skin;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD6E9DE)),
    ),
    child: Center(child: TuantuanIcon(icon, size: size - 14)),
  );
}

class TuantuanRecordCard extends StatelessWidget {
  const TuantuanRecordCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.accent = SunnyPalette.primaryContainer,
    this.onTap,
    this.texture,
    this.cornerDecoration,
  });
  final String icon, title, subtitle;
  final Widget? trailing;
  final Color accent;
  final VoidCallback? onTap;
  final String? texture;
  final String? cornerDecoration;

  @override
  Widget build(BuildContext context) => PaperSurface(
    onTap: onTap,
    texture: texture,
    skin: TuantuanAssets.detailSections[TuantuanAssets.tone(accent)],
    cornerDecoration: cornerDecoration,
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
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    ),
  );
}

class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.wrapLabels = false,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool wrapLabels;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: Semantics(
              selected: index == selected,
              child: Material(
                color: index == selected
                    ? Theme.of(context).colorScheme.surface
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (index == selected) ...[
                              Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                overflow: wrapLabels ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: index == selected
                                      ? Theme.of(context).colorScheme.primary
                                      : SunnyPalette.ink,
                                ),
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
      ],
    ),
  );
}

/// A compact filter chip using the current theme colors.
class TuantuanFilterChip extends StatelessWidget {
  const TuantuanFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: label,
    selected: selected,
    onSelected: onSelected,
    showCheckmark: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    selectedColor: Theme.of(context).colorScheme.secondaryContainer,
    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    surfaceTintColor: Colors.transparent,
    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

/// Material confirmation retains native focus, semantics and scroll handling.
class TuantuanDialog extends StatelessWidget {
  const TuantuanDialog({super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: title,
    content: content,
    actions: actions,
    titleTextStyle: Theme.of(context).textTheme.titleLarge,
  );
}

/// Shared sheet skin, while the original sheet body owns height and scrolling.
Future<T?> showTuantuanBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool? showDragHandle,
  bool useSafeArea = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  showDragHandle: showDragHandle,
  useSafeArea: useSafeArea,
  builder: (context) {
    final body = builder(context);
    return body is TuantuanSheet ? body : TuantuanSheet(child: body);
  },
);

class TuantuanSheet extends StatelessWidget {
  const TuantuanSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: child,
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
