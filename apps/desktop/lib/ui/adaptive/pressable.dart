import 'package:flutter/material.dart';

/// What a custom control looks like at the moment: hovered, pressed, showing keyboard focus.
@immutable
class PressState {
  const PressState({required this.enabled, required this.hovered, required this.pressed, required this.focused});

  final bool enabled;
  final bool hovered;
  final bool pressed;

  /// Keyboard focus is shown (traditional highlight mode only, as for Material controls).
  final bool focused;
}

/// The interaction plumbing the custom controls share: click, keyboard activation (Space / Enter through the app's
/// default shortcuts), hover, press and focus state. It adds no semantics; each control describes itself.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onPressed, required this.builder});

  /// Null disables the control (not focusable, no hover).
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _activate() => widget.onPressed?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _activate()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _activate()),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: widget.builder(
          context,
          PressState(
            enabled: enabled,
            hovered: enabled && _hovered,
            pressed: enabled && _pressed,
            focused: enabled && _focused,
          ),
        ),
      ),
    );
  }
}
