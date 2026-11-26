import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import 'theme/tokens.dart';

enum StatusSeverity { success, caution, critical }

extension StatusSeverityColors on LiveBridgeTokens {
  StatusColors status(StatusSeverity severity) => switch (severity) {
    StatusSeverity.success => success,
    StatusSeverity.caution => caution,
    StatusSeverity.critical => critical,
  };
}

/// A high-visibility status strip under the header: an InfoBar on Windows (radius 4), a rounded inline banner on
/// macOS. Always icon + text, never colour alone; the icon takes the severity colour, the text stays primary.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.severity,
    this.onDismiss,
    this.dismissLabel,
    this.bold = true,
  }) : assert(onDismiss == null || dismissLabel != null, 'a dismissible banner needs a dismissLabel');

  final IconData icon;
  final String text;
  final StatusSeverity severity;
  final VoidCallback? onDismiss;
  final String? dismissLabel;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = t.status(severity);
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.fromLTRB(16, 6, onDismiss == null ? 16 : 6, 6),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(t.isWindows ? t.controlRadius : t.cardRadius),
              border: Border.all(color: t.cardStroke),
            ),
            child: Row(
              children: [
                Icon(icon, color: colors.foreground, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: t.textPrimary, fontWeight: bold ? FontWeight.w600 : null),
                  ),
                ),
                if (onDismiss != null)
                  Semantics(
                    button: true,
                    label: dismissLabel,
                    child: IconButton(
                      icon: Icon(Icons.close, color: t.textPrimary),
                      tooltip: dismissLabel,
                      onPressed: onDismiss,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MockBanner extends StatelessWidget {
  const MockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBanner(icon: Icons.science_outlined, text: context.l10n.mockBanner, severity: StatusSeverity.caution);
  }
}

class BypassBanner extends StatelessWidget {
  const BypassBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBanner(
      icon: Icons.warning_amber_rounded,
      text: context.l10n.bypassBanner,
      severity: StatusSeverity.critical,
    );
  }
}
