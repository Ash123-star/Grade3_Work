import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paths for the user-provided local illustration pack.
class TuantuanAssets {
  static const paper = 'assets/generated_ui/backgrounds/paper_dots.png';
  static const workspace =
      'assets/generated_ui/backgrounds/workspace_scene.png';

  static const newPack = 'assets/generated_ui/new_pack';
  static String skin(String name) => '$newPack/skins/$name.png';
  static const metric = '$newPack/surfaces/metric_card/metric_card_warm.png';
  static String tone(Color? color) => color == const Color(0xFFDDF1FA)
      ? 'blue'
      : color == const Color(0xFFF1E7FF)
      ? 'lavender'
      : color == const Color(0xFFFFE1E1)
      ? 'coral'
      : color == const Color(0xFFFFF4B8) ||
            color == const Color(0xFFFFF5C8) ||
            color == const Color(0xFFFFF0DA)
      ? 'warm'
      : 'mint';
  static const surfaces = <String, String>{
    'mint': '$newPack/surfaces/cards/card_mint.png',
    'warm': '$newPack/surfaces/cards/card_warm.png',
    'blue': '$newPack/surfaces/cards/card_blue.png',
    'lavender': '$newPack/surfaces/cards/card_lavender.png',
    'coral': '$newPack/surfaces/cards/card_coral.png',
  };
  static const detailSections = <String, String>{
    'mint': '$newPack/surfaces/detail_sections/detail_mint.png',
    'warm': '$newPack/surfaces/detail_sections/detail_warm.png',
    'blue': '$newPack/surfaces/detail_sections/detail_blue.png',
    'lavender': '$newPack/surfaces/detail_sections/detail_lavender.png',
    'coral': '$newPack/surfaces/detail_sections/detail_coral.png',
  };
  static const buttonSkins = <String, String>{
    'mint': '$newPack/controls/button_skins/button_mint.png',
    'coral': '$newPack/controls/button_skins/button_coral.png',
    'lavender': '$newPack/controls/button_skins/button_lavender.png',
    'warm': '$newPack/controls/button_skins/button_warm.png',
    'blue': '$newPack/controls/button_skins/button_blue.png',
    'cream': '$newPack/controls/button_skins/button_cream.png',
  };
  static const selectionSkins = <String, String>{
    'coral': '$newPack/controls/selection_skins/filter_coral.png',
    'mint': '$newPack/controls/selection_skins/filter_mint.png',
    'lavender': '$newPack/controls/selection_skins/filter_lavender.png',
    'cream': '$newPack/controls/selection_skins/filter_cream.png',
  };
  static const textures = <String, String>{
    'paper': '$newPack/textures/paper.png',
    'coralDots': '$newPack/textures/coral_dots.png',
    'mintGrid': '$newPack/textures/mint_grid.png',
    'lavenderCloud': '$newPack/textures/lavender_cloud.png',
    'warmSparkle': '$newPack/textures/warm_sparkle.png',
  };
  static const cardCorners = <String, String>{
    'mint': '$newPack/decorations/mint_corner.png',
    'warm': '$newPack/decorations/warm_corner.png',
    'blue': '$newPack/decorations/blue_corner.png',
    'lavender': '$newPack/decorations/lavender_corner.png',
    'coral': '$newPack/decorations/coral_corner.png',
  };
  static const illustrationLayers = <String, String>{
    'topLeft':
        '$newPack/backgrounds/illustration_layers/workspace_top_left.png',
    'topRight':
        '$newPack/backgrounds/illustration_layers/workspace_top_right.png',
    'bottomLeft':
        '$newPack/backgrounds/illustration_layers/workspace_bottom_left.png',
    'bottomRight':
        '$newPack/backgrounds/illustration_layers/workspace_bottom_right.png',
  };

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
  };
  static const aiAssets = <String, String>{
    'thinking': '$newPack/ai/thinking_cluster.png',
    'sources': '$newPack/ai/source_cloud.png',
    'relation': '$newPack/ai/relation_map.png',
    'priority': '$newPack/ai/priority_badge.png',
    'confirm': '$newPack/ai/confirm.png',
    'warning': '$newPack/ai/warning.png',
    'mascot': '$newPack/ai/thinking_mascot.png',
  };
  static const feedbackSkins = <String, String>{
    'modal': '$newPack/surfaces/feedback/modal_panel.png',
    'sheet': '$newPack/surfaces/feedback/bottom_sheet.png',
    'success': '$newPack/surfaces/feedback/toast_success.png',
    'warning': '$newPack/surfaces/feedback/toast_warning.png',
    'error': '$newPack/surfaces/feedback/toast_error.png',
  };
  static const calendarCells = <String, String>{
    'selected': '$newPack/calendar/cells/cell_selected.png',
  };
  static const recordPills = <String, String>{
    'mint': '$newPack/calendar/record_pills/pill_green.png',
    'coral': '$newPack/calendar/record_pills/pill_red.png',
    'lavender': '$newPack/calendar/record_pills/pill_purple.png',
    'blue': '$newPack/calendar/record_pills/pill_blue.png',
  };
}

class DogAssets {
  static const root = 'assets/generated_ui/dog';

  // Stable art direction, zero-based indices; see dog/manifest.json usage.
  static const calm = 0;
  static const friendly = 10;
  static const smiling = 15;
  static const sitting = 6;
  static const resting = 9;
  static const peeking = 15;
  static const faceWatermark = 2;
  static const restingWatermark = 3;
  static const weekdayAvatars = <int>[3, 7, 8, 9, 10, 11, 15];
  static const todayAvatar = 14;

