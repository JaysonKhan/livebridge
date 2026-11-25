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

  /// Every `savePreferences` call, in order; they are also merged into [settings] like the real store does.
  final List<Map<String, Object?>> savedPrefs = [];

  /// `saveTextFile`: the result (null = the user cancelled), an error to throw, and the last arguments.
  String? saveTextFileResult = '/Users/test/Documents/livebridge-test.md';
  Exception? saveTextFileError;
  String? savedFileName;
  String? savedFileContent;

  AnalyticsSummary summary = const AnalyticsSummary();
  String? analyticsExportResult = '/Users/test/Documents/analytics.jsonl';

  /// `telemetryStatus`: the result, or an exception to throw.
  TelemetryStatus telemetry = const TelemetryStatus();
  Exception? telemetryError;

  /// `sendFeedback`: the arguments of every call, an error to throw, and an optional gate to hold the call open.
  final List<({String message, String? email, int? rating})> feedbacks = [];
  Exception? feedbackError;
  Completer<void>? feedbackGate;

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
  Future<void> savePreferences(Map<String, Object?> preferences) async {
    calls.add('savePreferences');
    savedPrefs.add(Map.of(preferences));
    settings = {...settings, ...preferences};
  }

  @override
  Future<String?> saveTextFile({required String suggestedName, required String content}) async {
    calls.add('saveTextFile');
    savedFileName = suggestedName;
    savedFileContent = content;
    if (saveTextFileError != null) throw saveTextFileError!;
    return saveTextFileResult;
  }

  @override
  Future<void> rateTurn(Direction direction, int turnId, String rating) async =>
      calls.add('rateTurn(${direction.wire},$turnId,$rating)');

  @override
  Future<AnalyticsSummary> analyticsSummary() async {
    calls.add('analyticsSummary');
    return summary;
  }

  @override
  Future<String?> analyticsExport() async {
    calls.add('analyticsExport');
    return analyticsExportResult;
  }

  @override
  Future<void> analyticsClear() async => calls.add('analyticsClear');

  @override
  Future<TelemetryStatus> telemetryStatus() async {
    calls.add('telemetryStatus');
    if (telemetryError != null) throw telemetryError!;
    return telemetry;
  }

  @override
  Future<void> sendFeedback({required String message, String? email, int? rating}) async {
    calls.add('sendFeedback');
    feedbacks.add((message: message, email: email, rating: rating));
    if (feedbackGate != null) await feedbackGate!.future;
    if (feedbackError != null) throw feedbackError!;
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
