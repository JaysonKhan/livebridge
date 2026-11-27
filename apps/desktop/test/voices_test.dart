import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/bridge/voices_client.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_live_bridge.dart';

/// Answers what the test tells it to, and remembers every call.
class _RecordingClient implements VoicesClient {
  final List<({String url, VoicesAuth auth})> calls = [];
  VoicesFailure? failure;

  @override
  Future<List<Voice>> list({required String gatewayUrl, required VoicesAuth auth}) async {
    calls.add((url: gatewayUrl, auth: auth));
    if (failure != null) throw VoicesException(failure!);
    return const [Voice(id: 'fakevoice0000000001', name: 'Fake Aria')];
  }
}

void main() {
  group('HttpVoicesClient', () {
    late HttpServer server;
    late String base;
    late int status;
    late String body;
    late bool hang;
    final requests = <({String method, String path, String? authorization, String? providerKey})>[];

    setUp(() async {
      status = 200;
      body = '{"voices":[]}';
      hang = false;
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        requests.add((
          method: request.method,
          path: request.uri.path,
          authorization: request.headers.value(HttpHeaders.authorizationHeader),
          providerKey: request.headers.value('X-ElevenLabs-Api-Key'),
        ));
        if (hang) return;
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<VoicesFailure?> failureOf(Future<List<Voice>> listing) async {
      try {
        await listing;
        return null;
      } on VoicesException catch (e) {
        return e.failure;
      }
    }

    test('reports a failure with its path, status and code only', () async {
      final failures = <(String, int?, String)>[];
      final client = HttpVoicesClient(onFailure: (what, status, code) => failures.add((what, status, code)));
      status = 401;
      body = '{"error":"invalid_key","detail":"sk_body_secret"}';
      await failureOf(client.list(gatewayUrl: base, auth: const ProviderKeyAuth('el-key')));
      status = 200;
      body = 'not json';
      await failureOf(client.list(gatewayUrl: base, auth: const BearerAuth('t')));
      await server.close(force: true);
      await failureOf(client.list(gatewayUrl: base, auth: const BearerAuth('t')));
      expect(failures, [
        ('v1/voices', 401, 'invalid_key'),
        ('v1/voices', 200, 'bad_body'),
        ('v1/voices', null, 'network'),
      ]);
    });

    test('lists voices with the bearer token', () async {
      body = jsonEncode({
        'voices': [
          {
            'id': 'fakevoice0000000001',
            'name': 'Fake Aria',
            'gender': 'female',
            'age': 'young',
            'accent': 'american',
            'language': 'en',
            'use_case': 'conversational',
            'description': 'Warm and clear',
            'category': 'premade',
            'preview_url': 'https://samples.example/aria.mp3',
          },
          {'name': 'No id, so not a voice'},
          {
            'id': 'fakevoice0000000003',
            'name': 'Fake Dilnoza',
            'previews': {'uz': 'https://samples.example/dilnoza-uz.mp3', 'broken': 5},
          },
          'not even a map',
        ],
      });
      // A trailing slash on the saved address must not change the route.
      final voices = await HttpVoicesClient().list(gatewayUrl: '$base/', auth: const BearerAuth('secret-token'));

      expect(requests.single, (
        method: 'GET',
        path: '/v1/voices',
        authorization: 'Bearer secret-token',
        providerKey: null,
      ));
      expect(voices.map((v) => v.id), ['fakevoice0000000001', 'fakevoice0000000003']);
      final aria = voices.first;
      expect(
        [aria.name, aria.gender, aria.age, aria.accent, aria.language, aria.useCase, aria.description, aria.category],
        ['Fake Aria', 'female', 'young', 'american', 'en', 'conversational', 'Warm and clear', 'premade'],
      );
      expect(aria.previewUrl, 'https://samples.example/aria.mp3');
      expect(aria.previews, isEmpty);
      expect(voices.last.previews, {'uz': 'https://samples.example/dilnoza-uz.mp3'});
      expect(voices.last.previewUrl, isNull);
    });

    test('the ElevenLabs key goes in its own header and no bearer token is sent', () async {
      await HttpVoicesClient().list(gatewayUrl: base, auth: const ProviderKeyAuth('el-key'));
      expect(requests.single, (method: 'GET', path: '/v1/voices', authorization: null, providerKey: 'el-key'));
    });

    test('keeps a path the gateway address carries', () async {
      await HttpVoicesClient().list(gatewayUrl: '$base/bridge', auth: const BearerAuth('t'));
      expect(requests.single.path, '/bridge/v1/voices');
    });

    test('maps failures', () async {
      Future<VoicesFailure?> answering(int code, [String text = '{"error":"x"}']) {
        status = code;
        body = text;
        return failureOf(HttpVoicesClient().list(gatewayUrl: base, auth: const BearerAuth('t')));
      }

      expect(await answering(401), VoicesFailure.unauthorized);
      expect(await answering(401, '{"error":"invalid_token"}'), VoicesFailure.unauthorized);
      expect(await answering(401, '{"error":"invalid_key"}'), VoicesFailure.invalidKey);
      expect(await answering(401, '<html>nope</html>'), VoicesFailure.unauthorized);
      expect(await answering(404), VoicesFailure.unsupported);
      expect(await answering(502, '{"error":"voices_unavailable"}'), VoicesFailure.unavailable);
      expect(await answering(429), VoicesFailure.unavailable);
      // A 200 that is not a voice list (a proxy's page, say) is not a list either.
      expect(await answering(200, '<html>hello</html>'), VoicesFailure.unavailable);
      expect(await answering(200, '{"voices":"none"}'), VoicesFailure.unavailable);

      await server.close(force: true);
      expect(
        await failureOf(HttpVoicesClient().list(gatewayUrl: base, auth: const BearerAuth('t'))),
        VoicesFailure.network,
      );
      expect(
        await failureOf(HttpVoicesClient().list(gatewayUrl: 'not an address', auth: const BearerAuth('t'))),
        VoicesFailure.network,
      );
    });

    test('a gateway that never answers is a network failure after the timeout', () async {
      hang = true;
      final client = HttpVoicesClient(timeout: const Duration(milliseconds: 150));
      expect(await failureOf(client.list(gatewayUrl: base, auth: const BearerAuth('t'))), VoicesFailure.network);
    });
  });

  group('Voice', () {
    test('fromJson needs an id and a name', () {
      expect(Voice.fromJson({'id': 'fakevoice0000000001', 'name': 'Fake Aria'})?.name, 'Fake Aria');
      expect(Voice.fromJson({'id': 'fakevoice0000000001'}), isNull);
      expect(Voice.fromJson({'name': 'Fake Aria'}), isNull);
      expect(Voice.fromJson({'id': '', 'name': 'Fake Aria'}), isNull);
      expect(Voice.fromJson({'id': 7, 'name': 'Fake Aria'}), isNull);
      expect(Voice.fromJson('text'), isNull);
      expect(Voice.fromJson(null), isNull);
    });

    test('sampleFor prefers the language\'s own sample', () {
      const voice = Voice(
        id: 'fakevoice0000000001',
        name: 'Fake Aria',
        previewUrl: 'https://samples.example/general.mp3',
        previews: {'uz': 'https://samples.example/uz.mp3'},
      );
      expect(voice.sampleFor('uz'), 'https://samples.example/uz.mp3');
      expect(voice.sampleFor('ru'), 'https://samples.example/general.mp3');
      expect(const Voice(id: 'fakevoice0000000002', name: 'Fake Bruno').sampleFor('uz'), isNull);
    });
  });

  group('voicesProvider', () {
    const key = (mode: ConnectionMode.gateway, url: 'http://gateway');

    /// A container in the own-gateway mode with the address and token typed in.
    Future<ProviderContainer> gatewayContainer(_RecordingClient client) async {
      final bridge = FakeLiveBridge()..settings = {'connectionMode': 'gateway'};
      final container = ProviderContainer(
        overrides: [bridgeProvider.overrideWithValue(bridge), voicesClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      addTearDown(bridge.dispose);
      container.listen(connectionProvider, (_, _) {});
      container.read(setupProvider.notifier)
        ..setGatewayUrl('http://gateway')
        ..setAccessToken('tok');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final subscription = container.listen(voicesProvider(key), (_, _) {});
      addTearDown(subscription.close);
      return container;
    }

    test('asks the client with the gateway address and token, once per mode', () async {
      final client = _RecordingClient();
      final container = await gatewayContainer(client);

      expect((await container.read(voicesProvider(key).future)).single.name, 'Fake Aria');
      await container.read(voicesProvider(key).future);
      expect(client.calls, [(url: 'http://gateway', auth: const BearerAuth('tok'))]);
    });

    test('a failure is reported as it is and not retried behind the picker\'s back', () async {
      final client = _RecordingClient()..failure = VoicesFailure.unsupported;
      final container = await gatewayContainer(client);

      await expectLater(
        container.read(voicesProvider(key).future),
        throwsA(isA<VoicesException>().having((e) => e.failure, 'failure', VoicesFailure.unsupported)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(client.calls.length, 1);

      // Asking again is the picker's Retry.
      client.failure = null;
      container.invalidate(voicesProvider(key));
      expect((await container.read(voicesProvider(key).future)).single.name, 'Fake Aria');
      expect(client.calls.length, 2);
    });
  });
}
