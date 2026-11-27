import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/session_state.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/session_panel.dart';

import 'harness.dart';

const _readyManual = StateEvent(state: EngineState.ready, outReady: true, inReady: true, outCommit: OutCommit.manual);

final _panel = find.byKey(const Key('ptt-button'));
final _hold = find.byKey(const Key('mode-hold'));
final _auto = find.byKey(const Key('mode-auto'));

String _panelText(WidgetTester tester) =>
    tester.widgetList<Text>(find.descendant(of: _panel, matching: find.byType(Text))).map((t) => t.data).join();

WaveformPainter _waveform(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(const Key('talk-waveform'))).painter! as WaveformPainter;

Future<void> _meter(double micDb) => push(MetersEvent(mic: micDb));

void main() {
  for (final platform in HostPlatform.values) {
    group('${platform.name} look', () {
      testWidgets('without a session: the switch works, the panel waits with flat bars', (tester) async {
        final c = await pumpApp(tester, platform: platform);
        final label = tester.widget<Text>(find.descendant(of: _hold, matching: find.byType(Text)));
        if (platform == HostPlatform.windows) {
          expect(label.style, isNull, reason: 'the toggle button colours its label, also on the accent fill');
        }
        expect(_panelText(tester), en.talkNoSession);
        expect(_waveform(tester).live, isFalse);
        await tester.tap(_auto);
        await tester.pumpAndSettle();
        expect(c.read(setupProvider).outCommit, OutCommit.vad);
        await tester.tap(_hold);
        await tester.pumpAndSettle();
        expect(c.read(setupProvider).outCommit, OutCommit.manual);
        expect(fake.calls.where((call) => call.startsWith('setOutCommit')), isEmpty);
      });

      testWidgets('hold to talk: flat until pressed, live and teal while held, sent on release', (tester) async {
        await pumpApp(tester, platform: platform);
        await push(_readyManual);
        expect(_panelText(tester), en.talkHoldReady);
        await _meter(-20);
        expect(_waveform(tester).live, isFalse);
        expect(_waveform(tester).levels.every((l) => l == 0), isTrue, reason: 'nothing is sent, so nothing moves');

        final gesture = await tester.startGesture(tester.getCenter(_panel));
        await tester.pump();
        expect(_panelText(tester), en.talkHoldHeld);
        expect(_waveform(tester).live, isTrue);
        await _meter(-20);
        await _meter(-50);
        expect(_waveform(tester).levels.last, lessThan(_waveform(tester).levels[_waveform(tester).levels.length - 2]));
        expect(_waveform(tester).levels.last, greaterThanOrEqualTo(0));

        await gesture.up();
        await tester.pump();
        expect(fake.count('pttUp'), 1);
        expect(_panelText(tester), en.talkHoldReady);
        expect(_waveform(tester).levels.every((l) => l == 0), isTrue, reason: 'released: flat again');
      });

      testWidgets('switching to automatic mid-session listens with live bars; the panel takes no presses', (
        tester,
      ) async {
        await pumpApp(tester, platform: platform);
        await push(_readyManual);
        await tester.tap(_auto);
        await tester.pump();
        expect(fake.calls.last, 'setOutCommit(vad)');
        expect(_panelText(tester), en.talkListening);
        await _meter(-25);
        expect(_waveform(tester).live, isTrue);
        expect(_waveform(tester).levels.last, greaterThan(0));

        final gesture = await tester.startGesture(tester.getCenter(_panel));
        await gesture.up();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(fake.calls.where((call) => call.startsWith('ptt')), isEmpty);

        await tester.tap(_hold);
        await tester.pump();
        expect(fake.calls.last, 'setOutCommit(manual)');
        expect(_panelText(tester), en.talkHoldReady);
      });

      testWidgets('muted, bypass and connecting each say so and never move the bars', (tester) async {
        final c = await pumpApp(tester, platform: platform);
        c.read(setupProvider.notifier).setAutomatic(true);
        await push(const StateEvent(state: EngineState.connecting));
        expect(_panelText(tester), en.talkConnecting);
        await push(const StateEvent(state: EngineState.active, outReady: true, outgoingMuted: true));
        expect(_panelText(tester), en.talkMuted);
        expect(find.descendant(of: _panel, matching: find.byIcon(Icons.mic_off)), findsOneWidget);
        await _meter(-20);
        expect(_waveform(tester).live, isFalse);
        await push(const StateEvent(state: EngineState.active, outReady: true, bypass: true));
        expect(_panelText(tester), en.talkBypass);
        expect(_waveform(tester).live, isFalse);
        await push(const StateEvent(state: EngineState.degraded));
        expect(_panelText(tester), en.talkConnecting);
      });

      testWidgets('a press while muted does not hold', (tester) async {
        final c = await pumpApp(tester, platform: platform);
        await push(const StateEvent(state: EngineState.ready, outReady: true, outgoingMuted: true));
        final gesture = await tester.startGesture(tester.getCenter(_panel));
        await tester.pump();
        expect(c.read(sessionProvider).pttHeld, isFalse);
        expect(fake.count('pttDown'), 0);
        await gesture.up();
      });
    });
  }

  testWidgets('the setup list and the switch show the same mode', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text(en.turnPredictionTitle));
    await tester.pump();
    expect(c.read(setupProvider).outCommit, OutCommit.turnPrediction);
    await tester.tap(_hold);
    await tester.pumpAndSettle();
    expect(c.read(setupProvider).outCommit, OutCommit.manual);
    await tester.tap(_auto);
    await tester.pumpAndSettle();
    expect(c.read(setupProvider).outCommit, OutCommit.turnPrediction, reason: 'automatic is the last automatic mode');
  });

  testWidgets('an older gateway: the switch moves back and the message explains', (tester) async {
    final c = await pumpApp(tester);
    await push(_readyManual);
    await tester.tap(_auto);
    await tester.pump();
    await push(_readyManual);
    await push(const ErrorEvent(code: 'mode_switch_unsupported', message: 'raw', direction: 'out'));
    await tester.pump();
    expect(c.read(setupProvider).outCommit, OutCommit.manual);
    expect(find.textContaining(en.errModeSwitchUnsupported), findsOneWidget);
    expect(_panelText(tester), en.talkHoldReady);
  });
}
