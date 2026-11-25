import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys whose value is intentionally the same in every language (a product name, a technical abbreviation).
const _identicalOk = {'routingUpworkTitle', 'processPid', 'analyticsColP50', 'analyticsColP95'};

Map<String, String> _load(String lang) {
  final raw = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

Set<String> _placeholders(String message) => RegExp(r'\{(\w+)\}').allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final en = _load('en');

  for (final lang in ['uz', 'ru', 'tr']) {
    group('app_$lang.arb', () {
      final other = _load(lang);

      test('has every key of app_en.arb and no stray ones', () {
        expect(en.keys.toSet().difference(other.keys.toSet()), isEmpty, reason: 'missing in $lang');
        expect(other.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'not in the English template');
      });

      test('is really translated', () {
        final same = [
          for (final k in en.keys)
            if (other[k] == en[k] && !_identicalOk.contains(k)) k,
        ];
        expect(same, isEmpty, reason: 'identical to English (translate, or allow-list a true technical term)');
      });

      test('keeps the same placeholders as English', () {
        for (final k in en.keys) {
          expect(_placeholders(other[k] ?? ''), _placeholders(en[k]!), reason: 'placeholders differ in $k');
        }
      });

      test('has no empty values', () {
        expect([
          for (final e in other.entries)
            if (e.value.trim().isEmpty) e.key,
        ], isEmpty);
      });
    });
  }

  test('Uzbek uses the ASCII apostrophe, never a typographic one', () {
    final bad = [
      for (final e in _load('uz').entries)
        if (RegExp('[‘’ʻʼ]').hasMatch(e.value)) e.key,
    ];
    expect(bad, isEmpty);
  });
}
