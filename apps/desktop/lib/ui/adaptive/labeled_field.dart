import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A field with its label above it, as Fluent text box headers and macOS form labels are (a Material floating label
/// does not fit a 32 px or 24 px box). The label stays the field's accessible name.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.mergeSemantics = true});

  final String label;
  final Widget child;

  /// True merges the label into the field's node. False (for a field that holds more than one control, such as an
  /// editable drop-down with its menu button) puts the field in a group named by the label instead.
  final bool mergeSemantics;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Text(label, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: t.textPrimary));
    if (mergeSemantics) {
      return MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            SizedBox(height: t.labelGap),
            child,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: text),
        SizedBox(height: t.labelGap),
        Semantics(container: true, label: label, child: child),
      ],
    );
  }
}
