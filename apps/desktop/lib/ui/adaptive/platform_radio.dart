import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The platform's radio button glyph (no interaction of its own: the row around it handles clicks, focus and
/// semantics). Windows: 20 px, a strong-stroke ring when off, an accent disc with a 10 px text-on-accent centre when
/// on (12 px on hover, 8 px pressed). macOS: 16 px, a ring in the secondary label colour on the field fill when off,
/// an accent disc with a white centre dot when on.
class PlatformRadio extends StatelessWidget {
  const PlatformRadio({
    super.key,
    required this.selected,
    this.enabled = true,
    this.hovered = false,
    this.pressed = false,
  });

  final bool selected;
  final bool enabled;
  final bool hovered;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.isWindows ? 20.0 : 16.0;
    return CustomPaint(
      size: Size.square(size),
      painter: _RadioPainter(
        selected: selected,
        ring: enabled ? t.strongStroke : t.textDisabled,
        offFill: t.isWindows ? (hovered ? t.subtleFill : Colors.transparent) : t.fieldFill,
        disc: enabled ? t.accent.withValues(alpha: pressed ? 0.8 : (hovered ? 0.9 : 1)) : t.accentDisabled,
        dot: enabled ? t.onAccent : t.onAccentDisabled,
        dotDiameter: t.isWindows ? (pressed ? 8 : (hovered ? 12 : 10)) : 6,
      ),
    );
  }
}

class _RadioPainter extends CustomPainter {
  _RadioPainter({
    required this.selected,
    required this.ring,
    required this.offFill,
    required this.disc,
    required this.dot,
    required this.dotDiameter,
  });

  final bool selected;
  final Color ring;
  final Color offFill;
  final Color disc;
  final Color dot;
  final double dotDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (selected) {
      canvas.drawCircle(center, radius, Paint()..color = disc);
      canvas.drawCircle(center, dotDiameter / 2, Paint()..color = dot);
      return;
    }
    canvas.drawCircle(center, radius, Paint()..color = offFill);
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_RadioPainter old) =>
      old.selected != selected ||
      old.ring != ring ||
      old.offFill != offFill ||
      old.disc != disc ||
      old.dot != dot ||
      old.dotDiameter != dotDiameter;
}
