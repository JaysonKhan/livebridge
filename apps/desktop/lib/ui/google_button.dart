import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import 'adaptive/control_border.dart';
import 'adaptive/pressable.dart';

/// "Sign in with Google" as Google's branding rules draw it: the standard four-colour "G" on a white (light) or
/// #131314 (dark) button with a 1 px #747775 (light) / #8E918F (dark) stroke, the label in #1F1F1F / #E3E3E3 at
/// weight 500. The look is the same on every platform, as the rules ask.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF131314) : Colors.white;
    final stroke = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);
    final ink = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final label = context.l10n.signInWithGoogle;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Pressable(
        onPressed: onPressed,
        builder: (context, s) => FocusRing(
          visible: s.focused,
          radius: 20,
          inset: 4,
          child: Opacity(
            opacity: s.enabled ? 1 : 0.38,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                // A faint state layer on hover and press, as the guidelines allow.
                color: Color.alphaBlend(ink.withValues(alpha: s.pressed ? 0.12 : (s.hovered ? 0.08 : 0)), fill),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(dimension: 18, child: CustomPaint(painter: GoogleMarkPainter())),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google's "G" mark: the published 48 × 48 artwork, scaled to the paint area.
class GoogleMarkPainter extends CustomPainter {
  const GoogleMarkPainter();

  static const _red = Color(0xFFEA4335);
  static const _blue = Color(0xFF4285F4);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    void fill(Path path, Color color) => canvas.drawPath(path, Paint()..color = color);

    fill(
      Path()
        ..moveTo(24, 9.5)
        ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
        ..relativeLineTo(6.85, -6.85)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..relativeLineTo(7.98, 6.19)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close(),
      _red,
    );
    fill(
      Path()
        ..moveTo(46.98, 24.55)
        ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
        ..lineTo(24, 20)
        ..relativeLineTo(0, 9.02)
        ..relativeLineTo(12.94, 0)
        ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
        ..relativeLineTo(7.73, 6)
        ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
        ..close(),
      _blue,
    );
    fill(
      Path()
        ..moveTo(10.53, 28.59)
        ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
        ..relativeCubicTo(0, -1.6, 0.27, -3.14, 0.76, -4.59)
        ..relativeLineTo(-7.98, -6.19)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
        ..relativeLineTo(7.97, -6.19)
        ..close(),
      _yellow,
    );
    fill(
      Path()
        ..moveTo(24, 48)
        ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
        ..relativeLineTo(-7.73, -6)
        ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
        ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
        ..relativeLineTo(-7.98, 6.19)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close(),
      _green,
    );
  }

  @override
  bool shouldRepaint(GoogleMarkPainter oldDelegate) => false;
}
