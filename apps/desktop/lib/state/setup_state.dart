import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/languages.dart';
import '../bridge/models.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'session_state.dart';

const Object _keep = Object();

enum LostDeviceKind { microphone, headphones }

/// A selected device that disappeared; the UI words the notice in the current language.
class LostDevice {
  const LostDevice(this.kind, this.name);

  final LostDeviceKind kind;
  final String name;
}

/// The voices chosen in one connection mode: one per direction (a provider voice id; null = the gateway's configured
/// voice) and what each is called, kept from the moment it was picked so that showing the choice never needs the
/// gateway. A null name shows the id.
class VoiceChoice {
  const VoiceChoice({this.outId, this.inId, this.outName, this.inName});

  static const none = VoiceChoice();

  final String? outId;
  final String? inId;
  final String? outName;
  final String? inName;

  VoiceChoice withOut(String? id, String? name) =>
      VoiceChoice(outId: id, inId: inId, outName: id == null ? null : name, inName: inName);

  VoiceChoice withIn(String? id, String? name) =>
      VoiceChoice(outId: outId, inId: id, outName: outName, inName: id == null ? null : name);
}

/// The preference key of a voice setting in [mode]. The own gateway keeps the names it always had (`outVoiceId`);
/// the other modes prefix theirs (`accountOutVoiceId`, `keysOutVoiceId`) since their voice lists differ.
String _voiceKey(ConnectionMode? mode, String base) => switch (mode) {
  ConnectionMode.account => 'account${base[0].toUpperCase()}${base.substring(1)}',
  ConnectionMode.keys => 'keys${base[0].toUpperCase()}${base.substring(1)}',
  ConnectionMode.gateway || null => base,
};

class SetupState {
  const SetupState({
    this.devices = const [],
    this.processes = const [],
    this.micUid,
    this.headphonesUid,
    this.sourcePids = const {},
    this.myLang = kDefaultMyLang,
    this.targetLang = kDefaultTargetLang,
    this.mode = SessionMode.captions,
    this.outCommit = OutCommit.manual,
    this.gatewayUrl = 'http://127.0.0.1:8201',
    this.accessToken = '',
    this.translationModel = '',
    this.voices = const {},
    this.micPermission = 'undetermined',
    this.lostDevices = const [],
    this.captionFontSize = 18,
    this.showOriginal = true,
    this.showTranslated = true,
    this.uiLanguage,
    this.telemetryEnabled = true,
  });

  final List<AudioDevice> devices;
  final List<AudioProcess> processes;
  final String? micUid;
  final String? headphonesUid;
  final Set<int> sourcePids;

  /// What the owner speaks and what the other participant speaks (codes from `kLanguages`).
  final String myLang;
  final String targetLang;
  final SessionMode mode;
  final OutCommit outCommit;
  final String gatewayUrl;
  final String accessToken;
  final String translationModel;

  /// The voices chosen in each connection mode: the lists differ, so the choice is remembered per mode.
  final Map<ConnectionMode, VoiceChoice> voices;

  /// The choice of [mode]; the own gateway's when null (onboarding has no Voices group).
  VoiceChoice voicesFor(ConnectionMode? mode) => voices[mode ?? ConnectionMode.gateway] ?? VoiceChoice.none;
  final String micPermission;
  final List<LostDevice> lostDevices;
  final double captionFontSize;
  final bool showOriginal;
  final bool showTranslated;

  /// The saved interface language (`uz`, `ru`, `tr`, `en`); null follows the system language.
  final String? uiLanguage;

  /// Upload the numbers-only analytics log to the developer: on unless the user switched it off (a saved `false`
  /// stays off) or switched the analytics log off before choosing.
  final bool telemetryEnabled;

