// End-to-end smoke test of the real app: real Flutter UI, real method/event channels, real Swift audio engine and
// microphone, talking to a gateway running FAKE providers (placeholder text). It proves the wiring, not translation.
//
// Run (from the repo root, gateway first):
//   PROVIDER_MODE=fake FAKE_STT_SPEECH_RMS=1 GATEWAY_ACCESS_TOKEN=<token> node services/gateway/src/main.ts
//   cd apps/desktop && LIVEBRIDGE_EPHEMERAL_SETTINGS=1 flutter test integration_test/session_test.dart -d macos \
//       --dart-define=LB_TOKEN=<token>
// LIVEBRIDGE_EPHEMERAL_SETTINGS keeps the test out of your Keychain and preferences.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livebridge/main.dart' as app;
import 'package:livebridge/ui/banners.dart';
import 'package:livebridge/ui/consent_dialog.dart';

const gatewayUrl = String.fromEnvironment('LB_GATEWAY', defaultValue: 'http://127.0.0.1:8201');
const accessToken = String.fromEnvironment('LB_TOKEN');

Future<void> pumpUntil(WidgetTester tester, Finder finder, String what, {int seconds = 10}) async {
  for (var i = 0; i < seconds * 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $what');
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captions-only session: real devices, real mic, gateway with fake providers, panic stop', (tester) async {
    expect(accessToken, isNotEmpty, reason: 'pass --dart-define=LB_TOKEN=<gateway access token>');
    app.main();

    // Devices come from the Core Audio HAL through the native bridge; a Mac always has a built-in microphone.
    await pumpUntil(tester, find.byKey(const Key('start-button')), 'the home screen');
    await pumpUntil(
      tester,
      find.descendant(of: find.byKey(const Key('mic-dropdown')), matching: find.textContaining('MacBook')),
      'the built-in microphone in the device list',
    );
    // This machine has no BlackHole driver, and the app says so instead of pretending.
    expect(find.byKey(const Key('blackhole-missing')), findsOneWidget);

    await tapVisible(tester, find.text('Captions only'));
    // The setup panel is a lazily built list: scroll the gateway section into existence.
    await tester.scrollUntilVisible(
      find.byKey(const Key('access-token')),
      300,
      scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const Key('gateway-url')), gatewayUrl);
    await tester.enterText(find.byKey(const Key('access-token')), accessToken);
    await tester.pump(const Duration(milliseconds: 200));

    // Start is gated on the consent dialog.
    await tapVisible(tester, find.byKey(const Key('start-button')));
    await pumpUntil(tester, find.text(consentCheckboxLabel), 'the consent dialog');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm')).onPressed, isNull);
    await tester.tap(find.text(consentCheckboxLabel));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));

    // Readiness is reported by the gateway, and the mock banner makes clear this is not a real translation.
    await pumpUntil(tester, find.text('OUT: ready'), 'OUT: ready');
    expect(find.text(mockBannerText), findsOneWidget);
    expect(find.text('IN: not ready'), findsOneWidget);

    // Hold push-to-talk for 1.5 s: real microphone audio goes to the gateway only during this window.
    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('ptt-button'))));
    await tester.pump(const Duration(milliseconds: 1500));
    await hold.up();

    final lane = find.byKey(const Key('lane-out'));
    await pumpUntil(
      tester,
      find.descendant(of: lane, matching: find.textContaining('(uz→en) fake transcript')),
      'the caption and placeholder translation of the spoken turn',
    );
    expect(find.descendant(of: find.byKey(const Key('lane-in')), matching: find.textContaining('fake')), findsNothing);

    // Panic stop returns to idle; setup is usable again.
    await tester.tap(find.byKey(const Key('panic-button')));
    await pumpUntil(tester, find.byKey(const Key('start-button')), 'idle after panic');
    expect(find.text('OUT: ready'), findsNothing);
  });
}
