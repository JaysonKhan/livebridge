import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';

/// The native bridge. Tests override this with a fake.
final bridgeProvider = Provider<LiveBridge>((ref) => MethodChannelLiveBridge());
