import 'package:flutter/material.dart';

import '../../state/host_platform.dart';
import '../adaptive/control_border.dart';
import 'macos_theme.dart';
import 'tokens.dart';
import 'windows_theme.dart';

/// The theme for one platform look in one brightness: Windows 11 / Fluent on Windows, macOS on the Mac, both in the
/// LiveBridge brand accent. Material widgets are restyled through their component themes; the custom controls read
/// the same [LiveBridgeTokens] from the theme's extensions.
ThemeData buildTheme(HostPlatform platform, Brightness brightness) {
  final windows = platform == HostPlatform.windows;
  final t = windows ? windowsTokens(brightness) : macosTokens(brightness);
  final text = windows ? windowsTextTheme() : macosTextTheme();
  final dark = brightness == Brightness.dark;
  final body = text.bodyMedium!.copyWith(color: t.textPrimary);
  final small = text.bodySmall!.copyWith(color: t.textSecondary);
  final input = inputDecorationTheme(t, text);
  final menu = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(t.flyout),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: dark ? 0.5 : 0.18)),
    elevation: const WidgetStatePropertyAll(8),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.cardStroke),
      ),
    ),
  );
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.pttIdleFill,
    onPrimaryContainer: t.textPrimary,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.subtleFill,
    onSecondaryContainer: t.textPrimary,
    tertiary: t.accentText,
    onTertiary: t.onAccent,
    error: t.critical.foreground,
    onError: dark ? Colors.black : Colors.white,
    errorContainer: t.critical.background,
    onErrorContainer: t.textPrimary,
    surface: t.card,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    surfaceContainerLowest: t.card,
    surfaceContainerLow: t.card,
    surfaceContainer: t.card,
    surfaceContainerHigh: t.flyout,
    surfaceContainerHighest: t.flyout,
    outline: t.strongStroke,
    outlineVariant: t.divider,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? const Color(0xFFF3F3F3) : const Color(0xFF202020),
    onInverseSurface: dark ? Colors.black : Colors.white,
    inversePrimary: t.accentText,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: windows ? windowsFontFamily : null,
    fontFamilyFallback: windows ? windowsFontFallback : null,
    textTheme: text,
    extensions: [t],
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    // Desktop controls answer with colour changes, not ink ripples.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: t.subtleFill,
    focusColor: t.accent.withValues(alpha: 0.16),
    scaffoldBackgroundColor: t.page,
    canvasColor: t.flyout,
    cardColor: t.card,
    dividerColor: t.divider,
    iconTheme: IconThemeData(color: t.textPrimary, size: 18),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: windows ? t.textPrimary : t.accent,
      selectionColor: t.accent.withValues(alpha: 0.35),
      selectionHandleColor: t.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(style: accentButtonStyle(t, text)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: standardButtonStyle(t, text)),
    textButtonTheme: TextButtonThemeData(style: _linkButtonStyle(t, text)),
    iconButtonTheme: IconButtonThemeData(style: _iconButtonStyle(t)),
    inputDecorationTheme: input,
    dropdownMenuTheme: DropdownMenuThemeData(textStyle: body, inputDecorationTheme: input, menuStyle: menu),
    menuTheme: MenuThemeData(style: menu),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(body),
        foregroundColor: WidgetStatePropertyAll(t.textPrimary),
        backgroundColor: _states((s) {
          if (s.contains(WidgetState.pressed)) return t.subtleFillPressed;
          if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return t.subtleFill;
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.controlRadius))),
        minimumSize: WidgetStatePropertyAll(Size(0, windows ? 32 : 22)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: windows ? 12 : 8)),
        visualDensity: VisualDensity.standard,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
        side: BorderSide(color: t.cardStroke),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.divider, thickness: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: _states((s) {
        final hovered = windows && s.contains(WidgetState.hovered);
        if (s.contains(WidgetState.selected)) {
          if (s.contains(WidgetState.disabled)) return t.accentDisabled;
          if (s.contains(WidgetState.pressed)) return t.accentPressed;
          return hovered ? t.accent.withValues(alpha: 0.9) : t.accent;
        }
        if (s.contains(WidgetState.disabled)) return Colors.transparent;
        if (hovered) return t.subtleFill;
        return windows ? Colors.transparent : t.fieldFill;
      }),
      checkColor: _states((s) => s.contains(WidgetState.disabled) ? t.onAccentDisabled : t.onAccent),
      side: WidgetStateBorderSide.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return BorderSide.none;
        return BorderSide(color: s.contains(WidgetState.disabled) ? t.textDisabled : t.strongStroke);
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(windows ? 4 : 3.5)),
      // A halo only for keyboard focus; hover and press change the fill instead.
      overlayColor: _states(
        (s) => s.contains(WidgetState.focused) ? t.focusPrimary.withValues(alpha: 0.2) : Colors.transparent,
      ),
      splashRadius: 14,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      titleTextStyle: body,
      subtitleTextStyle: small,
      selectedColor: t.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.controlRadius)),
      visualDensity: VisualDensity.compact,
      // Desktop list rows: the text plus a little air, not Material's 56–72 px touch rows.
      minVerticalPadding: 4,
      minTileHeight: t.controlHeight + 8,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.strongStroke.withValues(alpha: t.strongStroke.a * 0.3),
      borderRadius: BorderRadius.circular(t.isWindows ? 2 : 3),
      // A plain bar (the level meters): no gap before the track and no stop dot at its end.
      trackGap: 0,
      stopIndicatorColor: Colors.transparent,
      stopIndicatorRadius: 0,
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: (windows ? text.bodySmall : text.labelSmall)!.copyWith(color: t.textPrimary),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: windows ? 6 : 4),
      decoration: BoxDecoration(
        color: t.flyout,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.cardStroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.4 : 0.14),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.dialog,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.3),
      barrierColor: Colors.black.withValues(alpha: windows ? 0.3 : 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.dialogRadius),
        side: BorderSide(color: t.cardStroke),
      ),
      titleTextStyle: (windows ? text.headlineSmall : text.titleLarge)!.copyWith(color: t.textPrimary),
      contentTextStyle: body,
      actionsPadding: EdgeInsets.all(windows ? 24 : 20),
    ),
    // Notices ("Saved to …", "Copied") are success messages: an InfoBar on Windows, a rounded banner on macOS.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 560,
      elevation: 4,
      backgroundColor: t.success.background,
      contentTextStyle: body,
      actionTextColor: t.accentText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(windows ? t.controlRadius : t.cardRadius),
        side: BorderSide(color: t.cardStroke),
      ),
    ),
  );
}

