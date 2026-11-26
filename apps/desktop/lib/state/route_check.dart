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
