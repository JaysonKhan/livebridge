import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../state/host_platform.dart';

/// The design tokens of one platform look (Windows 11 / Fluent or macOS) in one brightness. The theme carries them
/// as a [ThemeExtension]; the custom controls in `lib/ui/adaptive/` and the restyled widgets read them through
/// `context.tokens` instead of hard-coding colours or radii.
///
/// Colours are written `0xAARRGGBB`. The values come from `windows_theme.dart` and `macos_theme.dart`.
@immutable
class LiveBridgeTokens extends ThemeExtension<LiveBridgeTokens> {
  const LiveBridgeTokens({
    required this.platform,
    required this.controlRadius,
    required this.fieldRadius,
    required this.cardRadius,
    required this.dialogRadius,
    required this.pttRadius,
    required this.tagRadius,
    required this.controlHeight,
    required this.headerHeight,
    required this.headerLeadingInset,
    required this.brandMarkSize,
    required this.cardPadding,
    required this.labelGap,
    required this.page,
    required this.header,
    required this.card,
    required this.cardSecondary,
    required this.cardStroke,
    required this.flyout,
    required this.dialog,
    required this.controlFill,
    required this.controlFillHover,
    required this.controlFillPressed,
    required this.controlFillDisabled,
    required this.controlStroke,
    required this.controlStrokeBottom,
    required this.controlShadow,
    required this.strongStroke,
    required this.divider,
    required this.subtleFill,
    required this.subtleFillPressed,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentPressed,
    required this.onAccent,
    required this.accentText,
    required this.accentDisabled,
    required this.onAccentDisabled,
    required this.accentStroke,
    required this.accentStrokeBottom,
    required this.fieldFill,
    required this.fieldFillHover,
    required this.fieldFillFocused,
    required this.fieldStroke,
    required this.fieldBottom,
    required this.focusPrimary,
    required this.focusSecondary,
    required this.success,
    required this.caution,
    required this.critical,
    required this.pttIdleFill,
    required this.pttIdleBorder,
    required this.pttGlow,
  });

  final HostPlatform platform;

  bool get isWindows => platform == HostPlatform.windows;

  // Geometry.

  /// Buttons and other standard controls (Windows 4, macOS push button 6).
  final double controlRadius;

  /// Text boxes and drop-downs (Windows 4, macOS 5).
  final double fieldRadius;

  /// Cards, expanders and grouped boxes (Windows 8, macOS 10).
  final double cardRadius;

  /// Dialogs and sheets (Windows 8, macOS 12).
  final double dialogRadius;

  /// The push-to-talk control (Windows 8, macOS 12).
  final double pttRadius;

  /// Status tags (Windows 4; macOS capsules).
  final double tagRadius;

  /// Height of buttons, text boxes and drop-downs (Windows 32, macOS 24).
  final double controlHeight;

  /// Height of the window header (Windows brand bar 48, macOS unified toolbar 52).
  final double headerHeight;

  /// Space left free at the start of the header (macOS: the traffic lights).
  final double headerLeadingInset;
  final double brandMarkSize;
  final double cardPadding;

  /// Between a field's label and the field.
  final double labelGap;

  // Surfaces.

  /// Behind the content (Windows base / Mica fallback, macOS content area).
  final Color page;

  /// Behind the header (Windows base, macOS window background).
  final Color header;
  final Color card;

  /// The open part of an expander (Windows), the same as [card] on macOS.
  final Color cardSecondary;
  final Color cardStroke;

  /// Menus and tooltips.
  final Color flyout;
  final Color dialog;

  // Controls.

  final Color controlFill;
  final Color controlFillHover;
  final Color controlFillPressed;
  final Color controlFillDisabled;
  final Color controlStroke;

  /// The darker bottom edge of a standard control (WinUI ControlElevationBorderBrush); [controlStroke] on macOS.
  final Color controlStrokeBottom;

  /// The hairline shadow under a macOS push button; transparent on Windows.
  final Color controlShadow;

  /// Outlines of switches, check boxes and radios.
  final Color strongStroke;
  final Color divider;

  /// Hover fill of rows and subtle buttons.
  final Color subtleFill;
  final Color subtleFillPressed;

  // Text.

  final Color textPrimary;

  /// Descriptions and secondary text; at least 4.5:1 on the page and on cards.
  final Color textSecondary;

  /// Glyphs and outlines only: below 4.5:1, never used for text that must be read.
  final Color textTertiary;
  final Color textDisabled;

  // Accent (the brand, not the system accent).

  /// Accent fill (primary buttons, switch tracks, checked boxes).
  final Color accent;
  final Color accentPressed;

  /// Text and glyphs on [accent].
  final Color onAccent;

  /// Accent-coloured text and links on the page and on cards.
  final Color accentText;
  final Color accentDisabled;
  final Color onAccentDisabled;

  /// The elevation edge of an accent button (Windows); transparent on macOS.
  final Color accentStroke;
  final Color accentStrokeBottom;

  // Text boxes.