WidgetStateProperty<T> _states<T>(T Function(Set<WidgetState> states) resolve) =>
    WidgetStateProperty.resolveWith(resolve);

/// The focus ring while a control shows keyboard focus (not after a mouse click).
FocusRingStyle? _ring(LiveBridgeTokens t, Set<WidgetState> s) =>
    s.contains(WidgetState.focused) && FocusManager.instance.highlightMode == FocusHighlightMode.traditional
    ? FocusRingStyle.of(t)
    : null;

ButtonStyle _sized(LiveBridgeTokens t, TextTheme text) => ButtonStyle(
  textStyle: WidgetStatePropertyAll(text.bodyMedium),
  minimumSize: WidgetStatePropertyAll(Size(48, t.controlHeight)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: t.isWindows ? 12 : 10)),
  iconSize: WidgetStatePropertyAll(t.isWindows ? 16 : 14),
  elevation: const WidgetStatePropertyAll(0),
  shadowColor: const WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  visualDensity: VisualDensity.standard,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  splashFactory: NoSplash.splashFactory,
);

/// The accent ("primary") button: Windows accent button (hover 90 %, pressed 80 %, the on-accent elevation edge),
/// macOS default button (accent fill, white text; disabled it looks like a disabled push button). [fill] and
/// [onFill] replace the accent, e.g. for the red panic button.
ButtonStyle accentButtonStyle(LiveBridgeTokens t, TextTheme text, {Color? fill, Color? onFill}) {
  final base = fill ?? t.accent;
  final on = onFill ?? t.onAccent;
  Color foreground(Set<WidgetState> s) => s.contains(WidgetState.disabled) ? t.onAccentDisabled : on;
  return _sized(t, text).copyWith(
    backgroundColor: _states((s) {
      if (s.contains(WidgetState.disabled)) return t.accentDisabled;
      if (s.contains(WidgetState.pressed)) {
        return t.isWindows ? base.withValues(alpha: 0.8) : Color.alphaBlend(const Color(0x26000000), base);
      }
      if (t.isWindows && s.contains(WidgetState.hovered)) return base.withValues(alpha: 0.9);
      return base;
    }),
    foregroundColor: _states(foreground),
    iconColor: _states(foreground),
    side: _states((s) {
      if (s.contains(WidgetState.disabled)) return t.isWindows ? BorderSide.none : BorderSide(color: t.controlStroke);
      return t.isWindows ? BorderSide(color: t.accentStroke) : BorderSide.none;
    }),
    shape: _states((s) {
      final disabled = s.contains(WidgetState.disabled);
      return ControlBorder(
        radius: t.controlRadius,
        bottomColor: t.isWindows && !disabled && !s.contains(WidgetState.pressed) ? t.accentStrokeBottom : null,
        shadowColor: !t.isWindows && disabled ? t.controlShadow : null,
        focusRing: _ring(t, s),
      );
    }),
  );
}

