import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/route_check.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

// What Windows reports for AirPods (two endpoints) next to the laptop's own devices.
const _laptopMic = AudioDevice(uid: 'int-mic', name: 'Microphone Array (Realtek(R) Audio)', inputChannels: 2);
const _airPodsMic = AudioDevice(
  uid: 'bt-mic',
  name: 'Headset (AirPods Hands-Free)',
  inputChannels: 1,
  transport: 'bluetooth',
  isDefaultInput: true,
);
const _airPods = AudioDevice(
  uid: 'bt-out',
  name: 'Headphones (AirPods)',
  outputChannels: 2,
  transport: 'bluetooth',
  isDefaultOutput: true,
);
const _speakers = AudioDevice(uid: 'spk', name: 'Speakers (Realtek(R) Audio)', outputChannels: 2);
const _usbMic = AudioDevice(uid: 'usb-mic', name: 'USB Microphone', inputChannels: 1, transport: 'usb');
const _cableInput = AudioDevice(
  uid: 'cable-in',
  name: 'CABLE Input (VB-Audio Virtual Cable)',
  outputChannels: 2,
  transport: 'virtual',
  isDefaultOutput: true,
);

const _devices = [_laptopMic, _airPodsMic, _usbMic, _airPods, _speakers];

SetupState _setup({
  String? mic = 'int-mic',
  String? phones = 'bt-out',
  SessionMode mode = SessionMode.incoming,
  List<AudioDevice> devices = _devices,
}) => SetupState(devices: devices, micUid: mic, headphonesUid: phones, mode: mode);

void main() {
  group('Bluetooth microphone (Windows)', () {
    test('a Bluetooth microphone on Windows warns about Hands-Free', () {
      expect(routeWarnings(_setup(mic: 'bt-mic'), en, HostPlatform.windows), [en.warnBluetoothMicWindows]);
    });

    test('in every mode, captions too: the headset still switches to Hands-Free', () {
      for (final mode in SessionMode.values) {
        expect(routeWarnings(_setup(mic: 'bt-mic', mode: mode), en, HostPlatform.windows), [
          en.warnBluetoothMicWindows,
        ]);
      }
    });

    test('the built-in or a USB microphone does not warn', () {
      expect(routeWarnings(_setup(mic: 'int-mic'), en, HostPlatform.windows), isEmpty);
      expect(routeWarnings(_setup(mic: 'usb-mic'), en, HostPlatform.windows), isEmpty);
    });

    test('macOS does not warn', () {
      expect(routeWarnings(_setup(mic: 'bt-mic'), en, HostPlatform.macos), isEmpty);
    });

    test('warnings never block Start', () {
      final s = _setup(mic: 'bt-mic', phones: 'spk').copyWith(sourcePids: {100}, accessToken: 'token');
      expect(routeWarnings(s, en, HostPlatform.windows), hasLength(2));
      expect(startBlockers(s, en, HostPlatform.windows), isEmpty);
    });
  });

  group('headphones that are not the system output', () {
    test('the laptop speakers chosen while AirPods are the system output: names both', () {
      for (final platform in HostPlatform.values) {
        expect(routeWarnings(_setup(phones: 'spk'), en, platform), [
          en.warnHeadphonesNotSystemOutput(_speakers.name, _airPods.name),
        ]);
      }
    });

    test('the system output chosen does not warn', () {
      expect(routeWarnings(_setup(phones: 'bt-out'), en, HostPlatform.windows), isEmpty);
    });

    test('captions only play nothing, so they do not warn', () {
      expect(routeWarnings(_setup(phones: 'spk', mode: SessionMode.captions), en, HostPlatform.macos), isEmpty);
      expect(routeWarnings(_setup(phones: 'spk', mode: SessionMode.bidirectional), en, HostPlatform.macos), [
        en.warnHeadphonesNotSystemOutput(_speakers.name, _airPods.name),
      ]);
    });

    test('no warning without a known system output, a choice, or when the system output is a virtual cable', () {
      const unmarked = AudioDevice(uid: 'bt-out', name: 'Headphones (AirPods)', outputChannels: 2);
      expect(
        routeWarnings(_setup(phones: 'spk', devices: [_laptopMic, unmarked, _speakers]), en, HostPlatform.macos),
        isEmpty,
      );
      expect(routeWarnings(_setup(phones: null), en, HostPlatform.macos), isEmpty);
      expect(
        routeWarnings(_setup(phones: 'spk', devices: [_laptopMic, _speakers, _cableInput]), en, HostPlatform.windows),
        isEmpty,
      );
    });

    test('both warnings together, microphone first', () {
      expect(routeWarnings(_setup(mic: 'bt-mic', phones: 'spk'), en, HostPlatform.windows), [
        en.warnBluetoothMicWindows,
        en.warnHeadphonesNotSystemOutput(_speakers.name, _airPods.name),
      ]);
    });
  });

  group('in the Devices section', () {
    testWidgets('shown under the device fields; Start stays on', (tester) async {
      final c = await pumpApp(
        tester,
        bridge: FakeLiveBridge(devices: _devices),
        platform: HostPlatform.windows,
      );
      await fillToken();
      final notifier = c.read(setupProvider.notifier)
        ..setMode(SessionMode.incoming)
        ..setMic('bt-mic')
        ..setHeadphones('spk');
      notifier.toggleSource(100, true);
      await tester.pump();
      expect(find.text(en.warnBluetoothMicWindows), findsOneWidget);
      expect(find.text(en.warnHeadphonesNotSystemOutput(_speakers.name, _airPods.name)), findsOneWidget);
      expect(startEnabled(), isTrue);

      notifier
        ..setMic('usb-mic')
        ..setHeadphones('bt-out');
      await tester.pump();
      expect(find.text(en.warnBluetoothMicWindows), findsNothing);
      expect(find.text(en.warnHeadphonesNotSystemOutput(_speakers.name, _airPods.name)), findsNothing);
    });
  });
}
