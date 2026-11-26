/// Typed models for the Flutter <-> Swift bridge (see docs/bridge-contract.md).
library;

abstract interface class Wire {
  String get wire;
}

T? parseWire<T extends Wire>(List<T> values, Object? raw) {
  for (final v in values) {
    if (v.wire == raw) return v;
  }
  return null;
}

enum EngineState implements Wire {
  idle('idle'),
  connecting('connecting'),
  ready('ready'),
  active('active'),
  degraded('degraded'),
  stopping('stopping');

  const EngineState(this.wire);
  @override
  final String wire;
}

/// Which side of the conversation a caption belongs to.
enum Direction implements Wire {
  /// The owner speaking to the remote participant.
  out('out'),

  /// The remote participant speaking to the owner.
  incoming('in');

  const Direction(this.wire);
  @override
  final String wire;
}

enum CaptionKind implements Wire {
  partial('partial'),
  finalText('final'),
  translationDelta('translationDelta'),
  translationFinal('translationFinal'),

  /// The turn was captioned but neither translated nor spoken; the event carries a [SkipReason].
  skipped('skipped');

  const CaptionKind(this.wire);
  @override
  final String wire;
}

/// Why the gateway left a turn untranslated.
enum SkipReason implements Wire {
  /// The speech was already in the target language (usually the other side's voice reaching this microphone).
  sameLanguage('same_language'),

  /// Our own synthesized speech came back.
  echo('echo');

  const SkipReason(this.wire);
  @override
  final String wire;
}

enum SessionMode implements Wire {
  captions('captions'),
  incoming('incoming'),
  bidirectional('bidirectional');

  const SessionMode(this.wire);
  @override
  final String wire;
}

enum OutCommit implements Wire {
  manual('manual'),
  vad('vad'),
  turnPrediction('turn_prediction');

  const OutCommit(this.wire);
  @override
  final String wire;
}

/// How a session is paid for. The saved preference `connectionMode` stores [name]; `start` sends [wire].
enum ConnectionMode implements Wire {
  /// A signed-in account on the hosted gateway, paid from its balance.
  account('account'),

  /// The user's own provider keys on the hosted gateway.
  keys('keys'),

  /// The user's own gateway with its static token.
  gateway('token');

  const ConnectionMode(this.wire);
  @override
  final String wire;
}

/// The owner's judgement of one translated turn (`none` is sent over the bridge to clear it).
enum TurnRating implements Wire {
  good('good'),
  bad('bad');

  const TurnRating(this.wire);
  @override
  final String wire;
}

class AudioDevice {
  const AudioDevice({
    required this.uid,
    required this.name,
    this.inputChannels = 0,
    this.outputChannels = 0,
    this.sampleRate = 48000,
    this.transport = 'other',
    this.isDefaultInput = false,
    this.isDefaultOutput = false,
  });

  factory AudioDevice.fromMap(Map<Object?, Object?> m) => AudioDevice(
    uid: m['uid'] as String,
    name: m['name'] as String? ?? '',
    inputChannels: (m['inputChannels'] as num?)?.toInt() ?? 0,
    outputChannels: (m['outputChannels'] as num?)?.toInt() ?? 0,
    sampleRate: (m['sampleRate'] as num?)?.toDouble() ?? 0,
    transport: m['transport'] as String? ?? 'other',
    isDefaultInput: m['isDefaultInput'] as bool? ?? false,
    isDefaultOutput: m['isDefaultOutput'] as bool? ?? false,
  );

  final String uid;
  final String name;
  final int inputChannels;
  final int outputChannels;
  final double sampleRate;
  final String transport;
  final bool isDefaultInput;
  final bool isDefaultOutput;

  /// One end of a virtual audio cable: whatever is played into it comes out as a microphone. BlackHole on macOS is
  /// one device with both sides; VB-CABLE on Windows is two: "CABLE Input" (played into) and "CABLE Output" (recorded).
  bool get isVirtualCable {
    final n = name.toLowerCase();
    return n.contains('blackhole') || (n.contains('vb-audio') && n.contains('cable'));
  }

  bool get isVirtual => transport == 'virtual' || isVirtualCable;
}

class AudioProcess {
  const AudioProcess({required this.pid, required this.name, this.bundleId = '', this.isPlaying = false});

  factory AudioProcess.fromMap(Map<Object?, Object?> m) => AudioProcess(
    pid: (m['pid'] as num).toInt(),
    name: m['name'] as String? ?? '',
    bundleId: m['bundleId'] as String? ?? '',
    isPlaying: m['isPlaying'] as bool? ?? false,
  );

  final int pid;
  final String name;
  final String bundleId;
  final bool isPlaying;
}

