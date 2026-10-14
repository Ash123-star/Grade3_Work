import 'package:flutter/material.dart';

/// Paths for the user-provided local illustration pack.
class TuantuanAssets {
  static const paper = 'assets/generated_ui/backgrounds/paper_dots.png';
  static const workspace =
      'assets/generated_ui/backgrounds/workspace_scene.png';

  static const icons = <String, String>{
    'task': 'assets/generated_ui/icons/task.png',
    'log': 'assets/generated_ui/icons/log.png',
    'calendar': 'assets/generated_ui/icons/calendar.png',
    'approval': 'assets/generated_ui/icons/approval.png',
    'ai': 'assets/generated_ui/icons/ai.png',
    'members': 'assets/generated_ui/icons/members.png',
    'notification': 'assets/generated_ui/icons/notification.png',
    'mindmap': 'assets/generated_ui/icons/mindmap.png',
    'report': 'assets/generated_ui/icons/report.png',
    'settings': 'assets/generated_ui/icons/settings.png',
    'help': 'assets/generated_ui/icons/help.png',
    'empty': 'assets/generated_ui/icons/empty.png',
    'error': 'assets/generated_ui/icons/error.png',
    'loading': 'assets/generated_ui/icons/loading.png',
    'success': 'assets/generated_ui/icons/success.png',
  };

  static const mascots = <String, String>{
    'welcome': 'assets/generated_ui/mascot/mascot_welcome.png',
    'empty': 'assets/generated_ui/mascot/mascot_empty.png',
    'error': 'assets/generated_ui/mascot/mascot_error.png',
    'success': 'assets/generated_ui/mascot/mascot_success.png',
    'ai': 'assets/generated_ui/mascot/mascot_ai_processing.png',
  };

  static const decorations = <String, String>{
    'leaf_cluster': 'assets/generated_ui/decorations/leaf_cluster.png',
    'washi_tape': 'assets/generated_ui/decorations/washi_tape.png',
    'sparkle_pair': 'assets/generated_ui/decorations/sparkle_pair.png',
    'dot_cluster': 'assets/generated_ui/decorations/dot_cluster.png',
    'paper_label': 'assets/generated_ui/decorations/paper_label.png',
    'cloud_puffs': 'assets/generated_ui/decorations/cloud_puffs.png',
    'flower_sticker': 'assets/generated_ui/decorations/flower_sticker.png',
    'ribbon_loop': 'assets/generated_ui/decorations/ribbon_loop.png',
    'title_swoosh': 'assets/generated_ui/decorations/title_swoosh.png',
    'calendar_corner': 'assets/generated_ui/decorations/calendar_corner.png',
    'speech_bubble': 'assets/generated_ui/decorations/speech_bubble.png',
    'paper_clip': 'assets/generated_ui/decorations/paper_clip.png',
    'confetti_cluster': 'assets/generated_ui/decorations/confetti_cluster.png',
    'sun_arc': 'assets/generated_ui/decorations/sun_arc.png',
    'mint_blob': 'assets/generated_ui/decorations/mint_blob.png',
    'pig_tail_mark': 'assets/generated_ui/decorations/pig_tail_mark.png',
  };
}

class TuantuanIcon extends StatelessWidget {
  const TuantuanIcon(
    this.name, {
    super.key,
    this.size = 42,
    this.fit = BoxFit.contain,
  });
  final String name;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = TuantuanAssets.icons[name];
    if (path == null) return SizedBox(width: size, height: size);
    return Semantics(
      image: true,
      label: '$name 图标',
      child: Image.asset(path, width: size, height: size, fit: fit),
    );
  }
}

class TuantuanMascot extends StatelessWidget {
  const TuantuanMascot(
    this.pose, {
    super.key,
    this.size = 96,
    this.fit = BoxFit.contain,
  });
  final String pose;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = TuantuanAssets.mascots[pose];
    if (path == null) return SizedBox(width: size, height: size);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Image.asset(path, width: size, height: size, fit: fit),
      ),
    );
  }
}

class TuantuanDecoration extends StatelessWidget {
  const TuantuanDecoration(
    this.name, {
    super.key,
    this.size = 72,
    this.opacity = 1,
  });
  final String name;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final path = TuantuanAssets.decorations[name];
    if (path == null) return SizedBox(width: size, height: size);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            path,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class TuantuanPaperBackdrop extends StatelessWidget {
  const TuantuanPaperBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: Opacity(
          opacity: .12,
          child: Image.asset(TuantuanAssets.paper, fit: BoxFit.cover),
        ),
      ),
      child,
    ],
  );
}
