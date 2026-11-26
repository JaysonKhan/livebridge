import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/account_client.dart';
import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'session_state.dart';
import 'setup_state.dart';

export '../bridge/models.dart' show ConnectionMode;

/// The hosted gateway that account and own-keys sessions use.
const String kHostedGateway = String.fromEnvironment(
  'LIVEBRIDGE_GATEWAY',
  defaultValue: 'https://bridge.jaysonkhan.com',
);

/// The site that signs people in, keeps their balance and sells minutes.
const String kSiteBase = String.fromEnvironment('LIVEBRIDGE_SITE', defaultValue: 'https://jaysonkhan.com');

/// The site's app API. Tests override this with a fake.
final accountClientProvider = Provider<AccountClient>((ref) => HttpAccountClient(Uri.parse(kSiteBase)));

/// How often a running account session checks whether its access token needs refreshing.
const Duration _refreshCheck = Duration(seconds: 30);

/// The access token is refreshed for the running session when less than this is left.
const Duration _refreshAhead = Duration(minutes: 3);

const String _idChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

const Object _keep = Object();

/// Where the browser sign-in stands.
sealed class SignInPhase {
  const SignInPhase();
}

class SignInIdle extends SignInPhase {
  const SignInIdle();
}

/// The site's page is open; the person approves [userCode] there before [expiresAt]. [openFailed]: no browser could
/// be opened, so the person opens [page] by hand.
class SignInWaiting extends SignInPhase {
  const SignInWaiting(this.userCode, this.page, this.expiresAt, {this.openFailed = false});

  final String userCode;
  final Uri page;
  final DateTime expiresAt;
  final bool openFailed;
}

/// [reason] is `expired`, `denied`, `network` or `rate_limited`.
class SignInFailed extends SignInPhase {
  const SignInFailed(this.reason);

  final String reason;
}

/// What a Start needs from the connection: how it is paid for, the gateway and the secret(s). Never prints a secret.
class StartAuth {
  const StartAuth({
    required this.connection,
    required this.gatewayUrl,
    this.accessToken = '',
    this.elevenlabsApiKey,
    this.geminiApiKey,
  });

  final ConnectionMode connection;
  final String gatewayUrl;
  final String accessToken;
  final String? elevenlabsApiKey;
  final String? geminiApiKey;

  StartConfig applyTo(StartConfig base) => base.withAuth(
    connection: connection,
    gatewayUrl: gatewayUrl,
    accessToken: accessToken,
    elevenlabsApiKey: elevenlabsApiKey,
    geminiApiKey: geminiApiKey,
  );

  @override
  String toString() => 'StartAuth(${connection.name}, $gatewayUrl)';
}

class ConnectionState {
  const ConnectionState({
    this.mode,
    this.loaded = false,
    this.signIn = const SignInIdle(),
    this.account,
    this.packages = const [],
    this.notice,
    this.hasKeys = false,
    this.previous,
    this.startPending = false,
  });

  /// How sessions are paid for; null = not chosen yet (onboarding).
  final ConnectionMode? mode;

  /// The saved choice has been read.
  final bool loaded;
  final SignInPhase signIn;

  /// The signed-in account from `me/`; null until it is read, and while the site cannot be reached.
  final AccountInfo? account;

  /// What can be bought, in display order; empty until read.
  final List<Package> packages;

  /// Something to tell the person, as a code the UI words: `signed_out`.
  final String? notice;

  /// Both own provider keys are saved.
  final bool hasKeys;

  /// The mode left with "Change", which the onboarding can go back to; null when there is none (in memory only).
  final ConnectionMode? previous;

  /// A Start is getting what it needs (an account's token can take a refresh); Start is off meanwhile.
  final bool startPending;

  /// About how many minutes the balance lasts in [mode]; null when the balance or the rates are unknown.
  int? minutesLeft(SessionMode mode) {
    final a = account;
    if (a == null) return null;
    final captions = 2 * 60 * a.sttUnitsPerSecond;
    final perMinute = switch (mode) {
      SessionMode.bidirectional => a.unitsPerMinute.toDouble(),
      SessionMode.captions => captions.toDouble(),
      SessionMode.incoming => captions + (a.unitsPerMinute - captions) / 2,
    };
    if (perMinute <= 0) return null;
    return (a.balanceUnits / perMinute).floor();
  }

