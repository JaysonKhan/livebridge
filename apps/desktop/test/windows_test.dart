import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/route_check.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/setup_panel.dart';

import 'analytics_test.dart' show openAnalytics, tapVisible;
import 'fake_live_bridge.dart';
import 'harness.dart';

// What the Windows device list reports (windows/runner/audio_devices.cpp): VB-CABLE is two endpoints.
const _mic = AudioDevice(uid: 'win-mic', name: 'Microphone (Realtek(R) Audio)', inputChannels: 2, isDefaultInput: true);
const _headphones = AudioDevice(
  uid: 'win-hp',
  name: 'Headphones (Realtek(R) Audio)',
  outputChannels: 2,
  isDefaultOutput: true,
);
const _cableOutput = AudioDevice(
  uid: 'cable-out',
  name: 'CABLE Output (VB-Audio Virtual Cable)',
  inputChannels: 2,
  transport: 'virtual',
);
const _cableInput = AudioDevice(
  uid: 'cable-in',
  name: 'CABLE Input (VB-Audio Virtual Cable)',
  outputChannels: 2,
  transport: 'virtual',
);

FakeLiveBridge _windowsBridge({bool cable = true}) =>
    FakeLiveBridge(devices: [_mic, if (cable) _cableOutput, if (cable) _cableInput, _headphones]);

Future<void> _scrollTo(WidgetTester tester, String text) async {
  final scrollable = find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(text), 300, scrollable: scrollable);
}

void main() {
  group('Windows (VB-CABLE)', () {
    testWidgets('"CABLE Input" is the virtual mic; bidirectional is allowed and starts with it', (tester) async {
      final c = await pumpApp(tester, bridge: _windowsBridge(), platform: HostPlatform.windows);
      expect(c.read(setupProvider).virtualMic?.uid, 'cable-in');
      expect(find.text(en.virtualMicFoundWindows(_cableInput.name)), findsOneWidget);
      expect(find.text(en.vbCableMissingNotice), findsNothing);

      await fillToken();
      await tester.tap(find.text('Bidirectional speech'));
      await tester.pump();
      expect(startEnabled(), isTrue);

      await tester.tap(startButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.consentCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(fake.startedWith!.virtualMicUid, 'cable-in');
      expect(fake.startedWith!.micUid, 'win-mic');
      expect(fake.startedWith!.headphonesUid, 'win-hp');
    });

    testWidgets('"CABLE Output" as the microphone is refused', (tester) async {
      final c = await pumpApp(tester, bridge: _windowsBridge(), platform: HostPlatform.windows);
      await fillToken();
      expect(startEnabled(), isTrue);
      c.read(setupProvider.notifier).setMic('cable-out');
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.text(en.blockMicIsCable(_cableOutput.name)), findsOneWidget);
    });

    testWidgets('the cable never appears as headphones', (tester) async {
      final c = await pumpApp(tester, bridge: _windowsBridge(), platform: HostPlatform.windows);
      expect(c.read(setupProvider).outputDevices.map((d) => d.uid), ['win-hp']);
    });

    testWidgets('without VB-CABLE: the notice, the blocker, the error and routing help name VB-CABLE', (tester) async {
      await pumpApp(tester, bridge: _windowsBridge(cable: false), platform: HostPlatform.windows);
      expect(find.text(en.vbCableMissingNotice), findsOneWidget);
      expect(find.text(en.vbCableDownloadFrom(vbCableDownloadUrl)), findsOneWidget);

      await fillToken();
      await tester.tap(find.text('Bidirectional speech'));
      await tester.pump();
      expect(startEnabled(), isFalse);
      expect(find.text(en.blockBidirectionalNeedsVirtualWindows), findsOneWidget);

      await push(const ErrorEvent(code: 'no_virtual_mic', message: 'raw'));
      expect(find.text('no_virtual_mic: ${en.errNoVirtualMicWindows}'), findsOneWidget);

      await _scrollTo(tester, en.routingTitle);
      await tester.tap(find.text(en.routingTitle));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text(en.routingZoomDesktopTitle));
      await tapVisible(tester, find.text(en.routingWebTitle));
      expect(find.text('2. ${en.routingZoom2Windows}'), findsOneWidget);
      expect(find.text('2. ${en.routingWeb2Windows}'), findsOneWidget);
      expect(find.text(en.routingInstallVirtualWindows(vbCableDownloadUrl)), findsOneWidget);

      // Nothing macOS-only is left on the screen.
      expect(find.textContaining('BlackHole'), findsNothing);
      expect(find.textContaining('brew'), findsNothing);
    });

    testWidgets('the device test names CABLE Output and the Windows microphone setting', (tester) async {
      await pumpApp(tester, bridge: _windowsBridge(), platform: HostPlatform.windows);
      await _scrollTo(tester, en.testDevicesTitle);
      await tester.tap(find.text(en.testDevicesTitle));
      await tester.pumpAndSettle();
      expect(find.text(en.testToneNoteWindows), findsOneWidget);
      expect(find.text(en.micPrivacyWindows), findsOneWidget);
      expect(find.text(en.permissionRequest), findsNothing);
      await tester.tap(find.text(en.testVirtualMic));
      expect(fake.calls, contains('testTone(cable-in)'));
    });

    testWidgets('analytics and the sharing dialog say "this computer" and "Windows version"', (tester) async {
      await pumpApp(tester, bridge: _windowsBridge(), platform: HostPlatform.windows, size: const Size(1280, 4000));
      await openAnalytics(tester);
      expect(find.text(en.analyticsPrivacyWindows), findsOneWidget);
      expect(find.text(en.analyticsEnabledWindows), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('telemetry-switch')));
      expect(find.text(en.telemetryDialogSentWindows), findsOneWidget);
      expect(find.text(en.telemetryDialogSent), findsNothing);
    });
  });
}
