import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/route_check.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/consent_dialog.dart';
import 'package:livebridge/ui/setup_panel.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

void main() {
  group('unsafe routes', () {
    testWidgets('safe defaults enable Start once a token is entered', (tester) async {
      await pumpApp(tester);
      expect(startEnabled(), isFalse);
      expect(find.textContaining('Enter the access token'), findsOneWidget);
      await fillToken();
      expect(startEnabled(), isTrue);
    });

    testWidgets('microphone equal to the virtual mic is refused', (tester) async {
      final c = await pumpApp(tester);
      await fillToken();
      c.read(setupProvider.notifier).setMic('bh2');
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.textContaining('same device as the virtual microphone'), findsOneWidget);
    });

    testWidgets('virtual headphones are refused', (tester) async {
      final c = await pumpApp(tester);
      await fillToken();
      c.read(setupProvider.notifier).setHeadphones('bh2');
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.textContaining('headphones are a virtual device'), findsOneWidget);
    });

    testWidgets('bidirectional mode without BlackHole is refused', (tester) async {
      final c = await pumpApp(tester, bridge: FakeLiveBridge(devices: [FakeLiveBridge.mic, FakeLiveBridge.headphones]));
      await fillToken();
      await tester.tap(find.text('Bidirectional speech'));
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.textContaining('Bidirectional speech needs a virtual microphone'), findsOneWidget);
      c.read(setupProvider.notifier).setMode(SessionMode.captions);
      await tester.pump();
      expect(startEnabled(), isTrue);
    });

    testWidgets('bidirectional mode with BlackHole is allowed', (tester) async {
      await pumpApp(tester);
      await fillToken();
      await tester.tap(find.text('Bidirectional speech'));
      await tester.pump();
      expect(startEnabled(), isTrue);
    });

    testWidgets('incoming mode needs a meeting source', (tester) async {
      await pumpApp(tester);
      await fillToken();
      await tester.tap(find.text('Incoming audio'));
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.textContaining('at least one meeting source'), findsOneWidget);
      await tester.tap(find.text('zoom.us'));
      await tester.pump();
      expect(startEnabled(), isTrue);
    });

    testWidgets('BlackHole-missing notice shows only when no BlackHole device is listed', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge(devices: [FakeLiveBridge.mic, FakeLiveBridge.headphones]));
      expect(find.text(en.blackHoleMissingNotice), findsOneWidget);
      expect(find.textContaining(blackHoleInstallHint), findsWidgets);
    });

    testWidgets('no notice when BlackHole is present', (tester) async {
      await pumpApp(tester);
      expect(find.text(en.blackHoleMissingNotice), findsNothing);
      expect(find.textContaining('Virtual microphone: BlackHole 2ch'), findsOneWidget);
    });
  });

  group('consent gate', () {
    testWidgets('Start opens the dialog; start is only called after the checkbox and Confirm', (tester) async {
      await pumpApp(tester);
      await fillToken();
      await tester.tap(find.text('Uzbek ↔ Russian'));
      await tester.tap(find.text('Incoming audio'));
      await tester.tap(find.text('zoom.us'));
      await tester.enterText(find.byKey(const Key('translation-model')), 'gpt-x');
      await tester.pump();

      await tester.tap(startButton);
      await tester.pumpAndSettle();
      expect(find.text(consentTextEn), findsOneWidget);
      expect(find.text(consentTextRu), findsOneWidget);
      expect(find.text('Copy English'), findsOneWidget);
      expect(find.text('Copy Russian'), findsOneWidget);
      FilledButton confirm() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm'));
      expect(confirm().onPressed, isNull);
      expect(fake.calls, isNot(contains('start')));

      await tester.tap(find.text(en.consentCheckbox));
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      expect(fake.calls, isNot(contains('start')));

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      final saveAt = fake.calls.indexOf('saveSettings');
      expect(saveAt, greaterThanOrEqualTo(0));
      expect(fake.calls.indexOf('start'), greaterThan(saveAt));
      final cfg = fake.startedWith!;
      expect(cfg.gatewayUrl, 'http://127.0.0.1:8201');
      expect(cfg.accessToken, 'secret-token');
      expect(cfg.micUid, 'mic1');
      expect(cfg.headphonesUid, 'hp1');
      expect(cfg.virtualMicUid, isNull);
      expect(cfg.sourcePids, [100]);
      expect(cfg.targetLang, TargetLang.ru);
      expect(cfg.mode, SessionMode.incoming);
      expect(cfg.outCommit, OutCommit.manual);
      expect(cfg.translationModel, 'gpt-x');
      expect(fake.savedWith, same(cfg));
    });

    testWidgets('bidirectional start sends the BlackHole uid', (tester) async {
      await pumpApp(tester);
      await fillToken();
      await tester.tap(find.text('Bidirectional speech'));
      await tester.pump();
      await tester.tap(startButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.consentCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(fake.startedWith!.virtualMicUid, 'bh2');
      expect(fake.startedWith!.mode, SessionMode.bidirectional);
    });

    testWidgets('cancelling the dialog never starts', (tester) async {
      await pumpApp(tester);
      await fillToken();
      await tester.tap(startButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.calls, isNot(contains('start')));
      expect(fake.calls, isNot(contains('saveSettings')));
    });
  });

  group('push-to-talk', () {
    testWidgets('the button sends exactly one pttDown and one pttUp', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('ptt-button'))));
      await tester.pump();
      expect(fake.count('pttDown'), 1);
      expect(fake.count('pttUp'), 0);
      await gesture.up();
      await tester.pump();
      expect(fake.count('pttDown'), 1);
      expect(fake.count('pttUp'), 1);
    });

    testWidgets('Space sends one down and one up, ignoring key repeats', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.count('pttDown'), 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.count('pttDown'), 1);
      expect(fake.count('pttUp'), 1);
    });

    testWidgets('nothing is sent when the session is not ready', (tester) async {
      await pumpApp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('ptt-button'))));
      await gesture.up();
      await push(const StateEvent(state: EngineState.connecting));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.calls.where((c) => c.startsWith('ptt')), isEmpty);
    });

    testWidgets('nothing is sent when the turn mode is automatic', (tester) async {
      final c = await pumpApp(tester);
      c.read(setupProvider.notifier).setOutCommit(OutCommit.vad);
      await push(readyState);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.calls.where((c) => c.startsWith('ptt')), isEmpty);
    });

    testWidgets('nothing is sent while a text field is focused', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('gateway-url')));
      await tester.pump();
      await push(readyState);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.calls.where((c) => c.startsWith('ptt')), isEmpty);
    });
  });

  group('panic', () {
    testWidgets('the Panic button calls panic and is disabled when idle', (tester) async {
      await pumpApp(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('panic-button'))).onPressed, isNull);
      await push(readyState);
      await tester.tap(find.byKey(const Key('panic-button')));
      await tester.pump();
      expect(fake.count('panic'), 1);
    });

    testWidgets('Escape triggers panic only during a session', (tester) async {
      await pumpApp(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fake.count('panic'), 0);
      await push(const StateEvent(state: EngineState.active, outReady: true, capturing: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fake.count('panic'), 1);
    });
  });

  group('captions', () {
    String? laneText(String dir) {
      final texts = tt.widgetList<Text>(find.descendant(of: find.byKey(Key('lane-$dir')), matching: find.byType(Text)));
      return texts.map((t) => t.data).join('|');
    }

    testWidgets('partial, final, translation deltas and final render in the right lane', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      expect(find.text('You → them'), findsOneWidget);
      expect(find.text('Them → you'), findsOneWidget);

      await push(cap(Direction.out, 1, CaptionKind.partial, 'salom'));
      expect(laneText('out'), contains('salom'));
      await push(cap(Direction.out, 1, CaptionKind.partial, 'salom dunyo'));
      expect(laneText('out'), contains('salom dunyo'));
      expect(laneText('out'), isNot(contains('salom|')));
      await push(cap(Direction.out, 1, CaptionKind.finalText, 'Salom, dunyo'));
      await push(cap(Direction.out, 1, CaptionKind.translationDelta, 'Hello'));
      await push(cap(Direction.out, 1, CaptionKind.translationDelta, ' world'));
      expect(
        find.descendant(of: find.byKey(const Key('lane-out')), matching: find.text('Hello world')),
        findsOneWidget,
      );
      await push(cap(Direction.out, 1, CaptionKind.translationFinal, 'Hello, world!'));
      expect(laneText('out'), contains('Salom, dunyo'));
      expect(laneText('out'), contains('Hello, world!'));
      expect(laneText('out'), isNot(contains('Hello world')));

      // The in lane is untouched by out events, and vice versa.
      expect(laneText('incoming'), 'Them → you|No captions yet');
      await push(cap(Direction.incoming, 1, CaptionKind.finalText, 'How are you?'));
      await push(cap(Direction.incoming, 1, CaptionKind.translationFinal, 'Qalaysiz?'));
      expect(laneText('incoming'), contains('How are you?'));
      expect(laneText('incoming'), contains('Qalaysiz?'));
      expect(laneText('out'), isNot(contains('How are you?')));
      expect(laneText('out'), isNot(contains('Qalaysiz?')));
    });

    testWidgets('a skipped turn keeps its caption, says why, and offers no rating', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await push(cap(Direction.out, 1, CaptionKind.finalText, 'What about those projects?'));
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await push(
        const CaptionEvent(
          direction: Direction.out,
          turnId: 1,
          kind: CaptionKind.skipped,
          text: '',
          skipReason: SkipReason.sameLanguage,
        ),
      );
      expect(laneText('out'), contains('What about those projects?'));
      expect(find.byKey(const Key('skipped-out-1')), findsOneWidget);
      expect(find.text('Not translated — already in the target language'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byKey(const Key('rate-good-out-1')), findsNothing);

      await push(cap(Direction.incoming, 1, CaptionKind.finalText, 'How much does it cost?'));
      await push(
        const CaptionEvent(
          direction: Direction.incoming,
          turnId: 1,
          kind: CaptionKind.skipped,
          text: '',
          skipReason: SkipReason.echo,
        ),
      );
      expect(find.text('Ignored — our own translated speech came back (echo)'), findsOneWidget);
    });

    testWidgets('original and translated lines can be hidden and the font size changed', (tester) async {
      final c = await pumpApp(tester);
      await push(cap(Direction.out, 1, CaptionKind.finalText, 'Salom'));
      await push(cap(Direction.out, 1, CaptionKind.translationFinal, 'Hello'));
      await tester.tap(find.text('Show original'));
      await tester.pump();
      expect(laneText('out'), isNot(contains('Salom')));
      expect(laneText('out'), contains('Hello'));
      await tester.tap(find.text('Show translated'));
      await tester.pump();
      expect(laneText('out'), isNot(contains('Hello')));

      expect(c.read(setupProvider).captionFontSize, 18);
      await tester.tap(find.byTooltip('Larger captions'));
      await tester.tap(find.byTooltip('Larger captions'));
      await tester.tap(find.byTooltip('Smaller captions'));
      await tester.pump();
      expect(c.read(setupProvider).captionFontSize, 20);
    });
  });

  group('status and banners', () {
    testWidgets('mock and bypass banners follow state events', (tester) async {
      await pumpApp(tester);
      expect(find.text(en.mockBanner), findsNothing);
      expect(find.text(en.bypassBanner), findsNothing);
      await push(const StateEvent(state: EngineState.ready, mock: true, bypass: true));
      expect(find.text(en.mockBanner), findsOneWidget);
      expect(find.text(en.bypassBanner), findsOneWidget);
      await push(const StateEvent(state: EngineState.ready));
      expect(find.text(en.mockBanner), findsNothing);
      expect(find.text(en.bypassBanner), findsNothing);
    });

    testWidgets('OUT and IN readiness reflect the event flags', (tester) async {
      await pumpApp(tester);
      expect(find.text('OUT: not ready'), findsOneWidget);
      expect(find.text('IN: not ready'), findsOneWidget);
      await push(const StateEvent(state: EngineState.connecting));
      expect(find.text('State: Connecting'), findsOneWidget);
      expect(find.text('OUT: not ready'), findsOneWidget);
      await push(const StateEvent(state: EngineState.ready, outReady: true));
      expect(find.text('State: Ready'), findsOneWidget);
      expect(find.text('OUT: ready'), findsOneWidget);
      expect(find.text('IN: not ready'), findsOneWidget);
      await push(const StateEvent(state: EngineState.degraded, inReady: true));
      expect(find.text('State: Degraded'), findsOneWidget);
      expect(find.text('OUT: not ready'), findsOneWidget);
      expect(find.text('IN: ready'), findsOneWidget);
    });

    testWidgets('Capturing shows when capturing or active', (tester) async {
      await pumpApp(tester);
      expect(find.text('Capturing'), findsNothing);
      await push(const StateEvent(state: EngineState.ready, capturing: true));
      expect(find.text('Capturing'), findsOneWidget);
      await push(const StateEvent(state: EngineState.ready));
      expect(find.text('Capturing'), findsNothing);
      await push(const StateEvent(state: EngineState.active));
      expect(find.text('Capturing'), findsOneWidget);
    });

    testWidgets('latency shows the latest e2e with a stage breakdown tooltip', (tester) async {
      await pumpApp(tester);
      expect(find.text('Latency: —'), findsOneWidget);
      await push(const MetricsEvent(direction: Direction.out, e2eMs: 842, sttCommitMs: 120, ttsFirstAudioMs: 300));
      expect(find.text('Latency: 842 ms'), findsOneWidget);
      final tip = tester.widget<Tooltip>(
        find.ancestor(of: find.text('Latency: 842 ms'), matching: find.byType(Tooltip)),
      );
      expect(tip.message, contains('Speech recognition commit: 120 ms'));
      expect(tip.message, contains('Voice first audio: 300 ms'));
    });
  });

  group('controls', () {
    testWidgets('mute switches call the bridge', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await tester.tap(find.byKey(const Key('mute-out')));
      await tester.tap(find.byKey(const Key('mute-in')));
      await tester.pump();
      expect(fake.calls, containsAll(['setOutgoingMuted(true)', 'setIncomingAudioMuted(true)']));
    });

    testWidgets('bypass needs confirmation', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await tester.tap(find.byKey(const Key('bypass-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c.startsWith('setBypass')), isEmpty);
      await tester.tap(find.byKey(const Key('bypass-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on bypass'));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('setBypass(true)'));
      // Turning it off needs no confirmation (the engine reports bypass: true first).
      await push(const StateEvent(state: EngineState.ready, bypass: true));
      await tester.tap(find.byKey(const Key('bypass-switch')));
      await tester.pump();
      expect(fake.calls, contains('setBypass(false)'));
    });

    testWidgets('Stop calls stop while running', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await tester.tap(find.byKey(const Key('stop-button')));
      await tester.pump();
      expect(fake.count('stop'), 1);
    });
  });

  group('errors and devices', () {
    testWidgets('error strip shows code and message and can be dismissed', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await push(const ErrorEvent(code: 'tts_slow', message: 'Voice is slow'));
      expect(find.text('tts_slow: Voice is slow'), findsOneWidget);
      expect(find.text('State: Ready'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss error'));
      await tester.pump();
      expect(find.textContaining('tts_slow'), findsNothing);
    });

    testWidgets('a fatal error returns the UI to idle', (tester) async {
      await pumpApp(tester);
      await push(const StateEvent(state: EngineState.active, outReady: true, capturing: true, mock: true));
      await push(const ErrorEvent(code: 'gateway_lost', message: 'Connection closed', fatal: true));
      expect(find.text('State: Idle'), findsOneWidget);
      expect(find.text('OUT: not ready'), findsOneWidget);
      expect(find.text('Capturing'), findsNothing);
      expect(find.text(en.mockBanner), findsNothing);
      expect(find.textContaining('gateway_lost: Connection closed'), findsOneWidget);
    });

    testWidgets('devicesChanged clears a vanished selection and says so', (tester) async {
      final c = await pumpApp(tester);
      expect(c.read(setupProvider).micUid, 'mic1');
      expect(c.read(setupProvider).headphonesUid, 'hp1');
      fake.devices = [FakeLiveBridge.blackHole, FakeLiveBridge.headphones];
      await push(const DevicesChangedEvent());
      await tester.pumpAndSettle();
      expect(c.read(setupProvider).micUid, isNull);
      expect(c.read(setupProvider).headphonesUid, 'hp1');
      expect(find.textContaining('MacBook Microphone'), findsOneWidget);
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(find.textContaining('Choose a microphone.'), findsOneWidget);
    });
  });

  group('device test section', () {
    Future<void> openWizard(WidgetTester tester) async {
      final scrollable = find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Test your devices'), 300, scrollable: scrollable);
      await tester.tap(find.text('Test your devices'));
      await tester.pumpAndSettle();
    }

    testWidgets('meters run while open, render meters events and stop on close', (tester) async {
      await pumpApp(tester);
      await openWizard(tester);
      expect(fake.calls, contains('startMeters(mic1,[])'));
      await push(const MetersEvent(mic: -20, source: -120));
      expect(find.text('-20 dB'), findsOneWidget);
      expect(find.text('silent'), findsOneWidget);
      await tester.tap(find.text('Test your devices'));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'stopMeters');
    });

    testWidgets('test tones and permission request', (tester) async {
      final bridge = FakeLiveBridge()..permission = 'denied';
      await pumpApp(tester, bridge: bridge);
      await openWizard(tester);
      expect(find.text('Microphone permission: denied'), findsOneWidget);
      await tester.tap(find.text('Test headphones'));
      await tester.tap(find.text('Test virtual mic'));
      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(bridge.calls, containsAll(['testTone(hp1)', 'testTone(bh2)', 'requestMicrophonePermission']));
      expect(find.text('Microphone permission: granted'), findsOneWidget);
    });

    testWidgets('starting a session stops the meters and folds the section', (tester) async {
      await pumpApp(tester);
      await openWizard(tester);
      await fillToken();
      await tester.tap(startButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.consentCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(fake.calls.indexOf('stopMeters'), lessThan(fake.calls.indexOf('start')));
      expect(fake.count('stopMeters'), 1);
    });
  });

  group('settings', () {
    testWidgets('saved settings are loaded into the form', (tester) async {
      final bridge = FakeLiveBridge()
        ..settings = {
          'gatewayUrl': 'https://bridge.example.com',
          'accessToken': 'saved-token',
          'micUid': 'mic1',
          'headphonesUid': 'hp1',
          'sourcePids': [100, 999],
          'targetLang': 'ru',
          'mode': 'incoming',
          'outCommit': 'vad',
        };
      final c = await pumpApp(tester, bridge: bridge);
      final s = c.read(setupProvider);
      expect(s.gatewayUrl, 'https://bridge.example.com');
      expect(s.accessToken, 'saved-token');
      expect(s.sourcePids, {100});
      expect(s.targetLang, TargetLang.ru);
      expect(s.mode, SessionMode.incoming);
      expect(s.outCommit, OutCommit.vad);
      expect(find.text('https://bridge.example.com'), findsOneWidget);
      expect(startEnabled(), isTrue);
    });
  });
}