  ConnectionState copyWith({
    Object? mode = _keep,
    bool? loaded,
    SignInPhase? signIn,
    Object? account = _keep,
    List<Package>? packages,
    Object? notice = _keep,
    bool? hasKeys,
    Object? previous = _keep,
    bool? startPending,
  }) => ConnectionState(
    mode: identical(mode, _keep) ? this.mode : mode as ConnectionMode?,
    loaded: loaded ?? this.loaded,
    signIn: signIn ?? this.signIn,
    account: identical(account, _keep) ? this.account : account as AccountInfo?,
    packages: packages ?? this.packages,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
    hasKeys: hasKeys ?? this.hasKeys,
    previous: identical(previous, _keep) ? this.previous : previous as ConnectionMode?,
    startPending: startPending ?? this.startPending,
  );
}

/// The way sessions are paid for: a signed-in account, the user's own keys, or the user's own gateway. Secrets (the
/// keys, the refresh token, the access token) stay in private fields, never in the state.
class ConnectionNotifier extends Notifier<ConnectionState> {
  late LiveBridge _bridge;
  late AccountClient _client;
  late DateTime Function() _now;
  late Future<void> Function(Duration) _delay;
  late TokenKeeper _keeper;

  String? _deviceId;
  String? _elevenlabsKey;
  String? _geminiKey;
  bool _packagesLoaded = false;

  /// The refresh token save running right now, so that a sign-out can wait for it.
  Future<void>? _pendingSave;

  /// The `me/` read running now and the account it is for, so that callers join it instead of asking again.
  ({int run, Future<void> future})? _accountRead;

  // Bumping one of these cancels what was started under the old value: the sign-in polling, answers for an account
  // that is gone, the running session's token refreshes.
  int _signInRun = 0;
  int _accountRun = 0;
  int _refreshRun = 0;

  /// The running account session's config, kept to retry it once with a refreshed token.
  StartConfig? _accountStart;
  bool _startRetried = false;

  /// The access token the running account session has; null while no account session runs.
  String? _sessionToken;

