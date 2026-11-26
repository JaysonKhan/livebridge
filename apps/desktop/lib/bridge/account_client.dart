import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A pair of tokens from the site. The access token lives for minutes and only in memory; the refresh token is rotated
/// on every refresh and is the one secret that is saved.
class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken, required this.expiresAt});

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

/// What `device/start/` hands out: the code to poll with and the page the person opens.
class DeviceStart {
  const DeviceStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriComplete;

  /// Seconds the codes stay valid.
  final int expiresIn;

  /// Seconds between polls.
  final int interval;
}

/// One answer of `device/token/`.
sealed class DevicePoll {
  const DevicePoll();
}

/// Not approved yet; poll again after the interval.
class DevicePending extends DevicePoll {
  const DevicePending();
}

/// Poll less often: the caller adds 5 seconds to its interval.
class DeviceSlowDown extends DevicePoll {
  const DeviceSlowDown();
}

class DeviceGranted extends DevicePoll {
  const DeviceGranted(this.pair);

  final TokenPair pair;
}

/// The code ran out (or is no longer known); start again.
class DeviceExpired extends DevicePoll {
  const DeviceExpired();
}

/// The person declined on the site.
class DeviceDenied extends DevicePoll {
  const DeviceDenied();
}

class AccountInfo {
  const AccountInfo({
    required this.email,
    required this.name,
    required this.balanceUnits,
    required this.unitsPerMinute,
    required this.sttUnitsPerSecond,
    required this.ttsUnitsPerChar,
    required this.hasPurchase,
  });

  final String email;
  final String name;
  final int balanceUnits;
  final int unitsPerMinute;
  final int sttUnitsPerSecond;
  final int ttsUnitsPerChar;
  final bool hasPurchase;
}

class Package {
  const Package({required this.code, required this.priceCents, required this.units, required this.minutes});

  final String code;
  final int priceCents;
  final int units;
  final int minutes;
}

/// The refresh token was refused: the device is signed out and must sign in again.
class AccountSignedOut implements Exception {
  const AccountSignedOut();

  @override
  String toString() => 'AccountSignedOut';
}

/// The access token was refused (`401 invalid_token`): refresh it and retry once.
class AccountTokenStale implements Exception {
  const AccountTokenStale();

  @override
  String toString() => 'AccountTokenStale';
}

/// The site said no, or could not be reached. [code] is the site's error code, or `network` / `rate_limited`.
/// Only codes are carried — never a token.
class AccountError implements Exception {
  const AccountError(this.code);

  final String code;

  @override
  String toString() => 'AccountError($code)';
}

/// The site's app API.
abstract class AccountClient {
  Future<DeviceStart> startDevice({required String deviceId, required String deviceName});

  Future<DevicePoll> pollDevice(String deviceCode);

  Future<TokenPair> refresh(String refreshToken);

  Future<AccountInfo> me(String accessToken);

  Future<List<Package>> packages();

  /// The address to open in the browser. [language] is the interface language, so the site's success page matches it.
  Future<Uri> checkout(String accessToken, String packageCode, {String? language});

  Future<void> logout(String accessToken);
}

