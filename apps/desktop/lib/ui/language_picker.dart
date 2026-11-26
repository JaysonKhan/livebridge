import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/setup_state.dart';
import 'theme/tokens.dart';

/// Language names are always shown in their own language.
const uiLanguageNames = {'uz': "O'zbekcha", 'ru': 'Русский', 'tr': 'Türkçe', 'en': 'English'};

/// Compact interface-language dropdown for the header. Choosing a language applies and saves it at once.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    final t = context.tokens;
    return Tooltip(
      message: context.l10n.languagePickerTooltip,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('language-picker'),
          value: current,
          isDense: true,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: t.textPrimary),
          dropdownColor: t.flyout,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          icon: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.language, size: 16, color: t.textSecondary),
          ),
          items: [for (final e in uiLanguageNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (code) {
            if (code != null) ref.read(setupProvider.notifier).setUiLanguage(code);
          },
        ),
      ),
    );
  }
}
