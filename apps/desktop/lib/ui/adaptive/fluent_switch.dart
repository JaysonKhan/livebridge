import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'control_border.dart';
import 'pressable.dart';

/// The Windows 11 toggle switch: a 40×20 fully rounded track. Off: transparent track with a strong-stroke outline
/// and a 12 px knob in the same colour. On: accent track with a knob in the text-on-accent colour. The knob grows
/// to 14 px on hover and stretches while pressed, as in WinUI.
class FluentSwitch extends StatelessWidget {
  const FluentSwitch({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  static const width = 40.0;
  static const height = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120);
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: Pressable(
        onPressed: enabled ? () => onChanged!(!value) : null,
        builder: (context, s) {
          final Color track;
          final Color knob;
          if (!enabled) {
            track = value ? t.accentDisabled : Colors.transparent;
            knob = value ? t.onAccentDisabled : t.textDisabled;
          } else if (value) {
            track = t.accent.withValues(alpha: s.pressed ? 0.8 : (s.hovered ? 0.9 : 1));
            knob = t.onAccent;
          } else {
            track = s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent);
            knob = t.strongStroke;
          }
          final outline = value ? Colors.transparent : (enabled ? t.strongStroke : t.textDisabled);
          final knobHeight = s.hovered || s.pressed ? 14.0 : 12.0;
          final knobWidth = s.pressed ? 17.0 : knobHeight;
          return FocusRing(
            visible: s.focused,
            radius: height / 2,
            child: AnimatedContainer(
              duration: duration,
              width: width,
              height: height,
              // The 1 px border is inside the track too, so the knob sits as far from the ends as from the edges.
              padding: EdgeInsets.symmetric(horizontal: (height - knobHeight) / 2 - 1),
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(color: outline),
              ),
              child: AnimatedAlign(
                duration: duration,
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: duration,
                  width: knobWidth,
                  height: knobHeight,
                  decoration: BoxDecoration(color: knob, borderRadius: BorderRadius.circular(knobHeight / 2)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