/// `<siteBase>/api/livebridge/v1/…`, JSON in and out.
class HttpAccountClient implements AccountClient {
  HttpAccountClient(this.siteBase, {this.timeout = const Duration(seconds: 10), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Uri siteBase;

  /// For each whole exchange: connecting, the answer and its body.
  final Duration timeout;
  final DateTime Function() _now;

  @override
  Future<DeviceStart> startDevice({required String deviceId, required String deviceName}) async {
    final r = await _call('POST', 'device/start/', body: {'device_id': deviceId, 'device_name': deviceName});
    if (r.status != HttpStatus.created) throw _errorOf(r);
    return _parse(r, () {
      final m = r.json as Map;
      return DeviceStart(
        deviceCode: m['device_code'] as String,
        userCode: m['user_code'] as String,
        verificationUri: Uri.parse(m['verification_uri'] as String),
        verificationUriComplete: Uri.parse(m['verification_uri_complete'] as String),
        expiresIn: (m['expires_in'] as num).toInt(),
        interval: (m['interval'] as num).toInt(),
      );
    });
  }

  @override
  Future<DevicePoll> pollDevice(String deviceCode) async {
    final r = await _call('POST', 'device/token/', body: {'device_code': deviceCode});
    if (r.status == HttpStatus.ok) return _parse(r, () => DeviceGranted(_pair(r.json)));
    if (r.status == HttpStatus.badRequest) {
      switch (r.code) {
        case 'authorization_pending':
          return const DevicePending();
        case 'slow_down':
          return const DeviceSlowDown();
        case 'expired_token':
        case 'invalid_grant':
          return const DeviceExpired();
        case 'access_denied':
          return const DeviceDenied();
      }
    }
    throw _errorOf(r);
  }

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    final r = await _call('POST', 'token/refresh/', body: {'refresh_token': refreshToken});
    if (r.status == HttpStatus.unauthorized && r.code == 'invalid_grant') throw const AccountSignedOut();
    if (r.status != HttpStatus.ok) throw _errorOf(r);
    return _parse(r, () => _pair(r.json));
  }

  @override
  Future<AccountInfo> me(String accessToken) async {
    final r = await _call('GET', 'me/', bearer: accessToken);
    if (r.status != HttpStatus.ok) throw _errorOf(r, bearer: true);
    return _parse(r, () {
      final m = r.json as Map;
      final rates = m['rates'] as Map;
      return AccountInfo(
        email: m['email'] as String,
        name: (m['name'] as String?) ?? '',
        balanceUnits: (m['balance_units'] as num).toInt(),
        unitsPerMinute: (m['units_per_minute'] as num).toInt(),
        sttUnitsPerSecond: (rates['stt_units_per_second'] as num).toInt(),
        ttsUnitsPerChar: (rates['tts_units_per_char'] as num).toInt(),
        hasPurchase: m['has_purchase'] as bool,
      );
    });
  }

  @override
  Future<List<Package>> packages() async {
    final r = await _call('GET', 'packages/');
    if (r.status != HttpStatus.ok) throw _errorOf(r);
    return _parse(
      r,
      () => [
        for (final item in r.json as List)
          Package(
            code: (item as Map)['code'] as String,
            priceCents: (item['price_cents'] as num).toInt(),
            units: (item['units'] as num).toInt(),
            minutes: (item['minutes'] as num).toInt(),
          ),
      ],
    );
  }

  @override
  Future<Uri> checkout(String accessToken, String packageCode, {String? language}) async {
    final r = await _call('POST', 'checkout/', body: {'package': packageCode}, bearer: accessToken, language: language);
    if (r.status != HttpStatus.created) throw _errorOf(r, bearer: true);
    return _parse(r, () => Uri.parse((r.json as Map)['url'] as String));
  }

  @override
  Future<void> logout(String accessToken) async {
    final r = await _call('POST', 'logout/', bearer: accessToken);
    if (r.status != HttpStatus.noContent) throw _errorOf(r, bearer: true);
  }

  static TokenPair _pairAt(Object? json, DateTime now) {
    final m = json as Map;
    return TokenPair(
      accessToken: m['access_token'] as String,
      refreshToken: m['refresh_token'] as String,
      expiresAt: now.add(Duration(seconds: (m['expires_in'] as num).toInt())),
    );
  }

  TokenPair _pair(Object? json) => _pairAt(json, _now());

  /// Reads a successful answer; a body that is not what the contract says is a broken connection to us.
  T _parse<T>(_Reply r, T Function() read) {
    try {
      return read();
    } on Object {
      throw const AccountError('network');
    }
  }

  Exception _errorOf(_Reply r, {bool bearer = false}) {
    if (bearer && r.status == HttpStatus.unauthorized && r.code == 'invalid_token') return const AccountTokenStale();
    if (r.status == HttpStatus.tooManyRequests) return const AccountError('rate_limited');
    return AccountError(r.code ?? 'network');
  }

  Future<_Reply> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? bearer,
    String? language,
  }) async {
    final uri = siteBase.replace(path: '${siteBase.path.replaceFirst(RegExp(r'/+$'), '')}/api/livebridge/v1/$path');
    final client = HttpClient();
    try {
      return await _exchange(client, method, uri, body, bearer, language).timeout(timeout);
    } on Object {
      // Refused, unreachable, a TLS failure, a dropped connection or no answer in time.
      throw const AccountError('network');
    } finally {
      client.close(force: true);
    }
  }

  static Future<_Reply> _exchange(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, Object?>? body,
    String? bearer,
    String? language,
  ) async {
    final request = await client.openUrl(method, uri);
    // A token goes to the address it was made for and nowhere else.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (bearer != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    if (language != null) request.headers.set(HttpHeaders.acceptLanguageHeader, language);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await const Utf8Decoder(allowMalformed: true).bind(response).join();
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    return _Reply(response.statusCode, json);
  }
}

