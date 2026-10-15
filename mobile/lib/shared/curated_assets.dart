import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

/// Local Phosphor assets inherit the Material icon theme.
class AppArtworkIcon extends StatelessWidget {
  const AppArtworkIcon(
    this.name, {
    super.key,
    this.filled = false,
    this.size,
    this.color,
  });
  final String name;
  final bool filled;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return ExcludeSemantics(
      child: SvgPicture.asset(
        'assets/phosphor/$name${filled ? '-fill' : ''}.svg',
        width: size ?? theme.size ?? 24,
        height: size ?? theme.size ?? 24,
        colorFilter: ColorFilter.mode(
          color ?? theme.color ?? SunnyPalette.ink,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

/// Forui supplies the real badge widget; all visual roles remain app-owned.
class AppLabelBadge extends StatelessWidget {
  const AppLabelBadge(
    this.label, {
    super.key,
    this.color = SunnyPalette.orange,
    this.fontSize = 12,
    this.compact = false,
  });
  final String label;
  final Color color;
  final double fontSize;
  final bool compact;

  @override
  Widget build(BuildContext context) => FBadge(
    style: (_) => FBadgeStyle(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      contentStyle: FBadgeContentStyle(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 3 : 4,
        ),
        labelTextStyle: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: SunnyPalette.ink,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

enum CompanionPet { cat, dog }

/// Original decorative artwork never intercepts gestures or user identity semantics.
class PetCompanion extends StatelessWidget {
  const PetCompanion({super.key, this.pet = CompanionPet.cat, this.size = 72});
  final CompanionPet pet;
  final double size;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SvgPicture.asset(
        'assets/companions/${pet.name}.svg',
        width: size,
        height: size,
      ),
    ),
  );
}

bool _licensesRegistered = false;
void registerCuratedAssetLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    for (final entry in [('Phosphor Icons', 'phosphor'), ('Forui', 'forui')]) {
      yield LicenseEntryWithLineBreaks(
        [entry.$1],
        await rootBundle.loadString('assets/licenses/${entry.$2}-LICENSE.txt'),
      );
    }
  });
}
