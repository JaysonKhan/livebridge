import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/live_bridge.dart';
import 'package:livebridge/bridge/models.dart';

/// The real method-channel bridge against a mocked platform side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('events', () {
    const channel = EventChannel('livebridge/test-events');
    late MockStreamHandlerEventSink? sink;
    late int listens;
    late int cancels;

    setUp(() {
      sink = null;
      listens = 0;
      cancels = 0;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, events) {
            listens++;
            sink = events;
          },
          onCancel: (_) => cancels++,
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(channel, null));
    });

    test('any number of listeners share one platform subscription; one cancelling leaves the others', () async {
      final bridge = MethodChannelLiveBridge(eventChannel: channel);
      final first = <BridgeEvent>[];
      final second = <BridgeEvent>[];
      final a = bridge.events.listen(first.add);
      final b = bridge.events.listen(second.add);
      await pumpEventQueue();
      expect(listens, 1);

      sink!.success({'type': 'balance', 'balanceUnits': 5});
      await pumpEventQueue();
      expect(first, hasLength(1));
      expect(second, hasLength(1));

      await a.cancel();
      expect(cancels, 0, reason: 'the other listener still listens');
      sink!.success({'type': 'balance', 'balanceUnits': 4});
      await pumpEventQueue();
      expect(first, hasLength(1));
      expect((second.last as BalanceEvent).balanceUnits, 4);

      await b.cancel();
      expect(cancels, 1);
    });
  });

  group('methods', () {
    const channel = MethodChannel('livebridge/test-control');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    });

    const base = StartConfig(
      gatewayUrl: 'https://own.example',
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
      outVoiceId: 'voice-out',
      inVoiceId: 'voice-in',
    );
    const secretKeys = ['accessToken', 'gatewayUrl', 'elevenlabsApiKey', 'geminiApiKey', 'connection'];
    final configs = {
      'account': base.withAuth(
        connection: ConnectionMode.account,
        gatewayUrl: 'https://hosted.example',
        accessToken: 'access-1',
      ),
      'keys': base.withAuth(
        connection: ConnectionMode.keys,
        gatewayUrl: 'https://hosted.example',
        elevenlabsApiKey: 'el-key',
        geminiApiKey: 'gm-key',
      ),
    };

    for (final MapEntry(key: name, value: config) in configs.entries) {
      test('saveSettings in $name mode sends no gateway, token, key or connection (absent, not null)', () async {
        await MethodChannelLiveBridge(control: channel).saveSettings(config);
        final call = calls.single;
        expect(call.method, 'saveSettings');
        final args = call.arguments as Map;
        for (final key in secretKeys) {
          expect(args.containsKey(key), isFalse, reason: key);
        }
        expect(args['micUid'], 'mic1');
        // Voice choices are saved when picked, under their mode's names; a Start must not write the gateway's.
        expect(args.containsKey('outVoiceId'), isFalse);
        expect(args.containsKey('inVoiceId'), isFalse);
      });
    }

    test('start sends the connection and its secrets; updateAccessToken sends the new token', () async {
      final bridge = MethodChannelLiveBridge(control: channel);
      await bridge.start(configs['keys']!);
      await bridge.updateAccessToken('access-2');
      final start = calls.first.arguments as Map;
      expect(start['connection'], 'keys');
      expect(start['elevenlabsApiKey'], 'el-key');
      expect(start['geminiApiKey'], 'gm-key');
      expect([start['outVoiceId'], start['inVoiceId']], ['voice-out', 'voice-in']);
      expect(calls.last.method, 'updateAccessToken');
      expect(calls.last.arguments, {'accessToken': 'access-2'});
    });
  });
}
