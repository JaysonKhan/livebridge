import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/ui/app.dart';
import 'package:livebridge/ui/home_screen.dart';

import 'fake_live_bridge.dart';

/// The English strings, for assertions that must follow the ARB text instead of repeating it.
final en = lookupAppLocalizations(const Locale('en'));

late FakeLiveBridge fake;
late WidgetTester tt;

/// [forceLocale] pins the UI language (English by default so the assertions stay readable); pass null to let
/// the saved setting and the system language decide.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  FakeLiveBridge? bridge,
  Size size = const Size(1280, 2400),
  Locale? forceLocale = const Locale('en'),
}) async {
  tt = tester;
  fake = bridge ?? FakeLiveBridge();
  // Tall enough that the whole (lazy) setup list is built; the test font is much wider than a real one.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(fake.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(fake)],
      child: LiveBridgeApp(forcedLocale: forceLocale),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
}

Future<void> push(BridgeEvent e) async {
  fake.push(e);
  await tt.pump();
}

const readyState = StateEvent(state: EngineState.ready, outReady: true, inReady: true);

Finder get startButton => find.byKey(const Key('start-button'));
bool startEnabled() => tt.widget<FilledButton>(startButton).onPressed != null;

Future<void> fillToken() async {
  await tt.enterText(find.byKey(const Key('access-token')), 'secret-token');
  await tt.pump();
}

CaptionEvent cap(Direction d, int id, CaptionKind k, String t) =>
    CaptionEvent(direction: d, turnId: id, kind: k, text: t);

/// A finished turn: final original and final translation.
Future<void> pushFinishedTurn(Direction d, int id, String original, String translation) async {
  await push(cap(d, id, CaptionKind.finalText, original));
  await push(cap(d, id, CaptionKind.translationFinal, translation));
}
