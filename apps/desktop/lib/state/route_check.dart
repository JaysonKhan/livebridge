import '../bridge/models.dart';
import '../l10n/app_localizations.dart';
import 'setup_state.dart';

const blackHoleInstallHint = 'brew install blackhole-2ch';

/// Reasons why Start must stay disabled. Empty means the route is safe to start.
List<String> startBlockers(SetupState s, AppLocalizations l) {
  final reasons = <String>[];
  final mic = s.deviceByUid(s.micUid);
  final phones = s.deviceByUid(s.headphonesUid);
  final virtualMic = s.virtualMic;

  if (s.micUid == null) {
    reasons.add(l.blockChooseMic);
  } else if (virtualMic != null && s.micUid == virtualMic.uid) {
    reasons.add(l.blockMicIsVirtual(mic?.name ?? ''));
  }

  if (s.headphonesUid == null) {
    reasons.add(l.blockChooseHeadphones);
  } else if (phones != null && phones.isVirtual) {
    reasons.add(l.blockHeadphonesVirtual(phones.name));
  }

  if (s.mode == SessionMode.bidirectional && virtualMic == null) reasons.add(l.blockBidirectionalNeedsVirtual);
  if (s.mode == SessionMode.incoming && s.sourcePids.isEmpty) reasons.add(l.blockIncomingNeedsSource);
  if (s.myLang == s.targetLang) reasons.add(l.blockSameLanguages);
  if (s.gatewayUrl.trim().isEmpty) reasons.add(l.blockEnterGateway);
  if (s.accessToken.trim().isEmpty) reasons.add(l.blockEnterToken);
  return reasons;
}
