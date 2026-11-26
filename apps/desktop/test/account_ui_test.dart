import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/account_client.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/session_state.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/home_screen.dart';
import 'package:livebridge/ui/onboarding_screen.dart';

import 'fake_account_client.dart';
import 'fake_live_bridge.dart';
import 'harness.dart';

/// Waits that never finish: no refresh timer ticks, nothing is left pending.
Future<void> _hang(Duration _) => Completer<void>().future;

const _packages = [
  Package(code: 'starter', priceCents: 600, units: 300000, minutes: 50),
  Package(code: 'standard', priceCents: 1500, units: 900000, minutes: 150),
  Package(code: 'pro', priceCents: 4000, units: 3000000, minutes: 500),
];

/// The app signed in to an account with [balance] units, in bidirectional mode (6000 units a minute, so 54 000 units
/// last 9 minutes).
Future<(ProviderContainer, FakeAccountClient, List<Uri>)> pumpAccount(
  WidgetTester tester, {
  int balance = 54000,
  String mode = 'account',
  Map<String, Object?> settings = const {},
}) async {
  final site = FakeAccountClient()
    ..meAnswer = FakeAccountClient.info(balance)
    ..packageList = _packages;
  final opened = <Uri>[];
  final bridge = FakeLiveBridge()..settings = {'connectionMode': mode, 'accountRefreshToken': 'refresh-0', ...settings};
  final c = await pumpApp(
    tester,
    bridge: bridge,
    site: site,
    opener: (url) async {
      opened.add(url);
      return true;
    },
    overrides: [delayProvider.overrideWithValue(_hang)],
  );
  c.read(setupProvider.notifier).setMode(SessionMode.bidirectional);
  await tester.pumpAndSettle();
  return (c, site, opened);
}

Finder get chip => find.byKey(const Key('account-chip'));

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

String summary(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('connection-summary'))).data!;

Future<void> pushError(String code, {bool fatal = true}) =>
    push(ErrorEvent(code: code, message: 'raw $code', fatal: fatal));