/// The standard button: Windows button (control fill, elevation border with its darker bottom edge), macOS push
/// button (white bezel, hairline border and shadow).
ButtonStyle standardButtonStyle(LiveBridgeTokens t, TextTheme text) {
  Color foreground(Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) return t.textDisabled;
    if (t.isWindows && s.contains(WidgetState.pressed)) return t.textSecondary;
    return t.textPrimary;
  }

  return _sized(t, text).copyWith(
    backgroundColor: _states((s) {
      if (s.contains(WidgetState.disabled)) return t.controlFillDisabled;
      if (s.contains(WidgetState.pressed)) return t.controlFillPressed;
      if (s.contains(WidgetState.hovered)) return t.controlFillHover;
      return t.controlFill;
    }),
    foregroundColor: _states(foreground),
    iconColor: _states(foreground),
    side: WidgetStatePropertyAll(BorderSide(color: t.controlStroke)),
    shape: _states((s) {
      final rest = !s.contains(WidgetState.disabled) && !s.contains(WidgetState.pressed);
      return ControlBorder(
        radius: t.controlRadius,
        bottomColor: t.isWindows && rest ? t.controlStrokeBottom : null,
        shadowColor: t.isWindows ? null : t.controlShadow,
        focusRing: _ring(t, s),
      );
    }),
  );
}

/// Text buttons are hyperlink buttons: accent text, a subtle fill under the pointer.
ButtonStyle _linkButtonStyle(LiveBridgeTokens t, TextTheme text) {
  Color foreground(Set<WidgetState> s) {
    if (s.contains(WidgetState.disabled)) return t.textDisabled;
    if (s.contains(WidgetState.pressed)) return t.accentText.withValues(alpha: 0.8);
    return t.accentText;
  }

  return _sized(t, text).copyWith(
    minimumSize: WidgetStatePropertyAll(Size(0, t.controlHeight)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: t.isWindows ? 11 : 8)),
    backgroundColor: _states((s) {
      if (s.contains(WidgetState.disabled)) return Colors.transparent;
      if (s.contains(WidgetState.pressed)) return t.subtleFillPressed;
      if (s.contains(WidgetState.hovered)) return t.subtleFill;
      return Colors.transparent;
    }),
    foregroundColor: _states(foreground),
    iconColor: _states(foreground),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: _states((s) => ControlBorder(radius: t.controlRadius, focusRing: _ring(t, s))),
  );
}

/// Icon buttons are subtle buttons: no fill at rest, the subtle fill under the pointer.
ButtonStyle _iconButtonStyle(LiveBridgeTokens t) => ButtonStyle(
  foregroundColor: _states((s) => s.contains(WidgetState.disabled) ? t.textDisabled : t.textPrimary),
  iconColor: _states((s) => s.contains(WidgetState.disabled) ? t.textDisabled : t.textPrimary),
  backgroundColor: _states((s) {
    if (s.contains(WidgetState.disabled)) return Colors.transparent;
    if (s.contains(WidgetState.pressed)) return t.subtleFillPressed;
    if (s.contains(WidgetState.hovered)) return t.subtleFill;
    return Colors.transparent;
  }),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  shape: _states((s) => ControlBorder(radius: t.controlRadius, focusRing: _ring(t, s))),
  minimumSize: WidgetStatePropertyAll(Size.square(t.isWindows ? 32 : 26)),
  padding: WidgetStatePropertyAll(EdgeInsets.all(t.isWindows ? 8 : 5)),
  iconSize: const WidgetStatePropertyAll(16),
  visualDensity: VisualDensity.standard,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  splashFactory: NoSplash.splashFactory,
);

