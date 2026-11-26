import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How keyboard focus is drawn around a control. Windows: a 2 px outer stroke and a 1 px inner stroke, 3 px out
/// from the control (WinUI focus visual). macOS: a 3 px focus ring in the accent at 50 %.
@immutable
class FocusRingStyle {
  const FocusRingStyle({required this.windows, required this.primary, required this.secondary});

  FocusRingStyle.of(LiveBridgeTokens t)
    : this(windows: t.isWindows, primary: t.focusPrimary, secondary: t.focusSecondary);

  final bool windows;
  final Color primary;
  final Color secondary;

  /// Paints the ring outside [control].
  void paint(Canvas canvas, RRect control) {
    final stroke = Paint()..style = PaintingStyle.stroke;
    if (windows) {
      canvas.drawRRect(
        control.inflate(0.5),
        stroke
          ..color = secondary
          ..strokeWidth = 1,
      );
      canvas.drawRRect(
        control.inflate(2),
        stroke
          ..color = primary
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawRRect(
        control.inflate(1.5),
        stroke
          ..color = primary
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FocusRingStyle && other.windows == windows && other.primary == primary && other.secondary == secondary;

  @override
  int get hashCode => Object.hash(windows, primary, secondary);
}

/// Strokes [outline] with [color], turning to [bottomColor] along the bottom edge (WinUI ControlElevationBorderBrush:
/// the last pixel row of the outline is darker, the corners fade into it).
void _strokeOutline(Canvas canvas, RRect outline, double width, Color color, Color? bottomColor) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;
  final rect = outline.outerRect;
  if (bottomColor != null && bottomColor != color && rect.height > 2) {
    final h = rect.height;
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color, color, bottomColor],
      stops: [0, (h - 2) / h, (h - 1) / h],
    ).createShader(rect);
  }
  canvas.drawRRect(outline.deflate(width / 2), paint);
}

/// The border of standard and accent buttons: a 1 px rounded outline with a darker bottom edge (Windows) or a
/// hairline shadow underneath (macOS push button), plus the focus ring when focused.
class ControlBorder extends OutlinedBorder {
  const ControlBorder({super.side, this.radius = 4, this.bottomColor, this.shadowColor, this.focusRing});

  final double radius;

  /// The bottom edge of the outline; null keeps it the colour of [side].
  final Color? bottomColor;

  /// A hairline shadow under the control (0, 0.5, blur 1); null for none.
  final Color? shadowColor;

  /// Painted outside the control when not null.
  final FocusRingStyle? focusRing;

  RRect _rrect(Rect rect) => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect).deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  bool get preferPaintInterior => true;

  @override
  void paintInterior(Canvas canvas, Rect rect, Paint paint, {TextDirection? textDirection}) =>
      canvas.drawRRect(_rrect(rect), paint);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outline = _rrect(rect);
    final shadow = shadowColor;
    if (shadow != null && shadow.a > 0) {
      // Only outside the control, so the fill keeps its colour.
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(4))
          ..addRRect(outline),
      );
      canvas.drawRRect(
        outline.shift(const Offset(0, 0.5)),
        Paint()
          ..color = shadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(1)),
      );
      canvas.restore();
    }
    if (side.style != BorderStyle.none && side.width > 0) {
      _strokeOutline(canvas, outline, side.width, side.color, bottomColor);
    }
    focusRing?.paint(canvas, outline);
  }

  @override
  ControlBorder copyWith({BorderSide? side, double? radius}) => ControlBorder(
    side: side ?? this.side,
    radius: radius ?? this.radius,
    bottomColor: bottomColor,
    shadowColor: shadowColor,
    focusRing: focusRing,
  );

  @override
  ControlBorder scale(double t) => ControlBorder(
    side: side.scale(t),
    radius: radius * t,
    bottomColor: bottomColor,
    shadowColor: shadowColor,
    focusRing: focusRing,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is ControlBorder ? a._lerp(this, t) : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is ControlBorder ? _lerp(b, t) : super.lerpTo(b, t);

  ControlBorder _lerp(ControlBorder b, double t) => ControlBorder(
    side: BorderSide.lerp(side, b.side, t),
    radius: lerpDouble(radius, b.radius, t)!,
    bottomColor: Color.lerp(bottomColor, b.bottomColor, t),
    shadowColor: Color.lerp(shadowColor, b.shadowColor, t),
    focusRing: t < 0.5 ? focusRing : b.focusRing,
  );

  @override
  bool operator ==(Object other) =>
      other is ControlBorder &&
      other.side == side &&
      other.radius == radius &&
      other.bottomColor == bottomColor &&
      other.shadowColor == shadowColor &&
      other.focusRing == focusRing;

  @override
  int get hashCode => Object.hash(side, radius, bottomColor, shadowColor, focusRing);
}

