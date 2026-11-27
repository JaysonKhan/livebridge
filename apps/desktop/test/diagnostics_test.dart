import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/connection_state.dart';
import 'package:livebridge/state/diagnostics.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

// Realistic shapes of what the app holds (none of them real).
const elevenLabsKey = 'sk_3f9a1c0b7d2e4f6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e';
const geminiKey = 'AIzaSyD3x-AmPlE_kEy0123456789abcdefghijk';
const refreshToken = 'lbr_q7Zr0-vN3kP_x9LmT2bW8yC4dF6hJ1sA5eG0iK3oU7w';
const accessToken = 'lba_Zk3oU7wq7Zr0-vN3kP_x9LmT2bW8yC4dF6hJ1sA5eG0';
const staticToken = 'my-own-gateway-token';
const saidOut = 'SAID-OUT-TEXT';
const translatedOut = 'TRANSLATED-OUT-TEXT';
const saidIn = 'SAID-IN-TEXT';
const translatedIn = 'TRANSLATED-IN-TEXT';
const partial = 'PARTIAL-SPEECH-TEXT';

String logOf(ProviderContainer c) => c.read(diagnosticLogProvider).text();

/// The account session's token timer waits forever instead of real seconds.
Future<void> _hang(Duration _) => Completer<void>().future;

/// Starts a session in the saved connection mode and sends everything that could carry speech or a secret.
/// Every install also keeps the own gateway's token it was set up with (the owner's own install does), so the app
/// holds it in every mode.
Future<String> exercise(WidgetTester tester, Map<String, Object?> settings) async {
  final bridge = FakeLiveBridge()..settings = {'accessToken': staticToken, ...settings};
  final c = await pumpApp(tester, bridge: bridge, overrides: [delayProvider.overrideWithValue(_hang)]);
  await c.read(connectionProvider.notifier).start(c.read(setupProvider).toConfig(c.read(connectionProvider).mode));
  await tester.pumpAndSettle();
  await push(const StateEvent(state: EngineState.active, outReady: true, message: 'retry with $staticToken'));
  await pushFinishedTurn(Direction.out, 1, saidOut, translatedOut);
  await pushFinishedTurn(Direction.incoming, 1, saidIn, translatedIn);
  await push(cap(Direction.out, 2, CaptionKind.partial, partial));
  await push(
    const ErrorEvent(code: 'provider_error', message: 'refused $elevenLabsKey $geminiKey $refreshToken $staticToken'),
  );
  bridge.savePreferencesError = PlatformException(code: 'settings_failed', message: 'could not store $refreshToken');
  c.read(setupProvider.notifier).setUiLanguage('ru');
  await tester.pumpAndSettle();
  c
      .read(diagnosticLogProvider)
      .add(
        'exception',
        describeError(
          const FormatException('bad body {"access_token":"$accessToken"} $staticToken'),
          StackTrace.current,
          context: 'flutter',
        ),
      );
  return logOf(c);
}

void expectNothingSaidOrSecret(String log) {
  for (final value in [
    saidOut,
    translatedOut,
    saidIn,
    translatedIn,
    partial,
    elevenLabsKey,
    geminiKey,
    refreshToken,
    accessToken,
    staticToken,
    // What the fake site answers to a refresh.
    'access-1',
    'refresh-1',
    'SECRETQUERY',
  ]) {
    expect(log, isNot(contains(value)), reason: value);
  }
}

