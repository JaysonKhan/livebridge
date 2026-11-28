import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import 'connection_state.dart';
import 'diagnostic_log.dart';
import 'providers.dart';
import 'setup_state.dart';

export 'diagnostic_log.dart' show DiagnosticLog;

/// The diagnostic log of this run. `main` replaces it with one that also writes the rolling file.
final diagnosticLogProvider = Provider<DiagnosticLog>((ref) => DiagnosticLog.memory());

/// Feeds the diagnostic log while the app runs: the app and its versions, the connection, the devices and the choice
/// of them, engine state, errors, turn timings. Captions, meters and the balance are never recorded. `LiveBridgeApp`
/// keeps it alive.
final diagnosticRecorderProvider = Provider<void>((ref) {
  final log = ref.watch(diagnosticLogProvider);
  // The own gateway's token is typed by the user and may look like anything, so it is matched by value.
  log.secrets = () => [ref.read(setupProvider).accessToken.trim()];
  final recorder = _Recorder(log);
  final sub = ref.watch(bridgeProvider).events.listen(recorder.event);
  ref.onDispose(sub.cancel);
  ref.listen(setupProvider, (_, next) => recorder.setup(next), fireImmediately: true);
  ref.listen(
    connectionProvider,
    (_, next) => recorder.connection(next, ref.read(setupProvider).gatewayUrl),
    fireImmediately: true,
  );
  unawaited(recorder.app(ref.read(bridgeProvider)));
});

/// The host of a gateway address, never its path, query or anything else; `-` when it has none.
String gatewayHost(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  return host.isEmpty ? '-' : host;
}

String _device(AudioDevice d) =>
    '"${d.name}" in=${d.inputChannels} out=${d.outputChannels} ${d.sampleRate.round()} Hz ${d.transport}'
    '${d.isDefaultInput ? ' default-in' : ''}${d.isDefaultOutput ? ' default-out' : ''}';

String _chosen(AudioDevice? d) => d == null ? 'none' : _device(d);

List<String> _sourceNames(SetupState s) => [
  for (final p in s.processes)
    if (s.sourcePids.contains(p.pid)) p.name,
];

/// The most the site accepts as a report's `devices`, measured by [siteJsonBytes].
const int kReportDevicesLimit = 16 * 1024;

/// The length the site measures for [value]: Python's `json.dumps` (", " and ": " between items, every character
/// outside printable ASCII as `\uXXXX`, so a Cyrillic letter counts six). Only the JSON types a report holds.
int siteJsonBytes(Object? value) {
  // The brackets and ", " between the items: two characters an item, two for an empty one.
  int items(List<int> lengths) => lengths.isEmpty ? 2 : lengths.fold(2 * lengths.length, (n, l) => n + l);
  return switch (value) {
    null || true => 4,
    false => 5,
    num() => '$value'.length,
    String() => value.codeUnits.fold(2, (n, c) => n + _escapedLength(c)),
    List() => items([for (final v in value) siteJsonBytes(v)]),
    Map() => items([for (final e in value.entries) siteJsonBytes('${e.key}') + 2 + siteJsonBytes(e.value)]),
    _ => throw ArgumentError.value(value, 'value', 'not a JSON value'),
  };
}

int _escapedLength(int unit) => switch (unit) {
  0x22 || 0x5C || 0x08 || 0x0C || 0x0A || 0x0D || 0x09 => 2, // \" \\ \b \f \n \r \t
  >= 0x20 && < 0x7F => 1,
  _ => 6, // \uXXXX, a character outside the BMP as two of them
};

