import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/bug_report_client.dart';
import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';
import 'connection_state.dart';
import 'diagnostics.dart';

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

/// Sends problem reports to the developer's site. Tests override this with a fake.
final bugReportClientProvider = Provider<BugReportClient>(
  (ref) => HttpBugReportClient(
    onFailure: (path, status, code) =>
        ref.read(diagnosticLogProvider).add('http', 'site $path → ${status ?? '-'} $code'),
  ),
);

/// Reads the gateway's voice list. Tests override this with a fake.
final voicesClientProvider = Provider<VoicesClient>(
  (ref) => HttpVoicesClient(
    onFailure: (path, status, code) =>
        ref.read(diagnosticLogProvider).add('http', 'gateway $path → ${status ?? '-'} $code'),
  ),
);

/// The voices the current connection may use, per mode (and, for the own gateway, its address). The credential is not
/// part of the key: it is fetched inside, from the connection. Nothing keeps it between uses: each picker that opens
/// reads the list anew, so neither a failure nor an old list outlives the dialog that showed it.
final voicesProvider = FutureProvider.autoDispose.family<List<Voice>, ({ConnectionMode mode, String url})>(
  (ref, key) async {
    final client = ref.watch(voicesClientProvider);
    final connection = ref.read(connectionProvider.notifier);
    // Never ask in another mode's name than the one this list was opened for (a sign-out in between changes it).
    void checkMode() {
      if (ref.read(connectionProvider).mode != key.mode) throw const VoicesException(VoicesFailure.unauthorized);
    }

    var access = await connection.voicesAccess();
    checkMode();
    try {
      return await client.list(gatewayUrl: access.url, auth: access.auth);
    } on VoicesException catch (e) {
      // An account's access token can be refused just as it ran out: refresh it once and ask again.
      if (key.mode != ConnectionMode.account || e.failure != VoicesFailure.unauthorized) rethrow;
    }
    checkMode();
    access = await connection.voicesAccess(forceRefresh: true);
    checkMode();
    return client.list(gatewayUrl: access.url, auth: access.auth);
  },
  // A failure is shown with a Retry button. Retrying unasked would hide it and keep asking a gateway that refused.
  retry: (_, _) => null,
);
