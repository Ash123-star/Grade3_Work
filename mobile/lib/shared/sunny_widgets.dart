import 'package:flutter/material.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

enum BuddyPose { welcome, writing, explaining, success, empty, retry }

/// Original project-owned vector companion; no competitor art or animation.
class WorkBuddy extends StatelessWidget {
  const WorkBuddy({super.key, this.size = 76, this.pose = BuddyPose.welcome});
  final double size;
  final BuddyPose pose;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: size,
        height: size * 1.4,
        child: CustomPaint(painter: _BuddyPainter(pose)),
      ),
    ),
  );
}

class _BuddyPainter extends CustomPainter {
  const _BuddyPainter(this.pose);
  final BuddyPose pose;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 90, size.height / 128);
    final p = Paint();
    void fill(Path path, Color color, {Color? stroke, double width = 2}) {
      p
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawPath(path, p);
      if (stroke != null) {
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = stroke;
        canvas.drawPath(path, p);
      }
      p.style = PaintingStyle.fill;
    }

    const outline = Color(0xFF805036);
    // Small cream shoes retain the same silhouette across all six poses.
    p.color = SunnyPalette.orange;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(19, 110, 22, 14),
        const Radius.circular(6),
      ),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 110, 22, 14),
        const Radius.circular(6),
      ),
      p,
    );
    fill(
      Path()
        ..moveTo(17, 73)
        ..quadraticBezierTo(45, 52, 73, 73)
        ..lineTo(80, 112)
        ..quadraticBezierTo(48, 128, 10, 110)
        ..close(),
      SunnyPalette.primary,
      stroke: outline,
    );
    fill(
      Path()
        ..moveTo(34, 76)
        ..lineTo(55, 76)
        ..lineTo(60, 108)
        ..lineTo(29, 108)
        ..close(),
      SunnyPalette.surface,
    );
    p.color = SunnyPalette.orange;
    canvas.drawCircle(const Offset(45, 43), 31, p);
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = outline;
    canvas.drawCircle(const Offset(45, 43), 31, p);
    p.style = PaintingStyle.fill;
    fill(
      Path()
        ..moveTo(14, 39)
        ..quadraticBezierTo(10, 0, 45, 7)
        ..quadraticBezierTo(80, 6, 77, 39)
        ..lineTo(63, 25)
        ..lineTo(48, 30)
        ..lineTo(34, 20)
        ..close(),
      const Color(0xFF805036),
    );
    p.color = SunnyPalette.ink;
    if (pose == BuddyPose.success) {
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(30, 45)
          ..quadraticBezierTo(34, 38, 38, 45),
        p,
      );
      canvas.drawPath(
        Path()
          ..moveTo(52, 45)
          ..quadraticBezierTo(56, 38, 60, 45),
        p,
      );
    } else {
      canvas.drawCircle(const Offset(34, 44), 3, p);
      canvas.drawCircle(const Offset(56, 44), 3, p);
    }
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final quiet = pose == BuddyPose.empty || pose == BuddyPose.retry;
    canvas.drawPath(
      Path()
        ..moveTo(38, 55)
        ..quadraticBezierTo(45, quiet ? 57 : 62, 52, 55),
      p,
    );
    p.style = PaintingStyle.fill;
    p.color = const Color(0xFFFFB59F);
    canvas.drawOval(const Rect.fromLTWH(19, 51, 12, 6), p);
    canvas.drawOval(const Rect.fromLTWH(58, 51, 12, 6), p);
    void arm(Offset a, Offset b) {
      p
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 12
        ..color = outline;
      canvas.drawLine(a, b, p);
      p
        ..strokeWidth = 9
        ..color = SunnyPalette.primary;
      canvas.drawLine(a, b, p);
      p
        ..style = PaintingStyle.fill
        ..color = SunnyPalette.orange;
      canvas.drawCircle(b, 6, p);
    }

    void notebook() {
      final book = RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 90, 43, 25),
        const Radius.circular(5),
      );
      p
        ..style = PaintingStyle.fill
        ..color = SunnyPalette.surface;
      canvas.drawRRect(book, p);
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF275E8D);
      canvas.drawRRect(book, p);
      canvas.drawLine(const Offset(28, 91), const Offset(28, 114), p);
      p
        ..strokeWidth = 1.5
        ..color = SunnyPalette.muted;
      canvas.drawLine(const Offset(34, 99), const Offset(54, 99), p);
      canvas.drawLine(const Offset(34, 105), const Offset(50, 105), p);
    }

    if ([
      BuddyPose.welcome,
      BuddyPose.explaining,
      BuddyPose.success,
    ].contains(pose)) {
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF275E8D);
      canvas.drawLine(const Offset(35, 77), const Offset(73, 103), p);
      final bag = RRect.fromRectAndRadius(
        const Rect.fromLTWH(52, 93, 31, 22),
        const Radius.circular(6),
      );
      p
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF92C9E9);
      canvas.drawRRect(bag, p);
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF275E8D);
      canvas.drawRRect(bag, p);
    }
    switch (pose) {
      case BuddyPose.welcome:
        arm(const Offset(19, 83), const Offset(8, 64));
        arm(const Offset(68, 79), const Offset(77, 92));
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFC45E14);
        canvas.drawArc(const Rect.fromLTWH(1, 48, 18, 14), -2.4, 1.2, false, p);
      case BuddyPose.writing:
        arm(const Offset(19, 83), const Offset(24, 100));
        notebook();
        arm(const Offset(68, 79), const Offset(52, 92));
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF7650B6);
        canvas.drawLine(const Offset(58, 80), const Offset(43, 105), p);
      case BuddyPose.explaining:
        arm(const Offset(68, 79), const Offset(77, 92));
        arm(const Offset(19, 83), const Offset(5, 78));
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF7650B6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1, 60, 19, 12),
            const Radius.circular(4),
          ),
          p,
        );
        canvas.drawLine(const Offset(6, 64), const Offset(15, 64), p);
        canvas.drawLine(const Offset(6, 68), const Offset(12, 68), p);
      case BuddyPose.success:
        arm(const Offset(19, 83), const Offset(10, 63));
        arm(const Offset(68, 79), const Offset(79, 65));
        p
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFDEF4E6);
        canvas.drawCircle(const Offset(78, 49), 10, p);
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF246447);
        canvas.drawPath(
          Path()
            ..moveTo(73, 49)
            ..lineTo(77, 53)
            ..lineTo(83, 45),
          p,
        );
      case BuddyPose.empty:
        arm(const Offset(19, 83), const Offset(25, 100));
        notebook();
        arm(const Offset(68, 79), const Offset(76, 100));
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF7650B6);
        canvas.drawLine(const Offset(76, 86), const Offset(76, 111), p);
      case BuddyPose.retry:
        arm(const Offset(19, 83), const Offset(25, 100));
        notebook();
        arm(const Offset(68, 79), const Offset(59, 102));
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF275E8D);
        canvas.drawArc(const Rect.fromLTWH(67, 62, 17, 17), -.8, 4.6, false, p);
        canvas.drawPath(
          Path()
            ..moveTo(69, 62)
            ..lineTo(67, 69)
            ..lineTo(74, 68),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter oldDelegate) =>
      oldDelegate.pose != pose;
}

class SunnyWelcome extends StatelessWidget {
  const SunnyWelcome({
    super.key,
    required this.title,
    required this.subtitle,
    this.color = const Color(0xFFE6FAEF),
    this.pose = BuddyPose.welcome,
    this.pet,
    this.mascotAsset,
  });
  final String title, subtitle;
  final Color color;
  final BuddyPose pose;
  final CompanionPet? pet;
  final String? mascotAsset;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFB7CFC2), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x143E6654),
          offset: Offset(0, 3),
          blurRadius: 8,
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: SunnyPalette.muted, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (mascotAsset case final asset?)
          TuantuanMascot(asset, size: 96)
        else if (pet case final companion?)
          PetCompanion(pet: companion)
        else
          WorkBuddy(size: 52, pose: pose),
      ],
    ),
  );
}