void main() {
  test('describeError names the type once and keeps no home folder', () {
    final stack = StackTrace.fromString(
      '#0      Foo.bar (file:///Users/someone/app/lib/x.dart:12:3)\n'
      '#1      main (package:livebridge/main.dart:5:7)\n',
    );
    final text = describeError(const FormatException('bad'), stack, context: 'flutter');
    expect(text, 'flutter: FormatException: bad @ x.dart:12:3 < package:livebridge/main.dart:5:7');
    expect(describeError('plain', null, context: 'platform'), 'platform: String: plain');
  });

  testWidgets('logs the app, its versions and the statistics choice', (tester) async {
    final bridge = FakeLiveBridge()
      ..telemetry = const TelemetryStatus(enabled: true, appVersion: '1.2.1+4', osVersion: 'macOS 26.6.2');
    final log = logOf(await pumpApp(tester, bridge: bridge));
    expect(log, contains('app       version=1.2.1+4 os=macOS 26.6.2'));
    expect(log, contains('arch='));
    expect(log, contains('statistics=on'));
  });

  testWidgets('logs state, errors, timings and device changes', (tester) async {
    final c = await pumpApp(tester);
    await push(const StateEvent(state: EngineState.connecting));
    await push(readyState);
    await push(
      const MetricsEvent(
        direction: Direction.out,
        turnId: 3,
        e2eMs: 1350,
        sttCommitMs: 302,
        translateFirstMs: 690,
        translateTotalMs: 760,
        ttsFirstAudioMs: 238,
        ttsTotalMs: 900,
        audioMs: 2480,
        model: 'gemini-3.5-flash-lite',
      ),
    );
    await push(const ErrorEvent(code: 'gateway_error', message: 'upstream said no', direction: 'out'));
    fake.devices = [
      ...FakeLiveBridge.defaultDevices(),
      const AudioDevice(
        uid: 'usb1',
        name: 'USB Headset',
        inputChannels: 1,
        outputChannels: 2,
        transport: 'usb',
        sampleRate: 44100,
      ),
    ];
    await push(const DevicesChangedEvent());
    await tester.pumpAndSettle();
    final log = logOf(c);
    expect(log, contains('state     connecting'));
    expect(log, contains('state     ready out in'));
    expect(
      log,
      contains(
        'turn      out #3 e2e=1350 stt=302 translate=690/760 tts=238/900 audio=2480 model=gemini-3.5-flash-lite',
      ),
    );
    expect(log, contains('error     gateway_error out: upstream said no'));
    expect(log, contains('devices   changed'));
    expect(log, contains('device    "USB Headset" in=1 out=2 44100 Hz usb'));
  });

  testWidgets('logs the chosen devices with transport and rate', (tester) async {
    final log = logOf(await pumpApp(tester));
    expect(log, contains('selection mic "MacBook Microphone" in=1 out=0 48000 Hz builtin default-in'));
    expect(log, contains('selection headphones "AirPods" in=0 out=2 48000 Hz bluetooth default-out'));
    expect(log, contains('selection virtual-mic "BlackHole 2ch"'));
    expect(log, contains('selection mode=captions uz→en commit=manual sources=[]'));
  });

  testWidgets('describeDevices carries the choice and the list, without device ids', (tester) async {
    final c = await pumpApp(tester);
    c.read(setupProvider.notifier).toggleSource(100, true);
    final d = describeDevices(c.read(setupProvider));
    expect((d['mic']! as Map)['name'], 'MacBook Microphone');
    expect((d['headphones']! as Map)['transport'], 'bluetooth');
    expect((d['virtualMic']! as Map)['name'], 'BlackHole 2ch');
    expect(d['sources'], ['zoom.us']);
    expect([d['mode'], d['myLang'], d['targetLang'], d['outCommit']], ['captions', 'uz', 'en', 'manual']);
    expect((d['devices']! as List).length, 3);
    final encoded = jsonEncode(d);
    for (final uid in ['mic1', 'hp1', 'bh2']) {
      expect(encoded, isNot(contains(uid)));
    }
  });

  group('never holds what was said, keys or tokens', () {
    testWidgets('account mode', (tester) async {
      final log = await exercise(tester, {'connectionMode': 'account', 'accountRefreshToken': refreshToken});
      expectNothingSaidOrSecret(log);
      expect(log, contains('person@example.com'));
      expect(log, contains('bridge.jaysonkhan.com'));
      expect(log, contains('[secret]'));
    });

    testWidgets('own keys', (tester) async {
      final log = await exercise(tester, {
        'connectionMode': 'keys',
        'elevenlabsApiKey': elevenLabsKey,
        'geminiApiKey': geminiKey,
      });
      expectNothingSaidOrSecret(log);
      expect(log, isNot(contains('email=')));
      expect(log, contains('bridge.jaysonkhan.com'));
    });

    testWidgets('own gateway', (tester) async {
      final log = await exercise(tester, {
        'connectionMode': 'gateway',
        'accessToken': staticToken,
        'gatewayUrl': 'https://gw.example.test/bridge?key=SECRETQUERY',
      });
      expectNothingSaidOrSecret(log);
      expect(log, contains('gw.example.test'));
    });
  });

  testWidgets('the e-mail is logged only in account mode', (tester) async {
    final bridge = FakeLiveBridge()..settings = {'connectionMode': 'account', 'accountRefreshToken': refreshToken};
    final c = await pumpApp(tester, bridge: bridge, overrides: [delayProvider.overrideWithValue(_hang)]);
    expect(logOf(c), contains('connection mode=account email=person@example.com'));
    await c.read(connectionProvider.notifier).saveKeys(elevenLabsKey, geminiKey);
    await tester.pumpAndSettle();
    final lines = logOf(c).split('\n').where((l) => l.contains(' connection ')).toList();
    expect(lines.last, contains('mode=keys'));
    expect(lines.last, isNot(contains('email=')));
  });
}
