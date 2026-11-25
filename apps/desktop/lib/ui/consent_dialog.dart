import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';

/// The two sentences the owner reads to the other participant. They are never translated.
/// "A synthesized voice", not "my own voice": the configured voice is not necessarily the speaker's.
const consentTextEn =
    'I use a live AI interpreter that translates my speech and speaks it in a synthesized voice. '
    'May I use it during this call?';
const consentTextRu =
    'Я использую ИИ-переводчик в реальном времени: он озвучивает мой перевод синтезированным голосом. Вы не против?';
const consentCheckboxLabel = 'The other participants have been informed and agreed';

/// Returns true only when the owner ticked the checkbox and pressed Confirm.
Future<bool> showConsentDialog(BuildContext context) async {
  final result = await showDialog<bool>(context: context, builder: (_) => const _ConsentDialog());
  return result ?? false;
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog();

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool _agreed = false;

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.copied)));
  }

  Widget _block(String language, String text, String copyLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(language, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(text),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _copy(text), icon: const Icon(Icons.copy), label: Text(copyLabel)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.consentTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.consentIntro),
              const SizedBox(height: 12),
              _block('English', consentTextEn, l.consentCopyEnglish),
              _block('Русский', consentTextRu, l.consentCopyRussian),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: Text(l.consentCheckbox),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(onPressed: _agreed ? () => Navigator.of(context).pop(true) : null, child: Text(l.confirm)),
      ],
    );
  }
}
