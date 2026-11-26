import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/setup_state.dart';
import 'adaptive/platform_dropdown.dart';

/// Language names are always shown in their own language.
const uiLanguageNames = {'uz': "O'zbekcha", 'ru': 'Русский', 'tr': 'Türkçe', 'en': 'English'};

/// The interface-language picker in the header: a compact pop-up button showing the current language. Choosing a
/// language applies and saves it at once.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    return Tooltip(
      message: context.l10n.languagePickerTooltip,
      child: PlatformDropdown<String>(
        key: const Key('language-picker'),
        entries: [for (final e in uiLanguageNames.entries) (value: e.key, label: e.value)],
        value: current,
        expand: false,
        onChanged: ref.read(setupProvider.notifier).setUiLanguage,
      ),
    );
  }
}
