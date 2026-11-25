import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/setup_state.dart';

/// Language names are always shown in their own language.
const uiLanguageNames = {'uz': "O'zbekcha", 'ru': 'Русский', 'tr': 'Türkçe', 'en': 'English'};

/// Compact interface-language dropdown for the header. Choosing a language applies and saves it at once.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    return Tooltip(
      message: context.l10n.languagePickerTooltip,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('language-picker'),
          value: current,
          isDense: true,
          icon: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.language, size: 18)),
          items: [for (final e in uiLanguageNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (code) {
            if (code != null) ref.read(setupProvider.notifier).setUiLanguage(code);
          },
        ),
      ),
    );
  }
}
