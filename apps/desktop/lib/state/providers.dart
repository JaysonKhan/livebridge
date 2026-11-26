import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';

/// The native bridge. Tests override this with a fake.
final bridgeProvider = Provider<LiveBridge>((ref) => MethodChannelLiveBridge());

/// The saved settings, read once at startup and shared: each `loadSettings` reads the Keychain items and can raise a
/// system prompt per read.
final savedSettingsProvider = Provider<Future<Map<String, Object?>>>((ref) => ref.watch(bridgeProvider).loadSettings());

/// Opens a page in the default browser. Tests override this to record the addresses.
final urlOpenerProvider = Provider<Future<bool> Function(Uri url)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// The current time. Tests override this to move time on.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Waits. Tests override this so that nothing waits real seconds.
final delayProvider = Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

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
