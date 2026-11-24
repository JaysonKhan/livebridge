import 'dart:async';

import 'package:livebridge/bridge/live_bridge.dart';
import 'package:livebridge/bridge/models.dart';

/// Records every call and lets tests push events.
class FakeLiveBridge implements LiveBridge {
  FakeLiveBridge({List<AudioDevice>? devices, List<AudioProcess>? processes})
    : devices = devices ?? defaultDevices(),
      processes = processes ?? defaultProcesses();

  static const mic = AudioDevice(
    uid: 'mic1',
    name: 'MacBook Microphone',
    inputChannels: 1,
    transport: 'builtin',
    isDefaultInput: true,
  );
  static const blackHole = AudioDevice(
    uid: 'bh2',
    name: 'BlackHole 2ch',
    inputChannels: 2,
    outputChannels: 2,
    transport: 'virtual',
  );
  static const headphones = AudioDevice(
    uid: 'hp1',
    name: 'AirPods',
    outputChannels: 2,
    transport: 'bluetooth',
    isDefaultOutput: true,
  );

  static List<AudioDevice> defaultDevices() => [mic, blackHole, headphones];
  static List<AudioProcess> defaultProcesses() => [
    const AudioProcess(pid: 200, name: 'Chrome', bundleId: 'com.google.Chrome'),
    const AudioProcess(pid: 100, name: 'zoom.us', bundleId: 'us.zoom.xos', isPlaying: true),
  ];

  List<AudioDevice> devices;
  List<AudioProcess> processes;
  Map<String, Object?> settings = {};
  String permission = 'granted';

  final List<String> calls = [];
  StartConfig? startedWith;
  StartConfig? savedWith;

  final _events = StreamController<BridgeEvent>.broadcast(sync: true);

  void push(BridgeEvent e) => _events.add(e);
  Future<void> dispose() => _events.close();

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<List<AudioDevice>> listDevices() async => List.of(devices);

  @override
  Future<List<AudioProcess>> listAudioProcesses() async => List.of(processes);

  @override
  Future<Map<String, Object?>> loadSettings() async => settings;

  @override
  Future<void> saveSettings(StartConfig config) async {
    calls.add('saveSettings');
    savedWith = config;
  }

  @override
  Future<String> microphonePermission() async => permission;

  @override
  Future<bool> requestMicrophonePermission() async {
    calls.add('requestMicrophonePermission');
    permission = 'granted';
    return true;
  }

  @override
  Future<void> startMeters({required String? micUid, required List<int> sourcePids}) async =>
      calls.add('startMeters($micUid,$sourcePids)');

  @override
  Future<void> stopMeters() async => calls.add('stopMeters');

  @override
  Future<void> testTone(String uid) async => calls.add('testTone($uid)');

  @override
  Future<void> start(StartConfig config) async {
    calls.add('start');
    startedWith = config;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> pttDown() async => calls.add('pttDown');

  @override
  Future<void> pttUp() async => calls.add('pttUp');

  @override
  Future<void> setOutgoingMuted(bool muted) async => calls.add('setOutgoingMuted($muted)');

  @override
  Future<void> setIncomingAudioMuted(bool muted) async => calls.add('setIncomingAudioMuted($muted)');

  @override
  Future<void> setBypass(bool enabled) async => calls.add('setBypass($enabled)');

  @override
  Future<void> panic() async => calls.add('panic');
}
