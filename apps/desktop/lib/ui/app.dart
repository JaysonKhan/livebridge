import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/setup_state.dart';
import 'home_screen.dart';

class LiveBridgeApp extends ConsumerWidget {
  const LiveBridgeApp({super.key, this.forcedLocale});

  /// Overrides the saved and system language. Tests use it to pin a language.
  final Locale? forcedLocale;

  static ThemeData _theme(Brightness b) =>
      ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal, brightness: b, visualDensity: VisualDensity.compact);

  /// The saved language wins, then the system language when it is supported, else English.
  static Locale _resolve(Locale? locale, Iterable<Locale> supported) =>
      supported.where((s) => s.languageCode == locale?.languageCode).firstOrNull ?? const Locale('en');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(setupProvider.select((s) => s.uiLanguage));
    return MaterialApp(
      title: 'LiveBridge AI',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: forcedLocale ?? (saved == null ? null : Locale(saved)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: _resolve,
      home: const HomeScreen(),
    );
  }
}
