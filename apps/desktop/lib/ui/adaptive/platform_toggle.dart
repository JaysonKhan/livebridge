import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// An on/off option with a visible label, in place of a Material FilterChip. Windows: a toggle button (a standard
/// button when off; accent fill and a check mark when on, so the state is not shown by colour alone). macOS: a check
/// box with its label.
class PlatformToggle extends StatelessWidget {
  const PlatformToggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (t.isWindows) {
      return Semantics(
        toggled: value,
        child: OutlinedButton(
          // The accent button style when on; the same widget either way, so keyboard focus survives the toggle.
          style: value ? FilledButtonTheme.of(context).style : null,
          onPressed: () => onChanged(!value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value) ...[const Icon(Icons.check, size: 16), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );
    }
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Padding(padding: const EdgeInsets.only(right: 4), child: Text(label)),
          ),
        ],
      ),
    );
  }
}
