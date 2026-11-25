import 'package:flutter/material.dart';

import '../l10n/labels.dart';

/// A full-width, high-visibility strip. Always icon + text, never colour alone.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.onDismiss,
    this.dismissLabel,
    this.bold = true,
  }) : assert(onDismiss == null || dismissLabel != null, 'a dismissible banner needs a dismissLabel');

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onDismiss;
  final String? dismissLabel;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Material(
          color: background,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: foreground, fontWeight: bold ? FontWeight.w800 : null, fontSize: 15),
                  ),
                ),
                if (onDismiss != null)
                  Semantics(
                    button: true,
                    label: dismissLabel,
                    child: IconButton(
                      icon: Icon(Icons.close, color: foreground),
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
    final c = Theme.of(context).colorScheme;
    return StatusBanner(
      icon: Icons.science_outlined,
      text: context.l10n.mockBanner,
      background: c.tertiaryContainer,
      foreground: c.onTertiaryContainer,
    );
  }
}

class BypassBanner extends StatelessWidget {
  const BypassBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return StatusBanner(
      icon: Icons.warning_amber_rounded,
      text: context.l10n.bypassBanner,
      background: c.error,
      foreground: c.onError,
    );
  }
}
