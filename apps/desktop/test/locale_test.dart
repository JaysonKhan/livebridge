import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

Finder startLabel(String text) => find.descendant(of: startButton, matching: find.text(text));

Future<void> pickLanguage(WidgetTester tester, String endonym) async {
  await tester.tap(find.byKey(const Key('language-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(endonym).last);
  await tester.pumpAndSettle();
}

void main() {
  group('each language renders', () {
    const expected = {
      'en': ('Start session', 'You → them'),
      'uz': ('Sessiyani boshlash', 'Siz → suhbatdosh'),
      'ru': ('Начать сессию', 'Вы → собеседник'),
      'tr': ('Oturumu başlat', 'Siz → karşı taraf'),
    };
    for (final MapEntry(key: code, value: (start, lane)) in expected.entries) {
      testWidgets(code, (tester) async {
        await pumpApp(tester, forceLocale: Locale(code));
        expect(startLabel(start), findsOneWidget);
        expect(find.text(lane), findsOneWidget);
        expect(Localizations.localeOf(tester.element(startButton)).languageCode, code);
      });
    }
  });

  testWidgets('the header picker lists the four endonyms', (tester) async {
    await pumpApp(tester, forceLocale: null);
    await tester.tap(find.byKey(const Key('language-picker')));
    await tester.pumpAndSettle();
    for (final name in ["O'zbekcha", 'Русский', 'Türkçe', 'English']) {
      expect(find.text(name), findsWidgets);
    }
  });

  testWidgets('picking a language switches the UI at once and saves uiLanguage', (tester) async {
    await pumpApp(tester, forceLocale: null);
    expect(startLabel('Start session'), findsOneWidget);
    await pickLanguage(tester, 'Русский');
    expect(startLabel('Начать сессию'), findsOneWidget);
    expect(startLabel('Start session'), findsNothing);
    expect(fake.savedPrefs.last, {'uiLanguage': 'ru'});

    await pickLanguage(tester, "O'zbekcha");
    expect(startLabel('Sessiyani boshlash'), findsOneWidget);
    expect(fake.savedPrefs.last, {'uiLanguage': 'uz'});
  });

  testWidgets('a saved uiLanguage is applied at startup', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'uiLanguage': 'tr'}, forceLocale: null);
    expect(startLabel('Oturumu başlat'), findsOneWidget);
  });

  testWidgets('a saved uiLanguage wins over the system language', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru', 'RU')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'uiLanguage': 'uz'}, forceLocale: null);
    expect(startLabel('Sessiyani boshlash'), findsOneWidget);
  });

  testWidgets('an unknown saved uiLanguage is ignored', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'uiLanguage': 'xx'}, forceLocale: null);
    expect(startLabel('Start session'), findsOneWidget);
  });

  testWidgets('a supported system language is followed when nothing is saved', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('tr', 'TR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester, forceLocale: null);
    expect(startLabel('Oturumu başlat'), findsOneWidget);
  });

  testWidgets('an unsupported system language falls back to English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester, forceLocale: null);
    expect(startLabel('Start session'), findsOneWidget);
    expect(Localizations.localeOf(tester.element(startButton)).languageCode, 'en');
  });

  group('error strip', () {
    testWidgets('a known code shows its localized message and keeps the code', (tester) async {
      await pumpApp(tester, forceLocale: const Locale('uz'));
      await push(const ErrorEvent(code: 'tts_failed', message: 'TTS provider returned 500'));
      expect(find.text("tts_failed: Gapni ovozga aylantirib bo'lmadi."), findsOneWidget);
      expect(find.textContaining('TTS provider'), findsNothing);
    });

    testWidgets('an unknown code falls back to the raw message', (tester) async {
      await pumpApp(tester, forceLocale: const Locale('ru'));
      await push(const ErrorEvent(code: 'mystery', message: 'Something odd'));
      expect(find.text('mystery: Something odd'), findsOneWidget);
    });

    testWidgets('a fatal error adds the localized session-ended note', (tester) async {
      await pumpApp(tester, forceLocale: const Locale('tr'));
      await push(const ErrorEvent(code: 'session_expired', message: 'expired', fatal: true));
      expect(find.textContaining('session_expired: Oturumun süresi doldu.'), findsOneWidget);
      expect(find.textContaining('(oturum sona erdi)'), findsOneWidget);
    });
  });

  testWidgets('caption preferences are saved and restored', (tester) async {
    final bridge = FakeLiveBridge();
    final c = await pumpApp(tester, bridge: bridge);
    await tester.tap(find.byTooltip(en.captionsLarger));
    await tester.tap(find.text(en.showOriginal));
    await tester.tap(find.text(en.showTranslated));
    await tester.pump();
    expect(bridge.savedPrefs, [
      {'captionFontSize': 20.0},
      {'showOriginal': false},
      {'showTranslated': false},
    ]);
    expect(c, isNotNull);

    final restored = FakeLiveBridge()
      ..settings = {'captionFontSize': 26.0, 'showOriginal': false, 'showTranslated': true};
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, bridge: restored);
    expect(find.text('Size 26'), findsOneWidget);
  });
}