/// The border of text boxes and drop-down fields: a 1 px rounded outline with a bottom line on top of it
/// ([bottomWidth] px of [bottomColor], clipped to the rounded corners), plus the focus ring when not null.
///
/// Windows text box: strong-stroke bottom line at rest, a 2 px accent line when focused. macOS: the outline only,
/// turning accent with the focus ring around it.
class ControlInputBorder extends InputBorder {
  const ControlInputBorder({super.borderSide, this.radius = 4, this.bottomColor, this.bottomWidth = 1, this.focusRing});

  final double radius;
  final Color? bottomColor;
  final double bottomWidth;
  final FocusRingStyle? focusRing;

  RRect _rrect(Rect rect) => RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect).deflate(borderSide.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final outline = _rrect(rect);
    if (borderSide.style != BorderStyle.none && borderSide.width > 0) {
      _strokeOutline(canvas, outline, borderSide.width, borderSide.color, null);
    }
    final bottom = bottomColor;
    if (bottom != null && bottomWidth > 0) {
      canvas.save();
      canvas.clipRRect(outline);
      canvas.drawRect(
        Rect.fromLTRB(rect.left, rect.bottom - bottomWidth, rect.right, rect.bottom),
        Paint()..color = bottom,
      );
      canvas.restore();
    }
    focusRing?.paint(canvas, outline);
  }

  @override
  ControlInputBorder copyWith({BorderSide? borderSide}) => ControlInputBorder(
    borderSide: borderSide ?? this.borderSide,
    radius: radius,
    bottomColor: bottomColor,
    bottomWidth: bottomWidth,
    focusRing: focusRing,
  );

  @override
  ControlInputBorder scale(double t) => ControlInputBorder(
    borderSide: borderSide.scale(t),
    radius: radius * t,
    bottomColor: bottomColor,
    bottomWidth: bottomWidth * t,
    focusRing: focusRing,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is ControlInputBorder ? a._lerp(this, t) : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is ControlInputBorder ? _lerp(b, t) : super.lerpTo(b, t);

  ControlInputBorder _lerp(ControlInputBorder b, double t) => ControlInputBorder(
    borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
    radius: lerpDouble(radius, b.radius, t)!,
    bottomColor: Color.lerp(bottomColor, b.bottomColor, t),
    bottomWidth: lerpDouble(bottomWidth, b.bottomWidth, t)!,
    focusRing: t < 0.5 ? focusRing : b.focusRing,
  );

  @override
  bool operator ==(Object other) =>
      other is ControlInputBorder &&
      other.borderSide == borderSide &&
      other.radius == radius &&
      other.bottomColor == bottomColor &&
      other.bottomWidth == bottomWidth &&
      other.focusRing == focusRing;

  @override
  int get hashCode => Object.hash(borderSide, radius, bottomColor, bottomWidth, focusRing);
}

/// Paints the focus ring around its child (no layout change) while [visible]. A positive [inset] draws it inside
/// the child instead, for a child that fills a clipping parent (an expander header in its card).
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.visible, required this.radius, required this.child, this.inset = 0});

  final bool visible;
  final double radius;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: visible ? _FocusRingPainter(FocusRingStyle.of(context.tokens), radius, inset) : null,
      child: child,
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.style, this.radius, this.inset);

  final FocusRingStyle style;
  final double radius;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    // The ring reaches 3 px beyond the rectangle it surrounds.
    final rect = (Offset.zero & size).deflate(inset);
    style.paint(canvas, RRect.fromRectAndRadius(rect, Radius.circular((radius - inset).clamp(0, radius))));
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => old.style != style || old.radius != radius || old.inset != inset;
}
