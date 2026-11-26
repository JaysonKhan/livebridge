import 'dart:async';

import 'package:livebridge/bridge/account_client.dart';

/// A scripted site: answers what a test sets and remembers every request. Its tokens are made-up test values.
class FakeAccountClient implements AccountClient {
  /// The clock the issued tokens' lifetimes count from.
  DateTime Function() now = DateTime.now;

  /// `device/start/`: the answer, or an exception to throw.
  Object start = DeviceStart(
    deviceCode: 'lbd_test',
    userCode: 'ABCD-EFGH',
    verificationUri: Uri.parse('https://site.test/en/connect/'),
    verificationUriComplete: Uri.parse('https://site.test/en/connect/?code=ABCD-EFGH'),
    expiresIn: 600,
    interval: 5,
  );
  final List<({String deviceId, String deviceName})> starts = [];

  /// `device/token/`: answers in order (a [DevicePoll] or an exception to throw); pending once they run out.
  final List<Object> polls = [];
  int pollCount = 0;

  /// `token/refresh/`: the n-th refresh answers `access-n` / `refresh-n`, valid for 15 minutes; or throws this.
  Object? refreshError;
  final List<String> refreshedWith = [];

  /// While set and not completed, refreshes are recorded but do not answer.
  Completer<void>? refreshGate;

  /// `me/`: the answer, or an exception to throw.
  Object meAnswer = info(54000);
  final List<String> meTokens = [];

  /// `packages/`: the answer, or an exception to throw.
  Object packageList = const [Package(code: 'p10', priceCents: 1000, units: 600000, minutes: 100)];
  int packagesCalls = 0;

  final List<String> logouts = [];
  Object? logoutError;

  /// While set and not completed, logouts are recorded but do not answer (offline, waiting for a timeout).
  Completer<void>? logoutGate;

  /// `checkout/`: the address to answer, or an exception to throw.
  Object checkoutAnswer = Uri.parse('https://pay.test/session/1');
  final List<({String token, String code, String? language})> checkouts = [];

  static AccountInfo info(int balance) => AccountInfo(
    email: 'person@example.com',
    name: 'Person',
    balanceUnits: balance,
    unitsPerMinute: 6000,
    sttUnitsPerSecond: 12,
    ttsUnitsPerChar: 5,
    hasPurchase: false,
  );

  T _answer<T>(Object value) {
    if (value is Exception) throw value;
    return value as T;
  }

  @override
  Future<DeviceStart> startDevice({required String deviceId, required String deviceName}) async {
    starts.add((deviceId: deviceId, deviceName: deviceName));
    return _answer(start);
  }

  @override
  Future<DevicePoll> pollDevice(String deviceCode) async {
    pollCount++;
    return polls.isEmpty ? const DevicePending() : _answer(polls.removeAt(0));
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshedWith.add(refreshToken);
    final gate = refreshGate;
    if (gate != null) await gate.future;
    final error = refreshError;
    if (error != null) throw error;
    final n = refreshedWith.length;
    return TokenPair(
      accessToken: 'access-$n',
      refreshToken: 'refresh-$n',
      expiresAt: now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<AccountInfo> me(String accessToken) async {
    meTokens.add(accessToken);
    return _answer(meAnswer);
  }

  @override
  Future<List<Package>> packages() async {
    packagesCalls++;
    return _answer(packageList);
  }

  @override
  Future<Uri> checkout(String accessToken, String packageCode, {String? language}) async {
    checkouts.add((token: accessToken, code: packageCode, language: language));
    return _answer(checkoutAnswer);
  }

  @override
  Future<void> logout(String accessToken) async {
    logouts.add(accessToken);
    final gate = logoutGate;
    if (gate != null) await gate.future;
    final error = logoutError;
    if (error != null) throw error;
  }
}
