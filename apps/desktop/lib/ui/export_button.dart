import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/export_document.dart';
import '../state/providers.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';

/// Saves the conversation as Markdown. The first export in an app run asks the owner to confirm that the
/// other participant agreed, because the file holds their words.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key});

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _confirmed = false;

  Future<bool> _confirm() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.exportConsentTitle),
        content: Text(l.exportConsentBody),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l.exportConsentConfirm)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _export() async {
    if (!_confirmed) {
      if (!await _confirm() || !mounted) return;
      _confirmed = true;
    }
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(sessionProvider);
    final setup = ref.read(setupProvider);
    final now = DateTime.now();
    final content = buildConversationMarkdown(
      l: l,
      exportedAt: now,
      languages: l.languagePair(
        setup.myLang,
        setup.targetLang,
        ref.read(languageNamesProvider(l.localeName)).value ?? const {},
      ),
      mode: setup.mode,
      outTurns: session.outTurns,
      inTurns: session.inTurns,
    );
    try {
      final path = await ref.read(bridgeProvider).saveTextFile(suggestedName: exportFileName(now), content: content);
      if (path != null) messenger.showSnackBar(SnackBar(content: Text(l.exportSaved(path))));
    } on Exception catch (e) {
      if (mounted) ref.read(sessionProvider.notifier).reportException(e, 'saveTextFile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTurns = ref.watch(sessionProvider.select((s) => s.outTurns.isNotEmpty || s.inTurns.isNotEmpty));
    return OutlinedButton.icon(
      key: const Key('export-button'),
      onPressed: hasTurns ? _export : null,
      icon: const Icon(Icons.ios_share),
      label: Text(context.l10n.exportConversation),
    );
  }
}
