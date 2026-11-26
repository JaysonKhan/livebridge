import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'fluent_switch.dart';

/// The platform's switch: the Fluent toggle switch on Windows, the macOS switch (a Cupertino switch in the brand
/// accent, scaled to the 38×22 of an AppKit switch) on the Mac.
class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// CupertinoSwitch lays out at 59×39 around a 51×31 track; this brings the track to about 38×22.
  static const _macScale = 0.74;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (t.isWindows) return FluentSwitch(value: value, onChanged: onChanged);
    return SizedBox(
      width: 59 * _macScale,
      height: 39 * _macScale,
      child: FittedBox(
        child: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: t.accent,
          inactiveTrackColor: t.strongStroke.withValues(alpha: t.strongStroke.a * 0.4),
          focusColor: t.focusPrimary,
        ),
      ),
    );
  }
}

/// A [SwitchListTile] that shows the platform switch: the title (and subtitle) on the left, the switch on the right.
/// Clicking the text toggles too; the switch is the one keyboard stop, and the text is merged into its semantics.
///
/// It extends [SwitchListTile] to keep that widget's API and type (the tests read `value` and `onChanged` from it).
class PlatformSwitchListTile extends SwitchListTile {
  const PlatformSwitchListTile({
    super.key,
    required super.value,
    required super.onChanged,
    required Widget super.title,
    super.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onChanged!(!value) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: text.bodyMedium!.copyWith(color: enabled ? t.textPrimary : t.textDisabled),
                      child: title!,
                    ),
                    if (subtitle case final subtitle?)
                      DefaultTextStyle.merge(
                        style: text.bodySmall!.copyWith(color: t.textSecondary),
                        child: subtitle,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            AdaptiveSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
