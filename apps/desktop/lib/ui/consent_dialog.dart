import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const consentTextEn =
    'I use a live AI interpreter that translates my speech using my own synthesized voice. '
    'May I use it during this call?';
const consentTextRu =
    'Я использую ИИ-переводчик в реальном времени с синтезом моего собственного голоса. Вы не против?';
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
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
    return AlertDialog(
      title: const Text('Tell the other participants first'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Say or paste this sentence into the call chat before you start.'),
              const SizedBox(height: 12),
              _block('English', consentTextEn, 'Copy English'),
              _block('Русский', consentTextRu, 'Copy Russian'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: const Text(consentCheckboxLabel),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _agreed ? () => Navigator.of(context).pop(true) : null, child: const Text('Confirm')),
      ],
    );
  }
}
