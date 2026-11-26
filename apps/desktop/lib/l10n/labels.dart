import 'package:flutter/widgets.dart';

import '../bridge/languages.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';
import '../state/host_platform.dart';
import 'app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Maps enums and wire codes to localized text in one place.
extension AppLocalizationsLabels on AppLocalizations {
  /// A session language's name: our own wording for the four interface languages, the system's name
  /// ([systemNames], code -> name in the interface language) for the rest, the English name as a last resort.
  String languageName(String code, [Map<String, String> systemNames = const {}]) => switch (code) {
    'uz' => languageUz,
    'en' => languageEn,
    'ru' => languageRu,
    'tr' => languageTr,
    _ => systemNames[code] ?? kLanguages[code] ?? code,
  };

  String languagePair(String myLang, String theirLang, [Map<String, String> systemNames = const {}]) =>
      '${languageName(myLang, systemNames)} ↔ ${languageName(theirLang, systemNames)}';

  String modeTitle(SessionMode mode) => switch (mode) {
    SessionMode.captions => modeCaptionsTitle,
    SessionMode.incoming => modeIncomingTitle,
    SessionMode.bidirectional => modeBidirectionalTitle,
  };

  String engineState(EngineState s) => switch (s) {
    EngineState.idle => stateIdle,
    EngineState.connecting => stateConnecting,
    EngineState.ready => stateReady,
    EngineState.active => stateActive,
    EngineState.degraded => stateDegraded,
    EngineState.stopping => stateStopping,
  };

  String permissionStatus(String status) => switch (status) {
    'granted' => permissionGranted,
    'denied' => permissionDenied,
    _ => permissionUndetermined,
  };

  String laneTitle(Direction d) => d == Direction.out ? laneOut : laneIn;

  /// Why the voice list could not be shown.
  String voicesFailure(VoicesFailure failure) => switch (failure) {
    VoicesFailure.unauthorized => voicesUnauthorized,
    VoicesFailure.unsupported => voicesUnsupported,
    VoicesFailure.unavailable => voicesUnavailable,
    VoicesFailure.network => voicesNetwork,
    VoicesFailure.invalidKey => voicesInvalidKey,
  };

  String turnSkipped(SkipReason reason) => switch (reason) {
    SkipReason.sameLanguage => turnSkippedSameLanguage,
    SkipReason.echo => turnSkippedEcho,
  };

  /// A localized message for a known engine/gateway error code, or null (the caller then shows the raw message).
  String? errorMessage(String code, HostPlatform platform) => switch (code) {
    'provider_unavailable' => errProviderUnavailable,
    'translation_failed' => errTranslationFailed,
    'translation_rejected' => errTranslationRejected,
    'tts_failed' => errTtsFailed,
    'voice_not_found' => errVoiceNotFound,
    'capture_backlog' => errCaptureBacklog,
    'capture_overflow' => errCaptureOverflow,
    'synthesis_congested' => errSynthesisCongested,
    'playback_overflow' => errPlaybackOverflow,
    'source_gone' => errSourceGone,
    'device_removed' => errDeviceRemoved,
    'gateway_unreachable' => errGatewayUnreachable,
    'unauthorized' => errUnauthorized,
    'session_limit' => errSessionLimit,
    'session_expired' => errSessionExpired,
    'no_virtual_mic' => platform == HostPlatform.windows ? errNoVirtualMicWindows : errNoVirtualMic,
    'no_headphones' => errNoHeadphones,
    'no_microphone' => errNoMicrophone,
    'unsafe_route' => errUnsafeRoute,
    _ => null,
  };
}
