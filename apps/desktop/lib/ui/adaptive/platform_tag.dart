import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A compact, read-only status tag (icon + text, never colour alone). Windows: a radius-4 pill on the control fill
/// with the control stroke. macOS: a capsule with a separator-coloured border. [status] tints it (e.g. Capturing).
class PlatformTag extends StatelessWidget {
  const PlatformTag({super.key, required this.icon, required this.label, this.status, this.bold = false});

  final IconData icon;
  final String label;
  final StatusColors? status;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = this.status;
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: t.textPrimary, fontWeight: bold ? FontWeight.w600 : null);
    return Container(
      constraints: BoxConstraints(minHeight: t.isWindows ? 24 : 20),
      padding: EdgeInsets.symmetric(horizontal: t.isWindows ? 8 : 9, vertical: 2),
      decoration: BoxDecoration(
        color: status?.background ?? (t.isWindows ? t.controlFill : Colors.transparent),
        border: Border.all(
          color: status?.foreground.withValues(alpha: 0.4) ?? (t.isWindows ? t.controlStroke : t.divider),
        ),
        borderRadius: BorderRadius.circular(t.tagRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: t.isWindows ? 14 : 13, color: status?.foreground ?? t.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
