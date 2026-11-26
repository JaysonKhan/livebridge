import 'dart:async';

import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/account_client.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/route_check.dart';
import 'package:livebridge/state/session_state.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_account_client.dart';
import 'fake_live_bridge.dart';

final en = lookupAppLocalizations(const Locale('en'));

late FakeLiveBridge bridge;
late FakeAccountClient site;
late FakeDelays delays;
late List<Uri> opened;
late DateTime now;

/// Lets every pending microtask and zero-length timer run.
Future<void> flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Every wait the app asks for, held until the test lets it finish.
class FakeDelays {
  final List<Duration> asked = [];
  final List<(Duration, Completer<void>)> _pending = [];

  Future<void> call(Duration d) {
    asked.add(d);
    final c = Completer<void>();
    _pending.add((d, c));
    return c.future;
  }

  bool get waiting => _pending.isNotEmpty;

  /// Finishes the oldest wait, moving the clock on by its length.
  Future<void> next() async {
    final (d, c) = _pending.removeAt(0);
    now = now.add(d);
    c.complete();
    await flush();
  }
}

/// A container with the fake bridge, site, opener, clock and waits; the connection is loaded from [settings], with the
/// site prepared by [prepare] first.
Future<ProviderContainer> load([
  Map<String, Object?> settings = const {},
  void Function(FakeAccountClient site)? prepare,
]) async {
  now = DateTime.utc(2026, 11, 26, 12);
  bridge = FakeLiveBridge()..settings = {...settings};
  site = FakeAccountClient()..now = () => now;
  prepare?.call(site);
  delays = FakeDelays();
  opened = [];
  final c = ProviderContainer(
    overrides: [
      bridgeProvider.overrideWithValue(bridge),
      accountClientProvider.overrideWithValue(site),
      urlOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
      delayProvider.overrideWithValue(delays.call),
      clockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(c.dispose);
  addTearDown(bridge.dispose);
  c.listen(connectionProvider, (_, _) {});
  c.listen(setupProvider, (_, _) {});
  await flush();
  return c;
}

ConnectionNotifier notifier(ProviderContainer c) => c.read(connectionProvider.notifier);

const accountSettings = {'connectionMode': 'account', 'accountRefreshToken': 'refresh-0'};

const base = StartConfig(
  gatewayUrl: 'http://127.0.0.1:8201',
  accessToken: '',
  micUid: 'mic1',
  headphonesUid: 'hp1',
  virtualMicUid: null,
  sourcePids: [],
  myLang: 'uz',
  targetLang: 'ru',
  mode: SessionMode.captions,
  outCommit: OutCommit.manual,
  translationModel: null,
);

const secretKeys = {'accessToken', 'gatewayUrl', 'elevenlabsApiKey', 'geminiApiKey', 'connection'};

Matcher failed(String reason) => isA<SignInFailed>().having((f) => f.reason, 'reason', reason);

bool deletesRefreshToken(Map<String, Object?> m) =>
    m.containsKey('accountRefreshToken') && m['accountRefreshToken'] == null;

void main() {
  group('loading', () {
    test('a saved static token without a saved choice becomes the own gateway (no onboarding)', () async {
      final c = await load({'accessToken': 'static-token', 'gatewayUrl': 'https://own.example'});
      expect(c.read(connectionProvider).loaded, isTrue);
      expect(c.read(connectionProvider).mode, ConnectionMode.gateway);
      expect(bridge.savedPrefs, isEmpty, reason: 'loading writes nothing');
    });

    test('nothing saved means onboarding', () async {
      final c = await load();
      expect(c.read(connectionProvider).loaded, isTrue);
      expect(c.read(connectionProvider).mode, isNull);
    });

    test('a saved "none" loads as onboarding even with a saved static token', () async {
      final c = await load({'connectionMode': 'none', 'accessToken': 'static-token'});
      expect(c.read(connectionProvider).mode, isNull);
    });

    test('a saved choice wins', () async {
      expect((await load({'connectionMode': 'gateway'})).read(connectionProvider).mode, ConnectionMode.gateway);
      final keys = await load({'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key', 'geminiApiKey': 'gm-key'});
      expect(keys.read(connectionProvider).mode, ConnectionMode.keys);
      expect(keys.read(connectionProvider).hasKeys, isTrue);
    });

    test('the saved settings are read once, shared by the setup and the connection', () async {
      final c = await load({'accessToken': 'static-token', 'micUid': 'mic1'});
      expect(bridge.loadSettingsCount, 1);
      expect(c.read(setupProvider).accessToken, 'static-token');
      expect(c.read(connectionProvider).mode, ConnectionMode.gateway);
    });

    test('an account loads me/ and the packages', () async {
      final c = await load(accountSettings);
      final s = c.read(connectionProvider);
      expect(s.mode, ConnectionMode.account);
      expect(s.account?.balanceUnits, 54000);
      expect(s.packages.map((p) => p.code), ['p10']);
      expect(site.refreshedWith, ['refresh-0']);
      expect(bridge.savedPrefs, [
        {'accountRefreshToken': 'refresh-1'},
      ], reason: 'the rotated refresh token is saved');
    });

    test('offline me/ leaves the account unknown and Start unblocked', () async {
      final c = await load(accountSettings, (site) {
        site.meAnswer = const AccountError('network');
        site.packageList = const AccountError('network');
      });
      final s = c.read(connectionProvider);
      expect(s.mode, ConnectionMode.account);
      expect(s.account, isNull);
      expect(s.notice, isNull);
      expect(startBlockers(c.read(setupProvider), en, HostPlatform.macos, connection: s), isEmpty);
      expect(notifier(c).minutesLeft(SessionMode.captions), isNull);

      // Back online: the next refresh fills in the account and retries the packages.
      site.meAnswer = FakeAccountClient.info(54000);
      site.packageList = const [Package(code: 'p10', priceCents: 1000, units: 600000, minutes: 100)];
      await notifier(c).refreshAccount();
      expect(c.read(connectionProvider).account?.balanceUnits, 54000);
      expect(c.read(connectionProvider).packages, hasLength(1));
      await notifier(c).refreshAccount();
      expect(site.packagesCalls, 2, reason: 'loaded once, after the failed try');
    });

    test('a refused refresh token signs out with a notice', () async {
      final c2 = await load(accountSettings, (site) => site.refreshError = const AccountSignedOut());
      expect(c2.read(connectionProvider).mode, isNull);
      expect(c2.read(connectionProvider).notice, 'signed_out');
      expect(bridge.savedPrefs.last, {'accountRefreshToken': null, 'connectionMode': 'none'});
      expect(site.logouts, isEmpty);
    });
  });

  group('settings map', () {
    test('toSettingsMap in account mode has no token, keys, gateway or connection', () {
      final account = base.withAuth(
        connection: ConnectionMode.account,
        gatewayUrl: kHostedGateway,
        accessToken: 'access-1',
      );
      expect(account.toSettingsMap().keys.toSet().intersection(secretKeys), isEmpty);
      expect(account.toSettingsMap()['micUid'], 'mic1');
      final keys = base.withAuth(
        connection: ConnectionMode.keys,
        gatewayUrl: kHostedGateway,
        elevenlabsApiKey: 'el-key',
        geminiApiKey: 'gm-key',
      );
      expect(keys.toSettingsMap().keys.toSet().intersection(secretKeys), isEmpty);
      expect(keys.toMap(), containsPair('connection', 'keys'));
      expect(keys.toMap(), containsPair('elevenlabsApiKey', 'el-key'));
      expect(base.toMap(), containsPair('connection', 'token'), reason: 'the own gateway is wire "token"');
    });
  });

  group('minutes', () {
    test('54 000 units at the site defaults: 9 bidirectional, 37 captions, 14 incoming', () async {
      final c = await load(accountSettings);
      expect(notifier(c).minutesLeft(SessionMode.bidirectional), 9);
      expect(notifier(c).minutesLeft(SessionMode.captions), 37);
      expect(notifier(c).minutesLeft(SessionMode.incoming), 14);
    });

    test('unknown without an account or rates', () {
      expect(const ConnectionState().minutesLeft(SessionMode.captions), isNull);
      const noRates = AccountInfo(
        email: '',
        name: '',
        balanceUnits: 100,
        unitsPerMinute: 0,
        sttUnitsPerSecond: 0,
        ttsUnitsPerChar: 0,
        hasPurchase: false,
      );
      expect(const ConnectionState(account: noRates).minutesLeft(SessionMode.bidirectional), isNull);
      expect(const ConnectionState(account: noRates).minutesLeft(SessionMode.captions), isNull);
    });
  });

  group('sign-in', () {
    test('polling honours interval and slow_down, saves the refresh token and sets mode account', () async {
      final c = await load({'uiLanguage': 'ru'});
      site.polls.addAll([
        const DevicePending(),
        const DeviceSlowDown(),
        const DevicePending(),
        DeviceGranted(
          TokenPair(
            accessToken: 'access-g',
            refreshToken: 'refresh-g',
            expiresAt: now.add(const Duration(minutes: 15)),
          ),
        ),
      ]);
      final done = notifier(c).beginSignIn();
      await flush();

      final waiting = c.read(connectionProvider).signIn as SignInWaiting;
      expect(waiting.userCode, 'ABCD-EFGH');
      expect(waiting.page, Uri.parse('https://site.test/ru/connect/?code=ABCD-EFGH'));
      expect(waiting.expiresAt, now.add(const Duration(seconds: 600)));
      expect(opened, [waiting.page]);
      expect(site.starts.single.deviceId, matches(RegExp(r'^[A-Za-z0-9]{24}$')));
      expect(site.starts.single.deviceName.length, inInclusiveRange(1, 80));
      expect(bridge.savedPrefs.first, {'deviceId': site.starts.single.deviceId});

      while (delays.waiting) {
        await delays.next();
      }
      await done;
      expect(delays.asked, const [
        Duration(seconds: 5),
        Duration(seconds: 5),
        Duration(seconds: 10),
        Duration(seconds: 10),
      ]);
      expect(site.pollCount, 4);
      final s = c.read(connectionProvider);
      expect(s.mode, ConnectionMode.account);
      expect(s.signIn, isA<SignInIdle>());
      expect(bridge.savedPrefs, contains(equals({'accountRefreshToken': 'refresh-g', 'connectionMode': 'account'})));
      expect(site.meTokens, ['access-g']);
      expect(s.account?.balanceUnits, 54000);
      expect(s.packages, hasLength(1));
    });

    test('the device id is created once', () async {
      final c = await load({'deviceId': 'SavedDeviceId00000000001'});
      site.polls.add(const DeviceExpired());
      final done = notifier(c).beginSignIn();
      await flush();
      await delays.next();
      await done;
      expect(site.starts.single.deviceId, 'SavedDeviceId00000000001');
      expect(bridge.savedPrefs, isEmpty);
    });

    test('expired_token fails as expired', () async {
      final c = await load();
      site.polls.add(const DeviceExpired());
      final done = notifier(c).beginSignIn();
      await flush();
      await delays.next();
      await done;
      expect(c.read(connectionProvider).signIn, failed('expired'));
      expect(c.read(connectionProvider).mode, isNull);
    });

    test('access_denied fails as denied', () async {
      final c = await load();
      site.polls.add(const DeviceDenied());
      final done = notifier(c).beginSignIn();
      await flush();
      await delays.next();
      await done;
      expect(c.read(connectionProvider).signIn, failed('denied'));
    });

    test('the code running out on the clock fails as expired without another poll', () async {
      final c = await load();
      site.start = DeviceStart(
        deviceCode: 'lbd_test',
        userCode: 'ABCD-EFGH',
        verificationUri: Uri.parse('https://site.test/en/connect/'),
        verificationUriComplete: Uri.parse('https://site.test/en/connect/?code=ABCD-EFGH'),
        expiresIn: 12,
        interval: 5,
      );
      final done = notifier(c).beginSignIn();
      await flush();
      while (delays.waiting) {
        await delays.next();
      }
      await done;
      expect(site.pollCount, 2);
      expect(c.read(connectionProvider).signIn, failed('expired'));
    });

    test('a network error while polling just tries again', () async {
      final c = await load();
      site.polls.addAll([
        const AccountError('network'),
        DeviceGranted(
          TokenPair(
            accessToken: 'access-g',
            refreshToken: 'refresh-g',
            expiresAt: now.add(const Duration(minutes: 15)),
          ),
        ),
      ]);
      final done = notifier(c).beginSignIn();
      await flush();
      while (delays.waiting) {
        await delays.next();
      }
      await done;
      expect(c.read(connectionProvider).mode, ConnectionMode.account);
    });

    test('a failed start: offline is network, 429 is rate_limited', () async {
      final c = await load();
      site.start = const AccountError('network');
      await notifier(c).beginSignIn();
      expect(c.read(connectionProvider).signIn, failed('network'));
      site.start = const AccountError('rate_limited');
      await notifier(c).beginSignIn();
      expect(c.read(connectionProvider).signIn, failed('rate_limited'));
      expect(opened, isEmpty);
    });

    test('cancelling stops polling; the page can be opened again while waiting', () async {
      final c = await load({'uiLanguage': 'tr'});
      final done = notifier(c).beginSignIn();
      await flush();
      final page = Uri.parse('https://site.test/en/connect/?code=ABCD-EFGH');
      expect(opened, [page], reason: 'tr uses /en/');
      await notifier(c).openPageAgain();
      expect(opened, [page, page]);
      notifier(c).cancelSignIn();
      expect(c.read(connectionProvider).signIn, isA<SignInIdle>());
      await delays.next();
      await done;
      expect(site.pollCount, 0);
      expect(c.read(connectionProvider).mode, isNull);
    });
  });

  group('start', () {
    test('account: the hosted gateway and a fresh access token; the settings carry no secret', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      final cfg = bridge.startedWith!;
      expect(cfg.connection, ConnectionMode.account);
      expect(cfg.gatewayUrl, kHostedGateway);
      expect(cfg.accessToken, 'access-1');
      expect(cfg.toMap()['connection'], 'account');
      expect(bridge.savedSettings.last.keys.toSet().intersection(secretKeys), isEmpty);
    });

    test('keys: the hosted gateway, both keys and no static token', () async {
      final c = await load({
        'connectionMode': 'keys',
        'elevenlabsApiKey': 'el-key',
        'geminiApiKey': 'gm-key',
        'accessToken': 'static-token',
        'gatewayUrl': 'https://own.example',
      });
      await notifier(c).start(base);
      final cfg = bridge.startedWith!;
      expect(cfg.connection, ConnectionMode.keys);
      expect(cfg.gatewayUrl, kHostedGateway);
      expect(cfg.accessToken, isEmpty);
      expect(cfg.elevenlabsApiKey, 'el-key');
      expect(cfg.geminiApiKey, 'gm-key');
      expect(cfg.toMap()['connection'], 'keys');
      expect(bridge.savedSettings.last.keys.toSet().intersection(secretKeys), isEmpty);
      final auth = await notifier(c).authForStart();
      expect('$auth', isNot(contains('el-key')));
      expect('$auth', isNot(contains('gm-key')));
    });

    test('own gateway: the setup address and static token, wire "token"', () async {
      final c = await load({'accessToken': 'static-token', 'gatewayUrl': 'https://own.example'});
      await notifier(c).start(base);
      final cfg = bridge.startedWith!;
      expect(cfg.connection, ConnectionMode.gateway);
      expect(cfg.gatewayUrl, 'https://own.example');
      expect(cfg.accessToken, 'static-token');
      expect(cfg.toMap()['connection'], 'token');
      expect(bridge.savedPrefs, isEmpty, reason: 'a Start never writes a secret');
    });

    test('invalid_token on start: one retry with a refreshed token; a second refusal keeps the account', () async {
      const refused = ErrorEvent(code: 'invalid_token', message: 'refused', fatal: true);
      final c = await load(accountSettings);
      await notifier(c).start(base);
      expect(bridge.startedWith!.accessToken, 'access-1');

      bridge.push(refused);
      await flush();
      expect(bridge.count('start'), 2);
      expect(bridge.startedWith!.accessToken, 'access-2');
      expect(site.refreshedWith, ['refresh-0', 'refresh-1'], reason: 'one forced refresh');
      expect(c.read(sessionProvider).error, isNull, reason: 'the refusal that is retried is not shown');

      bridge.push(refused);
      await flush();
      expect(bridge.count('start'), 2, reason: 'no second retry');
      expect(c.read(connectionProvider).mode, ConnectionMode.account);
      expect(c.read(connectionProvider).notice, isNull);
      expect(bridge.savedPrefs.where(deletesRefreshToken), isEmpty, reason: 'the refresh token is kept');
      expect(bridge.settings['accountRefreshToken'], 'refresh-2');
      expect(c.read(sessionProvider).error?.code, 'invalid_token', reason: 'shown, worded by the UI');

      // The next Start gets its own retry.
      await notifier(c).start(base);
      bridge.push(refused);
      await flush();
      expect(bridge.count('start'), 4);
      expect(bridge.startedWith!.accessToken, 'access-3');
    });

    test('invalid_token, and the forced refresh is refused: signed out', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      site.refreshError = const AccountSignedOut();
      bridge.push(const ErrorEvent(code: 'invalid_token', message: 'refused', fatal: true));
      await flush();
      expect(bridge.count('start'), 1);
      expect(c.read(connectionProvider).mode, isNull);
      expect(c.read(connectionProvider).notice, 'signed_out');
      expect(bridge.savedPrefs.last, {'accountRefreshToken': null, 'connectionMode': 'none'});
    });

    test('the site unreachable at Start: accounts_unavailable, carrying no English text', () async {
      final c = await load(accountSettings);
      now = now.add(const Duration(minutes: 16));
      site.refreshError = const AccountError('network');
      await notifier(c).start(base);
      final error = c.read(sessionProvider).error!;
      expect(error.code, 'accounts_unavailable');
      expect(error.message, isEmpty);
      expect(bridge.count('start'), 0);
    });

    test('other fatal codes reach the session untouched', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      bridge.push(const ErrorEvent(code: 'balance_exhausted', message: 'empty', fatal: true));
      await flush();
      expect(bridge.count('start'), 1);
      expect(c.read(sessionProvider).error?.code, 'balance_exhausted');
      expect(c.read(connectionProvider).mode, ConnectionMode.account);
    });

    test('the refresh timer hands a new token to the running session, and stops with it', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      expect(c.read(sessionProvider).running, isTrue);
      var ticks = 0;
      while (bridge.updatedTokens.isEmpty && ticks++ < 60) {
        await delays.next();
      }
      expect(bridge.updatedTokens, ['access-2']);
      expect(now, DateTime.utc(2026, 11, 26, 12, 12), reason: 'refreshed once 3 minutes are left, not before');
      expect(bridge.savedPrefs.last, {'accountRefreshToken': 'refresh-2'});

      bridge.push(const StateEvent(state: EngineState.idle));
      await flush();
      while (delays.waiting) {
        await delays.next();
      }
      now = now.add(const Duration(hours: 1));
      await flush();
      expect(bridge.updatedTokens, ['access-2']);
      expect(site.refreshedWith, hasLength(2));
    });

    test('a balance event updates the account; an empty balance blocks Start', () async {
      final c = await load(accountSettings);
      bridge.push(const BalanceEvent(0));
      await flush();
      final s = c.read(connectionProvider);
      expect(s.account?.balanceUnits, 0);
      expect(startBlockers(c.read(setupProvider), en, HostPlatform.macos, connection: s), [en.blockBalanceEmpty]);
      expect(BridgeEvent.fromMap({'type': 'balance', 'balanceUnits': 12}), isA<BalanceEvent>());
      expect((BridgeEvent.fromMap({'type': 'balance', 'balanceUnits': 12}) as BalanceEvent).balanceUnits, 12);
      expect(BridgeEvent.fromMap({'type': 'balance'}), isNull);
    });

    test('keys mode without both keys is blocked; the own gateway keeps its checks', () async {
      final c = await load({'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key'});
      final s = c.read(connectionProvider);
      expect(startBlockers(c.read(setupProvider), en, HostPlatform.macos, connection: s), [en.blockEnterKeys]);
      final g = await load({'connectionMode': 'gateway'});
      expect(startBlockers(g.read(setupProvider), en, HostPlatform.macos, connection: g.read(connectionProvider)), [
        en.blockEnterToken,
      ]);
    });
  });

  group('choices', () {
    test('saveGateway saves the address and token and fills the setup fields', () async {
      final c = await load();
      await notifier(c).saveGateway('https://own.example', 'static-token');
      expect(bridge.savedPrefs.last, {
        'gatewayUrl': 'https://own.example',
        'accessToken': 'static-token',
        'connectionMode': 'gateway',
      });
      expect(c.read(connectionProvider).mode, ConnectionMode.gateway);
      expect(c.read(setupProvider).gatewayUrl, 'https://own.example');
      expect(c.read(setupProvider).accessToken, 'static-token');
    });

    test('saveKeys saves both keys and the choice', () async {
      final c = await load();
      await notifier(c).saveKeys('el-key', 'gm-key');
      expect(bridge.savedPrefs.last, {
        'elevenlabsApiKey': 'el-key',
        'geminiApiKey': 'gm-key',
        'connectionMode': 'keys',
      });
      expect(c.read(connectionProvider).mode, ConnectionMode.keys);
      expect(c.read(connectionProvider).hasKeys, isTrue);
    });

    test('changeConnection saves "none" and keeps the saved secrets', () async {
      final c = await load({'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key', 'geminiApiKey': 'gm-key'});
      await notifier(c).changeConnection();
      expect(bridge.savedPrefs.last, {'connectionMode': 'none'});
      expect(c.read(connectionProvider).mode, isNull);
    });

    test('signOut logs out, deletes the refresh token and saves "none"', () async {
      final c = await load(accountSettings);
      await notifier(c).signOut();
      expect(site.logouts, ['access-1']);
      expect(bridge.savedPrefs.last, {'accountRefreshToken': null, 'connectionMode': 'none'});
      expect(c.read(connectionProvider).mode, isNull);
      expect(c.read(connectionProvider).notice, isNull);
      expect(c.read(connectionProvider).account, isNull);
    });

    test('signOut never deletes the refresh token while a save is still running', () async {
      final c = await load(accountSettings);
      site.logoutError = const AccountError('network');
      now = now.add(const Duration(minutes: 16));
      bridge.savePrefsGate = Completer<void>();
      final refreshing = notifier(c).refreshAccount();
      await flush();
      expect(bridge.savedPrefs.last, {'accountRefreshToken': 'refresh-2'});

      final out = notifier(c).signOut();
      await flush();
      expect(bridge.savedPrefs.where(deletesRefreshToken), isEmpty);

      bridge.savePrefsGate!.complete();
      await out;
      await refreshing;
      final saveAt = bridge.savedPrefs.indexWhere((m) => m['accountRefreshToken'] == 'refresh-2');
      final deleteAt = bridge.savedPrefs.indexWhere(deletesRefreshToken);
      expect(deleteAt, greaterThan(saveAt));
      expect(site.logouts, ['access-2'], reason: 'a failed logout does not block');
      expect(c.read(connectionProvider).mode, isNull);
      expect(c.read(connectionProvider).account, isNull, reason: 'a me/ answer after sign-out is dropped');
    });
  });

  group('leaving a mode stops a running session first', () {
    /// Notes in the bridge's call log the moment the mode becomes null, to order it against `stop`.
    void markModeNull(ProviderContainer c) => c.listen(connectionProvider.select((s) => s.mode), (_, mode) {
      if (mode == null) bridge.calls.add('mode:null');
    });

    void expectStoppedFirst() {
      expect(bridge.calls, contains('stop'));
      expect(bridge.calls.indexOf('stop'), lessThan(bridge.calls.indexOf('mode:null')));
    }

    test('signOut', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      markModeNull(c);
      await notifier(c).signOut();
      expectStoppedFirst();
    });

    test('changeConnection', () async {
      final c = await load({'connectionMode': 'keys', 'elevenlabsApiKey': 'el-key', 'geminiApiKey': 'gm-key'});
      await notifier(c).start(base);
      markModeNull(c);
      await notifier(c).changeConnection();
      expectStoppedFirst();
    });

    test('an automatic sign-out (the refresh token refused while the session runs)', () async {
      final c = await load(accountSettings);
      await notifier(c).start(base);
      markModeNull(c);
      site.refreshError = const AccountSignedOut();
      var ticks = 0;
      while (c.read(connectionProvider).mode != null && ticks++ < 60) {
        await delays.next();
      }
      expect(c.read(connectionProvider).notice, 'signed_out');
      expectStoppedFirst();
    });

    test('nothing to stop without a session', () async {
      final c = await load({'connectionMode': 'gateway'});
      await notifier(c).changeConnection();
      expect(bridge.calls, isNot(contains('stop')));
    });
  });

  group('pages', () {
    test('the account page follows the interface language', () async {
      final uz = await load({'uiLanguage': 'uz'});
      await notifier(uz).openAccountPage();
      expect(opened, [Uri.parse('$kSiteBase/uz/account/')]);
      final tr = await load({'uiLanguage': 'tr'});
      await notifier(tr).openAccountPage();
      expect(opened, [Uri.parse('$kSiteBase/en/account/')]);
    });

    test('topUp opens the checkout page in the interface language', () async {
      final c = await load({...accountSettings, 'uiLanguage': 'ru'});
      expect(await notifier(c).topUp('p10'), isNull);
      expect(site.checkouts.single, (token: 'access-1', code: 'p10', language: 'ru'));
      expect(opened, [Uri.parse('https://pay.test/session/1')]);

      site.checkoutAnswer = const AccountError('checkout_unavailable');
      expect(await notifier(c).topUp('p10'), 'checkout_unavailable');
      expect(opened, hasLength(1));
    });
  });
}
