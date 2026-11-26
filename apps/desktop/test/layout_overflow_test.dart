import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/l10n/labels.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/state/setup_state.dart';
import 'package:livebridge/ui/home_screen.dart';
import 'package:livebridge/ui/session_panel.dart';
import 'package:livebridge/ui/setup_panel.dart';

import 'fake_live_bridge.dart';
import 'fake_voices_client.dart';
import 'harness.dart';

/// Voices as wide as the provider's get: a 71-character name, every tag, the longest label values seen live.
const _wideVoices = [
  Voice(
    id: 'fakevoice0000000021',
    name: 'Sardor - Cheerful, Playful, Bright and Friendly Uzbek Conversation Voice',
    gender: 'male',
    age: 'middle_aged',
    accent: 'modern standard',
    language: 'uz',
    useCase: 'informative_educational',
    description: 'A long description that only the search reads.',
    previewUrl: 'https://samples.example/sardor.mp3',
  ),
  Voice(
    id: 'fakevoice0000000022',
    name: 'Short',
    gender: 'female',
    age: 'young',
    accent: 'american',
    language: 'en',
    useCase: 'characters_animation',
  ),
  Voice(id: 'fakevoice0000000023', name: 'No tags at all'),
];

/// Every interface language on both platform looks, at the default window size and on large screens, with every
/// section of the setup column built and opened: any clipped row (a RenderFlex overflow) fails the test. The test font
/// draws every glyph a full em wide, much wider than a real font, so passing here leaves room in the real app.
void main() {
  const windowSize = Size(1280, 720);

  ScrollPosition setupScroll(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(SetupPanel), matching: find.byType(Scrollable)).first)
      .position;

  /// Scrolls the setup column step by step to its end, so the lazy list builds (and lays out) every section.
  Future<void> scrollThroughSetup(WidgetTester tester) async {
    final position = setupScroll(tester);
    position.jumpTo(0);
    await tester.pump();
    while (position.pixels < position.maxScrollExtent) {
      position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
      await tester.pump();
    }
  }

  /// Opens a section of the setup column. Scrolls by position, not by dragging: a drag in the middle of the column
  /// can land on the meeting-source list and scroll that instead.
  Future<void> open(WidgetTester tester, String title) async {
    final position = setupScroll(tester);
    position.jumpTo(0);
    await tester.pump();
    while (find.text(title).evaluate().isEmpty && position.pixels < position.maxScrollExtent) {
      position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
      await tester.pump();
    }
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  /// Pumps the app at [size], checks the column widths, then builds, opens and fills everything.
  Future<void> exercise(WidgetTester tester, HostPlatform platform, String code, Size size) async {
    // No virtual microphone, so the longer "install BlackHole / VB-CABLE" notice is on screen too.
    final bridge = FakeLiveBridge(devices: [FakeLiveBridge.mic, FakeLiveBridge.headphones])
      ..summary = const AnalyticsSummary(
        sessions: 3,
        turns: 42,
        e2eMs: TimingStat(count: 40, p50: 811, p95: 1234, max: 2345),
        errors: {'tts_failed': 2},
        path: '/Users/x/LiveBridge/analytics.jsonl',
      );
    final c = await pumpApp(
      tester,
      bridge: bridge,
      voices: FakeVoicesClient(voices: _wideVoices),
      size: size,
      forceLocale: Locale(code),
      platform: platform,
    );
    final l = lookupAppLocalizations(Locale(code));

    // The setup column grows with the window up to 480; the session content stops at 1600 and stays centred.
    expect(tester.getSize(find.byType(SetupPanel)).width, setupColumnWidth(size.width));
    final session = find.byType(SessionPanel);
    final content = find.descendant(of: session, matching: find.byType(Column)).first;
    final contentRect = tester.getRect(content);
    expect(contentRect.width, lessThanOrEqualTo(SessionPanel.maxContentWidth));
    expect(contentRect.center.dx, moreOrLessEquals(tester.getRect(session).center.dx, epsilon: 0.5));

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

    // The Voices group with the longest voice name chosen, then its picker open with every filter and tag.
    c.read(setupProvider.notifier)
      ..setAccessToken('token')
      ..setMode(SessionMode.bidirectional)
      ..setOutVoice('fakevoice0000000021');
    await tester.pump(const Duration(seconds: 1));
    final change = find.byKey(const Key('voice-out-change'));
    final position = setupScroll(tester)..jumpTo(0);
    await tester.pump();
    while (change.evaluate().isEmpty && position.pixels < position.maxScrollExtent) {
      position.jumpTo(math.min(position.pixels + 200, position.maxScrollExtent));
      await tester.pump();
    }
    await tester.ensureVisible(change);
    await tester.pumpAndSettle();
    // The chosen voice is named in its row, however long the name.
    expect(find.text(_wideVoices.first.name), findsOneWidget);
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-picker')), findsOneWidget);
    expect(find.text(l.voicePickerTitleOut), findsOneWidget);
    for (final facet in ['gender', 'age', 'accent', 'language', 'use']) {
      expect(find.byKey(Key('voice-filter-$facet')), findsOneWidget, reason: facet);
    }
    final dialog = tester.getSize(find.byKey(const Key('voice-picker')));
    expect(dialog.width, lessThanOrEqualTo(560));
    expect(dialog.height, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, l.cancel));
    await tester.pumpAndSettle();
    c.read(setupProvider.notifier).setMode(SessionMode.captions);
    await tester.pump();

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
  }

  for (final platform in HostPlatform.values) {
    for (final code in ['uz', 'ru', 'tr', 'en']) {
      testWidgets('${platform.name} / $code: nothing overflows at 1280×720', (tester) async {
        await exercise(tester, platform, code, windowSize);
      });
      for (final size in const [Size(1920, 1200), Size(2560, 1440)]) {
        testWidgets('${platform.name} / $code: large screen ${size.width.round()}×${size.height.round()}', (
          tester,
        ) async {
          await exercise(tester, platform, code, size);
        });
      }
    }
  }
}
