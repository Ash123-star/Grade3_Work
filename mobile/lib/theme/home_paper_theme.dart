import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Values shared with the approved home-daily-todos.html prototype.
/// Scoped to the home and its dialogs; other business pages keep their theme.
class HomePaperTokens extends ThemeExtension<HomePaperTokens> {
  const HomePaperTokens({
    this.canvas = SunnyPalette.paper,
    this.surface = const Color(0xFFFFFEFA),
    this.note = const Color(0xFFF1E1C8),
    this.ink = const Color(0xFF3E4941),
    this.muted = const Color(0xFF687268),
    this.line = const Color(0xFFE9DFCF),
    this.accent = const Color(0xFFF3A45D),
    this.green = const Color(0xFF32694D),
  });

  final Color canvas, surface, note, ink, muted, line, accent, green;
  static const accentInk = Color(0xFF44210D);
  static const orangeInk = Color(0xFF74421C);
  static const mint = Color(0xFFE9F2E7);
  static const error = Color(0xFFA53E3B);
  static const noteEdge = Color(0xFFDCC6A5);
  static const noteShadow = Color(0x18AD8C61);
  static const noteRule = Color(0xFFE3D0B1);
  static const noteFold = Color(0xFFE6D1AF);
  static const previewLine = Color(0x13415246);
  static const moreInk = Color(0xFF4F685A);
  static const messageSurface = Color(0xFFFFF5E4);
  static const messageEdge = Color(0xFFEDDFC7);
  static const unread = Color(0xFFC16C40);
  static const binding = Color(0xFFC7D4BD);
  static const bindingEdge = Color(0xFFB8C9AE);
  static const sheetShadow = Color(0x29E8DCC7);
  static const todayEdge = Color(0xFFC77A34);
  static const outside = Color(0xFF8B8D81);
  static const todaySurface = Color(0xFFFFF3E3);
  static const checkEdge = Color(0xFF8B9D89);
  static const completedEdge = Color(0xFF83A187);
  static const rowLine = Color(0xFFEEE9DF);
  static const navigationSurface = Color(0xFFF8F6EA);
  static const navigationLine = Color(0xFFE8E2D3);
  static const navigationTray = Color(0xFFFFDFB7);
  static const navigationInk = Color(0xFF5C442A);
  static const navigationDot = Color(0xFFBD742E);

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
      primary: paper.accent,
      onPrimary: HomePaperTokens.accentInk,
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
        side: const BorderSide(color: Color(0xFFCBD2C3)),
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
        borderSide: const BorderSide(color: Color(0xFFCBD2C3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFCBD2C3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: paper.green, width: 2),
      ),
    ),
  );
}