class _Reply {
  _Reply(this.status, this.json);

  final int status;
  final Object? json;

  /// The `error` code of a failure body, when there is one.
  String? get code {
    final j = json;
    final e = j is Map ? j['error'] : null;
    return e is String && e.isNotEmpty ? e : null;
  }
}

/// Keeps the access token fresh. One refresh at a time — every caller awaits the same one — and the new refresh token
/// is handed to `onRefreshed` (which saves it) before anyone gets the new access token, because the site signs the
/// device out when a retired refresh token is presented.
class TokenKeeper {
  TokenKeeper({
    required this.client,
    required this.onRefreshed,
    String? refreshToken,
    TokenPair? pair,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _refreshToken = pair?.refreshToken ?? refreshToken,
       _accessToken = pair?.accessToken,
       _expiresAt = pair?.expiresAt;

  final AccountClient client;

  /// Saves the new pair's refresh token. If it throws, the pair is still kept in memory and the error reaches the
  /// callers of that refresh.
  final Future<void> Function(TokenPair pair) onRefreshed;
  final DateTime Function() _now;

  String? _refreshToken;
  String? _accessToken;
  DateTime? _expiresAt;

  /// A pair that arrived from a refresh but could not be saved yet. It is the only valid refresh token, so it stays in
  /// memory and the next call saves it again before returning anything.
  TokenPair? _unsaved;
  Future<String>? _inFlight;
  Object? _ticket;
  int _epoch = 0;

  /// When the access token in memory stops being valid; null when there is none.
  DateTime? get expiresAt => _expiresAt;

  /// Takes a pair obtained elsewhere (the device grant). Its refresh token is saved by the caller.
  void adopt(TokenPair pair) {
    _reset();
    _refreshToken = pair.refreshToken;
    _accessToken = pair.accessToken;
    _expiresAt = pair.expiresAt;
  }

  /// Forgets everything (signed out).
  void clear() {
    _reset();
    _refreshToken = null;
    _accessToken = null;
    _expiresAt = null;
  }

  // Whatever is in flight belongs to the session that is gone: its answer is dropped and nobody joins it.
  void _reset() {
    _epoch++;
    _inFlight = null;
    _ticket = null;
    _unsaved = null;
  }

  /// A token valid for at least [minRemaining], refreshed if needed; [force] refreshes even a fresh one (after a
  /// `401 invalid_token`). Throws [AccountSignedOut] when there is no refresh token or the site refused it. A pair
  /// that could not be saved earlier is saved first; if that fails again the error is rethrown.
  Future<String> accessToken({Duration minRemaining = const Duration(seconds: 60), bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (_unsaved == null) {
      final access = _accessToken;
      final expires = _expiresAt;
      if (!force && access != null && expires != null && expires.difference(_now()) > minRemaining) {
        return Future.value(access);
      }
      if (_refreshToken == null) return Future.error(const AccountSignedOut());
    }
    final ticket = Object();
    final future = _work(_epoch, ticket, force, minRemaining);
    _ticket = ticket;
    return _inFlight = future;
  }

  Future<String> _work(int epoch, Object ticket, bool force, Duration minRemaining) async {
    try {
      final pending = _unsaved;
      if (pending != null) {
        await onRefreshed(pending);
        if (epoch != _epoch) throw const AccountSignedOut();
        if (identical(_unsaved, pending)) _unsaved = null;
        final expires = _expiresAt;
        if (!force && expires != null && expires.difference(_now()) > minRemaining) return _accessToken!;
      }
      final refreshToken = _refreshToken;
      if (refreshToken == null) throw const AccountSignedOut();
      final pair = await client.refresh(refreshToken);
      // Signed out or re-signed in while the request was out: its answer belongs to a session that is gone.
      if (epoch != _epoch) throw const AccountSignedOut();
      _refreshToken = pair.refreshToken;
      _accessToken = pair.accessToken;
      _expiresAt = pair.expiresAt;
      _unsaved = pair;
      await onRefreshed(pair);
      if (epoch == _epoch && identical(_unsaved, pair)) _unsaved = null;
      return pair.accessToken;
    } finally {
      // Only the refresh that is still current clears the slot; a stale one must not wipe a newer one.
      if (identical(_ticket, ticket)) {
        _inFlight = null;
        _ticket = null;
      }
    }
  }
}
