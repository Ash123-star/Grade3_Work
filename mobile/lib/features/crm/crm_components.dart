import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

// Semantic colors and geometry match crm-customer-workspace.css.
abstract final class CrmTone {
  static const canvas = SunnyPalette.paper,
      surface = SunnyPalette.surface,
      ink = SunnyPalette.ink,
      muted = SunnyPalette.muted,
      yellow = Color(0xffffda35),
      accent = SunnyPalette.primaryStrong,
      line = Color(0xffeee4cd),
      outline = Color(0xffcabb96),
      red = Color(0xffb3433e),
      green = Color(0xff39734e),
      chips = Color(0xfff1ebdc);
}

TextStyle crmStyle(
  double size, {
  Color color = CrmTone.ink,
  bool bold = false,
  bool rounded = false,
  double height = 1.4,
}) => TextStyle(
  fontSize: size,
  color: color,
  height: height,
  fontFamily: rounded ? AppTypography.displayFamily : null,
  fontWeight: bold || rounded ? FontWeight.w700 : FontWeight.w400,
  letterSpacing: 0,
);

Widget crmText(
  String value,
  double size, {
  Color color = CrmTone.ink,
  bool bold = false,
  bool rounded = false,
  double height = 1.4,
  TextAlign? align,
}) => Text(
  value,
  style: crmStyle(
    size,
    color: color,
    bold: bold,
    rounded: rounded,
    height: height,
  ),
  textAlign: align,
);
Widget crmSmall(String value) =>
    crmText(value, 12, color: CrmTone.muted, height: 1.65);
const crmGap = SizedBox(height: 12);

BoxDecoration crmBox({
  Color color = CrmTone.surface,
  Color? border = CrmTone.line,
  double radius = 18,
}) => BoxDecoration(
  color: color,
  border: border == null ? null : Border.all(color: border),
  borderRadius: BorderRadius.circular(radius),
);

class CrmButton extends StatelessWidget {
  const CrmButton(
    this.label,
    this.onTap, {
    super.key,
    this.primary = false,
    this.plain = false,
    this.height = 52,
    this.size = 15,
    this.radius = 15,
    this.border = CrmTone.outline,
    this.semanticLabel,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary, plain;
  final double height, size, radius;
  final Color border;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: plain ? CrmTone.accent : CrmTone.ink,
      disabledForegroundColor: CrmTone.muted,
      backgroundColor: plain
          ? Colors.transparent
          : primary
          ? CrmTone.yellow
          : CrmTone.surface,
      disabledBackgroundColor: primary
          ? const Color(0xffffed9d)
          : CrmTone.canvas,
      minimumSize: Size(0, height),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      side: plain || primary ? null : BorderSide(color: border),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      semanticsLabel: semanticLabel,
      style: TextStyle(
        fontSize: size,
        fontWeight: primary || plain ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: 0,
      ),
    ),
  );
}

