import 'package:flutter/widgets.dart';

import '../bridge/models.dart';
import 'app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Maps enums and wire codes to localized text in one place.
extension AppLocalizationsLabels on AppLocalizations {
  String languagePair(TargetLang lang) => lang == TargetLang.en ? pairEn : pairRu;

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

  /// A localized message for a known engine/gateway error code, or null (the caller then shows the raw message).
  String? errorMessage(String code) => switch (code) {
    'provider_unavailable' => errProviderUnavailable,
    'translation_failed' => errTranslationFailed,
    'translation_rejected' => errTranslationRejected,
    'tts_failed' => errTtsFailed,
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
    'no_virtual_mic' => errNoVirtualMic,
    'no_headphones' => errNoHeadphones,
    'no_microphone' => errNoMicrophone,
    'unsafe_route' => errUnsafeRoute,
    _ => null,
  };
}
