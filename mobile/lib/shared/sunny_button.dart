import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pandora_mobile/theme/app_theme.dart';
import 'page_states.dart';

/// A restrained themed action button with stable loading and focus states.
class SunnyPrimaryButton extends StatefulWidget {
  const SunnyPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.loading,
  }) : icon = null;
  const SunnyPrimaryButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.loading,
  }) : child = label;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;

  /// When provided, both idle and busy allocate the same progress slot.
  final bool? loading;
  @override
  State<SunnyPrimaryButton> createState() => _SunnyPrimaryButtonState();
}

class _SunnyPrimaryButtonState extends State<SunnyPrimaryButton> {
  final states = WidgetStatesController();
  bool get enabled => widget.onPressed != null && widget.loading != true;
  @override
  void initState() {
    super.initState();
    states.addListener(update);
  }

  void update() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    states.removeListener(update);
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SunnyPaperTokens.of(context),
        scheme = Theme.of(context).colorScheme;
    final pressed = enabled && states.value.contains(WidgetState.pressed);
    final focused = states.value.contains(WidgetState.focused);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : tokens.pressDuration;
    final shift = pressed ? 1.0 : 0.0;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 8)],
        if (widget.loading != null) const SizedBox(width: 24),
        Flexible(child: widget.child),
        if (widget.loading != null)
          SizedBox(
            width: 24,
            height: 16,
            child: widget.loading == true
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ExcludeSemantics(
                      child: SunnyLoadingIndicator(
                        size: 14,
                        color: tokens.disabledInk,
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.zero,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, shift, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.buttonRadius),
          boxShadow: focused
              ? [BoxShadow(color: tokens.focus, spreadRadius: 2)]
              : const [],
        ),
        child: Semantics(
          liveRegion: widget.loading == true,
          value: widget.loading == true ? '正在处理' : null,
          child: FilledButton(
            statesController: states,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onPressed: enabled ? widget.onPressed : null,
            style: (widget.style ?? const ButtonStyle()).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled)
                    ? tokens.disabled
                    : s.contains(WidgetState.pressed)
                    ? tokens.pressed
                    : scheme.primary,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled)
                    ? tokens.disabledInk
                    : scheme.onPrimary,
              ),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.buttonRadius),
                  side: BorderSide(
                    color: enabled
                        ? tokens.actionEdge.withValues(alpha: .3)
                        : tokens.disabled,
                  ),
                ),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
              animationDuration: duration,
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}