class CrmSurface extends StatelessWidget {
  const CrmSurface(
    this.child, {
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    this.color = CrmTone.surface,
    this.border = CrmTone.line,
    this.radius = 18,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color, border;
  final double radius;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class CrmSegments extends StatelessWidget {
  const CrmSegments(
    this.labels,
    this.selected,
    this.onSelected, {
    super.key,
    this.dock = false,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool dock;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(dock ? 0 : 3),
    decoration: dock
        ? null
        : crmBox(color: CrmTone.chips, border: null, radius: 14),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) SizedBox(width: dock ? 5 : 2),
          Expanded(
            child: Semantics(
              selected: i == selected,
              child: TextButton(
                onPressed: () => onSelected(i),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 2,
                  ),
                  foregroundColor: CrmTone.ink,
                  backgroundColor: i == selected
                      ? CrmTone.yellow
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(dock ? 13 : 11),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: crmText(
                  labels[i],
                  dock ? 14 : 13,
                  bold: dock || i == selected,
                  align: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class CrmFrame extends StatelessWidget {
  const CrmFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.back,
    required this.body,
    this.dock,
    this.help,
    this.backLabel = '返回',
    this.scroll,
  });
  final String title, subtitle, backLabel;
  final VoidCallback back;
  final VoidCallback? help;
  final Widget body;
  final Widget? dock;
  final ScrollController? scroll;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: CrmTone.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: Scaffold(
      backgroundColor: CrmTone.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: CrmButton(
                        '‹',
                        back,
                        height: 48,
                        size: 24,
                        border: CrmTone.line,
                        semanticLabel: backLabel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: crmText(
                              title,
                              23,
                              rounded: true,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 3),
                          crmText(subtitle, 12, color: CrmTone.muted),
                        ],
                      ),
                    ),
                    if (help != null)
                      SizedBox(
                        width: 48,
                        child: CrmButton(
                          '?',
                          help,
                          height: 48,
                          size: 24,
                          border: CrmTone.line,
                          semanticLabel: '查看客户手帐说明',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: body,
              ),
            ),
            if (dock != null)
              Container(
                decoration: const BoxDecoration(
                  color: CrmTone.surface,
                  border: Border(top: BorderSide(color: CrmTone.line)),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: dock!,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class CrmDisclosure extends StatefulWidget {
  const CrmDisclosure(
    this.title,
    this.child, {
    super.key,
    this.initiallyOpen = false,
  });
  final String title;
  final Widget child;
  final bool initiallyOpen;
  @override
  State<CrmDisclosure> createState() => _CrmDisclosureState();
}

class _CrmDisclosureState extends State<CrmDisclosure> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) => CrmSurface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: open,
          child: InkWell(
            onTap: () => setState(() => open = !open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(child: crmText(widget.title, 13)),
                  crmText(open ? '−' : '＋', 14, color: CrmTone.accent),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 15),
            child: widget.child,
          ),
      ],
    ),
    radius: 16,
    padding: const EdgeInsets.symmetric(horizontal: 13),
  );
}

Widget crmFields(List<(String, String)> values) => CrmSurface(
  Column(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: CrmTone.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: crmText(
                  values[i].$1,
                  14,
                  color: CrmTone.muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 6,
                child: crmText(
                  values[i].$2,
                  14,
                  align: TextAlign.right,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  ),
);

Widget crmBadge(String label) {
  final (background, ink) = switch (label) {
    '有效' || '已完成' => (const Color(0xffedf3e9), CrmTone.green),
    '已到期' || '已取消' || '已退款' => (const Color(0xfffbece7), CrmTone.red),
    '已结束' || '配送中' => (const Color(0xffedf1f6), const Color(0xff456175)),
    _ => (const Color(0xfffff0b4), CrmTone.accent),
  };
  return DecoratedBox(
    decoration: crmBox(color: background, border: null, radius: 7),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: crmText(label, 11, color: ink, bold: true),
    ),
  );
}

Widget crmPager(int page, int count, ValueChanged<int> change) => Row(
  children: [
    Expanded(
      child: CrmButton(
        '‹ 上一页',
        page > 0 ? () => change(page - 1) : null,
        height: 48,
        size: 13,
        radius: 12,
        border: CrmTone.line,
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: crmSmall('${page + 1} / $count'),
    ),
    Expanded(
      child: CrmButton(
        '下一页 ›',
        page + 1 < count ? () => change(page + 1) : null,
        height: 48,
        size: 13,
        radius: 12,
        border: CrmTone.line,
      ),
    ),
  ],
);

Widget crmHint(String value, {bool error = false, bool success = false}) =>
    Container(
      decoration: crmBox(
        color: error
            ? const Color(0xfffff0e8)
            : success
            ? const Color(0xffedf3e9)
            : const Color(0xfff3efdf),
        border: null,
        radius: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Semantics(
        liveRegion: true,
        child: crmText(
          value,
          12,
          color: error
              ? CrmTone.red
              : success
              ? CrmTone.green
              : CrmTone.accent,
          height: 1.6,
        ),
      ),
    );

Widget crmEmpty(
  String title,
  String message, {
  String icon = 'empty',
  bool useStatusIcon = false,
  String? action,
  VoidCallback? onTap,
}) => Padding(
  padding: const EdgeInsets.fromLTRB(6, 32, 6, 22),
  child: Column(
    children: [
      Image.asset(
        'assets/generated_ui/sunshine/${useStatusIcon ? 'icons' : 'mascots'}/$icon.png',
        width: 100,
        height: 100,
        excludeFromSemantics: true,
      ),
      crmGap,
      crmText(title, 20, rounded: true, align: TextAlign.center),
      const SizedBox(height: 8),
      crmText(
        message,
        14,
        color: CrmTone.muted,
        height: 1.8,
        align: TextAlign.center,
      ),
      const SizedBox(height: 22),
      if (action != null)
        SizedBox(width: 190, child: CrmButton(action, onTap, primary: true)),
    ],
  ),
);

Widget crmSection(String title, {Widget? action}) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 10),
  child: Row(
    children: [
      Expanded(child: crmText(title, 17, rounded: true)),
      ?action,
    ],
  ),
);

Widget crmTimeline(List<List<String>> lines) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final line in lines)
      Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xffe4d8b8), width: 2)),
        ),
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          0,
          identical(line, lines.last) ? 0 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            crmText(line[1], 13, bold: true),
            crmText(line[0], 13, color: CrmTone.muted),
          ],
        ),
      ),
  ],
);

Future<T?> crmSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  backgroundColor: CrmTone.surface,
  showDragHandle: false,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  constraints: const BoxConstraints(maxWidth: 410),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: false, child: builder(context)),
  ),
);

class CrmSheetBody extends StatelessWidget {
  const CrmSheetBody(
    this.title,
    this.body, {
    super.key,
    this.close,
    this.actions,
  });
  final String title;
  final Widget body;
  final VoidCallback? close;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight:
          MediaQuery.sizeOf(context).height * .84 -
          MediaQuery.viewInsetsOf(context).bottom * .65,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: crmBox(
              color: const Color(0xffd4c6a5),
              border: null,
              radius: 5,
            ),
          ),
          crmGap,
          Row(
            children: [
              Expanded(child: crmText(title, 21, rounded: true)),
              SizedBox(
                width: 48,
                child: CrmButton(
                  '×',
                  close ?? () => Navigator.pop(context),
                  height: 48,
                  size: 22,
                  border: CrmTone.line,
                  semanticLabel: '关闭弹层',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(child: SingleChildScrollView(child: body)),
          if (actions != null) ...[const SizedBox(height: 18), actions!],
        ],
      ),
    ),
  );
}

Widget crmActions(Widget a, Widget b, {int primaryFlex = 1}) => Row(
  children: [
    Expanded(child: a),
    const SizedBox(width: 8),
    Expanded(flex: primaryFlex, child: b),
  ],
);
