library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

@immutable
class CuteTokens extends ThemeExtension<CuteTokens> {
  const CuteTokens();
  static const ink = Color(0xFF263238),
      mint = Color(0xFF75C9B7),
      coral = Color(0xFFFF9D87),
      canvas = Color(0xFFFAFCFB),
      cream = Color(0xFFFFF9F0),
      line = Color(0xFFDCE6E1),
      muted = Color(0xFF5B6D65),
      blue = Color(0xFFE9F2FC),
      yellow = Color(0xFFFFF3C9);
  static const gap = 16.0, radius = 8.0;
  @override
  CuteTokens copyWith() => this;
  @override
  CuteTokens lerp(covariant CuteTokens? other, double t) => this;
}

ThemeData cuteTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF257D68),
    surface: Colors.white,
    primary: const Color(0xFF257D68),
    onSurface: CuteTokens.ink,
    secondary: CuteTokens.coral,
  ),
  scaffoldBackgroundColor: CuteTokens.canvas,
  extensions: const [CuteTokens()],
  appBarTheme: const AppBarTheme(
    backgroundColor: CuteTokens.canvas,
    centerTitle: false,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      color: CuteTokens.ink,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
  ),
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
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: CuteTokens.line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xFFD8EFE6),
    height: 76,
  ),
);

class CuteArt extends StatelessWidget {
  const CuteArt(this.code, {super.key, this.size = 56});
  final String code;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/openmoji/$code.svg',
    package: 'cute_ui',
    width: size,
    height: size,
    semanticsLabel: '工作插画',
    placeholderBuilder: (_) => SizedBox(width: size, height: size),
  );
}

class CuteCard extends StatelessWidget {
  const CuteCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.onTap,
  });
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CuteTokens.radius),
      side: const BorderSide(color: CuteTokens.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color = CuteTokens.blue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: CuteTokens.ink),
      ),
    ),
  );
}

class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    this.title = '这里还没有记录',
    this.subtitle = '新的安排会出现在这里',
    this.action,
  });
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CuteArt('1F331', size: 88),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.message, {super.key, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => EmptyIllustration(
    title: '暂时没能加载',
    subtitle: message,
    action: TextButton.icon(
      onPressed: retry,
      icon: const Icon(Icons.refresh),
      label: const Text('重新加载'),
    ),
  );
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Column(children: [LinearProgressIndicator(), SizedBox(height: 216)]),
  );
}