/// One synthesized voice the gateway offers (`GET /v1/voices`).
class Voice {
  const Voice({
    required this.id,
    required this.name,
    this.gender,
    this.age,
    this.accent,
    this.language,
    this.useCase,
    this.description,
    this.category,
    this.previewUrl,
    this.previews = const {},
  });

  final String id;
  final String name;
  final String? gender;
  final String? age;
  final String? accent;
  final String? language;
  final String? useCase;
  final String? description;
  final String? category;

  /// The voice's general sample.
  final String? previewUrl;

  /// A sample per language code, where the provider has one.
  final Map<String, String> previews;

  /// Null when [json] is not a voice: an id and a name are required.
  static Voice? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final id = text('id');
    final name = text('name');
    if (id == null || name == null) return null;
    final previews = json['previews'];
    return Voice(
      id: id,
      name: name,
      gender: text('gender'),
      age: text('age'),
      accent: text('accent'),
      language: text('language'),
      useCase: text('use_case'),
      description: text('description'),
      category: text('category'),
      previewUrl: text('preview_url'),
      previews: {
        if (previews is Map)
          for (final MapEntry(:key, :value) in previews.entries)
            if (key is String && value is String) key: value,
      },
    );
  }

  /// The address of the sample to play for a session language: that language's own, else the general one.
  String? sampleFor(String lang) => previews[lang] ?? previewUrl;
}

class StartConfig {
  const StartConfig({
    required this.gatewayUrl,
    required this.accessToken,
    required this.micUid,
    required this.headphonesUid,
    required this.virtualMicUid,
    required this.sourcePids,
    required this.myLang,
    required this.targetLang,
    required this.mode,
    required this.outCommit,
    required this.translationModel,
    this.outVoiceId,
    this.inVoiceId,
    this.connection = ConnectionMode.gateway,
    this.elevenlabsApiKey,
    this.geminiApiKey,
  });

  final String gatewayUrl;

  /// The static gateway token or the account's access token; empty with [ConnectionMode.keys].
  final String accessToken;
  final String micUid;
  final String headphonesUid;
  final String? virtualMicUid;
  final List<int> sourcePids;

  /// The owner's language and the other participant's language (codes from `kLanguages`).
  final String myLang;
  final String targetLang;
  final SessionMode mode;
  final OutCommit outCommit;
  final String? translationModel;

  /// The voice chosen for the owner's translated speech and for the other participant's; null = the gateway's own.
  final String? outVoiceId;
  final String? inVoiceId;

  final ConnectionMode connection;

  /// The user's own provider keys, with [ConnectionMode.keys] only.
  final String? elevenlabsApiKey;
  final String? geminiApiKey;

  /// The same config paid for another way: [connection] with its gateway and secrets.
  StartConfig withAuth({
    required ConnectionMode connection,
    required String gatewayUrl,
    String accessToken = '',
    String? elevenlabsApiKey,
    String? geminiApiKey,
  }) => StartConfig(
    gatewayUrl: gatewayUrl,
    accessToken: accessToken,
    micUid: micUid,
    headphonesUid: headphonesUid,
    virtualMicUid: virtualMicUid,
    sourcePids: sourcePids,
    myLang: myLang,
    targetLang: targetLang,
    mode: mode,
    outCommit: outCommit,
    translationModel: translationModel,
    outVoiceId: outVoiceId,
    inVoiceId: inVoiceId,
    connection: connection,
    elevenlabsApiKey: elevenlabsApiKey,
    geminiApiKey: geminiApiKey,
  );

  /// The `start` arguments.
  Map<String, Object?> toMap() => {
    'gatewayUrl': gatewayUrl,
    'accessToken': accessToken,
    'micUid': micUid,
    'headphonesUid': headphonesUid,
    'virtualMicUid': virtualMicUid,
    'sourcePids': sourcePids,
    'myLang': myLang,
    'targetLang': targetLang,
    'mode': mode.wire,
    'outCommit': outCommit.wire,
    'translationModel': translationModel,
    'outVoiceId': outVoiceId,
    'inVoiceId': inVoiceId,
    'connection': connection.wire,
    'elevenlabsApiKey': elevenlabsApiKey,
    'geminiApiKey': geminiApiKey,
  };

  /// What a Start saves: the route and session choices. The gateway address, the token, the keys and the connection
  /// are left out, not nulled — a null would delete the saved own-gateway address or token — so they are saved only
  /// when the user chooses them. The voices are left out too: a choice is saved when it is picked, under its connection
  /// mode's own names, and a Start of another mode must not overwrite or erase them.
  Map<String, Object?> toSettingsMap() => {
    for (final MapEntry(:key, :value) in toMap().entries)
      if (!const {
        'gatewayUrl',
        'accessToken',
        'connection',
        'elevenlabsApiKey',
        'geminiApiKey',
        'outVoiceId',
        'inVoiceId',
      }.contains(key))
        key: value,
  };
}

