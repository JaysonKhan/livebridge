import 'package:flutter/material.dart';

import '../../state/host_platform.dart';
import 'brand.dart';
import 'tokens.dart';

/// macOS. Apple does not publish hex values; these are AppKit's semantic colours as they render (Light | Dark),
/// with the brand accent in place of the system accent. The font is the system font (Flutter's default on macOS,
/// SF Pro), so no family is set.

/// Measured on macOS 26 with the unified toolbar set up in `macos/Runner/MainFlutterWindow.swift`: the toolbar row
/// is 52 pt tall with the traffic lights centred in it (14 pt buttons at x 19, 42 and 65, so they end at 79 pt).
const macToolbarHeight = 52.0;

/// The header content starts after the traffic lights (79 pt) plus the usual gap before a first toolbar item.
const macTrafficLightsInset = 92.0;

LiveBridgeTokens macosTokens(Brightness brightness) {
  final light = brightness == Brightness.light;
  Color pick(int l, int d) => Color(light ? l : d);
  final accent = light ? Brand.teal : Brand.macDarkAccent;
  final box = pick(0xFFFFFFFF, 0xFF2A2A2A);
  final pushFill = pick(0xFFFFFFFF, 0x2EFFFFFF);
  final pushStroke = pick(0x26000000, 0x1AFFFFFF);
  // Apple's secondaryLabel (#80000000) is 4.0:1 on white; a little darker keeps descriptions at 4.5:1 or more.
  final secondary = pick(0x99000000, 0x8CFFFFFF);
  final tertiary = pick(0x42000000, 0x40FFFFFF);
  return LiveBridgeTokens(
    platform: HostPlatform.macos,
    controlRadius: 6,
    fieldRadius: 5,
    cardRadius: 10,
    dialogRadius: 12,
    pttRadius: 12,
    tagRadius: 999,
    controlHeight: 24,
    headerHeight: macToolbarHeight,
    headerLeadingInset: macTrafficLightsInset,
    brandMarkSize: 20,
    cardPadding: 12,
    labelGap: 4,
    page: pick(0xFFF5F5F5, 0xFF1E1E1E),
    header: pick(0xFFECECEC, 0xFF262626),
    card: box,
    cardSecondary: box,
    cardStroke: pick(0x0F000000, 0x14FFFFFF),
    flyout: box,
    dialog: pick(0xFFECECEC, 0xFF262626),
    controlFill: pushFill,
    controlFillHover: pushFill,
    controlFillPressed: pick(0xFFE6E6E6, 0x40FFFFFF),
    // A disabled push button keeps its bezel; only the label dims.
    controlFillDisabled: pushFill,
    controlStroke: pushStroke,
    controlStrokeBottom: pushStroke,
    controlShadow: pick(0x26000000, 0x00000000),
    strongStroke: pick(0x80000000, 0x8CFFFFFF),
    divider: pick(0x1A000000, 0x1AFFFFFF),
    subtleFill: pick(0x0A000000, 0x0FFFFFFF),
    subtleFillPressed: pick(0x14000000, 0x1AFFFFFF),
    textPrimary: pick(0xD9000000, 0xD9FFFFFF),
    textSecondary: secondary,
    textTertiary: tertiary,
    textDisabled: tertiary,
    accent: accent,
    accentPressed: Color.alphaBlend(const Color(0x26000000), accent),
    onAccent: const Color(0xFFFFFFFF),
    accentText: light ? Brand.tealDark : Brand.mint,
    // A disabled default button looks like a disabled push button.
    accentDisabled: pushFill,
    onAccentDisabled: tertiary,
    accentStroke: const Color(0x00000000),
    accentStrokeBottom: const Color(0x00000000),
    fieldFill: pick(0xFFFFFFFF, 0x0DFFFFFF),
    fieldFillHover: pick(0xFFFFFFFF, 0x0DFFFFFF),
    fieldFillFocused: pick(0xFFFFFFFF, 0x0DFFFFFF),
    fieldStroke: pushStroke,
    fieldBottom: pushStroke,
    // The accent at 50 %; in the dark the lighter accent (mint), as the teal ring would barely show.
    focusPrimary: (light ? accent : Brand.mint).withValues(alpha: 0.5),
    focusSecondary: const Color(0x00000000),
    success: StatusColors(foreground: pick(0xFF0F7B0F, 0xFF6CCB5F), background: pick(0xFFDFF6DD, 0xFF393D1B)),
    caution: StatusColors(foreground: pick(0xFF9D5D00, 0xFFFCE100), background: pick(0xFFFFF4CE, 0xFF433519)),
    critical: StatusColors(foreground: pick(0xFFC42B1C, 0xFFFF99A4), background: pick(0xFFFDE7E9, 0xFF442726)),
    pttIdleFill: light ? Color.alphaBlend(Brand.mint.withValues(alpha: 0.12), box) : Brand.night,
    pttIdleBorder: light ? accent : Brand.mint.withValues(alpha: 0.4),
    pttGlow: Brand.mint.withValues(alpha: 0.45),
  );
}

/// AppKit's text styles mapped onto Material's slots: body 13/16, small 11/14, headline 13 semibold, title3 15/20
/// semibold, title2 17/22 semibold. Section headers are 13 semibold (group titles), descriptions 11.
TextTheme macosTextTheme() {
  TextStyle s(double size, double line, [FontWeight weight = FontWeight.w400]) =>
      TextStyle(fontSize: size, height: line / size, fontWeight: weight, letterSpacing: 0);
  const semibold = FontWeight.w600;
  return TextTheme(
    displayLarge: s(17, 22, semibold),
    displayMedium: s(17, 22, semibold),
    displaySmall: s(17, 22, semibold),
    headlineLarge: s(17, 22, semibold),
    headlineMedium: s(17, 22, semibold),
    headlineSmall: s(15, 20, semibold),
    titleLarge: s(15, 20, semibold),
    titleMedium: s(13, 16, semibold),
    titleSmall: s(13, 16, semibold),
    bodyLarge: s(13, 16),
    bodyMedium: s(13, 16),
    bodySmall: s(11, 14),
    labelLarge: s(13, 16, semibold),
    labelMedium: s(11, 14, semibold),
    labelSmall: s(11, 14),
  );
}
