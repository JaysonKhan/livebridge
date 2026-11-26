import 'package:flutter/material.dart';

import '../../state/host_platform.dart';
import 'brand.dart';
import 'tokens.dart';

/// Windows 11 / Fluent. The colours are Microsoft's WinUI theme resources (Light | Dark), with the brand accent in
/// place of the system accent.

/// Segoe UI Variable Text on Windows 11, Segoe UI before it.
const windowsFontFamily = 'Segoe UI Variable Text';
const windowsFontFallback = ['Segoe UI'];

LiveBridgeTokens windowsTokens(Brightness brightness) {
  final light = brightness == Brightness.light;
  Color pick(int l, int d) => Color(light ? l : d);
  final accent = light ? Brand.teal : Brand.mint;
  final card = pick(0xFFFBFBFB, 0xFF2B2B2B);
  return LiveBridgeTokens(
    platform: HostPlatform.windows,
    controlRadius: 4,
    fieldRadius: 4,
    cardRadius: 8,
    dialogRadius: 8,
    pttRadius: 8,
    tagRadius: 4,
    controlHeight: 32,
    headerHeight: 48,
    headerLeadingInset: 16,
    brandMarkSize: 24,
    cardPadding: 16,
    labelGap: 8,
    // SolidBackgroundFillColorBase, the Mica fallback.
    page: pick(0xFFF3F3F3, 0xFF202020),
    header: pick(0xFFF3F3F3, 0xFF202020),
    // CardBackgroundFillColorDefault / Secondary over the base.
    card: card,
    cardSecondary: pick(0xFFF5F5F5, 0xFF272727),
    cardStroke: pick(0x0F000000, 0x19000000),
    // AcrylicBackgroundFillColorDefault fallback.
    flyout: pick(0xFFF9F9F9, 0xFF2C2C2C),
    // SurfaceStrokeColorFlyout; MenuFlyout / ComboBox list geometry.
    flyoutStroke: pick(0x0F000000, 0x33000000),
    menuRadius: 8,
    menuInset: 4,
    menuItemHeight: 32,
    dialog: card,
    controlFill: pick(0xB3FFFFFF, 0x0FFFFFFF),
    controlFillHover: pick(0x80F9F9F9, 0x15FFFFFF),
    controlFillPressed: pick(0x4DF9F9F9, 0x08FFFFFF),
    controlFillDisabled: pick(0x4DF9F9F9, 0x0BFFFFFF),
    controlStroke: pick(0x0F000000, 0x12FFFFFF),
    controlStrokeBottom: pick(0x29000000, 0x18FFFFFF),
    controlShadow: const Color(0x00000000),
    strongStroke: pick(0x72000000, 0x8BFFFFFF),
    divider: pick(0x0F000000, 0x15FFFFFF),
    subtleFill: pick(0x09000000, 0x0FFFFFFF),
    subtleFillPressed: pick(0x06000000, 0x0AFFFFFF),
    textPrimary: pick(0xE4000000, 0xFFFFFFFF),
    textSecondary: pick(0x9E000000, 0xC5FFFFFF),
    textTertiary: pick(0x72000000, 0x87FFFFFF),
    textDisabled: pick(0x5C000000, 0x5DFFFFFF),
    accent: accent,
    accentPressed: accent.withValues(alpha: 0.8),
    onAccent: pick(0xFFFFFFFF, 0xFF000000),
    accentText: light ? Brand.tealDark : Brand.mint,
    accentDisabled: pick(0x37000000, 0x28FFFFFF),
    onAccentDisabled: pick(0xFFFFFFFF, 0x87FFFFFF),
    // AccentControlElevationBorderBrush.
    accentStroke: const Color(0x14FFFFFF),
    accentStrokeBottom: pick(0x66000000, 0x24000000),
    fieldFill: pick(0xB3FFFFFF, 0x0FFFFFFF),
    fieldFillHover: pick(0x80F9F9F9, 0x15FFFFFF),
    fieldFillFocused: pick(0xFFFFFFFF, 0xFF1E1E1E),
    fieldStroke: pick(0x0F000000, 0x12FFFFFF),
    fieldBottom: pick(0x72000000, 0x8BFFFFFF),
    focusPrimary: pick(0xE4000000, 0xFFFFFFFF),
    focusSecondary: pick(0xB3FFFFFF, 0xB3000000),
    success: StatusColors(foreground: pick(0xFF0F7B0F, 0xFF6CCB5F), background: pick(0xFFDFF6DD, 0xFF393D1B)),
    caution: StatusColors(foreground: pick(0xFF9D5D00, 0xFFFCE100), background: pick(0xFFFFF4CE, 0xFF433519)),
    critical: StatusColors(foreground: pick(0xFFC42B1C, 0xFFFF99A4), background: pick(0xFFFDE7E9, 0xFF442726)),
    pttIdleFill: light ? Color.alphaBlend(Brand.mint.withValues(alpha: 0.12), card) : Brand.night,
    pttIdleBorder: light ? accent : Brand.mint.withValues(alpha: 0.4),
    pttGlow: Brand.mint.withValues(alpha: 0.45),
  );
}

/// The Fluent type ramp mapped onto Material's slots: Caption 12/16, Body 14/20, Body Strong 14/20 semibold,
/// Body Large 18/24, Subtitle 20/28 semibold, Title 28/36 semibold. Controls and section headers use Body / Body
/// Strong, dialog titles Subtitle.
TextTheme windowsTextTheme() {
  TextStyle s(double size, double line, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: windowsFontFamily,
    fontFamilyFallback: windowsFontFallback,
    fontSize: size,
    height: line / size,
    fontWeight: weight,
    letterSpacing: 0,
  );
  const semibold = FontWeight.w600;
  return TextTheme(
    displayLarge: s(28, 36, semibold),
    displayMedium: s(28, 36, semibold),
    displaySmall: s(28, 36, semibold),
    headlineLarge: s(28, 36, semibold),
    headlineMedium: s(28, 36, semibold),
    headlineSmall: s(20, 28, semibold),
    titleLarge: s(20, 28, semibold),
    titleMedium: s(14, 20, semibold),
    titleSmall: s(14, 20, semibold),
    bodyLarge: s(14, 20),
    bodyMedium: s(14, 20),
    bodySmall: s(12, 16),
    labelLarge: s(14, 20, semibold),
    labelMedium: s(12, 16, semibold),
    labelSmall: s(12, 16),
  );
}