  SetupState copyWith({
    List<AudioDevice>? devices,
    List<AudioProcess>? processes,
    Object? micUid = _keep,
    Object? headphonesUid = _keep,
    Set<int>? sourcePids,
    String? myLang,
    String? targetLang,
    SessionMode? mode,
    OutCommit? outCommit,
    String? gatewayUrl,
    String? accessToken,
    String? translationModel,
    Map<ConnectionMode, VoiceChoice>? voices,
    String? micPermission,
    List<LostDevice>? lostDevices,
    double? captionFontSize,
    bool? showOriginal,
    bool? showTranslated,
    Object? uiLanguage = _keep,
    bool? telemetryEnabled,
  }) => SetupState(
    devices: devices ?? this.devices,
    processes: processes ?? this.processes,
    micUid: identical(micUid, _keep) ? this.micUid : micUid as String?,
    headphonesUid: identical(headphonesUid, _keep) ? this.headphonesUid : headphonesUid as String?,
    sourcePids: sourcePids ?? this.sourcePids,
    myLang: myLang ?? this.myLang,
    targetLang: targetLang ?? this.targetLang,
    mode: mode ?? this.mode,
    outCommit: outCommit ?? this.outCommit,
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    accessToken: accessToken ?? this.accessToken,
    translationModel: translationModel ?? this.translationModel,
    voices: voices ?? this.voices,
    micPermission: micPermission ?? this.micPermission,
    lostDevices: lostDevices ?? this.lostDevices,
    captionFontSize: captionFontSize ?? this.captionFontSize,
    showOriginal: showOriginal ?? this.showOriginal,
    showTranslated: showTranslated ?? this.showTranslated,
    uiLanguage: identical(uiLanguage, _keep) ? this.uiLanguage : uiLanguage as String?,
    telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
  );

  /// Physical microphones (anything with input channels; a virtual one is refused by the route check).
  List<AudioDevice> get inputDevices => devices.where((d) => d.inputChannels > 0).toList();

  /// Physical headphones: outputs, excluding virtual devices.
  List<AudioDevice> get outputDevices => devices.where((d) => d.outputChannels > 0 && !d.isVirtual).toList();

  /// The virtual cable the translated speech is played into, so it needs output channels: VB-CABLE's "CABLE Input"
  /// on Windows, BlackHole on macOS (preferring the 2ch variant).
  AudioDevice? get virtualMic {
    final cables = devices.where((d) => d.isVirtualCable && d.outputChannels > 0).toList();
    bool named(AudioDevice d, String part) => d.name.toLowerCase().contains(part);
    return cables.where((d) => named(d, 'cable input')).firstOrNull ??
        cables.where((d) => named(d, '2ch')).firstOrNull ??
        cables.firstOrNull;
  }

  AudioDevice? deviceByUid(String? uid) => devices.where((d) => d.uid == uid).firstOrNull;

  /// Builds the `start` config with the voices of the [connection] mode (the own gateway's when null). Only valid when
  /// the route check has no blockers.
  StartConfig toConfig([ConnectionMode? connection]) => StartConfig(
    gatewayUrl: gatewayUrl.trim(),
    accessToken: accessToken.trim(),
    micUid: micUid!,
    headphonesUid: headphonesUid!,
    virtualMicUid: mode == SessionMode.bidirectional ? virtualMic?.uid : null,
    sourcePids: (sourcePids.toList()..sort()),
    myLang: myLang,
    targetLang: targetLang,
    mode: mode,
    outCommit: outCommit,
    translationModel: translationModel.trim().isEmpty ? null : translationModel.trim(),
    // Always both: the gateway ignores the voice of a direction that does not speak.
    outVoiceId: voicesFor(connection).outId,
    inVoiceId: voicesFor(connection).inId,
  );
}

/// A saved voice id or name, or null when nothing usable is saved.
String? _savedVoice(Object? value) => value is String && value.isNotEmpty ? value : null;

class SetupNotifier extends Notifier<SetupState> {
  @override
  SetupState build() {
    Future.microtask(load);
    return const SetupState();
  }

