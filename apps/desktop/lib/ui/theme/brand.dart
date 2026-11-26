import 'package:flutter/painting.dart';

/// The LiveBridge brand colours, taken from the app logo. Both platforms use the brand accent instead of the system
/// accent (Apple and Microsoft both allow an app accent).
abstract final class Brand {
  static const deep = Color(0xFF0E1F22);
  static const night = Color(0xFF14403D);

  /// Accent fill in light themes; white text on it is 5.1:1.
  static const teal = Color(0xFF0E7C6B);

  /// Accent-coloured text and links on light backgrounds (5.5:1).
  static const tealDark = Color(0xFF0B6E5F);

  /// Accent fill in the Windows dark theme (black text on it is 13.4:1) and accent text on dark backgrounds (10.4:1).
  static const mint = Color(0xFF7FE0C8);
  static const mintSoft = Color(0xFFA8EEDC);

  /// Accent fill in the macOS dark theme; white text on it is 4.65:1.
  static const macDarkAccent = Color(0xFF118372);

  /// The rounded brand mark (128 px), shown in the window header.
  static const logoAsset = 'assets/brand/logo_mark.png';

  /// The name in the window header, the same as the window title.
  static const appName = 'JK - LiveBridge';
}
