import '../bridge/models.dart';
import '../l10n/app_localizations.dart';
import 'connection_state.dart';
import 'host_platform.dart';
import 'setup_state.dart';

const blackHoleInstallHint = 'brew install blackhole-2ch';

/// Where Windows users get VB-CABLE (free).
const vbCableDownloadUrl = 'https://vb-audio.com/Cable/';

/// Reasons why Start must stay disabled. Empty means the route is safe to start.
List<String> startBlockers(
  SetupState s,
  AppLocalizations l,
  HostPlatform platform, {
  ConnectionState connection = const ConnectionState(),
}) {
  final reasons = <String>[];
  final mic = s.deviceByUid(s.micUid);
  final phones = s.deviceByUid(s.headphonesUid);
  final virtualMic = s.virtualMic;
  final windows = platform == HostPlatform.windows;

  if (s.micUid == null) {
    reasons.add(l.blockChooseMic);
  } else if (virtualMic != null && s.micUid == virtualMic.uid) {
    reasons.add(l.blockMicIsVirtual(mic?.name ?? ''));
  } else if (mic != null && mic.isVirtualCable) {
    // E.g. VB-CABLE's "CABLE Output": the translation played into the cable would come back as the microphone.
    reasons.add(l.blockMicIsCable(mic.name));
  }

  if (s.headphonesUid == null) {
    reasons.add(l.blockChooseHeadphones);
  } else if (phones != null && phones.isVirtual) {
    reasons.add(l.blockHeadphonesVirtual(phones.name));
  }

  if (s.mode == SessionMode.bidirectional && virtualMic == null) {
    reasons.add(windows ? l.blockBidirectionalNeedsVirtualWindows : l.blockBidirectionalNeedsVirtual);
  }
  if (s.mode == SessionMode.incoming && s.sourcePids.isEmpty) reasons.add(l.blockIncomingNeedsSource);
  if (s.myLang == s.targetLang) reasons.add(l.blockSameLanguages);
  switch (connection.mode) {
    case ConnectionMode.account:
      // Only a balance known to be empty blocks; an unknown one (offline) never does.
      final balance = connection.account?.balanceUnits;
      if (balance != null && balance <= 0) reasons.add(l.blockBalanceEmpty);
    case ConnectionMode.keys:
      if (!connection.hasKeys) reasons.add(l.blockEnterKeys);
    case ConnectionMode.gateway || null:
      if (s.gatewayUrl.trim().isEmpty) reasons.add(l.blockEnterGateway);
      if (s.accessToken.trim().isEmpty) reasons.add(l.blockEnterToken);
  }
  return reasons;
}

/// Device choices that work but are probably not what the person wants. Unlike [startBlockers] they never keep Start
/// off.
List<String> routeWarnings(SetupState s, AppLocalizations l, HostPlatform platform) {
  final warnings = <String>[];
  final mic = s.deviceByUid(s.micUid);
  final phones = s.deviceByUid(s.headphonesUid);

  // Recording from a Bluetooth headset makes Windows switch it to the Hands-Free profile (the AirPods case).
  if (platform == HostPlatform.windows && mic?.transport == 'bluetooth') warnings.add(l.warnBluetoothMicWindows);

  // Captions only play nothing, so where the headphones are does not matter then. A virtual cable as the system
  // output is a routing of its own, not where the person listens.
  final systemOutput = s.outputDevices.where((d) => d.isDefaultOutput).firstOrNull;
  if (s.mode != SessionMode.captions &&
      phones != null &&
      !phones.isVirtual &&
      systemOutput != null &&
      systemOutput.uid != phones.uid) {
    warnings.add(l.warnHeadphonesNotSystemOutput(phones.name, systemOutput.name));
  }
  return warnings;
}