  Future<void> load() async {
    final bridge = ref.read(bridgeProvider);
    try {
      final saved = await ref.read(savedSettingsProvider);
      final devices = await bridge.listDevices();
      final processes = await bridge.listAudioProcesses();
      final permission = await bridge.microphonePermission();
      if (!ref.mounted) return;

      final base = state.copyWith(devices: devices, processes: processes, micPermission: permission);
      final savedMic = saved['micUid'] as String?;
      final savedPhones = saved['headphonesUid'] as String?;
      final mic =
          base.inputDevices.where((d) => d.uid == savedMic).firstOrNull ??
          base.inputDevices.where((d) => d.isDefaultInput && !d.isVirtual).firstOrNull;
      final phones =
          base.outputDevices.where((d) => d.uid == savedPhones).firstOrNull ??
          base.outputDevices.where((d) => d.isDefaultOutput).firstOrNull;
      final livePids = processes.map((p) => p.pid).toSet();
      final savedPids = (saved['sourcePids'] as List?)?.whereType<int>() ?? const <int>[];
      state = base.copyWith(
        micUid: mic?.uid,
        headphonesUid: phones?.uid,
        sourcePids: savedPids.where(livePids.contains).toSet(),
        gatewayUrl: saved['gatewayUrl'] as String?,
        accessToken: saved['accessToken'] as String?,
        translationModel: saved['translationModel'] as String?,
        voices: {
          for (final mode in ConnectionMode.values)
            mode: VoiceChoice(
              outId: _savedVoice(saved[_voiceKey(mode, 'outVoiceId')]),
              inId: _savedVoice(saved[_voiceKey(mode, 'inVoiceId')]),
              outName: _savedVoice(saved[_voiceKey(mode, 'outVoiceName')]),
              inName: _savedVoice(saved[_voiceKey(mode, 'inVoiceName')]),
            ),
        },
        myLang: kLanguages.containsKey(saved['myLang']) ? saved['myLang'] as String : null,
        targetLang: kLanguages.containsKey(saved['targetLang']) ? saved['targetLang'] as String : null,
        mode: parseWire(SessionMode.values, saved['mode']),
        outCommit: parseWire(OutCommit.values, saved['outCommit']),
        captionFontSize: (saved['captionFontSize'] as num?)?.clamp(12, 40).toDouble(),
        showOriginal: saved['showOriginal'] as bool?,
        showTranslated: saved['showTranslated'] as bool?,
        uiLanguage: AppLocalizations.supportedLocales.any((l) => l.languageCode == saved['uiLanguage'])
            ? saved['uiLanguage'] as String
            : null,
        // No saved choice: on, unless the analytics log (which sharing uploads) was switched off.
        telemetryEnabled: saved['telemetryEnabled'] as bool? ?? saved['analyticsEnabled'] != false,
      );
    } on Exception catch (e) {
      ref.read(sessionProvider.notifier).reportException(e, 'loadSettings');
    }
  }

  /// Re-queries devices (after `devicesChanged`). A selected device that vanished is cleared and reported.
  Future<void> refreshDevices() async {
    try {
      final devices = await ref.read(bridgeProvider).listDevices();
      if (!ref.mounted) return;
      final old = state;
      final lost = <LostDevice>[];
      var next = old.copyWith(devices: devices);
      if (old.micUid != null && !next.inputDevices.any((d) => d.uid == old.micUid)) {
        lost.add(LostDevice(LostDeviceKind.microphone, old.deviceByUid(old.micUid)?.name ?? old.micUid!));
        next = next.copyWith(micUid: null);
      }
      if (old.headphonesUid != null && !devices.any((d) => d.uid == old.headphonesUid && d.outputChannels > 0)) {
        lost.add(LostDevice(LostDeviceKind.headphones, old.deviceByUid(old.headphonesUid)?.name ?? old.headphonesUid!));
        next = next.copyWith(headphonesUid: null);
      }
      state = lost.isEmpty ? next : next.copyWith(lostDevices: lost);
    } on Exception catch (e) {
      ref.read(sessionProvider.notifier).reportException(e, 'listDevices');
    }
  }

