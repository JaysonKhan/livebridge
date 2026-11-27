import 'package:flutter/services.dart';

import 'languages.dart';
import 'models.dart';

/// Everything Flutter can ask of the native engine. See docs/bridge-contract.md.
abstract class LiveBridge {
  Stream<BridgeEvent> get events;

  Future<List<AudioDevice>> listDevices();
  Future<List<AudioProcess>> listAudioProcesses();
  Future<Map<String, Object?>> loadSettings();

  /// Saves what a Start remembers ([StartConfig.toSettingsMap]): never the gateway, a token or a key.
  Future<void> saveSettings(StartConfig config);

  /// Saves preference keys (contract `saveSettings`: the given keys are merged, `null` removes a key).
  Future<void> savePreferences(Map<String, Object?> preferences);
  Future<String?> saveTextFile({required String suggestedName, required String content});

  /// Names of the session languages in the interface language [locale] (code -> name), from the system's locale
  /// data. A code the system has no name for is left out.
  Future<Map<String, String>> languageNames(String locale);
  Future<void> rateTurn(Direction direction, int turnId, String rating);
  Future<AnalyticsSummary> analyticsSummary();
  Future<String?> analyticsExport();
  Future<void> analyticsClear();
  Future<TelemetryStatus> telemetryStatus();

  /// Sends a feedback message to the developer. Throws a `PlatformException` with code `rate_limited`,
  /// `feedback_rejected` or `feedback_failed`.
  Future<void> sendFeedback({required String message, String? email, int? rating});
  Future<String> microphonePermission();
  Future<bool> requestMicrophonePermission();
  Future<void> startMeters({required String? micUid, required List<int> sourcePids});
  Future<void> stopMeters();
  Future<void> testTone(String uid);
  Future<void> start(StartConfig config);

  /// Replaces the access token the running session uses at its next automatic reconnect.
  Future<void> updateAccessToken(String accessToken);
  Future<void> stop();
  Future<void> pttDown();
  Future<void> pttUp();
  Future<void> setOutgoingMuted(bool muted);
  Future<void> setIncomingAudioMuted(bool muted);
  Future<void> setBypass(bool enabled);

  /// Changes the outgoing turn mode of the running session (and of its reconnects); nothing happens without one.
  Future<void> setOutCommit(OutCommit commit);
  Future<void> panic();
}

class MethodChannelLiveBridge implements LiveBridge {
  MethodChannelLiveBridge({MethodChannel? control, EventChannel? eventChannel})
    : _control = control ?? const MethodChannel('livebridge/control'),
      _eventChannel = eventChannel ?? const EventChannel('livebridge/events');

  final MethodChannel _control;
  final EventChannel _eventChannel;

  /// One stream for every listener: each `receiveBroadcastStream()` replaces the channel's single platform handler, so
  /// a second one would take the events from the first, and cancelling either would stop both. This one subscribes on
  /// its first listener and cancels after its last.
  @override
  late final Stream<BridgeEvent> events = _eventChannel
      .receiveBroadcastStream()
      .map((raw) => raw is Map ? BridgeEvent.fromMap(raw) : null)
      .where((e) => e != null)
      .cast<BridgeEvent>();

  @override
  Future<List<AudioDevice>> listDevices() async {
    final raw = await _control.invokeListMethod<Map<Object?, Object?>>('listDevices') ?? const [];
    return raw.map(AudioDevice.fromMap).toList();
  }

  @override
  Future<List<AudioProcess>> listAudioProcesses() async {
    final raw = await _control.invokeListMethod<Map<Object?, Object?>>('listAudioProcesses') ?? const [];
    return raw.map(AudioProcess.fromMap).toList();
  }

  @override
  Future<Map<String, Object?>> loadSettings() async =>
      await _control.invokeMapMethod<String, Object?>('loadSettings') ?? const {};

  @override
  Future<void> saveSettings(StartConfig config) => _control.invokeMethod<void>('saveSettings', config.toSettingsMap());

  @override
  Future<void> savePreferences(Map<String, Object?> preferences) =>
      _control.invokeMethod<void>('saveSettings', preferences);

  @override
  Future<String?> saveTextFile({required String suggestedName, required String content}) =>
      _control.invokeMethod<String>('saveTextFile', {'suggestedName': suggestedName, 'content': content});

  @override
  Future<Map<String, String>> languageNames(String locale) async =>
      (await _control.invokeMapMethod<String, String>('languageNames', {
        'codes': kLanguages.keys.toList(),
        'locale': locale,
      })) ??
      const {};

  @override
  Future<void> rateTurn(Direction direction, int turnId, String rating) =>
      _control.invokeMethod<void>('rateTurn', {'direction': direction.wire, 'turnId': turnId, 'rating': rating});

  @override
  Future<AnalyticsSummary> analyticsSummary() async =>
      AnalyticsSummary.fromMap(await _control.invokeMapMethod<Object?, Object?>('analyticsSummary') ?? const {});

  @override
  Future<String?> analyticsExport() => _control.invokeMethod<String>('analyticsExport');

  @override
  Future<void> analyticsClear() => _control.invokeMethod<void>('analyticsClear');

  @override
  Future<TelemetryStatus> telemetryStatus() async =>
      TelemetryStatus.fromMap(await _control.invokeMapMethod<Object?, Object?>('telemetryStatus') ?? const {});

  @override
  Future<void> sendFeedback({required String message, String? email, int? rating}) =>
      _control.invokeMethod<void>('sendFeedback', {'message': message, 'email': email, 'rating': rating});

  @override
  Future<String> microphonePermission() async =>
      await _control.invokeMethod<String>('microphonePermission') ?? 'undetermined';

  @override
  Future<bool> requestMicrophonePermission() async =>
      await _control.invokeMethod<bool>('requestMicrophonePermission') ?? false;

  @override
  Future<void> startMeters({required String? micUid, required List<int> sourcePids}) =>
      _control.invokeMethod<void>('startMeters', {'micUid': micUid, 'sourcePids': sourcePids});

  @override
  Future<void> stopMeters() => _control.invokeMethod<void>('stopMeters');

  @override
  Future<void> testTone(String uid) => _control.invokeMethod<void>('testTone', {'uid': uid});

  @override
  Future<void> start(StartConfig config) => _control.invokeMethod<void>('start', config.toMap());

  @override
  Future<void> updateAccessToken(String accessToken) =>
      _control.invokeMethod<void>('updateAccessToken', {'accessToken': accessToken});

  @override
  Future<void> stop() => _control.invokeMethod<void>('stop');

  @override
  Future<void> pttDown() => _control.invokeMethod<void>('pttDown');

  @override
  Future<void> pttUp() => _control.invokeMethod<void>('pttUp');

  @override
  Future<void> setOutgoingMuted(bool muted) => _control.invokeMethod<void>('setOutgoingMuted', {'muted': muted});

  @override
  Future<void> setIncomingAudioMuted(bool muted) =>
      _control.invokeMethod<void>('setIncomingAudioMuted', {'muted': muted});

  @override
  Future<void> setBypass(bool enabled) => _control.invokeMethod<void>('setBypass', {'enabled': enabled});

  @override
  Future<void> setOutCommit(OutCommit commit) => _control.invokeMethod<void>('setOutCommit', {'commit': commit.wire});

  @override
  Future<void> panic() => _control.invokeMethod<void>('panic');
}
