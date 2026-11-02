import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class _SplashPalette {
  static const yellow = Color(0xFFFFD52B);
  static const ink = Color(0xFF333333);
  static const white = Color(0xFFFFFFFF);
}

/// Keeps session recovery mounted while the brand layer hands off to the app.
class PandoraSplash extends StatefulWidget {
  const PandoraSplash({super.key, required this.child});
  final Widget child;

  @override
  State<PandoraSplash> createState() => _PandoraSplashState();
}

class _PandoraSplashState extends State<PandoraSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _arrival;
  late final Animation<double> _wordmark;
  late final Animation<double> _handoff;
  late final Animation<double> _cover;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    final reduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: reduced ? 180 : 2400),
    )..addStatusListener(_onStatus);
    _arrival = CurveTween(
      curve: const Interval(0, .225, curve: Curves.easeOutCubic),
    ).animate(_controller);
    _wordmark = CurveTween(
      curve: const Interval(.055, .225, curve: Curves.easeOut),
    ).animate(_controller);
    _handoff = CurveTween(
      curve: Interval(reduced ? 0 : .84, 1, curve: Curves.easeInOutCubic),
    ).animate(_controller);
    _cover = Tween<double>(begin: 1, end: 0).animate(_handoff);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _dismissed = true);
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final reduced = MediaQuery.disableAnimationsOf(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Keep this subtree in the same slot after removing the overlay.
              IgnorePointer(
                ignoring: !_dismissed,
                child: ExcludeFocus(
                  excluding: !_dismissed,
                  child: ExcludeSemantics(excluding: !_dismissed, child: child),
                ),
              ),
              if (!_dismissed)
                AnnotatedRegion<SystemUiOverlayStyle>(
                  value: const SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: Brightness.dark,
                    statusBarBrightness: Brightness.light,
                    systemNavigationBarColor: _SplashPalette.yellow,
                    systemNavigationBarIconBrightness: Brightness.dark,
                  ),
                  child: FadeTransition(
                    opacity: _cover,
                    child: Semantics(
                      container: true,
                      label: '潘多拉工作台，正在启动',
                      child: ExcludeSemantics(
                        child: ColoredBox(
                          color: _SplashPalette.yellow,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: _BrandScenePainter(
                                    arrival: reduced ? 1 : _arrival.value,
                                  ),
                                ),
                              ),
                              SafeArea(
                                child: Align(
                                  alignment: const Alignment(0, -.46),
                                  child: FadeTransition(
                                    opacity: reduced
                                        ? const AlwaysStoppedAnimation(1)
                                        : _wordmark,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: Text(
                                        '潘多拉工作台',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'TuantuanDisplay',
                                          fontSize: 34,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                          color: _SplashPalette.ink,
                                          letterSpacing: 0,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
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
            ],
          );
        },
      ),
    ),
  );
}

class _BrandScenePainter extends CustomPainter {
  const _BrandScenePainter({required this.arrival});
  final double arrival;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width * 1.18, size.height * .60);
    final lift = (1 - arrival) * 28;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width - side * .91, size.height - side * .96 + lift);
    canvas.scale(side / 1024);

    final body = Path()
      ..moveTo(1120, 500)
      ..cubicTo(1040, 254, 773, 157, 560, 265)
      ..cubicTo(399, 338, 313, 454, 278, 633)
      ..cubicTo(169, 577, 32, 602, 26, 715)
      ..cubicTo(18, 813, 87, 939, 176, 1060)
      ..lineTo(1120, 1060)
      ..close();
    final outline = Paint()
      ..color = _SplashPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 52
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(body, Paint()..color = _SplashPalette.white);
    canvas.drawPath(body, outline);

    final eye = Paint()
      ..color = _SplashPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 76
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(546, 650), const Offset(585, 723), eye);
    canvas.drawPath(
      Path()
        ..moveTo(807, 566)
        ..lineTo(777, 631)
        ..lineTo(838, 655),
      eye..strokeWidth = 64,
    );

    final heart = Path()
      ..moveTo(145, 778)
      ..cubicTo(89, 758, 91, 716, 126, 719)
      ..cubicTo(115, 678, 166, 663, 185, 704)
      ..cubicTo(193, 726, 185, 748, 182, 771)
      ..close();
    canvas.drawPath(heart, Paint()..color = _SplashPalette.yellow);

    final rays = Paint()
      ..color = _SplashPalette.ink
      ..strokeWidth = 32
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(437, 230), const Offset(419, 128), rays);
    canvas.drawLine(const Offset(328, 247), const Offset(291, 198), rays);
    canvas.drawLine(const Offset(279, 361), const Offset(205, 339), rays);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandScenePainter oldDelegate) =>
      oldDelegate.arrival != arrival;
}
