import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/account_client.dart';

typedef _Reply = ({int status, Object? body, Map<String, String> headers});

class _Seen {
  _Seen(this.method, this.path, this.body, this.headers);
  final String method;
  final String path;
  final Map<String, Object?> body;
  final HttpHeaders headers;
}

/// Counts refreshes and answers from a script; the test releases each answer.
class _FakeClient implements AccountClient {
  _FakeClient(this.now);
  final DateTime Function() now;
  final List<String> refreshed = [];
  final List<Completer<TokenPair>> gates = [];
  Object? failure;
  int serial = 0;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshed.add(refreshToken);
    if (gates.isNotEmpty) return gates.removeAt(0).future;
    if (failure != null) throw failure!;
    serial++;
    return TokenPair(
      accessToken: 'acc$serial',
      refreshToken: 'ref$serial',
      expiresAt: now().add(const Duration(minutes: 15)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('HttpAccountClient', () {
    late HttpServer server;
    late HttpAccountClient client;
    late Map<String, _Reply> replies;
    late bool hang;
    late bool drop;
    final seen = <_Seen>[];
    final clock = DateTime.utc(2026, 11, 26, 12);

    _Reply json(int status, Object? body, {Map<String, String> headers = const {}}) =>
        (status: status, body: body, headers: headers);

    setUp(() async {
      replies = {};
      hang = false;
      drop = false;
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        seen.add(
          _Seen(
            request.method,
            request.uri.path,
            text.isEmpty ? {} : jsonDecode(text) as Map<String, Object?>,
            request.headers,
          ),
        );
        if (hang) return;
        if (drop) {
          (await request.response.detachSocket()).destroy();
          return;
        }
        final reply = replies[request.uri.path] ?? json(404, {'error': 'not_found'});
        request.response.statusCode = reply.status;
        reply.headers.forEach(request.response.headers.set);
        if (reply.body != null) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(reply.body is String ? reply.body : jsonEncode(reply.body));
        }
        await request.response.close();
      });
      client = HttpAccountClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
        timeout: const Duration(milliseconds: 500),
        now: () => clock,
      );
    });
    tearDown(() => server.close(force: true));

    const base = '/api/livebridge/v1';
    final pairBody = {'access_token': 'lba_x', 'refresh_token': 'lbr_x', 'token_type': 'Bearer', 'expires_in': 900};

    Future<Object> thrownBy(Future<Object?> call) async {
      try {
        await call;
      } on Object catch (e) {
        return e;
      }
      fail('did not throw');
    }

