import 'package:flutter/material.dart';
import 'package:cute_ui/cute_ui.dart'
    hide EmptyIllustration, ErrorPanel, LoadingSkeleton;

class PaperLayoutTokens extends ThemeExtension<PaperLayoutTokens> {
  const PaperLayoutTokens({this.cardRadius = 20, this.sectionGap = 20});
  final double cardRadius, sectionGap;
  @override
  PaperLayoutTokens copyWith({double? cardRadius, double? sectionGap}) =>
      PaperLayoutTokens(
        cardRadius: cardRadius ?? this.cardRadius,
        sectionGap: sectionGap ?? this.sectionGap,
      );
  @override
  PaperLayoutTokens lerp(covariant PaperLayoutTokens? other, double t) =>
      other == null
      ? this
      : PaperLayoutTokens(
          cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
          sectionGap: sectionGap + (other.sectionGap - sectionGap) * t,
        );
}

/// App-owned semantic roles; cute_ui reads these through its theme extension.
class SunnyPalette {
  static const primary = Color(0xFF55D8A5);
  static const primaryStrong = Color(0xFF319E7A);
  static const onPrimary = Color(0xFF193A2D);
  static const paper = Color(0xFFFFFDF4);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF43514B);
  static const muted = Color(0xFF7F8B83);
  static const mint = Color(0xFFE6FAEF);
  static const blue = Color(0xFFDDF1FA);
  static const purple = Color(0xFFF1E7FF);
  static const orange = Color(0xFFFFF4B8);
  static const coral = Color(0xFFFFE1E1);
  static const brandOrange = Color(0xFFFF8A24);
  static const calendarEntries = [coral, mint, blue, purple];
}

/// Semantic roles owned by the app, separate from immutable illustration colors.
class SunnyPaperTokens extends ThemeExtension<SunnyPaperTokens> {
  const SunnyPaperTokens({
    this.canvas = SunnyPalette.paper,
    this.pressed = const Color(0xFF319E7A),
    this.actionEdge = const Color(0xFF247B5D),
    this.focus = const Color(0xFF8B4AC9),
    this.warm = const Color(0xFFFFF4B8),
    this.ai = SunnyPalette.purple,
    this.information = SunnyPalette.blue,
    this.success = SunnyPalette.mint,
    this.disabled = const Color(0xFFF1E8DC),
    this.disabledInk = SunnyPalette.muted,
    this.cardRadius = 20,
    this.buttonRadius = 18,
    this.buttonEdge = 3,
    this.pressDuration = const Duration(milliseconds: 100),
  });
  final Color canvas,
      pressed,
      actionEdge,
      focus,
      warm,
      ai,
      information,
      success,
      disabled,
      disabledInk;
  final double cardRadius, buttonRadius, buttonEdge;
  final Duration pressDuration;

  static SunnyPaperTokens of(BuildContext context) =>
      Theme.of(context).extension<SunnyPaperTokens>() ??
      const SunnyPaperTokens();

  @override
  SunnyPaperTokens copyWith({
    Color? canvas,
    Color? pressed,
    Color? actionEdge,
    Color? focus,
    Color? warm,
    Color? ai,
    Color? information,
    Color? success,
    Color? disabled,
    Color? disabledInk,
    double? cardRadius,
    double? buttonRadius,
    double? buttonEdge,
    Duration? pressDuration,
  }) => SunnyPaperTokens(
    canvas: canvas ?? this.canvas,
    pressed: pressed ?? this.pressed,
    actionEdge: actionEdge ?? this.actionEdge,
    focus: focus ?? this.focus,
    warm: warm ?? this.warm,
    ai: ai ?? this.ai,
    information: information ?? this.information,
    success: success ?? this.success,
    disabled: disabled ?? this.disabled,
    disabledInk: disabledInk ?? this.disabledInk,
    cardRadius: cardRadius ?? this.cardRadius,
    buttonRadius: buttonRadius ?? this.buttonRadius,
    buttonEdge: buttonEdge ?? this.buttonEdge,
    pressDuration: pressDuration ?? this.pressDuration,
  );

  @override
  SunnyPaperTokens lerp(covariant SunnyPaperTokens? other, double t) {
    if (other == null) return this;
    double mix(double a, double b) => a + (b - a) * t;
    return SunnyPaperTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      pressed: Color.lerp(pressed, other.pressed, t)!,
      actionEdge: Color.lerp(actionEdge, other.actionEdge, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      ai: Color.lerp(ai, other.ai, t)!,
      information: Color.lerp(information, other.information, t)!,
      success: Color.lerp(success, other.success, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledInk: Color.lerp(disabledInk, other.disabledInk, t)!,
      cardRadius: mix(cardRadius, other.cardRadius),
      buttonRadius: mix(buttonRadius, other.buttonRadius),
      buttonEdge: mix(buttonEdge, other.buttonEdge),
      pressDuration: Duration(
        microseconds: mix(
          pressDuration.inMicroseconds.toDouble(),
          other.pressDuration.inMicroseconds.toDouble(),
        ).round(),
      ),
    );
  }
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SunnyPalette.primary,
    primary: SunnyPalette.primary,
    onPrimary: SunnyPalette.onPrimary,
    primaryContainer: SunnyPalette.mint,
    onPrimaryContainer: const Color(0xFF246447),
    secondary: const Color(0xFF7650B6),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFF1E7FF),
    onSecondaryContainer: const Color(0xFF7650B6),
    tertiary: const Color(0xFF319E7A),
    onTertiary: Colors.white,
    tertiaryContainer: SunnyPalette.mint,
    onTertiaryContainer: const Color(0xFF246447),
    surface: SunnyPalette.surface,
    onSurface: SunnyPalette.ink,
    onSurfaceVariant: SunnyPalette.muted,
    outline: const Color(0xFFB7CFC2),
    outlineVariant: const Color(0xFFE1EEE7),
    error: const Color(0xFFC94E5B),
    errorContainer: SunnyPalette.coral,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, letterSpacing: 0),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: SunnyPalette.muted,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SunnyPalette.muted,
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: SunnyPalette.paper,
    extensions: const [CuteTokens(), PaperLayoutTokens(), SunnyPaperTokens()],
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SunnyPalette.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: SunnyPalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: TextStyle(
        color: SunnyPalette.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: SunnyPalette.muted,
        fontSize: 15,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: SunnyPalette.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFFB7CFC2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      modalElevation: 8,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SunnyPalette.paper,
      foregroundColor: SunnyPalette.ink,
      centerTitle: false,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: SunnyPalette.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SunnyPalette.primary,
        foregroundColor: SunnyPalette.onPrimary,
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SunnyPalette.ink,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SunnyPalette.primary,
      foregroundColor: SunnyPalette.onPrimary,
      shape: CircleBorder(),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SunnyPalette.surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB7CFC2), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF319E7A), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFC94E5B), width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB33643), width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SunnyPalette.surface,
      indicatorColor: SunnyPalette.mint,
      height: 76,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? const Color(0xFF319E7A)
              : SunnyPalette.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? const Color(0xFF319E7A)
              : SunnyPalette.muted,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: const WidgetStatePropertyAll(SunnyPalette.ink),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SunnyPalette.primary
              : const Color(0xFFFFF0DA),
        ),
      ),
    ),
  );
}
