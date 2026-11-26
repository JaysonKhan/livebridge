import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/account_client.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/ui/google_button.dart';
import 'package:livebridge/ui/home_screen.dart';
import 'package:livebridge/ui/onboarding_screen.dart';

import 'fake_account_client.dart';
import 'fake_live_bridge.dart';
import 'harness.dart';

/// Waits that never finish: nothing polls, nothing is left pending for the test to clean up.
Future<void> _hang(Duration _) => Completer<void>().future;

/// Waits that finish at once: the sign-in polls straight away.
Future<void> _now(Duration _) async {}

Future<ProviderContainer> pumpOnboarding(
  WidgetTester tester, {
  FakeAccountClient? site,
  Future<void> Function(Duration) delay = _hang,
  FakeLiveBridge? bridge,
}) {
  return pumpApp(
    tester,
    bridge: bridge,
    onboarding: true,
    site: site,
    overrides: [delayProvider.overrideWithValue(delay)],
  );
}

Finder get googleButton => find.byType(GoogleButton);
Finder get saveKeysButton => find.byKey(const Key('keys-save'));
Finder get saveGatewayButton => find.byKey(const Key('gateway-save'));

bool enabled(Finder f) => tt.widget<FilledButton>(f).onPressed != null;

Future<void> openKeys() async {
  await tt.tap(find.text(en.onboardingOwnKeys));
  await tt.pumpAndSettle();
}