    test('reports a failure with its path, status and code only', () async {
      final failures = <(String, int?, String)>[];
      final watched = HttpAccountClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
        timeout: const Duration(milliseconds: 500),
        now: () => clock,
        onFailure: (what, status, code) => failures.add((what, status, code)),
      );
      replies['$base/token/refresh/'] = json(401, {'error': 'invalid_grant', 'detail': 'lbr_body_secret'});
      replies['$base/packages/'] = json(429, {'error': 'rate_limited'});
      replies['$base/device/token/'] = json(400, {'error': 'authorization_pending'});
      await thrownBy(watched.refresh('lbr_mine'));
      await thrownBy(watched.packages());
      expect(await watched.pollDevice('lbd_x'), isA<DevicePending>()); // waiting for the person is not a failure
      drop = true;
      await thrownBy(watched.me('lba_mine'));
      expect(failures, [
        ('token/refresh/', 401, 'invalid_grant'),
        ('packages/', 429, 'rate_limited'),
        ('me/', null, 'network'),
      ]);
    });

    test('startDevice posts the device and reads the codes', () async {
      replies['$base/device/start/'] = json(201, {
        'device_code': 'lbd_1',
        'user_code': 'ABCD-EFGH',
        'verification_uri': 'https://jaysonkhan.com/en/connect/',
        'verification_uri_complete': 'https://jaysonkhan.com/en/connect/?code=ABCD-EFGH',
        'expires_in': 600,
        'interval': 5,
      });
      final start = await client.startDevice(deviceId: 'dev_12345678', deviceName: 'My Mac');
      expect(start.deviceCode, 'lbd_1');
      expect(start.userCode, 'ABCD-EFGH');
      expect(start.verificationUri, Uri.parse('https://jaysonkhan.com/en/connect/'));
      expect(start.verificationUriComplete.query, 'code=ABCD-EFGH');
      expect(start.expiresIn, 600);
      expect(start.interval, 5);
      expect(seen.single.method, 'POST');
      expect(seen.single.body, {'device_id': 'dev_12345678', 'device_name': 'My Mac'});
    });

    test('startDevice maps invalid_device and rate limits', () async {
      replies['$base/device/start/'] = json(400, {'error': 'invalid_device'});
      expect(await thrownBy(client.startDevice(deviceId: 'x', deviceName: 'n')), isA<AccountError>());
      expect(
        ((await thrownBy(client.startDevice(deviceId: 'x', deviceName: 'n'))) as AccountError).code,
        'invalid_device',
      );
      replies['$base/device/start/'] = json(429, {'error': 'rate_limited'}, headers: {'Retry-After': '60'});
      expect(
        ((await thrownBy(client.startDevice(deviceId: 'x', deviceName: 'n'))) as AccountError).code,
        'rate_limited',
      );
    });

    test('each poll answer maps to its class', () async {
      Future<DevicePoll> poll() => client.pollDevice('lbd_1');
      replies['$base/device/token/'] = json(200, pairBody);
      final granted = await poll();
      expect(granted, isA<DeviceGranted>());
      final pair = (granted as DeviceGranted).pair;
      expect(pair.accessToken, 'lba_x');
      expect(pair.refreshToken, 'lbr_x');
      expect(pair.expiresAt, clock.add(const Duration(seconds: 900)));
      expect(seen.last.body, {'device_code': 'lbd_1'});

      for (final (code, matcher) in <(String, Matcher)>[
        ('authorization_pending', isA<DevicePending>()),
        ('slow_down', isA<DeviceSlowDown>()),
        ('expired_token', isA<DeviceExpired>()),
        ('invalid_grant', isA<DeviceExpired>()),
        ('access_denied', isA<DeviceDenied>()),
      ]) {
        replies['$base/device/token/'] = json(400, {'error': code});
        expect(await poll(), matcher, reason: code);
      }
      replies['$base/device/token/'] = json(400, {'error': 'something_new'});
      expect(((await thrownBy(poll())) as AccountError).code, 'something_new');
      replies['$base/device/token/'] = json(429, {'error': 'rate_limited'});
      expect(((await thrownBy(poll())) as AccountError).code, 'rate_limited');
    });

    test('refresh returns the new pair; 401 invalid_grant signs out', () async {
      replies['$base/token/refresh/'] = json(200, pairBody);
      final pair = await client.refresh('lbr_old');
      expect(pair.refreshToken, 'lbr_x');
      expect(seen.single.body, {'refresh_token': 'lbr_old'});
      replies['$base/token/refresh/'] = json(401, {'error': 'invalid_grant'});
      expect(await thrownBy(client.refresh('lbr_old')), isA<AccountSignedOut>());
    });

    test('me reads the account; 401 invalid_token is stale', () async {
      replies['$base/me/'] = json(200, {
        'account_id': 7,
        'email': 'a@b.c',
        'name': 'Ada',
        'balance_units': 30000,
        'units_per_minute': 6000,
        'rates': {'stt_units_per_second': 12, 'tts_units_per_char': 5},
        'has_purchase': true,
      });
      final info = await client.me('lba_tok');
      expect(info.email, 'a@b.c');
      expect(info.name, 'Ada');
      expect(info.balanceUnits, 30000);
      expect(info.unitsPerMinute, 6000);
      expect(info.sttUnitsPerSecond, 12);
      expect(info.ttsUnitsPerChar, 5);
      expect(info.hasPurchase, isTrue);
      expect(seen.single.method, 'GET');
      expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer lba_tok');
      replies['$base/me/'] = json(401, {'error': 'invalid_token'});
      expect(await thrownBy(client.me('lba_tok')), isA<AccountTokenStale>());
    });

    test('packages lists the active ones in order', () async {
      replies['$base/packages/'] = json(200, [
        {'code': 'small', 'price_cents': 500, 'currency': 'usd', 'units': 60000, 'minutes': 10},
        {'code': 'big', 'price_cents': 2000, 'currency': 'usd', 'units': 300000, 'minutes': 50},
      ]);
      final list = await client.packages();
      expect(list.map((p) => p.code), ['small', 'big']);
      expect(list.first.priceCents, 500);
      expect(list.first.units, 60000);
      expect(list.first.minutes, 10);
      expect(seen.single.headers.value(HttpHeaders.authorizationHeader), isNull);
    });

    test('checkout sends the package and the language, returns the url', () async {
      replies['$base/checkout/'] = json(201, {'url': 'https://pay.example/session/1'});
      final url = await client.checkout('lba_tok', 'small', language: 'uz');
      expect(url, Uri.parse('https://pay.example/session/1'));
      expect(seen.single.body, {'package': 'small'});
      expect(seen.single.headers.value(HttpHeaders.acceptLanguageHeader), 'uz');
      expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer lba_tok');

      replies['$base/checkout/'] = json(503, {'error': 'checkout_unavailable'});
      expect(((await thrownBy(client.checkout('t', 'small'))) as AccountError).code, 'checkout_unavailable');
      replies['$base/checkout/'] = json(404, {'error': 'unknown_package'});
      expect(((await thrownBy(client.checkout('t', 'zzz'))) as AccountError).code, 'unknown_package');
      replies['$base/checkout/'] = json(429, {'error': 'rate_limited'});
      expect(((await thrownBy(client.checkout('t', 'small'))) as AccountError).code, 'rate_limited');
      replies['$base/checkout/'] = json(401, {'error': 'invalid_token'});
      expect(await thrownBy(client.checkout('t', 'small')), isA<AccountTokenStale>());
    });

    test('logout sends the bearer and accepts 204', () async {
      replies['$base/logout/'] = json(204, null);
      await client.logout('lba_tok');
      expect(seen.single.method, 'POST');
      expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer lba_tok');
      replies['$base/logout/'] = json(401, {'error': 'invalid_token'});
      expect(await thrownBy(client.logout('lba_tok')), isA<AccountTokenStale>());
    });

    test('a dropped connection, a hang, a refused port and bad bodies are all "network"', () async {
      replies['$base/me/'] = json(200, {'email': 'a@b.c'}); // fields missing
      expect(((await thrownBy(client.me('t'))) as AccountError).code, 'network');
      replies['$base/me/'] = json(200, 'not json');
      expect(((await thrownBy(client.me('t'))) as AccountError).code, 'network');
      replies['$base/me/'] = json(500, '<html>');
      expect(((await thrownBy(client.me('t'))) as AccountError).code, 'network');

      drop = true;
      expect(((await thrownBy(client.me('t'))) as AccountError).code, 'network');
      drop = false;
      hang = true;
      expect(((await thrownBy(client.me('t'))) as AccountError).code, 'network');

      final port = server.port;
      await server.close(force: true);
      final dead = HttpAccountClient(Uri.parse('http://127.0.0.1:$port'), timeout: const Duration(milliseconds: 500));
      expect(((await thrownBy(dead.packages())) as AccountError).code, 'network');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // for tearDown
    });

    test('errors never carry a token', () async {
      replies['$base/me/'] = json(401, {'error': 'invalid_token'});
      final e = await thrownBy(client.me('lba_secret_value'));
      expect(e.toString(), isNot(contains('lba_secret_value')));
    });
  });

  group('TokenKeeper', () {
    var clock = DateTime.utc(2026, 11, 26, 12);
    late _FakeClient fake;
    late List<TokenPair> saved;
    Future<void> Function(TokenPair)? onSave;

    TokenKeeper keeper({String? refresh = 'ref0', TokenPair? pair}) => TokenKeeper(
      client: fake,
      refreshToken: refresh,
      pair: pair,
      onRefreshed: (p) async {
        saved.add(p);
        await onSave?.call(p);
      },
      now: () => clock,
    );

    TokenPair fresh([int minutes = 15]) => TokenPair(
      accessToken: 'cur',
      refreshToken: 'ref0',
      expiresAt: clock.add(Duration(minutes: minutes)),
    );

    setUp(() {
      clock = DateTime.utc(2026, 11, 26, 12);
      fake = _FakeClient(() => clock);
      saved = [];
      onSave = null;
    });

    test('a fresh token is returned without a request', () async {
      final k = keeper(pair: fresh());
      expect(await k.accessToken(), 'cur');
      expect(fake.refreshed, isEmpty);
      expect(k.expiresAt, clock.add(const Duration(minutes: 15)));
    });

    test('under 60 s left (or no token yet) refreshes with the current refresh token', () async {
      final k = keeper(pair: fresh().copyWithExpiry(clock.add(const Duration(seconds: 59))));
      expect(await k.accessToken(), 'acc1');
      expect(fake.refreshed, ['ref0']);
      expect(saved.single.refreshToken, 'ref1');
      // the new refresh token is the one used next
      clock = clock.add(const Duration(minutes: 20));
      expect(await k.accessToken(), 'acc2');
      expect(fake.refreshed, ['ref0', 'ref1']);

      final cold = keeper();
      expect(await cold.accessToken(), 'acc3');
    });

    test('minRemaining widens the window and force refreshes a fresh token', () async {
      final k = keeper(pair: fresh(2));
      expect(await k.accessToken(minRemaining: const Duration(minutes: 3)), 'acc1');
      expect(await k.accessToken(), 'acc1');
      expect(fake.refreshed, hasLength(1));
      expect(await k.accessToken(force: true), 'acc2');
      expect(fake.refreshed, ['ref0', 'ref1']);
    });

    test('concurrent callers share one refresh and one token', () async {
      final k = keeper();
      final gate = Completer<TokenPair>();
      fake.gates.add(gate);
      final a = k.accessToken();
      final b = k.accessToken(force: true);
      final c = k.accessToken(minRemaining: const Duration(minutes: 3));
      await Future<void>.delayed(Duration.zero);
      gate.complete(fresh().copyWithExpiry(clock.add(const Duration(minutes: 15))).renamed('shared', 'refS'));
      expect(await Future.wait([a, b, c]), ['shared', 'shared', 'shared']);
      expect(fake.refreshed, hasLength(1));
      expect(saved, hasLength(1));
    });

    test('onRefreshed completes before the token is returned', () async {
      final k = keeper();
      final saving = Completer<void>();
      onSave = (_) => saving.future;
      var returned = false;
      final f = k.accessToken().then((t) {
        returned = true;
        return t;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(saved, hasLength(1));
      expect(returned, isFalse);
      saving.complete();
      expect(await f, 'acc1');
    });

    test('a failed save keeps the new pair in memory and rethrows to every caller', () async {
      final k = keeper();
      onSave = (_) async => throw const FileSystemException('keychain');
      expect(k.accessToken(), throwsA(isA<FileSystemException>()));
      await Future<void>.delayed(Duration.zero);
      onSave = null;
      // the new refresh token (ref1) is the only valid one now, and the token is still fresh
      clock = clock.add(const Duration(minutes: 20));
      expect(await k.accessToken(), 'acc2');
      expect(fake.refreshed, ['ref0', 'ref1']);
    });

    test('a failed save is retried by the next call, which returns the same token without a new refresh', () async {
      final k = keeper();
      var saves = 0;
      final failing = Completer<void>();
      onSave = (_) {
        saves++;
        return failing.future;
      };
      final a = k.accessToken();
      final b = k.accessToken();
      final ea = expectLater(a, throwsA(isA<FileSystemException>()));
      final eb = expectLater(b, throwsA(isA<FileSystemException>()));
      await Future<void>.delayed(Duration.zero);
      failing.completeError(const FileSystemException('keychain'));
      await Future.wait([ea, eb]);
      expect(saves, 1);
      expect(fake.refreshed, hasLength(1));
      // still failing: rethrown again, still unsaved
      onSave = (_) async => throw const FileSystemException('keychain');
      await expectLater(k.accessToken(), throwsA(isA<FileSystemException>()));
      onSave = null;
      expect(await k.accessToken(), 'acc1');
      expect(saved.map((p) => p.refreshToken), ['ref1', 'ref1', 'ref1']);
      expect(fake.refreshed, hasLength(1));
      // saved now: no more saving
      expect(await k.accessToken(), 'acc1');
      expect(saved, hasLength(3));
    });

    test('clear() during a refresh drops its answer: nothing stored, nothing saved', () async {
      final k = keeper(pair: fresh().copyWithExpiry(clock));
      final g = Completer<TokenPair>();
      fake.gates.add(g);
      final f = k.accessToken();
      final e = expectLater(f, throwsA(isA<AccountSignedOut>()));
      await Future<void>.delayed(Duration.zero);
      k.clear();
      g.complete(fresh().renamed('late', 'refLate'));
      await e;
      expect(saved, isEmpty);
      expect(k.expiresAt, isNull);
      await expectLater(k.accessToken(), throwsA(isA<AccountSignedOut>()));
      expect(fake.refreshed, ['ref0']);
    });

    test('adopt() during a stale refresh: the next call gets the adopted token, the stale answer is dropped', () async {
      final k = keeper();
      final g = Completer<TokenPair>();
      fake.gates.add(g);
      final stale = k.accessToken();
      final e = expectLater(stale, throwsA(isA<AccountSignedOut>()));
      await Future<void>.delayed(Duration.zero);
      k.adopt(
        TokenPair(accessToken: 'granted', refreshToken: 'refG', expiresAt: clock.add(const Duration(minutes: 15))),
      );
      expect(await k.accessToken(), 'granted');
      g.complete(fresh().renamed('late', 'refLate'));
      await e;
      expect(saved, isEmpty);
      expect(await k.accessToken(), 'granted');
      expect(fake.refreshed, ['ref0']);
    });

    test('a stale refresh finishing after a newer one started does not clear the newer one', () async {
      final k = keeper();
      final g1 = Completer<TokenPair>();
      final g2 = Completer<TokenPair>();
      fake.gates.addAll([g1, g2]);
      final stale = k.accessToken();
      final e = expectLater(stale, throwsA(isA<AccountSignedOut>()));
      await Future<void>.delayed(Duration.zero);
      k.adopt(TokenPair(accessToken: 'old', refreshToken: 'refG', expiresAt: clock)); // already due
      final newer = k.accessToken();
      await Future<void>.delayed(Duration.zero);
      expect(fake.refreshed, ['ref0', 'refG']);
      g1.complete(fresh().renamed('late', 'refLate'));
      await e;
      final joined = k.accessToken(); // must join the newer refresh, not start a third
      expect(fake.refreshed, hasLength(2));
      g2.complete(fresh().renamed('newest', 'refN'));
      expect(await Future.wait([newer, joined]), ['newest', 'newest']);
      expect(saved.single.refreshToken, 'refN');
    });

    test('no refresh token: signed out without a request', () async {
      final k = keeper(refresh: null);
      expect(k.accessToken(), throwsA(isA<AccountSignedOut>()));
      expect(fake.refreshed, isEmpty);
    });

    test('a failed refresh rethrows and leaves nothing in flight', () async {
      final k = keeper();
      fake.failure = const AccountSignedOut();
      await expectLater(k.accessToken(), throwsA(isA<AccountSignedOut>()));
      fake.failure = const AccountError('network');
      await expectLater(k.accessToken(), throwsA(isA<AccountError>()));
      fake.failure = null;
      expect(await k.accessToken(), 'acc1');
      expect(fake.refreshed, ['ref0', 'ref0', 'ref0']);
    });

    test('adopt takes a pair from the device grant; clear forgets it', () async {
      final k = keeper(refresh: null);
      k.adopt(
        TokenPair(accessToken: 'granted', refreshToken: 'refG', expiresAt: clock.add(const Duration(minutes: 15))),
      );
      expect(await k.accessToken(), 'granted');
      expect(fake.refreshed, isEmpty);
      expect(k.expiresAt, isNotNull);
      k.clear();
      expect(k.expiresAt, isNull);
      expect(k.accessToken(), throwsA(isA<AccountSignedOut>()));
    });
  });
}

extension on TokenPair {
  TokenPair copyWithExpiry(DateTime at) =>
      TokenPair(accessToken: accessToken, refreshToken: refreshToken, expiresAt: at);
  TokenPair renamed(String access, String refresh) =>
      TokenPair(accessToken: access, refreshToken: refresh, expiresAt: expiresAt);
}