sealed class BridgeEvent {
  const BridgeEvent();

  /// Parses an event map from the EventChannel. Unknown or malformed events return null.
  static BridgeEvent? fromMap(Map<Object?, Object?> m) {
    try {
      return _parse(m);
    } on TypeError {
      return null;
    }
  }

  static BridgeEvent? _parse(Map<Object?, Object?> m) {
    switch (m['type']) {
      case 'state':
        final state = parseWire(EngineState.values, m['state']);
        if (state == null) return null;
        return StateEvent(
          state: state,
          outReady: m['outReady'] as bool? ?? false,
          inReady: m['inReady'] as bool? ?? false,
          capturing: m['capturing'] as bool? ?? false,
          mock: m['mock'] as bool? ?? false,
          bypass: m['bypass'] as bool? ?? false,
          outgoingMuted: m['outgoingMuted'] as bool? ?? false,
          incomingAudioMuted: m['incomingAudioMuted'] as bool? ?? false,
          message: m['message'] as String?,
        );
      case 'caption':
        final direction = parseWire(Direction.values, m['direction']);
        final kind = parseWire(CaptionKind.values, m['kind']);
        if (direction == null || kind == null) return null;
        return CaptionEvent(
          direction: direction,
          turnId: (m['turnId'] as num).toInt(),
          kind: kind,
          text: m['text'] as String? ?? '',
          skipReason: kind == CaptionKind.skipped
              ? parseWire(SkipReason.values, m['reason']) ?? SkipReason.sameLanguage
              : null,
        );
      case 'meters':
        return MetersEvent(
          mic: (m['mic'] as num?)?.toDouble() ?? -120,
          source: (m['source'] as num?)?.toDouble() ?? -120,
          outQueueMs: (m['outQueueMs'] as num?)?.toDouble() ?? 0,
          inQueueMs: (m['inQueueMs'] as num?)?.toDouble() ?? 0,
        );
      case 'metrics':
        final direction = parseWire(Direction.values, m['direction']);
        if (direction == null) return null;
        int? i(String k) => (m[k] as num?)?.toInt();
        return MetricsEvent(
          direction: direction,
          turnId: i('turnId') ?? 0,
          e2eMs: i('e2eMs'),
          sttCommitMs: i('sttCommitMs'),
          translateFirstMs: i('translateFirstMs'),
          translateTotalMs: i('translateTotalMs'),
          ttsFirstAudioMs: i('ttsFirstAudioMs'),
          ttsTotalMs: i('ttsTotalMs'),
          audioMs: i('audioMs'),
          model: m['model'] as String?,
        );
      case 'error':
        return ErrorEvent(
          code: m['code'] as String? ?? 'unknown',
          message: m['message'] as String? ?? '',
          direction: m['direction'] as String?,
          fatal: m['fatal'] as bool? ?? false,
        );
      case 'devicesChanged':
        return const DevicesChangedEvent();
      case 'balance':
        return BalanceEvent((m['balanceUnits'] as num).toInt());
    }
    return null;
  }
}

final class StateEvent extends BridgeEvent {
  const StateEvent({
    required this.state,
    this.outReady = false,
    this.inReady = false,
    this.capturing = false,
    this.mock = false,
    this.bypass = false,
    this.outgoingMuted = false,
    this.incomingAudioMuted = false,
    this.message,
  });

  final EngineState state;
  final bool outReady;
  final bool inReady;
  final bool capturing;
  final bool mock;
  final bool bypass;
  final bool outgoingMuted;
  final bool incomingAudioMuted;
  final String? message;
}

final class CaptionEvent extends BridgeEvent {
  const CaptionEvent({
    required this.direction,
    required this.turnId,
    required this.kind,
    required this.text,
    this.skipReason,
  });

  final Direction direction;
  final int turnId;
  final CaptionKind kind;
  final String text;

  /// Set on [CaptionKind.skipped] events only.
  final SkipReason? skipReason;
}

final class MetersEvent extends BridgeEvent {
  const MetersEvent({this.mic = -120, this.source = -120, this.outQueueMs = 0, this.inQueueMs = 0});

  /// dBFS, -120 = silence.
  final double mic;
  final double source;
  final double outQueueMs;
  final double inQueueMs;
}

final class MetricsEvent extends BridgeEvent {
  const MetricsEvent({
    required this.direction,
    this.turnId = 0,
    this.e2eMs,
    this.sttCommitMs,
    this.translateFirstMs,
    this.translateTotalMs,
    this.ttsFirstAudioMs,
    this.ttsTotalMs,
    this.audioMs,
    this.model,
  });

