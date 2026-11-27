import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/session_state.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

const _active = StateEvent(state: EngineState.active, outReady: true, inReady: true, outCommit: OutCommit.vad);
const _readyManual = StateEvent(state: EngineState.ready, outReady: true, inReady: true, outCommit: OutCommit.manual);

void main() {
  group('outgoing turn mode setting', () {
    testWidgets('automatic means VAD until another automatic mode is chosen', (tester) async {
      final c = await pumpApp(tester);
      final setup = c.read(setupProvider.notifier);
      expect(c.read(setupProvider).outCommit, OutCommit.manual);
      expect(c.read(setupProvider).outAutoCommit, OutCommit.vad);

      setup.setAutomatic(true);
      expect(c.read(setupProvider).outCommit, OutCommit.vad);

      setup.setOutCommit(OutCommit.turnPrediction);
      setup.setAutomatic(false);
      expect(c.read(setupProvider).outCommit, OutCommit.manual);
      setup.setAutomatic(true);
      expect(c.read(setupProvider).outCommit, OutCommit.turnPrediction, reason: 'the last automatic mode is kept');
    });

    testWidgets('a change is saved at once, the automatic mode with it', (tester) async {
      final c = await pumpApp(tester);
      c.read(setupProvider.notifier).setOutCommit(OutCommit.turnPrediction);
      expect(fake.savedPrefs.last, {'outCommit': 'turn_prediction', 'outAutoCommit': 'turn_prediction'});
      c.read(setupProvider.notifier).setAutomatic(false);
      expect(fake.savedPrefs.last, {'outCommit': 'manual', 'outAutoCommit': 'turn_prediction'});
    });

    Future<OutCommit> loadedAutomatic(WidgetTester tester, Map<String, Object?> settings) async {
      final c = await pumpApp(tester, bridge: FakeLiveBridge()..settings = settings);
      return c.read(setupProvider).outAutoCommit;
    }

    testWidgets('the saved automatic mode is loaded', (tester) async {
      expect(
        await loadedAutomatic(tester, {'outCommit': 'manual', 'outAutoCommit': 'turn_prediction'}),
        OutCommit.turnPrediction,
      );
    });

    testWidgets('a saved automatic outCommit stands for the automatic mode when none is saved', (tester) async {
      expect(await loadedAutomatic(tester, {'outCommit': 'turn_prediction'}), OutCommit.turnPrediction);
    });

    testWidgets('manual is never the automatic mode', (tester) async {
      expect(await loadedAutomatic(tester, {'outCommit': 'vad', 'outAutoCommit': 'manual'}), OutCommit.vad);
    });
  });

  group('switching during a session', () {
    testWidgets('without a session nothing is sent to the host', (tester) async {
      final c = await pumpApp(tester);
      c.read(setupProvider.notifier).setAutomatic(true);
      await tester.pump();
      expect(fake.calls.where((call) => call.startsWith('setOutCommit')), isEmpty);
    });

    testWidgets('during a session every change goes to the host', (tester) async {
      final c = await pumpApp(tester);
      await push(_readyManual);
      c.read(setupProvider.notifier).setAutomatic(true);
      await tester.pump();
      c.read(setupProvider.notifier).setAutomatic(false);
      await tester.pump();
      expect(fake.calls.where((call) => call.startsWith('setOutCommit')), [
        'setOutCommit(vad)',
        'setOutCommit(manual)',
      ]);
    });

    testWidgets('leaving hold-to-talk while held lets the host release; no pttUp follows', (tester) async {
      final c = await pumpApp(tester);
      await push(_readyManual);
      await c.read(sessionProvider.notifier).pttDown();
      expect(c.read(sessionProvider).pttHeld, isTrue);

      c.read(setupProvider.notifier).setAutomatic(true);
      await tester.pump();
      expect(c.read(sessionProvider).pttHeld, isFalse);
      await c.read(sessionProvider.notifier).pttUp();
      expect(fake.count('pttUp'), 0);
      expect(fake.calls.last, 'setOutCommit(vad)');
    });

    testWidgets('a gateway that cannot switch puts the setting back to the mode in force', (tester) async {
      final c = await pumpApp(tester);
      await push(_readyManual);
      c.read(setupProvider.notifier).setAutomatic(true);
      await tester.pump();
      await push(_readyManual);
      await push(const ErrorEvent(code: 'mode_switch_unsupported', message: 'cannot switch', direction: 'out'));
      expect(c.read(setupProvider).outCommit, OutCommit.manual);
      expect(c.read(sessionProvider).error?.code, 'mode_switch_unsupported');
    });

    testWidgets('the mode in force is kept from state events', (tester) async {
      final c = await pumpApp(tester);
      await push(_active);
      expect(c.read(sessionProvider).outCommit, OutCommit.vad);
    });
  });
}
