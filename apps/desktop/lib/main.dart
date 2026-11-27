import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/diagnostics.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final folder = DiagnosticLog.defaultFolder();
  runLiveBridge(log: folder == null ? DiagnosticLog.memory() : await DiagnosticLog.open(folder));
}

/// [forcedLocale] overrides the saved and system language (the integration test pins English with it). [log] is the
/// diagnostic log (a memory-only one when absent); Flutter's and the platform's uncaught errors go into it too.
void runLiveBridge({Locale? forcedLocale, DiagnosticLog? log}) {
  final diagnostics = log ?? DiagnosticLog.memory();
  final flutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnostics.add('exception', describeError(details.exception, details.stack, context: 'flutter'));
    (flutterHandler ?? FlutterError.presentError)(details);
  };
  final platformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.add('exception', describeError(error, stack, context: 'platform'));
    return platformHandler?.call(error, stack) ?? false;
  };
  runApp(
    ProviderScope(
      overrides: [diagnosticLogProvider.overrideWithValue(diagnostics)],
      child: LiveBridgeApp(forcedLocale: forcedLocale),
    ),
  );
}