void main() {
  group('the chip', () {
    testWidgets('account mode: the e-mail initial and the minutes left in the chosen mode', (tester) async {
      final (c, _, _) = await pumpAccount(tester);
      expect(find.descendant(of: chip, matching: find.text('P')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text(en.chipMinutes(9))), findsOneWidget);
      expect(en.chipMinutes(9), '≈ 9 min');
      // Captions cost less a minute, so the same balance lasts longer.
      c.read(setupProvider.notifier).setMode(SessionMode.captions);
      await tester.pump();
      expect(find.descendant(of: chip, matching: find.text(en.chipMinutes(37))), findsOneWidget);
    });

    testWidgets('no minutes are shown while the balance is unknown', (tester) async {
      final site = FakeAccountClient()..meAnswer = const AccountError('network');
      final bridge = FakeLiveBridge()..settings = {'connectionMode': 'account', 'accountRefreshToken': 'refresh-0'};
      await pumpApp(tester, bridge: bridge, site: site, overrides: [delayProvider.overrideWithValue(_hang)]);
      expect(find.textContaining('≈'), findsNothing);
    });

    testWidgets('account menu: Top up, Account page, Sign out', (tester) async {
      await pumpAccount(tester);
      await openMenu(tester);
      expect(find.text(en.topUp), findsOneWidget);
      expect(find.text(en.accountPage), findsOneWidget);
      expect(find.text(en.signOut), findsOneWidget);
      expect(find.text(en.changeConnection), findsNothing);
    });

    testWidgets('Account page opens the site; Sign out returns to the onboarding', (tester) async {
      final (c, site, opened) = await pumpAccount(tester);
      await openMenu(tester);
      await tester.tap(find.text(en.accountPage));
      await tester.pumpAndSettle();
      expect(opened.last.path, '/en/account/');
      await openMenu(tester);
      await tester.tap(find.text(en.signOut));
      await tester.pumpAndSettle();
      expect(site.logouts, hasLength(1));
      expect(c.read(connectionProvider).mode, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('keys mode names the mode and offers Change connection', (tester) async {
      final (c, _, _) = await pumpAccount(
        tester,
        mode: 'keys',
        settings: {'elevenlabsApiKey': 'k', 'geminiApiKey': 'g'},
      );
      expect(find.descendant(of: chip, matching: find.text(en.connectionOwnKeys)), findsOneWidget);
      await openMenu(tester);
      expect(find.text(en.changeConnection), findsOneWidget);
      expect(find.text(en.topUp), findsNothing);
      await tester.tap(find.text(en.changeConnection));
      await tester.pumpAndSettle();
      expect(c.read(connectionProvider).mode, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('gateway mode names the mode and offers Change connection', (tester) async {
      await pumpAccount(tester, mode: 'gateway');
      expect(find.descendant(of: chip, matching: find.text(en.onboardingOwnGateway)), findsOneWidget);
      await openMenu(tester);
      expect(find.text(en.changeConnection), findsOneWidget);
      expect(find.text(en.signOut), findsNothing);
    });
  });

  group('the top-up sheet', () {
    testWidgets('lists the three packages; choosing one opens the checkout and closes the sheet', (tester) async {
      final (_, site, opened) = await pumpAccount(tester);
      await openMenu(tester);
      await tester.tap(find.text(en.topUp));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top-up-sheet')), findsOneWidget);
      for (final p in _packages) {
        expect(find.byKey(Key('package-${p.code}')), findsOneWidget);
        expect(find.text(en.topUpMinutes(p.minutes)), findsOneWidget);
      }
      expect(find.text(r'$6'), findsOneWidget);
      expect(find.text(r'$15'), findsOneWidget);
      expect(find.text(r'$40'), findsOneWidget);
      expect(find.text(en.topUpTaxNote), findsOneWidget);

      await tester.tap(find.byKey(const Key('package-starter')));
      await tester.pumpAndSettle();
      expect(site.checkouts.single.code, 'starter');
      expect(opened.last, site.checkoutAnswer);
      expect(find.byKey(const Key('top-up-sheet')), findsNothing);
    });

    testWidgets('a refused checkout says why and keeps the sheet open', (tester) async {
      final (_, site, opened) = await pumpAccount(tester);
      site.checkoutAnswer = const AccountError('rate_limited');
      await openMenu(tester);
      await tester.tap(find.text(en.topUp));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('package-pro')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('top-up-sheet')), findsOneWidget);
      expect(find.text(en.topUpRateLimited), findsOneWidget);
      expect(opened, isEmpty);
      site.checkoutAnswer = const AccountError('network');
      await tester.tap(find.byKey(const Key('package-pro')));
      await tester.pumpAndSettle();
      expect(find.text(en.topUpNetwork), findsOneWidget);
      site.checkoutAnswer = const AccountError('checkout_unavailable');
      await tester.tap(find.byKey(const Key('package-pro')));
      await tester.pumpAndSettle();
      expect(find.text(en.topUpUnavailable), findsOneWidget);
    });

    testWidgets('without packages it asks again and says so while they are missing', (tester) async {
      final site = FakeAccountClient()
        ..meAnswer = FakeAccountClient.info(54000)
        ..packageList = const AccountError('network');
      final bridge = FakeLiveBridge()..settings = {'connectionMode': 'account', 'accountRefreshToken': 'refresh-0'};
      await pumpApp(tester, bridge: bridge, site: site, overrides: [delayProvider.overrideWithValue(_hang)]);
      final before = site.packagesCalls;
      await openMenu(tester);
      await tester.tap(find.text(en.topUp));
      await tester.pumpAndSettle();
      expect(site.packagesCalls, greaterThan(before));
      expect(find.text(en.topUpNoPackages), findsOneWidget);
      site.packageList = _packages;
      await tester.tap(find.text(en.topUpTryAgain));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('package-starter')), findsOneWidget);
    });
  });

  group('the balance', () {
    testWidgets('an empty balance blocks Start with its reason', (tester) async {
      await pumpAccount(tester, balance: 0);
      expect(startEnabled(), isFalse);
      expect(find.text(en.blockBalanceEmpty), findsOneWidget);
    });

    testWidgets('a balance blocks nothing', (tester) async {
      await pumpAccount(tester);
      expect(startEnabled(), isTrue);
      expect(find.text(en.blockBalanceEmpty), findsNothing);
    });

    testWidgets('coming back to the window refreshes the account', (tester) async {
      final (c, site, _) = await pumpAccount(tester, balance: 0);
      expect(startEnabled(), isFalse);
      final calls = site.meTokens.length;
      site.meAnswer = FakeAccountClient.info(600000);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(site.meTokens.length, calls + 1);
      expect(c.read(connectionProvider).account!.balanceUnits, 600000);
      expect(startEnabled(), isTrue);
    });

    testWidgets('own keys and own gateway do not ask the site', (tester) async {
      final (_, site, _) = await pumpAccount(tester, mode: 'gateway');
      final calls = site.meTokens.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(site.meTokens.length, calls);
    });
  });

  group('the banners', () {
    for (final code in ['balance_empty', 'balance_exhausted']) {
      testWidgets('$code: balance is empty, with a Top up button that opens the sheet', (tester) async {
        await pumpAccount(tester);
        await pushError(code);
        expect(find.text(en.bannerBalanceEmpty), findsOneWidget);
        expect(find.textContaining(code), findsNothing, reason: 'the generic strip is replaced');
        await tester.tap(find.byKey(const Key('banner-top-up')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('top-up-sheet')), findsOneWidget);
      });
    }

    testWidgets('billing_unavailable', (tester) async {
      await pumpAccount(tester);
      await pushError('billing_unavailable');
      expect(find.text(en.bannerBillingUnavailable), findsOneWidget);
      expect(find.byKey(const Key('banner-top-up')), findsNothing);
    });

    testWidgets('idle_timeout: ended after ten minutes, with a Start button that asks for consent', (tester) async {
      await pumpAccount(tester);
      await pushError('idle_timeout');
      expect(find.text(en.bannerIdleTimeout), findsOneWidget);
      await tester.tap(find.byKey(const Key('banner-start')));
      await tester.pumpAndSettle();
      expect(find.text(en.consentCheckbox), findsOneWidget);
    });

    testWidgets('session_replaced', (tester) async {
      await pumpAccount(tester);
      await pushError('session_replaced');
      expect(find.text(en.bannerSessionReplaced), findsOneWidget);
    });

    testWidgets('session_limit', (tester) async {
      await pumpAccount(tester);
      await pushError('session_limit');
      expect(find.text(en.bannerSessionLimit), findsOneWidget);
    });

    testWidgets('a banner can be dismissed', (tester) async {
      await pumpAccount(tester);
      await pushError('session_replaced');
      await tester.tap(find.byTooltip(en.dismissError));
      await tester.pump();
      expect(find.text(en.bannerSessionReplaced), findsNothing);
    });

    testWidgets('other codes keep the generic strip', (tester) async {
      await pumpAccount(tester);
      await pushError('tts_failed', fatal: false);
      expect(find.textContaining('tts_failed'), findsOneWidget);
    });

    testWidgets('invalid_token is not shown in account mode', (tester) async {
      final (c, _, _) = await pumpAccount(tester);
      await pushError('invalid_token');
      expect(c.read(sessionProvider).error?.code, 'invalid_token');
      expect(find.textContaining('invalid_token'), findsNothing);
    });
  });

  group('the connection summary', () {
    testWidgets('account: the e-mail, and Change returns to the onboarding', (tester) async {
      final (c, _, _) = await pumpAccount(tester);
      expect(find.byKey(const Key('gateway-url')), findsNothing);
      expect(find.byKey(const Key('access-token')), findsNothing);
      expect(find.byKey(const Key('translation-model')), findsOneWidget);
      expect(summary(tester), 'person@example.com');
      await tester.tap(find.byKey(const Key('connection-change')));
      await tester.pumpAndSettle();
      expect(c.read(connectionProvider).mode, isNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('keys: Own keys', (tester) async {
      await pumpAccount(tester, mode: 'keys', settings: {'elevenlabsApiKey': 'k', 'geminiApiKey': 'g'});
      expect(summary(tester), en.connectionOwnKeys);
    });

    testWidgets('gateway: the address', (tester) async {
      await pumpAccount(tester, mode: 'gateway', settings: {'gatewayUrl': 'https://gw.example'});
      expect(summary(tester), 'https://gw.example');
    });
  });
}