  final Color fieldFill;
  final Color fieldFillHover;
  final Color fieldFillFocused;
  final Color fieldStroke;

  /// The bottom line of a text box at rest (Windows strong stroke; [fieldStroke] on macOS).
  final Color fieldBottom;

  // Keyboard focus.

  /// Windows: the 2 px outer focus stroke. macOS: the 3 px focus ring (accent at 50 %).
  final Color focusPrimary;

  /// Windows: the 1 px inner focus stroke. Transparent on macOS.
  final Color focusSecondary;

  // Status (InfoBar on Windows, inline banners on macOS).

  final StatusColors success;
  final StatusColors caution;
  final StatusColors critical;

  // The push-to-talk control, the one brand element.

  final Color pttIdleFill;
  final Color pttIdleBorder;

  /// The soft glow under the held push-to-talk control, the only glow in the app.
  final Color pttGlow;

  /// Tokens are fixed per platform and brightness; nothing overrides single values.
  @override
  LiveBridgeTokens copyWith() => this;

  @override
  LiveBridgeTokens lerp(LiveBridgeTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    return LiveBridgeTokens(
      platform: t < 0.5 ? platform : other.platform,
      controlRadius: d(controlRadius, other.controlRadius),
      fieldRadius: d(fieldRadius, other.fieldRadius),
      cardRadius: d(cardRadius, other.cardRadius),
      dialogRadius: d(dialogRadius, other.dialogRadius),
      pttRadius: d(pttRadius, other.pttRadius),
      tagRadius: d(tagRadius, other.tagRadius),
      controlHeight: d(controlHeight, other.controlHeight),
      headerHeight: d(headerHeight, other.headerHeight),
      headerLeadingInset: d(headerLeadingInset, other.headerLeadingInset),
      brandMarkSize: d(brandMarkSize, other.brandMarkSize),
      cardPadding: d(cardPadding, other.cardPadding),
      labelGap: d(labelGap, other.labelGap),
      page: c(page, other.page),
      header: c(header, other.header),
      card: c(card, other.card),
      cardSecondary: c(cardSecondary, other.cardSecondary),
      cardStroke: c(cardStroke, other.cardStroke),
      flyout: c(flyout, other.flyout),
      dialog: c(dialog, other.dialog),
      controlFill: c(controlFill, other.controlFill),
      controlFillHover: c(controlFillHover, other.controlFillHover),
      controlFillPressed: c(controlFillPressed, other.controlFillPressed),
      controlFillDisabled: c(controlFillDisabled, other.controlFillDisabled),
      controlStroke: c(controlStroke, other.controlStroke),
      controlStrokeBottom: c(controlStrokeBottom, other.controlStrokeBottom),
      controlShadow: c(controlShadow, other.controlShadow),
      strongStroke: c(strongStroke, other.strongStroke),
      divider: c(divider, other.divider),
      subtleFill: c(subtleFill, other.subtleFill),
      subtleFillPressed: c(subtleFillPressed, other.subtleFillPressed),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      accent: c(accent, other.accent),
      accentPressed: c(accentPressed, other.accentPressed),
      onAccent: c(onAccent, other.onAccent),
      accentText: c(accentText, other.accentText),
      accentDisabled: c(accentDisabled, other.accentDisabled),
      onAccentDisabled: c(onAccentDisabled, other.onAccentDisabled),
      accentStroke: c(accentStroke, other.accentStroke),
      accentStrokeBottom: c(accentStrokeBottom, other.accentStrokeBottom),
      fieldFill: c(fieldFill, other.fieldFill),
      fieldFillHover: c(fieldFillHover, other.fieldFillHover),
      fieldFillFocused: c(fieldFillFocused, other.fieldFillFocused),
      fieldStroke: c(fieldStroke, other.fieldStroke),
      fieldBottom: c(fieldBottom, other.fieldBottom),
      focusPrimary: c(focusPrimary, other.focusPrimary),
      focusSecondary: c(focusSecondary, other.focusSecondary),
      success: success.lerp(other.success, t),
      caution: caution.lerp(other.caution, t),
      critical: critical.lerp(other.critical, t),
      pttIdleFill: c(pttIdleFill, other.pttIdleFill),
      pttIdleBorder: c(pttIdleBorder, other.pttIdleBorder),
      pttGlow: c(pttGlow, other.pttGlow),
    );
  }
}

/// One status severity: [foreground] for its icon, [background] for the banner. Banner text stays the primary text
/// colour, as in a WinUI InfoBar.
@immutable
class StatusColors {
  const StatusColors({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  StatusColors lerp(StatusColors other, double t) => StatusColors(
    foreground: Color.lerp(foreground, other.foreground, t)!,
    background: Color.lerp(background, other.background, t)!,
  );
}

extension LiveBridgeTokensContext on BuildContext {
  /// The tokens of the current theme (always present under `LiveBridgeApp`).
  LiveBridgeTokens get tokens => Theme.of(this).extension<LiveBridgeTokens>()!;
}
