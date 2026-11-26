import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';

/// The native bridge. Tests override this with a fake.
final bridgeProvider = Provider<LiveBridge>((ref) => MethodChannelLiveBridge());

/// The session languages' names in one interface language (code -> name), from the system's locale data.
final languageNamesProvider = FutureProvider.family<Map<String, String>, String>(
  (ref, locale) => ref.watch(bridgeProvider).languageNames(locale),
);

/// Reads the gateway's voice list. Tests override this with a fake.
final voicesClientProvider = Provider<VoicesClient>((ref) => HttpVoicesClient());

/// The voices of one gateway, per address and access token. Nothing keeps it between uses: each picker that opens
/// reads the list anew, so neither a failure nor an old list outlives the dialog that showed it.
final voicesProvider = FutureProvider.autoDispose.family<List<Voice>, ({String url, String token})>(
  (ref, key) => ref.watch(voicesClientProvider).list(gatewayUrl: key.url, accessToken: key.token),
  // A failure is shown with a Retry button. Retrying unasked would hide it and keep asking a gateway that refused.
  retry: (_, _) => null,
);
