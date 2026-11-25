import '../bridge/models.dart';
import '../l10n/app_localizations.dart';
import 'host_platform.dart';
import 'setup_state.dart';

const blackHoleInstallHint = 'brew install blackhole-2ch';

/// Where Windows users get VB-CABLE (free).
const vbCableDownloadUrl = 'https://vb-audio.com/Cable/';

/// Reasons why Start must stay disabled. Empty means the route is safe to start.
List<String> startBlockers(SetupState s, AppLocalizations l, HostPlatform platform) {
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
  if (s.gatewayUrl.trim().isEmpty) reasons.add(l.blockEnterGateway);
  if (s.accessToken.trim().isEmpty) reasons.add(l.blockEnterToken);
  return reasons;
}
