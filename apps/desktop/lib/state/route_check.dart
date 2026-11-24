import '../bridge/models.dart';
import 'setup_state.dart';

const blackHoleMissingNotice = 'BlackHole 2ch not installed — outgoing speech unavailable; captions still work';
const blackHoleInstallHint = 'brew install blackhole-2ch';

/// Reasons why Start must stay disabled. Empty means the route is safe to start.
List<String> startBlockers(SetupState s) {
  final reasons = <String>[];
  final mic = s.deviceByUid(s.micUid);
  final phones = s.deviceByUid(s.headphonesUid);
  final virtualMic = s.virtualMic;

  if (s.micUid == null) {
    reasons.add('Choose a microphone.');
  } else if (virtualMic != null && s.micUid == virtualMic.uid) {
    reasons.add(
      'Unsafe route: the microphone is the same device as the virtual microphone (${mic?.name}). '
      'Choose your physical microphone.',
    );
  }

  if (s.headphonesUid == null) {
    reasons.add('Choose headphones.');
  } else if (phones != null && phones.isVirtual) {
    reasons.add('Unsafe route: the headphones are a virtual device (${phones.name}). Choose your physical headphones.');
  }

  if (s.mode == SessionMode.bidirectional && virtualMic == null) {
    reasons.add('Bidirectional speech needs a virtual microphone (BlackHole 2ch), which is not installed.');
  }
  if (s.mode == SessionMode.incoming && s.sourcePids.isEmpty) {
    reasons.add('Incoming audio needs at least one meeting source.');
  }
  if (s.gatewayUrl.trim().isEmpty) reasons.add('Enter the gateway URL.');
  if (s.accessToken.trim().isEmpty) reasons.add('Enter the access token.');
  return reasons;
}