  static String avatar(int index) =>
      '$root/avatars/avatar_${_number(index)}.png';
  static String pose(int index) => '$root/poses/pose_${_number(index)}.png';
  static String background(int index) =>
      '$root/backgrounds/background_${_number(index)}.png';

  static String _number(int index) =>
      (index % 16 + 1).toString().padLeft(2, '0');
}

class DogAvatar extends StatelessWidget {
  const DogAvatar({super.key, this.index = 0, this.size = 32});
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(child: Image.asset(
      DogAssets.avatar(index),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _missingDogArt(
        DogAssets.avatar(index), width: size, height: size,
      ),
    )),
  );
}

class DogPose extends StatelessWidget {
  const DogPose({super.key, this.index = 0, this.size = 72});
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(child: Image.asset(
      DogAssets.pose(index),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _missingDogArt(
        DogAssets.pose(index), width: size, height: size,
      ),
    )),
  );
}

class DogBackground extends StatelessWidget {
  const DogBackground({
    super.key,
    this.index = 0,
    this.opacity = .7,
    this.fit = BoxFit.contain,
  });
  final int index;
  final double opacity;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: ClipRect(child: Opacity(
        opacity: opacity,
        child: Image.asset(
          DogAssets.background(index),
          fit: fit,
          errorBuilder: (_, _, _) => _missingDogArt(DogAssets.background(index)),
        ),
      )),
    ),
  );
}

Widget _missingDogArt(String path, {double? width, double? height}) {
  assert(() {
    debugPrint('Brand decoration could not load: $path');
    return true;
  }());
  return SizedBox(width: width, height: height);
}

/// Raster borders keep their original proportions as blank centers stretch.
/// Labels and interactions are always rendered by Flutter above this layer.
class TuantuanSkin extends StatelessWidget {
  const TuantuanSkin(this.path, {super.key, this.opacity = 1});
  final String path;
  final double opacity;
  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last;
    final (slice, size, scale) = name.startsWith('detail_')
        ? (const Rect.fromLTRB(36, 38, 290, 152), const Size(360, 190), 3.0)
        : name.startsWith('button_')
        ? (const Rect.fromLTRB(92, 40, 208, 90), const Size(300, 130), 5.0)
        : name.startsWith('filter_')
        ? (const Rect.fromLTRB(65, 35, 235, 85), const Size(300, 120), 3.0)
        : name.startsWith('pill_')
        ? (const Rect.fromLTRB(48, 30, 192, 70), const Size(240, 100), 5.0)
        : name.startsWith('cell_')
        ? (const Rect.fromLTRB(45, 70, 175, 225), const Size(240, 280), 4.0)
        : name.startsWith('metric_')
        ? (const Rect.fromLTRB(85, 42, 275, 155), const Size(360, 220), 3.0)
        : name.startsWith('toast_')
        ? (const Rect.fromLTRB(105, 42, 285, 118), const Size(360, 160), 3.0)
        : name == 'modal_panel.png'
        ? (const Rect.fromLTRB(55, 50, 310, 210), const Size(360, 260), 2.0)
        : name == 'bottom_sheet.png'
        ? (const Rect.fromLTRB(55, 45, 305, 155), const Size(360, 220), 2.0)
        : name.contains('_corner')
        ? (const Rect.fromLTRB(72, 70, 170, 190), const Size(240, 260), 3.0)
        : (const Rect.fromLTRB(50, 55, 190, 245), const Size(240, 300), 3.0);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Very narrow calendar pills still need space for the stretch center.
            final minimumScale = math.max(
              scale,
              math.max(
                (size.width - slice.width) /
                    math.max(1, constraints.maxWidth - 1),
                (size.height - slice.height) /
                    math.max(1, constraints.maxHeight - 1),
              ),
            );
            // Binary scales avoid rounding in Flutter's exact nine-slice size
            // check, and explicit dimensions fill loose icon-tray constraints.
            final imageScale = math
                .pow(2, (math.log(minimumScale) / math.ln2).ceil())
                .toDouble();
            return Opacity(
              opacity: opacity,
              child: Image.asset(
                '${TuantuanAssets.newPack}/skins/$name',
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                centerSlice: Rect.fromLTRB(
                  slice.left / imageScale,
                  slice.top / imageScale,
                  slice.right / imageScale,
                  slice.bottom / imageScale,
                ),
                scale: imageScale,
                fit: BoxFit.fill,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Decorative raster layer. Content and input remain available if it is absent.
class TuantuanArt extends StatelessWidget {
  const TuantuanArt(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.opacity = 1,
  });
  final String path;
  final double? width, height;
  final BoxFit fit;
  final double opacity;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Image.asset(
          path,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => SizedBox(width: width, height: height),
        ),
      ),
    ),
  );
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
      Positioned(
        top: 0,
        left: -12,
        child: TuantuanArt(
          TuantuanAssets.illustrationLayers['topLeft']!,
          width: 112,
          height: 112,
          opacity: .48,
        ),
      ),
      Positioned(
        top: 0,
        right: -10,
        child: TuantuanArt(
          TuantuanAssets.illustrationLayers['topRight']!,
          width: 118,
          height: 118,
          opacity: .38,
        ),
      ),
      Positioned(
        bottom: 0,
        left: -8,
        child: TuantuanArt(
          TuantuanAssets.illustrationLayers['bottomLeft']!,
          width: 130,
          height: 130,
          opacity: .26,
        ),
      ),
      Positioned(
        bottom: 0,
        right: -8,
        child: TuantuanArt(
          TuantuanAssets.illustrationLayers['bottomRight']!,
          width: 145,
          height: 145,
          opacity: .34,
        ),
      ),
      child,
    ],
  );
}
