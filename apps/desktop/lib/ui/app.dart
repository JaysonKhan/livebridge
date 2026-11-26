import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/connection_state.dart';
import '../state/host_platform.dart';
import '../state/setup_state.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'theme/app_theme.dart';

class LiveBridgeApp extends ConsumerWidget {
  const LiveBridgeApp({super.key, this.forcedLocale});

  /// Overrides the saved and system language. Tests use it to pin a language.
  final Locale? forcedLocale;

  /// The saved language wins, then the system language when it is supported, else English.
  static Locale _resolve(Locale? locale, Iterable<Locale> supported) =>
      supported.where((s) => s.languageCode == locale?.languageCode).firstOrNull ?? const Locale('en');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(setupProvider.select((s) => s.uiLanguage));
    // The platform look (Fluent on Windows, macOS on the Mac) follows the host; light or dark follows the system.
    final platform = ref.watch(hostPlatformProvider);
    // The saved connection decides: nothing until it is read, the onboarding while none is chosen, else the app.
    final loaded = ref.watch(connectionProvider.select((s) => s.loaded));
    final chosen = ref.watch(connectionProvider.select((s) => s.mode != null));
    return MaterialApp(
      title: 'LiveBridge AI',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(platform, Brightness.light),
      darkTheme: buildTheme(platform, Brightness.dark),
      themeMode: ThemeMode.system,
      locale: forcedLocale ?? (saved == null ? null : Locale(saved)),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: _resolve,
      home: !loaded
          ? const Scaffold()
          : chosen
          ? const HomeScreen()
          : const OnboardingScreen(),
    );
  }
}