  final Direction direction;
  final int turnId;
  final int? e2eMs;
  final int? sttCommitMs;
  final int? translateFirstMs;
  final int? translateTotalMs;
  final int? ttsFirstAudioMs;
  final int? ttsTotalMs;
  final int? audioMs;

  /// The translation model that answered the turn.
  final String? model;
}

final class ErrorEvent extends BridgeEvent {
  const ErrorEvent({required this.code, required this.message, this.direction, this.fatal = false});

  final String code;
  final String message;
  final String? direction;
  final bool fatal;
}

final class DevicesChangedEvent extends BridgeEvent {
  const DevicesChangedEvent();
}

/// The account's balance after the gateway charged the running session.
final class BalanceEvent extends BridgeEvent {
  const BalanceEvent(this.balanceUnits);

  final int balanceUnits;
}

/// Percentiles of one timing series, in milliseconds.
class TimingStat {
  const TimingStat({required this.count, required this.p50, required this.p95, required this.max});

  static TimingStat? fromMap(Object? raw) {
    if (raw is! Map) return null;
    int i(String k) => (raw[k] as num?)?.toInt() ?? 0;
    return TimingStat(count: i('count'), p50: i('p50'), p95: i('p95'), max: i('max'));
  }

  final int count;
  final int p50;
  final int p95;
  final int max;
}

/// What `analyticsSummary` returns: numbers only, never transcript text.
class AnalyticsSummary {
  const AnalyticsSummary({
    this.enabled = true,
    this.path = '',
    this.fileSizeBytes = 0,
    this.sessions = 0,
    this.turns = 0,
    this.firstAt,
    this.lastAt,
    this.e2eMs,
    this.sttCommitMs,
    this.translateFirstMs,
    this.translateTotalMs,
    this.ttsFirstAudioMs,
    this.errors = const {},
    this.reconnects = 0,
    this.emptyTurns = 0,
    this.ratedGood = 0,
    this.ratedBad = 0,
  });

  factory AnalyticsSummary.fromMap(Map<Object?, Object?> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    final rawErrors = m['errors'];
    return AnalyticsSummary(
      enabled: m['enabled'] as bool? ?? true,
      path: m['path'] as String? ?? '',
      fileSizeBytes: i('fileSizeBytes'),
      sessions: i('sessions'),
      turns: i('turns'),
      firstAt: m['firstAt'] as String?,
      lastAt: m['lastAt'] as String?,
      e2eMs: TimingStat.fromMap(m['e2eMs']),
      sttCommitMs: TimingStat.fromMap(m['sttCommitMs']),
      translateFirstMs: TimingStat.fromMap(m['translateFirstMs']),
      translateTotalMs: TimingStat.fromMap(m['translateTotalMs']),
      ttsFirstAudioMs: TimingStat.fromMap(m['ttsFirstAudioMs']),
      errors: rawErrors is Map
          ? {for (final e in rawErrors.entries) e.key.toString(): (e.value as num?)?.toInt() ?? 0}
          : const {},
      reconnects: i('reconnects'),
      emptyTurns: i('emptyTurns'),
      ratedGood: i('ratedGood'),
      ratedBad: i('ratedBad'),
    );
  }

  final bool enabled;
  final String path;
  final int fileSizeBytes;
  final int sessions;
  final int turns;
  final String? firstAt;
  final String? lastAt;
  final TimingStat? e2eMs;
  final TimingStat? sttCommitMs;
  final TimingStat? translateFirstMs;
  final TimingStat? translateTotalMs;
  final TimingStat? ttsFirstAudioMs;
  final Map<String, int> errors;
  final int reconnects;
  final int emptyTurns;
  final int ratedGood;
  final int ratedBad;
}

/// Contract `telemetryStatus`: the state of the opt-in upload of the numbers-only log (docs/telemetry-api.md).
class TelemetryStatus {
  const TelemetryStatus({
    this.enabled = false,
    this.installId,
    this.endpoint = '',
    this.pendingRecords = 0,
    this.lastUploadAt,
    this.lastError,
  });

  factory TelemetryStatus.fromMap(Map<Object?, Object?> m) => TelemetryStatus(
    enabled: m['enabled'] as bool? ?? false,
    installId: m['installId'] as String?,
    endpoint: m['endpoint'] as String? ?? '',
    pendingRecords: (m['pendingRecords'] as num?)?.toInt() ?? 0,
    lastUploadAt: m['lastUploadAt'] as String?,
    lastError: m['lastError'] as String?,
  );

  final bool enabled;
  final String? installId;
  final String endpoint;
  final int pendingRecords;
  final String? lastUploadAt;
  final String? lastError;
}