void main() {
  testWidgets('a first launch shows the onboarding, not the main screen', (tester) async {
    await pumpOnboarding(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text(en.onboardingTitle), findsOneWidget);
    expect(find.text(en.onboardingSubtitle), findsOneWidget);
    expect(find.text(en.signInWithGoogle), findsOneWidget);
    expect(find.byKey(const Key('language-picker')), findsOneWidget);
    // Only one thing to do at first: the keys stay folded.
    expect(find.text(en.onboardingOwnKeys), findsOneWidget);
    expect(find.byKey(const Key('elevenlabs-key')), findsNothing);
    expect(find.text(en.onboardingOwnGateway), findsNothing);
  });

  testWidgets('nothing is shown until the saved choice is read', (tester) async {
    final gate = Completer<void>();
    final bridge = FakeLiveBridge();
    await tester.pumpWidget(const SizedBox()); // Reset.
    final c = await pumpApp(
      tester,
      bridge: bridge,
      onboarding: true,
      overrides: [
        savedSettingsProvider.overrideWith((ref) async {
          await gate.future;
          return <String, Object?>{};
        }),
      ],
    );
    expect(c.read(connectionProvider).loaded, isFalse);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('a saved static token goes straight to the main screen', (tester) async {
    final bridge = FakeLiveBridge()..settings = {'accessToken': 'saved-token'};
    await pumpOnboarding(tester, bridge: bridge);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('Google shows the code from the site and the browser buttons', (tester) async {
    final site = FakeAccountClient();
    final opened = <Uri>[];
    final c = await pumpApp(
      tester,
      onboarding: true,
      site: site,
      opener: (url) async {
        opened.add(url);
        return true;
      },
      overrides: [delayProvider.overrideWithValue(_hang)],
    );
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(c.read(connectionProvider).signIn, isA<SignInWaiting>());
    expect(find.text(en.signInWaitingTitle), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(googleButton, findsNothing);
    expect(opened, hasLength(1));

    await tester.tap(find.text(en.signInOpenAgain));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));

    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(c.read(connectionProvider).signIn, isA<SignInIdle>());
    expect(googleButton, findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsNothing);
  });

  testWidgets('an approved code enters the main screen in account mode', (tester) async {
    final site = FakeAccountClient();
    site.polls.add(
      DeviceGranted(
        TokenPair(accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now().add(const Duration(minutes: 15))),
      ),
    );
    final c = await pumpOnboarding(tester, site: site, delay: _now);
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(c.read(connectionProvider).mode, ConnectionMode.account);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  for (final (poll, reason, sentence) in [
    (const DeviceExpired(), 'expired', () => en.signInExpired),
    (const DeviceDenied(), 'denied', () => en.signInDenied),
  ]) {
    testWidgets('$reason: back to the button with a sentence above it', (tester) async {
      final site = FakeAccountClient()..polls.add(poll);
      final c = await pumpOnboarding(tester, site: site, delay: _now);
      await tester.tap(googleButton);
      await tester.pumpAndSettle();
      final state = c.read(connectionProvider).signIn;
      expect(state, isA<SignInFailed>());
      expect((state as SignInFailed).reason, reason);
      expect(find.text(sentence()), findsOneWidget);
      expect(googleButton, findsOneWidget);
      expect(tester.getBottomLeft(find.text(sentence())).dy, lessThan(tester.getTopLeft(googleButton).dy));
    });
  }

  testWidgets('the site being unreachable and rate limits have their own sentences', (tester) async {
    final site = FakeAccountClient()..start = const AccountError('network');
    await pumpOnboarding(tester, site: site);
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(find.text(en.signInNetwork), findsOneWidget);

    site.start = const AccountError('rate_limited');
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(find.text(en.signInRateLimited), findsOneWidget);
    expect(find.text(en.signInNetwork), findsNothing);
  });

  testWidgets('a signed-out notice is worded above the button', (tester) async {
    final bridge = FakeLiveBridge()..settings = {'connectionMode': 'account', 'accountRefreshToken': 'old-refresh'};
    final site = FakeAccountClient()..refreshError = const AccountSignedOut();
    final c = await pumpOnboarding(tester, site: site, bridge: bridge);
    expect(c.read(connectionProvider).notice, 'signed_out');
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(en.noticeSignedOut), findsOneWidget);
    // Starting a new sign-in clears it.
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(find.text(en.noticeSignedOut), findsNothing);
  });

  group('Back after Change', () {
    Finder back() => find.byKey(const Key('onboarding-back'));

    testWidgets('a first launch has no Back', (tester) async {
      await pumpOnboarding(tester);
      expect(back(), findsNothing);
    });

    for (final (mode, settings) in [
      ('gateway', {'connectionMode': 'gateway', 'accessToken': 'static-token', 'gatewayUrl': 'https://gw.example'}),
      ('keys', {'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key', 'geminiApiKey': 'gm-key'}),
      ('account', {'connectionMode': 'account', 'accountRefreshToken': 'refresh-0'}),
    ]) {
      testWidgets('$mode: Back returns to the main screen in the same mode, nothing typed again', (tester) async {
        final bridge = FakeLiveBridge()..settings = {...settings};
        final c = await pumpOnboarding(tester, bridge: bridge);
        final before = c.read(connectionProvider).mode;
        expect(before?.name, mode);
        await tester.tap(find.byKey(const Key('connection-change')));
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.text(en.onboardingBack), findsOneWidget);
        await tester.tap(back());
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(c.read(connectionProvider).mode, before);
        expect(bridge.settings['connectionMode'], mode);
      });
    }

    testWidgets('saved keys are filled in, hidden, after Change', (tester) async {
      final bridge = FakeLiveBridge()
        ..settings = {'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key', 'geminiApiKey': 'gm-key'};
      await pumpOnboarding(tester, bridge: bridge);
      await tester.tap(find.byKey(const Key('connection-change')));
      await tester.pumpAndSettle();
      await openKeys();
      for (final (key, value) in [('elevenlabs-key', 'el-key'), ('gemini-key', 'gm-key')]) {
        final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
        );
        expect(field.controller!.text, value);
        expect(field.obscureText, isTrue);
      }
      expect(enabled(saveKeysButton), isTrue);
    });
  });

  group('own keys', () {
    testWidgets('open on request; Save and continue needs both keys', (tester) async {
      await pumpOnboarding(tester);
      await openKeys();
      expect(find.byKey(const Key('elevenlabs-key')), findsOneWidget);
      expect(find.byKey(const Key('gemini-key')), findsOneWidget);
      expect(find.text(en.onboardingOwnGateway), findsOneWidget);
      expect(enabled(saveKeysButton), isFalse);

      await tester.enterText(find.byKey(const Key('elevenlabs-key')), 'el-key');
      await tester.pump();
      expect(enabled(saveKeysButton), isFalse);
      await tester.enterText(find.byKey(const Key('gemini-key')), '   ');
      await tester.pump();
      expect(enabled(saveKeysButton), isFalse, reason: 'blank is empty');
      await tester.enterText(find.byKey(const Key('gemini-key')), 'gm-key');
      await tester.pump();
      expect(enabled(saveKeysButton), isTrue);
    });

    testWidgets('the keys are hidden until the eye is pressed', (tester) async {
      await pumpOnboarding(tester);
      await openKeys();
      bool obscured() => tester
          .widget<TextField>(
            find.descendant(of: find.byKey(const Key('elevenlabs-key')), matching: find.byType(TextField)),
          )
          .obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.descendant(of: find.byKey(const Key('elevenlabs-key')), matching: find.byType(IconButton)));
      await tester.pump();
      expect(obscured(), isFalse);
      await tester.tap(find.descendant(of: find.byKey(const Key('elevenlabs-key')), matching: find.byType(IconButton)));
      await tester.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('saving enters the main screen in keys mode', (tester) async {
      final bridge = FakeLiveBridge();
      final c = await pumpOnboarding(tester, bridge: bridge);
      await openKeys();
      await tester.enterText(find.byKey(const Key('elevenlabs-key')), ' el-key ');
      await tester.enterText(find.byKey(const Key('gemini-key')), 'gm-key');
      await tester.pump();
      await tester.tap(saveKeysButton);
      await tester.pumpAndSettle();
      expect(c.read(connectionProvider).mode, ConnectionMode.keys);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(bridge.savedPrefs.last['connectionMode'], 'keys');
      expect(bridge.savedPrefs.last['elevenlabsApiKey'], 'el-key');
    });

    testWidgets('a failed save stays on the screen with a sentence', (tester) async {
      final bridge = FakeLiveBridge()..savePreferencesError = PlatformException(code: 'keychain', message: 'denied');
      final c = await pumpOnboarding(tester, bridge: bridge);
      await openKeys();
      await tester.enterText(find.byKey(const Key('elevenlabs-key')), 'el-key');
      await tester.enterText(find.byKey(const Key('gemini-key')), 'gm-key');
      await tester.pump();
      await tester.tap(saveKeysButton);
      await tester.pumpAndSettle();
      expect(c.read(connectionProvider).mode, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text(en.onboardingSaveFailed), findsOneWidget);
      // The typed keys are still there to try again.
      expect(find.text('el-key'), findsOneWidget);
    });
  });

  group('own gateway', () {
    Future<void> openGateway() async {
      await openKeys();
      await tt.tap(find.text(en.onboardingOwnGateway));
      await tt.pumpAndSettle();
    }

    testWidgets('starts with the current address; both fields are needed', (tester) async {
      await pumpOnboarding(tester);
      await openGateway();
      expect(find.byKey(const Key('onboarding-gateway-url')), findsOneWidget);
      final url = tester.widget<TextField>(find.byKey(const Key('onboarding-gateway-url')));
      expect(url.controller!.text, 'http://127.0.0.1:8201');
      expect(enabled(saveGatewayButton), isFalse);
      await tester.enterText(find.byKey(const Key('onboarding-gateway-token')), 'static-token');
      await tester.pump();
      expect(enabled(saveGatewayButton), isTrue);
      await tester.enterText(find.byKey(const Key('onboarding-gateway-url')), '  ');
      await tester.pump();
      expect(enabled(saveGatewayButton), isFalse);
    });

    testWidgets('saving enters the main screen in gateway mode', (tester) async {
      final bridge = FakeLiveBridge();
      final c = await pumpOnboarding(tester, bridge: bridge);
      await openGateway();
      await tester.enterText(find.byKey(const Key('onboarding-gateway-url')), 'https://gw.example');
      await tester.enterText(find.byKey(const Key('onboarding-gateway-token')), 'static-token');
      await tester.pump();
      await tester.tap(saveGatewayButton);
      await tester.pumpAndSettle();
      expect(c.read(connectionProvider).mode, ConnectionMode.gateway);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(bridge.savedPrefs.last['gatewayUrl'], 'https://gw.example');
    });

    testWidgets('after Change, a saved static token is pre-filled and can be saved with a new address', (tester) async {
      final bridge = FakeLiveBridge()..settings = {'connectionMode': 'gateway', 'accessToken': 'static-token'};
      final c = await pumpApp(tester, bridge: bridge, onboarding: true);
      expect(c.read(connectionProvider).mode, ConnectionMode.gateway);
      await tester.tap(find.byKey(const Key('connection-change')));
      await tester.pumpAndSettle();
      await openGateway();
      final token = tester.widget<TextField>(
        find.descendant(of: find.byKey(const Key('onboarding-gateway-token')), matching: find.byType(TextField)),
      );
      expect(token.controller!.text, 'static-token');
      expect(token.obscureText, isTrue);
      expect(enabled(saveGatewayButton), isTrue);
      await tester.enterText(find.byKey(const Key('onboarding-gateway-url')), 'https://new.example');
      await tester.pump();
      await tester.tap(saveGatewayButton);
      await tester.pumpAndSettle();
      expect(bridge.savedPrefs.last['gatewayUrl'], 'https://new.example');
      expect(bridge.savedPrefs.last['accessToken'], 'static-token');
    });
  });
}
