import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'sunshine_palette.dart';

/// Values shared with the approved home-daily-todos.html prototype.
/// Home geometry shares the global sunshine brand roles.
class HomePaperTokens extends ThemeExtension<HomePaperTokens> {
  const HomePaperTokens({
    this.canvas = SunnyPalette.paper,
    this.surface = const Color(0xFFFFFEFA),
    this.note = const Color(0xFFFFF4C9),
    this.ink = const Color(0xFF3D352B),
    this.muted = const Color(0xFF796F61),
    this.line = const Color(0xFFEEE4CD),
    this.accent = SunshinePalette.yellow,
    this.green = const Color(0xFF775B10),
  });

  final Color canvas, surface, note, ink, muted, line, accent, green;
  static const accentInk = Color(0xFF3D352B);
  static const orangeInk = Color(0xFF775B10);
  static const mint = Color(0xFFFFF0AC);
  static const error = Color(0xFFA53E3B);
  static const noteEdge = Color(0xFFEFDEA5);
  static const noteShadow = Color(0x109C7B20);
  static const noteRule = Color(0xFFF0E4BE);
  static const noteFold = Color(0xFFF0DF9D);
  static const previewLine = Color(0x18775B10);
  static const moreInk = Color(0xFF775B10);
  static const messageSurface = Color(0xFFFFF5D3);
  static const messageEdge = Color(0xFFF0E3BA);
  static const unread = Color(0xFFC76C35);
  static const binding = Color(0xFFE9CD63);
  static const bindingEdge = Color(0xFFD6B752);
  static const sheetShadow = Color(0x29E8DCC7);
  static const todayEdge = Color(0xFFC29B28);
  static const outside = Color(0xFF978C78);
  static const todaySurface = Color(0xFFFFF6D4);
  static const checkEdge = Color(0xFFCABB96);
  static const completedEdge = Color(0xFFD2AF26);
  static const rowLine = Color(0xFFEEE4CD);
  static const navigationSurface = Color(0xFFFFFEFA);
  static const navigationLine = Color(0xFFEEE4CD);
  static const navigationTray = Color(0xFFFFDA35);
  static const navigationInk = Color(0xFF3D352B);
  static const navigationDot = Color(0xFF775B10);

  static HomePaperTokens of(BuildContext context) =>
      Theme.of(context).extension<HomePaperTokens>() ?? const HomePaperTokens();

  TextStyle heading(double size, {double height = 1.4}) => AppTypography.display
      .copyWith(fontSize: size, height: height, color: ink);

  TextStyle body(double size, {Color? color, double height = 1.5}) => TextStyle(
    fontFamily: 'Roboto',
    fontSize: size,
    height: height,
    color: color ?? ink,
    letterSpacing: 0,
  );

  @override
  HomePaperTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? note,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? green,
  }) => HomePaperTokens(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    note: note ?? this.note,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    green: green ?? this.green,
  );

  @override
  HomePaperTokens lerp(covariant HomePaperTokens? other, double t) =>
      other == null
      ? this
      : HomePaperTokens(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          surface: Color.lerp(surface, other.surface, t)!,
          note: Color.lerp(note, other.note, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          line: Color.lerp(line, other.line, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          green: Color.lerp(green, other.green, t)!,
        );
}

ThemeData homePaperTheme(BuildContext context) {
  final base = Theme.of(context), paper = HomePaperTokens.of(context);
  return base.copyWith(
    extensions: [
      ...base.extensions.values.where((value) => value is! HomePaperTokens),
      paper,
    ],
    scaffoldBackgroundColor: paper.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: paper.green,
      onPrimary: paper.surface,
      secondary: paper.green,
      surface: paper.surface,
      onSurface: paper.ink,
      onSurfaceVariant: paper.muted,
      outlineVariant: paper.line,
      error: HomePaperTokens.error,
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: paper.heading(18),
      titleMedium: paper.heading(16),
      titleSmall: paper.heading(15),
      bodyLarge: paper.body(16),
      bodyMedium: paper.body(15),
      bodySmall: paper.body(12, color: paper.muted),
      labelSmall: paper.body(11, color: paper.muted),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: paper.green,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: paper.body(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: paper.accent,
        foregroundColor: HomePaperTokens.accentInk,
        minimumSize: const Size(48, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: paper.ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Color(0xFFCABB96)),
        padding: const EdgeInsets.all(12),
        textStyle: paper.body(13),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: const Color(0x4D3B4038),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: paper.line),
      ),
      titleTextStyle: paper.heading(18),
      contentTextStyle: paper.body(13),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCABB96)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCABB96)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: paper.green, width: 2),
      ),
    ),
  );
}
