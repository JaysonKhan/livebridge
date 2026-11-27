import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/sample_player.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/app.dart';

import 'fake_account_client.dart';
import 'fake_bug_report_client.dart';
import 'fake_live_bridge.dart';
import 'fake_sample_player.dart';
import 'fake_voices_client.dart';

/// The English strings, for assertions that must follow the ARB text instead of repeating it.
final en = lookupAppLocalizations(const Locale('en'));

late FakeLiveBridge fake;
late FakeVoicesClient fakeVoices;
late FakeSamplePlayer fakeSamples;
late FakeBugReportClient fakeReports;
late WidgetTester tt;

/// [forceLocale] pins the UI language (English by default so the assertions stay readable); pass null to let
/// the saved setting and the system language decide. [platform] forces the macOS or Windows wording (by default the
/// provider's own choice, which is macOS under `flutter test`). The app starts in the own-gateway mode, as an install
/// with a saved connection does; [onboarding] starts it as a first launch instead. [site] and [opener] replace the
/// fake site and browser; [overrides] adds provider overrides (the waits).
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  FakeLiveBridge? bridge,
  FakeVoicesClient? voices,
  Size size = const Size(1280, 2400),
  Locale? forceLocale = const Locale('en'),
  HostPlatform? platform,
  bool onboarding = false,
  FakeAccountClient? site,
  Future<bool> Function(Uri)? opener,
  List<Override> overrides = const [],
}) async {
  tt = tester;
  fake = bridge ?? FakeLiveBridge();
  if (!onboarding && !fake.settings.containsKey('connectionMode')) {
    fake.settings = {...fake.settings, 'connectionMode': 'gateway'};
  }
  fakeVoices = voices ?? FakeVoicesClient();
  fakeSamples = FakeSamplePlayer();
  fakeReports = FakeBugReportClient();
  // Tall enough that the whole (lazy) setup list is built; the test font is much wider than a real one.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(fake.dispose);
  addTearDown(fakeSamples.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeProvider.overrideWithValue(fake),
        // No test reaches a gateway or the audio plugin.
        voicesClientProvider.overrideWithValue(fakeVoices),
        samplePlayerProvider.overrideWithValue(fakeSamples),
        // Nor the site or a browser.
        accountClientProvider.overrideWithValue(site ?? FakeAccountClient()),
        bugReportClientProvider.overrideWithValue(fakeReports),
        urlOpenerProvider.overrideWithValue(opener ?? (url) async => true),
        if (platform != null) hostPlatformProvider.overrideWithValue(platform),
        ...overrides,
      ],
      child: LiveBridgeApp(forcedLocale: forceLocale),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> push(BridgeEvent e) async {
  fake.push(e);
  await tt.pump();
}

const readyState = StateEvent(state: EngineState.ready, outReady: true, inReady: true);

Finder get startButton => find.byKey(const Key('start-button'));
bool startEnabled() => tt.widget<FilledButton>(startButton).onPressed != null;

Future<void> fillToken() async {
  ProviderScope.containerOf(tt.element(find.byType(MaterialApp)))
      .read(setupProvider.notifier)
      .setAccessToken('secret-token');
  await tt.pump();
}

/// Picks a session language in the `my-language` / `their-language` dropdown by typing part of its name.
Future<void> pickLanguage(String key, String name) async {
  final field = find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));
  await tt.tap(field);
  await tt.pumpAndSettle();
  await tt.enterText(field, name);
  await tt.pumpAndSettle();
  await tt.tap(find.widgetWithText(MenuItemButton, name).last);
  await tt.pumpAndSettle();
}

CaptionEvent cap(Direction d, int id, CaptionKind k, String t) =>
    CaptionEvent(direction: d, turnId: id, kind: k, text: t);

/// A finished turn: final original and final translation.
Future<void> pushFinishedTurn(Direction d, int id, String original, String translation) async {
  await push(cap(d, id, CaptionKind.finalText, original));
  await push(cap(d, id, CaptionKind.translationFinal, translation));
}