  Future<void> refreshProcesses() async {
    try {
      final processes = await ref.read(bridgeProvider).listAudioProcesses();
      if (!ref.mounted) return;
      final live = processes.map((p) => p.pid).toSet();
      state = state.copyWith(processes: processes, sourcePids: state.sourcePids.where(live.contains).toSet());
    } on Exception catch (e) {
      ref.read(sessionProvider.notifier).reportException(e, 'listAudioProcesses');
    }
  }

  Future<void> refreshMicPermission({bool request = false}) async {
    final bridge = ref.read(bridgeProvider);
    try {
      if (request) await bridge.requestMicrophonePermission();
      final permission = await bridge.microphonePermission();
      if (ref.mounted) state = state.copyWith(micPermission: permission);
    } on Exception catch (e) {
      ref.read(sessionProvider.notifier).reportException(e, 'microphonePermission');
    }
  }

  void toggleSource(int pid, bool selected) {
    final next = {...state.sourcePids};
    selected ? next.add(pid) : next.remove(pid);
    state = state.copyWith(sourcePids: next);
  }

  void setMic(String? uid) => state = state.copyWith(micUid: uid);
  void setHeadphones(String? uid) => state = state.copyWith(headphonesUid: uid);
  void setMyLang(String v) => state = state.copyWith(myLang: v);
  void setTargetLang(String v) => state = state.copyWith(targetLang: v);
  void setMode(SessionMode v) => state = state.copyWith(mode: v);
  void setOutCommit(OutCommit v) => state = state.copyWith(outCommit: v);
  void setGatewayUrl(String v) => state = state.copyWith(gatewayUrl: v);
  void setAccessToken(String v) => state = state.copyWith(accessToken: v);
  void setTranslationModel(String v) => state = state.copyWith(translationModel: v);
  void dismissNotice() => state = state.copyWith(lostDevices: const []);

  /// Saves preference keys; a failure shows up in the error strip.
  void _persist(Map<String, Object?> preferences) => unawaited(
    ref
        .read(sessionProvider.notifier)
        .guard('saveSettings', () => ref.read(bridgeProvider).savePreferences(preferences)),
  );

  /// Chooses a direction's voice in the connection [mode] and saves the choice with its [name]; a null [id] goes back
  /// to the gateway's configured voice. The other modes' choices stay as they are.
  void setOutVoice(ConnectionMode mode, String? id, {String? name}) {
    final choice = state.voicesFor(mode).withOut(id, name);
    state = state.copyWith(voices: {...state.voices, mode: choice});
    _persist({_voiceKey(mode, 'outVoiceId'): choice.outId, _voiceKey(mode, 'outVoiceName'): choice.outName});
  }

  void setInVoice(ConnectionMode mode, String? id, {String? name}) {
    final choice = state.voicesFor(mode).withIn(id, name);
    state = state.copyWith(voices: {...state.voices, mode: choice});
    _persist({_voiceKey(mode, 'inVoiceId'): choice.inId, _voiceKey(mode, 'inVoiceName'): choice.inName});
  }

  void setShowOriginal(bool v) {
    state = state.copyWith(showOriginal: v);
    _persist({'showOriginal': v});
  }

  void setShowTranslated(bool v) {
    state = state.copyWith(showTranslated: v);
    _persist({'showTranslated': v});
  }

  void changeFontSize(double delta) {
    state = state.copyWith(captionFontSize: (state.captionFontSize + delta).clamp(12, 40).toDouble());
    _persist({'captionFontSize': state.captionFontSize});
  }

  void setUiLanguage(String code) {
    state = state.copyWith(uiLanguage: code);
    _persist({'uiLanguage': code});
  }

  /// Saves the choice to share anonymous statistics; completes when the preference is stored.
  Future<void> setTelemetryEnabled(bool v) async {
    state = state.copyWith(telemetryEnabled: v);
    await ref
        .read(sessionProvider.notifier)
        .guard('saveSettings', () => ref.read(bridgeProvider).savePreferences({'telemetryEnabled': v}));
  }
}

final setupProvider = NotifierProvider<SetupNotifier, SetupState>(SetupNotifier.new);
