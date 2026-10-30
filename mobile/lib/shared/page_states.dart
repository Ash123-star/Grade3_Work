import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'paper_layout.dart';

class SunnyLoadingIndicator extends StatefulWidget {
  const SunnyLoadingIndicator({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  State<SunnyLoadingIndicator> createState() => _SunnyLoadingIndicatorState();
}

class _SunnyLoadingIndicatorState extends State<SunnyLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => CustomPaint(
          painter: _SunnyLoadingPainter(
            _controller.value,
            widget.color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

class _SunnyLoadingPainter extends CustomPainter {
  const _SunnyLoadingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * .13;
    final bounds = Offset.zero & size;
    final track = Paint()
      ..color = color.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(bounds.center, size.shortestSide / 2 - stroke, track);
    canvas.drawArc(
      bounds.deflate(stroke),
      -1.5708 + progress * 6.2832,
      4.1888,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _SunnyLoadingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class SunnyProgressBar extends StatelessWidget {
  const SunnyProgressBar({
    super.key,
    required this.value,
    this.height = 5,
    this.color,
  });
  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          height: height,
          color: accent.withValues(alpha: .14),
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: constraints.maxWidth * value.clamp(0, 1).toDouble(),
            height: height,
            child: ColoredBox(color: accent),
          ),
        ),
      ),
    );
  }
}

class SunnyStatusIcon extends StatelessWidget {
  const SunnyStatusIcon({
    super.key,
    required this.icon,
    this.color,
    this.size = 56,
  });
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: accent.withValues(alpha: .2)),
      ),
      child: Icon(icon, size: size * .48, color: accent),
    );
  }
}

class SunnyStatusBadge extends StatelessWidget {
  const SunnyStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    this.color,
  });
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SunnyStatusPanel extends StatelessWidget {
  const SunnyStatusPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
    this.action,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: accent),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    this.title = '这里还没有记录',
    this.subtitle = '新的安排会出现在这里',
    this.action,
    this.showCharacter = true,
  });
  final String title, subtitle;
  final Widget? action;
  final bool showCharacter;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SunnyStatusIcon(
            icon: showCharacter ? Icons.inbox_outlined : Icons.lock_outline,
            size: 60,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        ?action,
      ],
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(
    this.message, {
    super.key,
    this.retry,
    this.retryLabel = '重新加载',
  });
  final String message;
  final String retryLabel;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => PaperSurface(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: 34,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
        if (retry != null)
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
      ],
    ),
  );
}

/// Uses the existing typed errors; access failures never expose stale content.
class RecordFailure extends StatelessWidget {
  const RecordFailure(this.error, {super.key, this.retry});
  final Object error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) {
    final kind = error is ApiFailure
        ? (error as ApiFailure).kind
        : FailureKind.server;
    final title = switch (kind) {
      FailureKind.forbidden => '无权访问',
      FailureKind.unauthorized => '登录已失效',
      FailureKind.notFound => '内容不可用',
      FailureKind.timeout || FailureKind.unavailable => '暂时无法连接',
      FailureKind.conflict => '内容已有新版本',
      _ => '加载未完成',
    };
    return PaperSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (kind == FailureKind.timeout || kind == FailureKind.unavailable)
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
          const SizedBox(height: 12),
          Text('$error'),
          const SizedBox(height: 16),
          if (retry != null &&
              ![
                FailureKind.forbidden,
                FailureKind.unauthorized,
                FailureKind.notFound,
              ].contains(kind))
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          TextButton(
            onPressed: () {
              if (kind == FailureKind.unauthorized) {
                context.go('/auth/login');
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
            child: Text(kind == FailureKind.unauthorized ? '重新登录' : '安全返回'),
          ),
        ],
      ),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SunnyLoadingIndicator(),
                SizedBox(width: 8),
                Text('正在加载'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperSurface(
                child: SizedBox(
                  height: 40,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 160,
                      height: 10,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