/// What a problem report sends as `devices`: the chosen microphone, headphones and virtual microphone, the meeting
/// apps, mode and languages, and the device list. Device ids stay out. A list too long for the site's limit (dozens
/// of endpoints, names outside ASCII) keeps its first entries, and `devicesOmitted` says how many were left out.
Map<String, Object?> describeDevices(SetupState s) {
  Map<String, Object?>? device(AudioDevice? d) => d == null
      ? null
      : {
          'name': d.name,
          'transport': d.transport,
          'sampleRate': d.sampleRate.round(),
          'inputChannels': d.inputChannels,
          'outputChannels': d.outputChannels,
          'isDefaultInput': d.isDefaultInput,
          'isDefaultOutput': d.isDefaultOutput,
        };
  final head = {
    'mic': device(s.deviceByUid(s.micUid)),
    'headphones': device(s.deviceByUid(s.headphonesUid)),
    'virtualMic': device(s.virtualMic),
    'sources': _sourceNames(s),
    'mode': s.mode.wire,
    'myLang': s.myLang,
    'targetLang': s.targetLang,
    'outCommit': s.outCommit.wire,
  };
  final all = [for (final d in s.devices) device(d)];
  Map<String, Object?> withFirst(int kept) => {
    ...head,
    'devices': all.sublist(0, kept),
    if (kept < all.length) 'devicesOmitted': all.length - kept,
  };
  var kept = all.length;
  while (kept > 0 && siteJsonBytes(withFirst(kept)) > kReportDevicesLimit) {
    kept--;
  }
  return withFirst(kept);
}

/// One line for a Start: how it connects and where, and what it captures and plays — never a token or a key.
List<String> describeStart(StartConfig config, SetupState setup) {
  String name(String? uid) => uid == null ? 'none' : '"${setup.deviceByUid(uid)?.name ?? uid}"';
  final sources = [
    for (final p in setup.processes)
      if (config.sourcePids.contains(p.pid)) p.name,
  ];
  return [
    'connection=${config.connection.name} gateway=${gatewayHost(config.gatewayUrl)} mode=${config.mode.wire} '
        '${config.myLang}→${config.targetLang} commit=${config.outCommit.wire} '
        'model=${config.translationModel ?? 'default'} '
        'voices=out:${config.outVoiceId == null ? 'default' : 'chosen'},in:${config.inVoiceId == null ? 'default' : 'chosen'}',
    'mic=${name(config.micUid)} headphones=${name(config.headphonesUid)} virtual-mic=${name(config.virtualMicUid)} '
        'sources=[${sources.join(', ')}]',
  ];
}

/// An exception for the log: where it came from, the first line of its text and the first frames of its stack.
/// The log redacts it like every line.
String describeError(Object error, StackTrace? stack, {required String context}) {
  final text = error.toString().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final type = '${error.runtimeType}';
  final frames = (stack?.toString() ?? '')
      .split('\n')
      .map((l) => RegExp(r'\(([^)]+)\)').firstMatch(l)?.group(1))
      .nonNulls
      // A file path would carry the user's home folder: the file name is enough.
      .map((f) => f.startsWith('file:') ? f.substring(f.lastIndexOf('/') + 1) : f)
      .take(4)
      .join(' < ');
  final head = text.startsWith(type) ? text : '$type: $text';
  return '$context: $head${frames.isEmpty ? '' : ' @ $frames'}';
}

class _Recorder {
  _Recorder(this.log);

  final DiagnosticLog log;
  String? _state;
  final Map<String, String> _last = {};

  /// Adds [text] under [category] unless the line kept under [key] says the same already.
  void _changed(String key, String category, String text) {
    if (_last[key] == text) return;
    _last[key] = text;
    log.add(category, text);
  }

