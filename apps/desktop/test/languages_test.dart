import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/languages.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/l10n/labels.dart';

void main() {
  test('the language list is the gateway protocol\'s table', () {
    // `flutter test` runs in apps/desktop; the fixture is what the gateway's own table is tested against.
    final fixture = jsonDecode(File('../../packages/protocol/fixtures/languages.json').readAsStringSync()) as Map;
    expect(kLanguages, fixture);
    expect(kLanguages, hasLength(90));
    expect(kLanguages.keys, containsAll([kDefaultMyLang, kDefaultTargetLang, 'ru', 'tr']));
  });

  test('language names: own wording, then the system name, then the English name', () {
    final uz = lookupAppLocalizations(const Locale('uz'));
    expect(uz.languageName('uz'), "O'zbekcha");
    expect(uz.languageName('tr', {'tr': 'turk'}), 'Turkcha');
    expect(uz.languageName('de', {'de': 'Nemischa'}), 'Nemischa');
    expect(uz.languageName('de'), 'German');
    expect(uz.languagePair('uz', 'en'), "O'zbekcha ↔ Inglizcha");
    expect(lookupAppLocalizations(const Locale('en')).languagePair('tr', 'de', {'de': 'German'}), 'Turkish ↔ German');
  });
}
