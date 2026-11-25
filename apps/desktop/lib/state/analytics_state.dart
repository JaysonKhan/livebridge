import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import 'providers.dart';
import 'session_state.dart';

class AnalyticsState {
  const AnalyticsState({this.summary, this.enabled = true, this.loading = false});

  final AnalyticsSummary? summary;
  final bool enabled;
  final bool loading;

  AnalyticsState copyWith({AnalyticsSummary? summary, bool? enabled, bool? loading}) => AnalyticsState(
    summary: summary ?? this.summary,
    enabled: enabled ?? this.enabled,
    loading: loading ?? this.loading,
  );
}

class AnalyticsNotifier extends Notifier<AnalyticsState> {
  @override
  AnalyticsState build() => const AnalyticsState();

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final summary = await ref.read(bridgeProvider).analyticsSummary();
      if (ref.mounted) state = AnalyticsState(summary: summary, enabled: summary.enabled);
    } on Exception catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false);
      ref.read(sessionProvider.notifier).reportException(e, 'analyticsSummary');
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      await ref.read(bridgeProvider).savePreferences({'analyticsEnabled': value});
      if (ref.mounted) state = state.copyWith(enabled: value);
    } on Exception catch (e) {
      if (ref.mounted) ref.read(sessionProvider.notifier).reportException(e, 'saveSettings');
    }
  }

  /// Asks where to save the raw log. Returns the saved path, or null if cancelled or failed (failure is reported).
  Future<String?> exportLog() async {
    try {
      return await ref.read(bridgeProvider).analyticsExport();
    } on Exception catch (e) {
      if (ref.mounted) ref.read(sessionProvider.notifier).reportException(e, 'analyticsExport');
      return null;
    }
  }

  Future<void> clear() async {
    await ref.read(sessionProvider.notifier).guard('analyticsClear', ref.read(bridgeProvider).analyticsClear);
    if (ref.mounted) await refresh();
  }
}

final analyticsProvider = NotifierProvider<AnalyticsNotifier, AnalyticsState>(AnalyticsNotifier.new);
