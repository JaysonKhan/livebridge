import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/ui/setup_panel.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

const _tall = Size(1280, 4000);

const _summary = AnalyticsSummary(
  sessions: 3,
  turns: 42,
  firstAt: '2026-11-20T10:15:00',
  lastAt: '2026-11-24T18:30:00',
  e2eMs: TimingStat(count: 40, p50: 811, p95: 1234, max: 2345),
  ttsFirstAudioMs: TimingStat(count: 12, p50: 301, p95: 452, max: 503),
  errors: {'tts_failed': 2},
  reconnects: 1,
  emptyTurns: 4,
  ratedGood: 5,
  ratedBad: 6,
  fileSizeBytes: 2048,
  path: '/Users/x/LiveBridge/analytics.jsonl',
);

Future<void> openAnalytics(WidgetTester tester) async {
  final scrollable = find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text(en.analyticsTitle), 300, scrollable: scrollable);
  await tester.tap(find.text(en.analyticsTitle));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the summary loads when the section opens and renders counts and timing rows', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..summary = _summary, size: _tall);
    expect(fake.count('analyticsSummary'), 0);
    await openAnalytics(tester);
    expect(fake.count('analyticsSummary'), 1);

    expect(find.text('Sessions: 3'), findsOneWidget);
    expect(find.text('Translated turns: 42'), findsOneWidget);
    expect(find.text('First record: 2026-11-20 10:15'), findsOneWidget);
    expect(find.text('Last record: 2026-11-24 18:30'), findsOneWidget);
    expect(find.text('Reconnects: 1'), findsOneWidget);
    expect(find.text('Empty turns: 4'), findsOneWidget);
    expect(find.text('Rated good: 5'), findsOneWidget);
    expect(find.text('Rated bad: 6'), findsOneWidget);
    expect(find.text('tts_failed: 2'), findsOneWidget);
    expect(find.text('Log size: 2.0 KB'), findsOneWidget);
    expect(find.text('File: /Users/x/LiveBridge/analytics.jsonl'), findsOneWidget);

    // End-to-end row: count, p50, p95, max.
    expect(find.text(en.analyticsRowE2e), findsOneWidget);
    for (final v in ['40', '811', '1234', '2345']) {
      expect(find.text(v), findsOneWidget);
    }
    expect(find.text(en.analyticsRowTtsFirst), findsOneWidget);
    expect(find.text('503'), findsOneWidget);
  });

  testWidgets('timing rows without data are not shown', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..summary = _summary, size: _tall);
    await openAnalytics(tester);
    expect(find.text(en.analyticsRowStt), findsNothing);
    expect(find.text(en.analyticsRowTranslateFirst), findsNothing);
    expect(find.text(en.analyticsRowTranslateTotal), findsNothing);
  });

  testWidgets('the whole timing table is hidden when there are no timings, and no errors reads as such', (
    tester,
  ) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..summary = const AnalyticsSummary(sessions: 1), size: _tall);
    await openAnalytics(tester);
    expect(find.text('Sessions: 1'), findsOneWidget);
    expect(find.text(en.analyticsColCount), findsNothing);
    expect(find.text(en.analyticsNoErrors), findsOneWidget);
  });

  testWidgets('the section says the log is numbers only and stays on this Mac', (tester) async {
    await pumpApp(tester, size: _tall);
    await openAnalytics(tester);
    expect(find.textContaining('numbers only'), findsOneWidget);
    expect(find.textContaining('no transcript text'), findsOneWidget);
    expect(find.textContaining('stays on this Mac'), findsOneWidget);
  });

  testWidgets('the switch persists analyticsEnabled', (tester) async {
    await pumpApp(tester, size: _tall);
    await openAnalytics(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('analytics-switch'))).value, isTrue);
    await tapVisible(tester, find.byKey(const Key('analytics-switch')));
    expect(fake.savedPrefs.last, {'analyticsEnabled': false});
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('analytics-switch'))).value, isFalse);
    await tapVisible(tester, find.byKey(const Key('analytics-switch')));
    expect(fake.savedPrefs.last, {'analyticsEnabled': true});
  });

  testWidgets('Refresh loads the summary again', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..summary = _summary, size: _tall);
    await openAnalytics(tester);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, en.refresh).last);
    expect(fake.count('analyticsSummary'), 2);
  });

  testWidgets('the summary reloads after a session ends', (tester) async {
    await pumpApp(tester, size: _tall);
    await openAnalytics(tester);
    expect(fake.count('analyticsSummary'), 1);
    await push(readyState);
    expect(fake.count('analyticsSummary'), 1);
    await push(const StateEvent(state: EngineState.idle));
    await tester.pumpAndSettle();
    expect(fake.count('analyticsSummary'), 2);
  });

  testWidgets('Clear log asks first, then clears and refreshes', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..summary = _summary, size: _tall);
    await openAnalytics(tester);

    await tapVisible(tester, find.text(en.analyticsClearLog));
    expect(find.text(en.analyticsClearTitle), findsOneWidget);
    expect(fake.calls, isNot(contains('analyticsClear')));

    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(fake.calls, isNot(contains('analyticsClear')));

    await tapVisible(tester, find.text(en.analyticsClearLog));
    await tester.tap(find.text(en.delete));
    await tester.pumpAndSettle();
    expect(fake.count('analyticsClear'), 1);
    expect(fake.count('analyticsSummary'), 2);
  });

  testWidgets('Export log calls analyticsExport and confirms the saved path', (tester) async {
    await pumpApp(tester, size: _tall);
    await openAnalytics(tester);
    await tapVisible(tester, find.text(en.analyticsExportLog));
    expect(fake.count('analyticsExport'), 1);
    expect(find.text('Saved to ${fake.analyticsExportResult}'), findsOneWidget);
  });

  testWidgets('Export log does nothing visible when the Save dialog is cancelled', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..analyticsExportResult = null, size: _tall);
    await openAnalytics(tester);
    await tapVisible(tester, find.text(en.analyticsExportLog));
    expect(fake.count('analyticsExport'), 1);
    expect(find.byType(SnackBar), findsNothing);
  });
}
