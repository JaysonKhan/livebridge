import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app.dart';

void main() => runLiveBridge();

/// [forcedLocale] overrides the saved and system language (the integration test pins English with it).
void runLiveBridge({Locale? forcedLocale}) {
  runApp(ProviderScope(child: LiveBridgeApp(forcedLocale: forcedLocale)));
}