  @override
  ConnectionState build() {
    _bridge = ref.watch(bridgeProvider);
    _client = ref.watch(accountClientProvider);
    _now = ref.watch(clockProvider);
    _delay = ref.watch(delayProvider);
    _keeper = _newKeeper(null);
    // Listening builds the session first, so it hears each bridge event (a fatal error ends it) before this does.
    ref.listen(sessionProvider.select((s) => s.running), (_, running) {
      if (!running) {
        _refreshRun++;
        _sessionToken = null;
      }
    });
    final sub = _bridge.events.listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      _signInRun++;
      _accountRun++;
      _refreshRun++;
    });
    Future.microtask(_load);
    return const ConnectionState();
  }

  TokenKeeper _newKeeper(String? refreshToken) =>
      TokenKeeper(client: _client, onRefreshed: _saveRefreshToken, refreshToken: refreshToken, now: _now);

  Future<void> _saveRefreshToken(TokenPair pair) async {
    final save = _bridge.savePreferences({'accountRefreshToken': pair.refreshToken});
    _pendingSave = save;
    try {
      await save;
    } finally {
      if (identical(_pendingSave, save)) _pendingSave = null;
    }
    await _handToSession(pair.accessToken);
  }

  /// The site keeps one access token per device, so a refresh outside the session's timer (the voice list, a top up)
  /// retires the running session's token: the session gets the new one at once, once its refresh token is saved.
  Future<void> _handToSession(String token) async {
    final held = _sessionToken;
    if (held == null || held == token || !ref.mounted || !ref.read(sessionProvider).running) return;
    try {
      await _bridge.updateAccessToken(token);
      _sessionToken = token;
    } on Exception {
      // The session's timer hands it over at its next check.
    }
  }

  Future<void> _load() async {
    Map<String, Object?> saved;
    try {
      saved = await ref.read(savedSettingsProvider);
    } on Exception {
      saved = const {}; // The setup reports the failure.
    }
    if (!ref.mounted) return;
    final deviceId = saved['deviceId'];
    _deviceId = deviceId is String && _deviceIdPattern.hasMatch(deviceId) ? deviceId : null;
    _elevenlabsKey = _text(saved['elevenlabsApiKey']);
    _geminiKey = _text(saved['geminiApiKey']);
    final choice = saved['connectionMode'];
    // Only a missing choice is migrated: an install with a saved static token is the own gateway. A saved `none`
    // (after "change connection" or a sign-out) stays onboarding.
    final mode = choice == null
        ? (_text(saved['accessToken']) == null ? null : ConnectionMode.gateway)
        : ConnectionMode.values.where((m) => m.name == choice).firstOrNull;
    if (mode == ConnectionMode.account) _keeper = _newKeeper(_text(saved['accountRefreshToken']));
    state = state.copyWith(mode: mode, loaded: true, hasKeys: _hasKeys);
    if (mode == ConnectionMode.account) await refreshAccount();
  }

  static String? _text(Object? value) => value is String && value.isNotEmpty ? value : null;

  bool get _hasKeys => _elevenlabsKey != null && _geminiKey != null;

  void _onEvent(BridgeEvent e) {
    switch (e) {
      case BalanceEvent(:final balanceUnits) when state.mode == ConnectionMode.account:
        final a = state.account;
        if (a == null) {
          // Not read yet (the site could not be reached at launch): read it now; the answer has this balance.
          unawaited(refreshAccount());
        } else {
          state = state.copyWith(
            account: AccountInfo(
              email: a.email,
              name: a.name,
              balanceUnits: balanceUnits,
              unitsPerMinute: a.unitsPerMinute,
              sttUnitsPerSecond: a.sttUnitsPerSecond,
              ttsUnitsPerChar: a.ttsUnitsPerChar,
              hasPurchase: a.hasPurchase,
            ),
          );
        }
      case StateEvent(state: EngineState.ready || EngineState.active):
        // Connected: a later refusal gets its own retry.
        _startRetried = false;
      case ErrorEvent(fatal: true, code: 'invalid_token'):
        final refused = _accountStart;
        if (refused != null) unawaited(_retryStart(refused));
      default:
        break;
    }
  }

  /// Signs in through the site in the browser: opens the approval page and polls until it is approved, declined or
  /// runs out.
  Future<void> beginSignIn() async {
    final run = ++_signInRun;
    state = state.copyWith(signIn: const SignInIdle(), notice: null);
    final DeviceStart start;
    try {
      start = await _client.startDevice(deviceId: await _ensureDeviceId(), deviceName: _deviceName());
    } on AccountError catch (e) {
      if (run == _signInRun && ref.mounted) {
        state = state.copyWith(signIn: SignInFailed(e.code == 'rate_limited' ? 'rate_limited' : 'network'));
      }
      return;
    }
    if (run != _signInRun || !ref.mounted) return;
    final expiresAt = _now().add(Duration(seconds: start.expiresIn));
    final page = _onSite(start.verificationUriComplete);
    if (!_openable(page)) {
      // Not a page of the site: nothing is opened and nothing polls.
      state = state.copyWith(signIn: const SignInFailed('network'));
      return;
    }
    state = state.copyWith(signIn: SignInWaiting(start.userCode, page, expiresAt));
    if (!await _open(page)) _browserFailed(run);
    var interval = Duration(seconds: start.interval);
    while (true) {
      await _delay(interval);
      if (run != _signInRun || !ref.mounted) return;
      if (!_now().isBefore(expiresAt)) {
        state = state.copyWith(signIn: const SignInFailed('expired'));
        return;
      }
      final DevicePoll poll;
      try {
        poll = await _client.pollDevice(start.deviceCode);
      } on AccountError {
        continue; // Offline for a moment: ask again at the next tick, until the code runs out.
      }
      if (run != _signInRun || !ref.mounted) return;
      switch (poll) {
        case DevicePending():
          continue;
        case DeviceSlowDown():
          interval += const Duration(seconds: 5);
        case DeviceExpired():
          state = state.copyWith(signIn: const SignInFailed('expired'));
          return;
        case DeviceDenied():
          state = state.copyWith(signIn: const SignInFailed('denied'));
          return;
        case DeviceGranted(:final pair):
          await _granted(pair);
          return;
      }
    }
  }

  Future<void> _granted(TokenPair pair) async {
    _accountRun++;
    _keeper.adopt(pair);
    try {
      await _bridge.savePreferences({'accountRefreshToken': pair.refreshToken, 'connectionMode': 'account'});
    } on Exception catch (e) {
      // Signed in for now; without the saved refresh token the next launch asks to sign in again.
      if (ref.mounted) ref.read(sessionProvider.notifier).reportException(e, 'saveSettings');
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      mode: ConnectionMode.account,
      signIn: const SignInIdle(),
      account: null,
      notice: null,
      previous: null,
    );
    await refreshAccount();
  }

  /// Opens the approval page again (the person closed the browser tab).
  Future<void> openPageAgain() async {
    final run = _signInRun;
    final phase = state.signIn;
    if (phase is SignInWaiting && !await _open(phase.page)) _browserFailed(run);
  }

  /// No browser opened the approval page: the waiting view shows its address to open by hand.
  void _browserFailed(int run) {
    final phase = state.signIn;
    if (run != _signInRun || !ref.mounted || phase is! SignInWaiting || phase.openFailed) return;
    state = state.copyWith(signIn: SignInWaiting(phase.userCode, phase.page, phase.expiresAt, openFailed: true));
  }

  void cancelSignIn() {
    _signInRun++;
    state = state.copyWith(signIn: const SignInIdle());
  }

  Future<String> _ensureDeviceId() async {
    final known = _deviceId;
    if (known != null) return known;
    final random = Random.secure();
    final id = String.fromCharCodes([
      for (var i = 0; i < 24; i++) _idChars.codeUnitAt(random.nextInt(_idChars.length)),
    ]);
    _deviceId = id;
    try {
      await _bridge.savePreferences({'deviceId': id});
    } on Exception {
      // Not saved: the next launch makes another one, and the site lists this computer once more.
    }
    return id;
  }

  static String _deviceName() {
    final name = Platform.localHostname;
    return name.length > 80 ? name.substring(0, 80) : name;
  }

  /// Chooses the user's own provider keys. Throws the bridge's error when they could not be saved; nothing changes
  /// then.
  Future<void> saveKeys(String elevenlabs, String gemini) async {
    final el = elevenlabs.trim();
    final gm = gemini.trim();
    // The secrets first: a host stores the other keys of a call even when a secret cannot be written, so the choice
    // is saved only once they are.
    await _bridge.savePreferences({'elevenlabsApiKey': el, 'geminiApiKey': gm});
    await _bridge.savePreferences({'connectionMode': 'keys'});
    _signInRun++;
    _elevenlabsKey = _text(el);
    _geminiKey = _text(gm);
    state = state.copyWith(
      mode: ConnectionMode.keys,
      hasKeys: _hasKeys,
      signIn: const SignInIdle(),
      notice: null,
      previous: null,
    );
  }

  /// The saved own keys, to fill in the onboarding's fields after "Change"; empty when none are saved.
  ({String elevenlabs, String gemini}) get savedKeys => (elevenlabs: _elevenlabsKey ?? '', gemini: _geminiKey ?? '');

  /// Chooses the user's own gateway; the address and token also fill the setup fields. Throws the bridge's error when
  /// they could not be saved; nothing changes then.
  Future<void> saveGateway(String url, String token) async {
    final u = url.trim();
    final t = token.trim();
    await _bridge.savePreferences({'gatewayUrl': u, 'accessToken': t});
    await _bridge.savePreferences({'connectionMode': 'gateway'});
    _signInRun++;
    ref.read(setupProvider.notifier)
      ..setGatewayUrl(u)
      ..setAccessToken(t);
    state = state.copyWith(mode: ConnectionMode.gateway, signIn: const SignInIdle(), notice: null, previous: null);
  }

  /// Back to onboarding, after stopping a running session; the saved keys, token and refresh token are kept, and the
  /// mode left is remembered for [restorePrevious]. Throws the bridge's error when the choice could not be saved.
  Future<void> changeConnection() async {
    final left = state.mode;
    await _stopRunningSession();
    await _bridge.savePreferences({'connectionMode': 'none'});
    _signInRun++;
    state = state.copyWith(mode: null, signIn: const SignInIdle(), notice: null, previous: left);
  }

  /// Undoes "Change": back to the mode left, with its saved secrets (an account resumes with its refresh token, which
  /// "Change" kept). Throws the bridge's error when the choice could not be saved; nothing changes then.
  Future<void> restorePrevious() async {
    final previous = state.previous;
    if (previous == null) return;
    await _bridge.savePreferences({'connectionMode': previous.name});
    _signInRun++;
    state = state.copyWith(mode: previous, signIn: const SignInIdle(), notice: null, previous: null);
    if (previous == ConnectionMode.account) await refreshAccount();
  }

  /// Stops a running session, deletes the refresh token and goes back to onboarding at once, then signs this computer
  /// out on the site in the background (best effort) with the access token in memory. It never refreshes for that:
  /// offline, a refresh and the logout could each wait for their timeout.
  Future<void> signOut() async {
    final token = _keeper.current;
    await _forget();
    if (token != null) unawaited(_logout(token));
  }

  Future<void> _logout(String token) async {
    try {
      await _client.logout(token);
    } on Exception {
      // Offline or refused: this computer has forgotten the account all the same.
    }
  }

  /// Forgets the account and stops a running session. No refresh can start after the keeper is cleared and a refresh
  /// token save that is still running finishes first, so the delete is the last write.
  Future<void> _forget({String? notice}) async {
    _accountRun++;
    _refreshRun++;
    _accountStart = null;
    _sessionToken = null;
    _keeper.clear();
    await _stopRunningSession();
    final saving = _pendingSave;
    if (saving != null) {
      try {
        await saving;
      } on Exception {
        // Its caller heard about the failure.
      }
    }
    try {
      await _bridge.savePreferences({'accountRefreshToken': null, 'connectionMode': 'none'});
    } on Exception catch (e) {
      if (ref.mounted) ref.read(sessionProvider.notifier).reportException(e, 'saveSettings');
    }
    if (!ref.mounted) return;
    state = state.copyWith(mode: null, account: null, signIn: const SignInIdle(), notice: notice, previous: null);
  }

  /// Ends a running session before the mode becomes null: onboarding has no Stop, and an account session is billed.
  Future<void> _stopRunningSession() async {
    if (ref.mounted && ref.read(sessionProvider).running) await ref.read(sessionProvider.notifier).stop();
  }

  /// The site refused the refresh token while [run] was the account: sign out with a notice. A sign-out that already
  /// happened is not repeated.
  Future<void> _signedOutDuring(int run) async {
    if (run == _accountRun) await _forget(notice: 'signed_out');
  }

  Future<T> _withAccessToken<T>(Future<T> Function(String token) call) async {
    final token = await _keeper.accessToken();
    try {
      return await call(token);
    } on AccountTokenStale {
      return call(await _keeper.accessToken(force: true));
    }
  }

  /// Reads the account (`me/`) and, until it has worked once, the packages. Offline, what is known stays: this never
  /// blocks Start. A call while a read for the same account runs joins it.
  Future<void> refreshAccount() {
    if (state.mode != ConnectionMode.account) return Future.value();
    final running = _accountRead;
    if (running != null && running.run == _accountRun) return running.future;
    final run = _accountRun;
    late final Future<void> read;
    read = _readAccount(run).whenComplete(() {
      if (identical(_accountRead?.future, read)) _accountRead = null;
    });
    _accountRead = (run: run, future: read);
    return read;
  }

  Future<void> _readAccount(int run) async {
    try {
      final info = await _withAccessToken(_client.me);
      if (run == _accountRun && ref.mounted) state = state.copyWith(account: info);
    } on AccountSignedOut {
      await _signedOutDuring(run);
      return;
    } on AccountError {
      // Offline or the site said no.
    } on AccountTokenStale {
      // Refused twice in a row; the next refresh tries again.
    } on PlatformException catch (e) {
      // The rotated refresh token could not be saved; the keeper saves it again on its next use.
      if (ref.mounted) ref.read(sessionProvider.notifier).reportException(e, 'saveSettings');
    }
    if (!_packagesLoaded && ref.mounted) await _loadPackages();
  }

  Future<void> _loadPackages() async {
    try {
      final list = await _client.packages();
      _packagesLoaded = true;
      if (ref.mounted) state = state.copyWith(packages: list);
    } on AccountError {
      // Read again at the next refreshAccount.
    }
  }

  /// Opens the site's checkout for [packageCode] in the browser. Null when the page opened, else a code: `signed_out`,
  /// the site's (`unknown_package`, `rate_limited`, `checkout_unavailable`), `network`, `open_failed` (not an https
  /// page, or no browser opened), or the bridge's when a refreshed token could not be saved.
  Future<String?> topUp(String packageCode) async {
    final run = _accountRun;
    try {
      final url = await _withAccessToken((t) => _client.checkout(t, packageCode, language: _uiLanguage()));
      return await _open(url) ? null : 'open_failed';
    } on AccountSignedOut {
      await _signedOutDuring(run);
      return 'signed_out';
    } on AccountError catch (e) {
      return e.code;
    } on AccountTokenStale {
      return 'invalid_token';
    } on PlatformException catch (e) {
      return e.code;
    }
  }

  /// Opens the account's page on the site.
  Future<void> openAccountPage() => _open(Uri.parse('$kSiteBase/${_sitePath()}/account/'));

  /// What the start config needs for the current mode: an account's access token (refreshed at most once), both own
  /// keys, or the setup's own gateway address and token. Onboarding has no Start; until it is shown, the setup's
  /// gateway fields are used. Throws [AccountSignedOut], [AccountError] or the bridge's save error for an account.
  Future<StartAuth> authForStart() async => switch (state.mode) {
    ConnectionMode.account => StartAuth(
      connection: ConnectionMode.account,
      gatewayUrl: kHostedGateway,
      accessToken: await _keeper.accessToken(),
    ),
    ConnectionMode.keys => StartAuth(
      connection: ConnectionMode.keys,
      gatewayUrl: kHostedGateway,
      elevenlabsApiKey: _elevenlabsKey ?? '',
      geminiApiKey: _geminiKey ?? '',
    ),
    ConnectionMode.gateway || null => StartAuth(
      connection: ConnectionMode.gateway,
      gatewayUrl: ref.read(setupProvider).gatewayUrl.trim(),
      accessToken: ref.read(setupProvider).accessToken.trim(),
    ),
  };

  /// What the voice list needs in the current mode: the hosted gateway with an account's access token (a new one when
  /// [forceRefresh]) or the ElevenLabs key, or the own gateway with its static token. The secret never leaves this call
  /// except in the returned auth. Throws a [VoicesException] when an account's token cannot be had: `unauthorized` when
  /// the site no longer knows this computer (which also signs out), `network` when it cannot be reached.
  Future<({String url, VoicesAuth auth})> voicesAccess({bool forceRefresh = false}) async {
    switch (state.mode) {
      case ConnectionMode.account:
        final run = _accountRun;
        try {
          return (url: kHostedGateway, auth: BearerAuth(await _keeper.accessToken(force: forceRefresh)));
        } on AccountSignedOut {
          await _signedOutDuring(run);
          throw const VoicesException(VoicesFailure.unauthorized);
        } on AccountError {
          throw const VoicesException(VoicesFailure.network);
        } on PlatformException {
          // The rotated refresh token could not be saved.
          throw const VoicesException(VoicesFailure.unavailable);
        }
      case ConnectionMode.keys:
        return (url: kHostedGateway, auth: ProviderKeyAuth(_elevenlabsKey ?? ''));
      case ConnectionMode.gateway || null:
        final setup = ref.read(setupProvider);
        return (url: setup.gatewayUrl.trim(), auth: BearerAuth(setup.accessToken.trim()));
    }
  }

  /// Starts a session with [base] (the setup's config), paid for by the current connection. Ignored while an earlier
  /// Start is still getting its token: both would reach the host, and the second would be refused as busy.
  Future<void> start(StartConfig base) async {
    if (state.startPending) return;
    final run = _accountRun;
    state = state.copyWith(startPending: true);
    final StartAuth auth;
    try {
      auth = await authForStart();
    } on AccountSignedOut {
      await _signedOutDuring(run);
      return;
    } on Exception catch (e) {
      if (ref.mounted) _reportStartFailure(e);
      return;
    } finally {
      if (ref.mounted) state = state.copyWith(startPending: false);
    }
    if (!ref.mounted) return;
    final config = auth.applyTo(base);
    _accountStart = config.connection == ConnectionMode.account ? config : null;
    _startRetried = false;
    await _startSession(config);
  }

  Future<void> _startSession(StartConfig config) async {
    await ref.read(sessionProvider.notifier).start(config);
    if (!ref.mounted || config.connection != ConnectionMode.account || !ref.read(sessionProvider).running) return;
    _sessionToken = config.accessToken;
    final run = ++_refreshRun;
    unawaited(_keepTokenFresh(run));
  }

  void _reportStartFailure(Exception e) {
    final session = ref.read(sessionProvider.notifier);
    if (e is AccountError) {
      // A code only: the error strip words it in the interface language.
      session.reportError(const ErrorEvent(code: 'accounts_unavailable', message: ''));
    } else {
      session.reportException(e, 'saveSettings');
    }
  }

  /// The gateway refused the account session's access token: refresh it and start the same session once more, without
  /// showing the refusal. A second refusal stays on the error strip and keeps the account: the site still accepted the
  /// refresh token, so the next Start tries again. Only the site refusing the refresh token signs out.
  Future<void> _retryStart(StartConfig refused) async {
    final run = _accountRun;
    if (_startRetried) return;
    _startRetried = true;
    ref.read(sessionProvider.notifier).dismissError();
    final String token;
    try {
      token = await _keeper.accessToken(force: true);
    } on AccountSignedOut {
      await _signedOutDuring(run);
      return;
    } on Exception catch (e) {
      if (ref.mounted) _reportStartFailure(e);
      return;
    }
    // A new Start or a sign-out while refreshing wins.
    if (!ref.mounted || !identical(_accountStart, refused)) return;
    final retry = refused.withAuth(
      connection: ConnectionMode.account,
      gatewayUrl: refused.gatewayUrl,
      accessToken: token,
    );
    _accountStart = retry;
    await _startSession(retry);
  }

  /// While the account session runs, hands it a new access token before the old one runs out; the session uses it at
  /// its next automatic reconnect.
  Future<void> _keepTokenFresh(int run) async {
    final account = _accountRun;
    while (true) {
      await _delay(_refreshCheck);
      if (run != _refreshRun || !ref.mounted) return;
      try {
        final token = await _keeper.accessToken(minRemaining: _refreshAhead);
        if (run != _refreshRun || !ref.mounted) return;
        if (token != _sessionToken) {
          await _bridge.updateAccessToken(token);
          _sessionToken = token;
        }
      } on AccountSignedOut {
        await _signedOutDuring(account);
        return;
      } on Exception {
        // Offline, or the new refresh token could not be saved yet: try again at the next check.
      }
    }
  }

  int? minutesLeft(SessionMode mode) => state.minutesLeft(mode);

  /// Opens [url] in the browser. False when it was not opened: not an https page (plain http only on this computer,
  /// for a test site), or no browser could be opened.
  Future<bool> _open(Uri url) async {
    if (!_openable(url)) return false;
    try {
      return await ref.read(urlOpenerProvider)(url);
    } on Exception {
      return false;
    }
  }

  static bool _openable(Uri url) =>
      url.host.isNotEmpty &&
      (url.scheme == 'https' || (url.scheme == 'http' && (url.host == 'localhost' || url.host == '127.0.0.1')));

  /// The interface language: the saved choice, else the system's when the app has it, else English.
  String _uiLanguage() {
    final code = ref.read(setupProvider).uiLanguage ?? PlatformDispatcher.instance.locale.languageCode;
    return AppLocalizations.supportedLocales.any((l) => l.languageCode == code) ? code : 'en';
  }

  /// The site's pages are in Uzbek, Russian and English; Turkish readers get English.
  String _sitePath() => switch (_uiLanguage()) {
    'uz' => 'uz',
    'ru' => 'ru',
    _ => 'en',
  };

  /// [page] (the site's `/en/…` address) in the interface language.
  Uri _onSite(Uri page) {
    final segments = page.pathSegments;
    if (segments.isEmpty || segments.first != 'en') return page;
    return page.replace(pathSegments: [_sitePath(), ...segments.skip(1)]);
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionState>(ConnectionNotifier.new);
