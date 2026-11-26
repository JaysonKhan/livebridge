import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/session_state.dart';
import 'package:livebridge/state/setup_state.dart';

void main() {
  group('BridgeEvent.fromMap', () {
    test('parses a state event', () {
      final e = BridgeEvent.fromMap({'type': 'state', 'state': 'ready', 'outReady': true, 'mock': true});
      expect(e, isA<StateEvent>());
      final s = e as StateEvent;
      expect(s.state, EngineState.ready);
      expect(s.outReady, isTrue);
      expect(s.inReady, isFalse);
      expect(s.mock, isTrue);
    });

    test('parses caption, metrics and error events', () {
      final c = BridgeEvent.fromMap({'type': 'caption', 'direction': 'in', 'turnId': 3, 'kind': 'final', 'text': 'Hi'});
      expect(c, isA<CaptionEvent>());
      expect((c as CaptionEvent).direction, Direction.incoming);
      expect(c.kind, CaptionKind.finalText);

      final m = BridgeEvent.fromMap({'type': 'metrics', 'direction': 'out', 'turnId': 1, 'e2eMs': 900});
      expect((m as MetricsEvent).e2eMs, 900);

      final err = BridgeEvent.fromMap({'type': 'error', 'code': 'x', 'message': 'boom', 'fatal': true});
      expect((err as ErrorEvent).fatal, isTrue);
    });

    test('ignores unknown or malformed events', () {
      expect(BridgeEvent.fromMap({'type': 'nope'}), isNull);
      expect(BridgeEvent.fromMap({'type': 'state', 'state': 'weird'}), isNull);
      expect(BridgeEvent.fromMap({'type': 'caption', 'direction': 'out', 'kind': 'partial'}), isNull);
    });
  });

  group('virtual cables', () {
    const blackHole2 = AudioDevice(uid: 'bh2', name: 'BlackHole 2ch', inputChannels: 2, outputChannels: 2);
    const blackHole16 = AudioDevice(uid: 'bh16', name: 'BlackHole 16ch', inputChannels: 16, outputChannels: 16);
    const cableOutput = AudioDevice(
      uid: 'co',
      name: 'CABLE Output (VB-Audio Virtual Cable)',
      inputChannels: 2,
      transport: 'virtual',
    );
    const cableInput = AudioDevice(
      uid: 'ci',
      name: 'CABLE Input (VB-Audio Virtual Cable)',
      outputChannels: 2,
      transport: 'virtual',
    );
    const voicemeeter = AudioDevice(
      uid: 'vm',
      name: 'VoiceMeeter Input (VB-Audio VoiceMeeter VAIO)',
      outputChannels: 8,
      transport: 'virtual',
    );
    const realtek = AudioDevice(uid: 'rt', name: 'Microphone (Realtek(R) Audio)', inputChannels: 2);

    test('BlackHole and both VB-CABLE endpoints are cables; other virtual devices and real ones are not', () {
      for (final d in [blackHole2, blackHole16, cableOutput, cableInput]) {
        expect(d.isVirtualCable, isTrue, reason: d.name);
        expect(d.isVirtual, isTrue, reason: d.name);
      }
      expect(voicemeeter.isVirtualCable, isFalse);
      expect(voicemeeter.isVirtual, isTrue);
      expect(realtek.isVirtualCable, isFalse);
      expect(realtek.isVirtual, isFalse);
    });

    test('the virtual mic takes output: CABLE Input on Windows, BlackHole 2ch first on macOS', () {
      expect(const SetupState(devices: [cableOutput, cableInput]).virtualMic?.uid, 'ci');
      expect(const SetupState(devices: [cableOutput, realtek]).virtualMic, isNull);
      expect(const SetupState(devices: [blackHole16, blackHole2]).virtualMic?.uid, 'bh2');
      expect(const SetupState(devices: [blackHole16]).virtualMic?.uid, 'bh16');
      expect(const SetupState(devices: [voicemeeter, realtek]).virtualMic, isNull);
    });
  });

  test('StartConfig.toMap uses the contract keys and wire values', () {
    const c = StartConfig(
      gatewayUrl: 'http://x',
      accessToken: 't',
      micUid: 'm',
      headphonesUid: 'h',
      virtualMicUid: null,
      sourcePids: [1],
      myLang: 'tr',
      targetLang: 'ru',
      mode: SessionMode.bidirectional,
      outCommit: OutCommit.turnPrediction,
      translationModel: null,
      outVoiceId: 'voiceChosenOut01',
    );
    expect(c.toMap(), {
      'gatewayUrl': 'http://x',
      'accessToken': 't',
      'micUid': 'm',
      'headphonesUid': 'h',
      'virtualMicUid': null,
      'sourcePids': [1],
      'myLang': 'tr',
      'targetLang': 'ru',
      'mode': 'bidirectional',
      'outCommit': 'turn_prediction',
      'translationModel': null,
      'outVoiceId': 'voiceChosenOut01',
      'inVoiceId': null,
      'connection': 'token',
      'elevenlabsApiKey': null,
      'geminiApiKey': null,
    });
  });

  test('a skipped caption event carries its reason and finishes the turn without a translation', () {
    final e = BridgeEvent.fromMap({
      'type': 'caption',
      'direction': 'out',
      'turnId': 2,
      'kind': 'skipped',
      'text': '',
      'reason': 'echo',
    });
    expect(e, isA<CaptionEvent>());
    expect((e as CaptionEvent).skipReason, SkipReason.echo);

    var turns = applyCaption(
      const [],
      const CaptionEvent(
        direction: Direction.out,
        turnId: 2,
        kind: CaptionKind.finalText,
        text: 'What about those projects?',
      ),
    );
    expect(turns.single.isLive, isTrue);
    turns = applyCaption(
      turns,
      const CaptionEvent(
        direction: Direction.out,
        turnId: 2,
        kind: CaptionKind.skipped,
        text: '',
        skipReason: SkipReason.sameLanguage,
      ),
    );
    expect(turns.single.skipped, SkipReason.sameLanguage);
    expect(turns.single.isLive, isFalse);
    expect(turns.single.original, 'What about those projects?');
    expect(turns.single.translationFinal, isFalse);
  });

  test('applyCaption: partial replaces, final commits, deltas append, translation final replaces', () {
    CaptionEvent ev(CaptionKind k, String t) => CaptionEvent(direction: Direction.out, turnId: 1, kind: k, text: t);
    var turns = <CaptionTurn>[];
    turns = applyCaption(turns, ev(CaptionKind.partial, 'hel'));
    turns = applyCaption(turns, ev(CaptionKind.partial, 'hello wor'));
    expect(turns.single.original, 'hello wor');
    expect(turns.single.originalFinal, isFalse);
    turns = applyCaption(turns, ev(CaptionKind.finalText, 'hello world'));
    turns = applyCaption(turns, ev(CaptionKind.partial, 'late partial'));
    expect(turns.single.original, 'hello world');
    turns = applyCaption(turns, ev(CaptionKind.translationDelta, 'Salom'));
    turns = applyCaption(turns, ev(CaptionKind.translationDelta, ' dunyo'));
    expect(turns.single.translation, 'Salom dunyo');
    turns = applyCaption(turns, ev(CaptionKind.translationFinal, 'Salom, dunyo!'));
    turns = applyCaption(turns, ev(CaptionKind.translationDelta, ' late'));
    expect(turns.single.translation, 'Salom, dunyo!');
    expect(turns.single.isLive, isFalse);
  });
}