/// Text boxes. Windows: 32 px, control fill, 1 px stroke with a strong-stroke bottom line; focused, a white (dark:
/// #1E1E1E) fill and a 2 px accent bottom line. macOS: 24 px, radius 5, white (dark: translucent) fill and a hairline
/// border; focused, an accent border with the 3 px focus ring outside. Labels sit above the box (`LabeledField`).
InputDecorationThemeData inputDecorationTheme(LiveBridgeTokens t, TextTheme text) {
  return InputDecorationThemeData(
    isDense: true,
    filled: true,
    visualDensity: VisualDensity.standard,
    contentPadding: fieldContentPadding(t, text.bodyLarge!.fontSize! * text.bodyLarge!.height!),
    // The suffix (a drop-down's menu button) fits in the control height instead of Material's 48 px minimum.
    suffixIconConstraints: BoxConstraints(
      minWidth: t.controlHeight,
      minHeight: t.controlHeight,
      maxHeight: t.controlHeight,
    ),
    fillColor: WidgetStateColor.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return t.controlFillDisabled;
      if (s.contains(WidgetState.focused)) return t.fieldFillFocused;
      if (s.contains(WidgetState.hovered)) return t.fieldFillHover;
      return t.fieldFill;
    }),
    hoverColor: Colors.transparent,
    hintStyle: text.bodyLarge!.copyWith(color: t.textSecondary),
    errorStyle: text.bodySmall!.copyWith(color: t.critical.foreground),
    helperStyle: text.bodySmall!.copyWith(color: t.textSecondary),
    counterStyle: text.bodySmall!.copyWith(color: t.textSecondary),
    suffixIconColor: t.textSecondary,
    border: textBoxBorder(t),
  );
}

/// The padding that centres content [contentHeight] tall in a field of the control height.
EdgeInsets fieldContentPadding(LiveBridgeTokens t, double contentHeight) {
  final vertical = (t.controlHeight - contentHeight) / 2;
  return EdgeInsets.fromLTRB(t.isWindows ? 11 : 7, vertical, t.isWindows ? 8 : 7, vertical);
}

/// The text box border for every state (see [inputDecorationTheme]).
InputBorder textBoxBorder(LiveBridgeTokens t) => WidgetStateInputBorder.resolveWith((s) {
  final focused = s.contains(WidgetState.focused);
  final error = s.contains(WidgetState.error);
  if (s.contains(WidgetState.disabled)) {
    return ControlInputBorder(
      borderSide: BorderSide(color: t.controlStroke),
      radius: t.fieldRadius,
    );
  }
  if (t.isWindows) {
    return ControlInputBorder(
      borderSide: BorderSide(color: t.fieldStroke),
      radius: t.fieldRadius,
      bottomColor: error ? t.critical.foreground : (focused ? t.accent : t.fieldBottom),
      bottomWidth: focused ? 2 : 1,
    );
  }
  return ControlInputBorder(
    borderSide: BorderSide(color: error ? t.critical.foreground : (focused ? t.accent : t.fieldStroke)),
    radius: t.fieldRadius,
    focusRing: focused ? FocusRingStyle.of(t) : null,
  );
});

/// A drop-down that is not typed into looks like a standard button: Windows ComboBox (control fill, elevation
/// border), macOS pop-up button (push-button bezel).
InputBorder comboBoxBorder(LiveBridgeTokens t) => WidgetStateInputBorder.resolveWith((s) {
  final focused =
      s.contains(WidgetState.focused) && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
  return ControlInputBorder(
    borderSide: BorderSide(color: t.controlStroke),
    radius: t.controlRadius,
    bottomColor: t.isWindows && !s.contains(WidgetState.disabled) ? t.controlStrokeBottom : null,
    focusRing: focused ? FocusRingStyle.of(t) : null,
  );
});
