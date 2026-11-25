import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';

/// The native bridge. Tests override this with a fake.
final bridgeProvider = Provider<LiveBridge>((ref) => MethodChannelLiveBridge());

/// The session languages' names in one interface language (code -> name), from the system's locale data.
final languageNamesProvider = FutureProvider.family<Map<String, String>, String>(
  (ref, locale) => ref.watch(bridgeProvider).languageNames(locale),
);
