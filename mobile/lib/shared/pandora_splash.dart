import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'generated_assets.dart';

/// Short, branded handoff from the native launch window into the real app.
/// The app is built underneath this layer, so session recovery can start while
/// the icon animation is playing.
class PandoraSplash extends StatefulWidget {
  const PandoraSplash({super.key, required this.child});
  final Widget child;

  @override
  State<PandoraSplash> createState() => _PandoraSplashState();
}

class _PandoraSplashState extends State<PandoraSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: .78,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 1550), () {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return widget.child;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return MediaQuery.fromView(
      view: view,
      child: Builder(
        builder: (context) {
          final size = MediaQuery.sizeOf(context);
          final reducedMotion = MediaQuery.disableAnimationsOf(context);
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                ColoredBox(
                  color: SunnyPalette.paper,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: .24,
                          child: TuantuanArt(
                            TuantuanAssets.textures['paper']!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Center(
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => FadeTransition(
                            opacity: reducedMotion
                                ? const AlwaysStoppedAnimation(1)
                                : _opacity,
                            child: ScaleTransition(
                              scale: reducedMotion
                                  ? const AlwaysStoppedAnimation(1)
                                  : _scale,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: math.min(size.width * .56, 230),
                                    height: math.min(size.width * .56, 230),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4D6),
                                      borderRadius: BorderRadius.circular(42),
                                      border: Border.all(
                                        color: const Color(0xFFE8D9C2),
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x35F5B96F),
                                          blurRadius: 28,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(32),
                                      child: Image.asset(
                                        'assets/icon_splash.png',
                                        fit: BoxFit.cover,
                                        semanticLabel: '潘多拉应用图标',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    '潘多拉',
                                    style: const TextStyle(
                                      fontFamily: 'TuantuanDisplay',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: SunnyPalette.ink,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    '把重要的事，放在一起',
                                    style: TextStyle(
                                      color: SunnyPalette.muted,
                                      fontSize: 13,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