  Future<void> app(LiveBridge bridge) async {
    TelemetryStatus? status;
    try {
      status = await bridge.telemetryStatus();
    } on Exception {
      status = null;
    }
    log.add(
      'app',
      'version=${status?.appVersion ?? '?'} os=${status?.osVersion ?? '?'} (${Platform.operatingSystemVersion}) '
          'arch=${Abi.current()} system-language=${PlatformDispatcher.instance.locale.toLanguageTag()} '
          'statistics=${status == null
              ? '?'
              : status.enabled
              ? 'on'
              : 'off'}',
    );
  }

  void event(BridgeEvent e) {
    switch (e) {
      case final StateEvent s:
        final message = s.message?.trim() ?? '';
        final text = [
          s.state.wire,
          if (s.outReady) 'out',
          if (s.inReady) 'in',
          if (s.capturing) 'capturing',
          if (s.mock) 'mock',
          if (s.bypass) 'bypass',
          if (s.outgoingMuted) 'out-muted',
          if (s.incomingAudioMuted) 'in-muted',
        ].join(' ');
        final line = message.isEmpty ? text : '$text: $message';
        if (line == _state) return;
        _state = line;
        log.add('state', line);
      case final ErrorEvent err:
        log.add('error', _errorText(err));
      case final MetricsEvent m:
        String pair(int? a, int? b) => '${a ?? '-'}/${b ?? '-'}';
        log.add(
          'turn',
          [
            '${m.direction.wire} #${m.turnId}',
            if (m.e2eMs != null) 'e2e=${m.e2eMs}',
            if (m.sttCommitMs != null) 'stt=${m.sttCommitMs}',
            if (m.translateFirstMs != null || m.translateTotalMs != null)
              'translate=${pair(m.translateFirstMs, m.translateTotalMs)}',
            if (m.ttsFirstAudioMs != null || m.ttsTotalMs != null) 'tts=${pair(m.ttsFirstAudioMs, m.ttsTotalMs)}',
            if (m.audioMs != null) 'audio=${m.audioMs}',
            if (m.model != null) 'model=${m.model}',
          ].join(' '),
        );
      case DevicesChangedEvent():
        log.add('devices', 'changed');
      case CaptionEvent() || MetersEvent() || BalanceEvent():
        break; // What was said, the levels and the balance stay out.
    }
  }

  void setup(SetupState s) {
    if (s.devices.isEmpty) return; // Not loaded yet.
    final list = s.devices.map(_device).join('\n');
    if (_last['devices'] != list) {
      _last['devices'] = list;
      log.add('devices', '${s.devices.length} on the system');
      for (final d in s.devices) {
        log.add('device', _device(d));
      }
    }
    _changed('mic', 'selection', 'mic ${_chosen(s.deviceByUid(s.micUid))}');
    _changed('headphones', 'selection', 'headphones ${_chosen(s.deviceByUid(s.headphonesUid))}');
    _changed('virtualMic', 'selection', 'virtual-mic ${_chosen(s.virtualMic)}');
    _changed(
      'session',
      'selection',
      'mode=${s.mode.wire} ${s.myLang}→${s.targetLang} commit=${s.outCommit.wire} '
          'sources=[${_sourceNames(s).join(', ')}]',
    );
    _changed(
      'settings',
      'settings',
      'ui=${s.uiLanguage ?? 'system'} statistics=${s.telemetryEnabled ? 'on' : 'off'} microphone-permission=${s.micPermission}',
    );
    if (s.lostDevices.isNotEmpty) {
      _changed('lost', 'devices', 'lost: ${s.lostDevices.map((d) => '${d.kind.name} "${d.name}"').join(', ')}');
    } else {
      _last.remove('lost');
    }
  }

  void connection(ConnectionState c, String gatewayUrl) {
    if (!c.loaded) return;
    final mode = c.mode;
    final email = mode == ConnectionMode.account ? c.account?.email : null;
    final host = switch (mode) {
      ConnectionMode.account || ConnectionMode.keys => gatewayHost(kHostedGateway),
      ConnectionMode.gateway => gatewayHost(gatewayUrl),
      null => '-',
    };
    _changed(
      'connection',
      'connection',
      'mode=${mode?.name ?? 'none'}${email == null ? '' : ' email=$email'} gateway=$host',
    );
    final signIn = switch (c.signIn) {
      SignInIdle() => 'idle',
      SignInWaiting(:final openFailed) => openFailed ? 'waiting (browser did not open)' : 'waiting',
      SignInFailed(:final reason) => 'failed $reason',
    };
    _changed('signIn', 'connection', 'sign-in $signIn');
    if (c.notice != null) _changed('notice', 'connection', 'notice ${c.notice}');
  }
}

String _errorText(ErrorEvent e) {
  final head = [e.code, if (e.fatal) 'fatal', if (e.direction != null) e.direction].join(' ');
  return e.message.trim().isEmpty ? head : '$head: ${e.message}';
}

/// Logs an error the app reported itself (a failed bridge call, a refused start); see `SessionNotifier.reportError`.
void recordAppError(DiagnosticLog log, ErrorEvent e) => log.add('error', 'app ${_errorText(e)}');
