import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/l10n/labels.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/ui/setup_panel.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

/// Every interface language on both platform looks, at the default window size, with every section of the setup
/// column built and opened: any clipped row (a RenderFlex overflow) fails the test. The test font draws every glyph
/// a full em wide, much wider than a real font, so passing here leaves room in the real app.
void main() {
  const windowSize = Size(1280, 720);

  /// Scrolls the setup column step by step to its end, so the lazy list builds (and lays out) every section.
  Future<void> scrollThroughSetup(WidgetTester tester) async {
    final scrollable = find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(0);
    await tester.pump();
    while (position.pixels < position.maxScrollExtent) {
      position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
      await tester.pump();
    }
  }

  Future<void> open(WidgetTester tester, String title) async {
    final scrollable = find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text(title), 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  for (final platform in HostPlatform.values) {
    for (final code in ['uz', 'ru', 'tr', 'en']) {
      testWidgets('${platform.name} / $code: nothing overflows at 1280×720', (tester) async {
        // No virtual microphone, so the longer "install BlackHole / VB-CABLE" notice is on screen too.
        final bridge = FakeLiveBridge(devices: [FakeLiveBridge.mic, FakeLiveBridge.headphones])
          ..summary = const AnalyticsSummary(
            sessions: 3,
            turns: 42,
            e2eMs: TimingStat(count: 40, p50: 811, p95: 1234, max: 2345),
            errors: {'tts_failed': 2},
            path: '/Users/x/LiveBridge/analytics.jsonl',
          );
        await pumpApp(tester, bridge: bridge, size: windowSize, forceLocale: Locale(code), platform: platform);
        final l = lookupAppLocalizations(Locale(code));

        // The session-language fields have room for the name of every interface language (they used to clip
        // "Узбекский" when the two sat side by side).
        for (final key in ['my-language', 'their-language']) {
          final field = tester
              .state<EditableTextState>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)))
              .renderEditable;
          for (final lang in ['uz', 'en', 'ru', 'tr']) {
            final painter = TextPainter(
              text: TextSpan(text: l.languageName(lang), style: field.text!.style),
              textDirection: TextDirection.ltr,
            )..layout();
            expect(painter.width, lessThanOrEqualTo(field.size.width), reason: '$key: ${l.languageName(lang)}');
            painter.dispose();
          }
        }

        await scrollThroughSetup(tester);
        await open(tester, l.testDevicesTitle);
        await open(tester, l.routingTitle);
        for (final topic in [l.routingZoomDesktopTitle, l.routingWebTitle, l.routingUpworkTitle, l.routingBackTitle]) {
          await open(tester, topic);
        }
        await open(tester, l.analyticsTitle);
        await scrollThroughSetup(tester);

        // The session side with every status tag and a captioned turn in each lane.
        await push(const StateEvent(state: EngineState.degraded, outReady: true, inReady: true, capturing: true));
        await push(const MetricsEvent(direction: Direction.out, e2eMs: 1842));
        await pushFinishedTurn(Direction.out, 1, 'Salom, qalaysiz?', 'Hello, how are you?');
        await pushFinishedTurn(Direction.incoming, 1, 'Fine, thanks.', 'Yaxshi, rahmat.');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
