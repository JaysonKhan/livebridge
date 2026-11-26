import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/bridge/voices_client.dart';
import 'package:livebridge/state/providers.dart';
import 'package:livebridge/state/setup_state.dart';

import 'fake_live_bridge.dart';
import 'fake_voices_client.dart';
import 'harness.dart';

const _token = 'secret-token';
const _aria = 'fakevoice0000000001';
const _bruno = 'fakevoice0000000002';

Finder get _outChange => find.byKey(const Key('voice-out-change'));
Finder get _inChange => find.byKey(const Key('voice-in-change'));
Finder get _picker => find.byKey(const Key('voice-picker'));
Finder get _rows => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> && key.value.startsWith('voice-row-');
});

bool _enabled(Finder button) => tt.widget<OutlinedButton>(button).onPressed != null;

String _text(String key) => tt.widget<Text>(find.byKey(Key(key))).data!;

/// The names in the open picker's rows, top to bottom.
List<String> _rowNames() => [
  for (final row in _rows.evaluate())
    tt.widget<Text>(find.descendant(of: find.byWidget(row.widget), matching: find.byType(Text)).first).data!,
];

/// The app with a token typed and both directions speaking.
Future<void> _pumpBidirectional(WidgetTester tester, {FakeVoicesClient? voices, FakeLiveBridge? bridge}) async {
  final c = await pumpApp(tester, voices: voices, bridge: bridge);
  c.read(setupProvider.notifier)
    ..setAccessToken(_token)
    ..setMode(SessionMode.bidirectional);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, Finder change) async {
  await tester.tap(change);
  await tester.pumpAndSettle();
  expect(_picker, findsOneWidget);
}

/// Picks an entry of one of the picker's filters.
Future<void> _filter(WidgetTester tester, String facet, String entry) async {
  await tester.tap(find.descendant(of: find.byKey(Key('voice-filter-$facet')), matching: find.byType(TextField)));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, entry).last);
  await tester.pumpAndSettle();
}

void main() {
  group('the Voices group', () {
    testWidgets('rows follow the mode', (tester) async {
      final c = await pumpApp(tester);
      await fillToken();
      expect(find.text(en.sectionVoices), findsOneWidget);
      expect(find.text(en.voiceOut), findsOneWidget);
      expect(find.text(en.voiceIn), findsOneWidget);
      // Captions only: nothing is spoken either way.
      expect([_enabled(_outChange), _enabled(_inChange)], [false, false]);

      c.read(setupProvider.notifier).setMode(SessionMode.incoming);
      await tester.pump();
      expect([_enabled(_outChange), _enabled(_inChange)], [false, true]);

      c.read(setupProvider.notifier).setMode(SessionMode.bidirectional);
      await tester.pump();
      expect([_enabled(_outChange), _enabled(_inChange)], [true, true]);
      // A row that cannot be changed keeps its text.
      expect(_text('voice-out-current'), en.voiceDefault);
      expect(_text('voice-in-current'), en.voiceDefault);
    });

    testWidgets('no token, no picker', (tester) async {
      final c = await pumpApp(tester);
      c.read(setupProvider.notifier).setMode(SessionMode.bidirectional);
      await tester.pump();
      expect([_enabled(_outChange), _enabled(_inChange)], [false, false]);
      expect(find.text(en.voiceNeedsToken), findsOneWidget);

      await fillToken();
      expect([_enabled(_outChange), _enabled(_inChange)], [true, true]);
      expect(find.text(en.voiceNeedsToken), findsNothing);
    });

    testWidgets('nothing is asked of the gateway until a picker opens', (tester) async {
      await _pumpBidirectional(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(fakeVoices.calls, isEmpty);

      await _open(tester, _outChange);
      expect(fakeVoices.calls, [(url: 'http://127.0.0.1:8201', token: _token)]);
    });

    testWidgets('a saved voice is shown by its name; an unknown saved voice shows its id', (tester) async {
      final bridge = FakeLiveBridge()
        ..settings = {
          'accessToken': 'saved-token',
          'mode': 'bidirectional',
          'outVoiceId': 'voiceNotInList0001',
          'inVoiceId': _bruno,
        };
      await pumpApp(tester, bridge: bridge);
      expect(_text('voice-out-current'), 'voiceNotInList0001');
      expect(_text('voice-in-current'), 'Fake Bruno');
      expect(fakeVoices.calls.length, 1);
      // "Default" is one click away.
      await _open(tester, _outChange);
      await tester.tap(find.byKey(const Key('voice-row-default')));
      await tester.pumpAndSettle();
      expect(_text('voice-out-current'), en.voiceDefault);
      expect(startEnabled(), isTrue);
    });

    testWidgets('typing the token does not ask the gateway on every keystroke', (tester) async {
      final bridge = FakeLiveBridge()..settings = {'accessToken': 'saved-token', 'inVoiceId': _bruno};
      final c = await pumpApp(tester, bridge: bridge);
      expect(fakeVoices.calls.length, 1);

      for (final typed in ['s', 'se', 'sec', 'secr', 'secre', 'secret']) {
        c.read(setupProvider.notifier).setAccessToken(typed);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fakeVoices.calls.length, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(fakeVoices.calls.length, 2);
      expect(fakeVoices.calls.last.token, 'secret');
    });
  });

  group('the picker', () {
    testWidgets('choosing a voice', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);
      expect(find.text(en.voicePickerTitleOut), findsOneWidget);
      expect(_rowNames(), [en.voiceDefault, 'Fake Aria', 'Fake Bruno', 'Fake Dilnoza', 'Fake Timur']);

      await tester.tap(find.text('Fake Bruno'));
      await tester.pumpAndSettle();
      expect(_picker, findsNothing);
      expect(_text('voice-out-current'), 'Fake Bruno');
      expect(_text('voice-in-current'), en.voiceDefault);
      final c = ProviderScope.containerOf(tester.element(startButton));
      expect(c.read(setupProvider).outVoiceId, _bruno);

      await tester.tap(startButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.consentCheckbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(fake.startedWith!.outVoiceId, _bruno);
      expect(fake.startedWith!.inVoiceId, isNull);
    });

    testWidgets('the incoming picker sets the other voice', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _inChange);
      expect(find.text(en.voicePickerTitleIn), findsOneWidget);
      await tester.tap(find.text('Fake Aria'));
      await tester.pumpAndSettle();
      expect(_text('voice-in-current'), 'Fake Aria');
      expect(_text('voice-out-current'), en.voiceDefault);
    });

    testWidgets('back to Default', (tester) async {
      await _pumpBidirectional(tester);
      final c = ProviderScope.containerOf(tester.element(startButton));
      c.read(setupProvider.notifier).setOutVoice(_bruno);
      await tester.pumpAndSettle();
      await _open(tester, _outChange);
      // The current voice is the marked one.
      expect(
        find.descendant(of: find.byKey(const Key('voice-row-$_bruno')), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(find.descendant(of: _rows, matching: find.byIcon(Icons.check)), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice-row-default')));
      await tester.pumpAndSettle();
      expect(_picker, findsNothing);
      expect(c.read(setupProvider).outVoiceId, isNull);
      expect(_text('voice-out-current'), en.voiceDefault);
    });

    testWidgets('the current voice comes first, right after Default', (tester) async {
      await _pumpBidirectional(tester);
      final c = ProviderScope.containerOf(tester.element(startButton));
      c.read(setupProvider.notifier).setOutVoice('fakevoice0000000004');
      await tester.pumpAndSettle();
      await _open(tester, _outChange);
      expect(_rowNames(), [en.voiceDefault, 'Fake Timur', 'Fake Aria', 'Fake Bruno', 'Fake Dilnoza']);
      // The other direction's picker keeps the list's own order.
      await tester.tap(find.widgetWithText(OutlinedButton, en.cancel));
      await tester.pumpAndSettle();
      await _open(tester, _inChange);
      expect(_rowNames(), [en.voiceDefault, 'Fake Aria', 'Fake Bruno', 'Fake Dilnoza', 'Fake Timur']);
    });

    testWidgets('the search field is ready to type into when the picker opens', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('tim');
      await tester.pumpAndSettle();
      expect(_rowNames(), [en.voiceDefault, 'Fake Timur']);
    });

    testWidgets('a list that stops being available takes its filters with it', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);
      expect(find.byKey(const Key('voice-filter-gender')), findsOneWidget);

      fakeVoices.failure = VoicesFailure.unavailable;
      ProviderScope.containerOf(tester.element(_picker))
          .invalidate(voicesProvider((url: 'http://127.0.0.1:8201', token: _token)));
      await tester.pumpAndSettle();
      expect(find.text(en.voicesUnavailable), findsOneWidget);
      expect(find.byKey(const Key('voice-filter-gender')), findsNothing);
      expect(_rowNames(), [en.voiceDefault]);
    });

    testWidgets('closing the picker without choosing keeps the choice', (tester) async {
      await _pumpBidirectional(tester);
      final c = ProviderScope.containerOf(tester.element(startButton));
      c.read(setupProvider.notifier).setOutVoice(_bruno);
      await tester.pumpAndSettle();
      await _open(tester, _outChange);
      await tester.tap(find.widgetWithText(OutlinedButton, en.cancel));
      await tester.pumpAndSettle();
      expect(_picker, findsNothing);
      expect(c.read(setupProvider).outVoiceId, _bruno);
    });

    testWidgets('filters and search narrow the list', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);

      await _filter(tester, 'gender', en.voiceGenderMale);
      expect(_rowNames(), [en.voiceDefault, 'Fake Bruno', 'Fake Timur']);
      await _filter(tester, 'age', en.voiceAgeOld);
      expect(_rowNames(), [en.voiceDefault, 'Fake Timur']);
      await _filter(tester, 'age', en.voiceFilterAll);
      await _filter(tester, 'gender', en.voiceFilterAll);
      expect(_rowNames().length, 5);

      await tester.enterText(find.byKey(const Key('voice-search')), 'dil');
      await tester.pumpAndSettle();
      expect(_rowNames(), [en.voiceDefault, 'Fake Dilnoza']);
      // The description is searched too, whatever the case.
      await tester.enterText(find.byKey(const Key('voice-search')), 'CALM NARR');
      await tester.pumpAndSettle();
      expect(_rowNames(), [en.voiceDefault, 'Fake Bruno']);

      await tester.enterText(find.byKey(const Key('voice-search')), 'nobody by this name');
      await tester.pumpAndSettle();
      expect(_rowNames(), [en.voiceDefault]);
      expect(find.text(en.voiceNoMatch), findsOneWidget);
    });

    testWidgets('a filter with one value is hidden', (tester) async {
      const voices = [
        Voice(id: 'fakevoice0000000011', name: 'One', gender: 'female', accent: 'american', age: 'middle_aged'),
        // The provider spells the same age two ways; that is one value, not two.
        Voice(id: 'fakevoice0000000012', name: 'Two', gender: 'male', accent: 'american', age: 'middle-aged'),
      ];
      await _pumpBidirectional(tester, voices: FakeVoicesClient(voices: voices));
      await _open(tester, _outChange);
      expect(find.byKey(const Key('voice-filter-gender')), findsOneWidget);
      for (final facet in ['accent', 'age', 'language', 'use']) {
        expect(find.byKey(Key('voice-filter-$facet')), findsNothing, reason: facet);
      }
    });

    testWidgets('samples', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);
      Finder play(String id) => find.byKey(Key('voice-play-$id'));
      IconButton button(String id) => tester.widget<IconButton>(play(id));

      // Voices without a sample cannot be played.
      expect(button('fakevoice0000000003').onPressed, isNull);
      expect(button('fakevoice0000000003').tooltip, en.voiceNoSample);
      expect(button(_aria).tooltip, en.voicePlaySample);

      // The outgoing direction speaks the other person's language (English by default): that sample is played.
      await tester.tap(play(_aria));
      await tester.pump();
      expect(fakeSamples.played, [FakeVoicesClient.ariaEnglishSample]);
      expect([button(_aria).tooltip, button(_bruno).tooltip], [en.voiceStopSample, en.voicePlaySample]);
      // Listening does not choose.
      expect(_picker, findsOneWidget);

      await tester.tap(play(_bruno));
      await tester.pump();
      expect(fakeSamples.played, [FakeVoicesClient.ariaEnglishSample, FakeVoicesClient.brunoSample]);
      expect([button(_aria).tooltip, button(_bruno).tooltip], [en.voicePlaySample, en.voiceStopSample]);

      fakeSamples.fail();
      await tester.pump();
      expect([button(_aria).tooltip, button(_bruno).tooltip], [en.voicePlaySample, en.voicePlaySample]);

      // The button of a playing sample stops it.
      await tester.tap(play(_bruno));
      await tester.pump();
      final stopsBefore = fakeSamples.stops;
      await tester.tap(play(_bruno));
      await tester.pump();
      expect(fakeSamples.stops, stopsBefore + 1);
      expect(button(_bruno).tooltip, en.voicePlaySample);

      // Closing the picker stops whatever plays.
      await tester.tap(play(_aria));
      await tester.pump();
      final stops = fakeSamples.stops;
      await tester.tap(find.widgetWithText(OutlinedButton, en.cancel));
      await tester.pumpAndSettle();
      expect(_picker, findsNothing);
      expect(fakeSamples.stops, stops + 1);
    });

    testWidgets('a filter chosen and a sample playing do not keep the picker from closing', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _outChange);
      await _filter(tester, 'gender', en.voiceGenderFemale);
      await tester.tap(find.byKey(const Key('voice-play-$_aria')));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, en.cancel));
      await tester.pumpAndSettle();
      expect(_picker, findsNothing);
    });

    testWidgets('the incoming picker plays the sample in my language, else the general one', (tester) async {
      await _pumpBidirectional(tester);
      await _open(tester, _inChange);
      // My language is Uzbek and Aria has no Uzbek sample.
      await tester.tap(find.byKey(const Key('voice-play-$_aria')));
      await tester.pump();
      expect(fakeSamples.played, [FakeVoicesClient.ariaSample]);
    });

    testWidgets('failures', (tester) async {
      await _pumpBidirectional(tester);
      final sentences = {
        VoicesFailure.unauthorized: en.voicesUnauthorized,
        VoicesFailure.unsupported: en.voicesUnsupported,
        VoicesFailure.unavailable: en.voicesUnavailable,
        VoicesFailure.network: en.voicesNetwork,
      };
      fakeVoices.failure = VoicesFailure.unauthorized;
      await _open(tester, _outChange);
      for (final MapEntry(key: failure, value: sentence) in sentences.entries) {
        fakeVoices.failure = failure;
        final asked = fakeVoices.calls.length;
        await tester.tap(find.byKey(const Key('voices-retry')));
        await tester.pumpAndSettle();
        expect(fakeVoices.calls.length, asked + 1, reason: failure.name);
        expect(find.text(sentence), findsOneWidget, reason: failure.name);
        // Going back to the default voice needs no list.
        expect(find.byKey(const Key('voice-row-default')), findsOneWidget);
        expect(startEnabled(), isTrue);
      }

      fakeVoices.failure = null;
      await tester.tap(find.byKey(const Key('voices-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('voices-retry')), findsNothing);
      expect(_rowNames().length, 5);
    });

    testWidgets('a list that is still loading shows progress', (tester) async {
      await _pumpBidirectional(tester);
      fakeVoices.gate = Completer<void>();
      await tester.tap(_outChange);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: _picker, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.byKey(const Key('voice-row-default')), findsOneWidget);

      fakeVoices.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_rowNames().length, 5);
    });

    testWidgets('many voices', (tester) async {
      final voices = [
        for (var i = 0; i < 300; i++)
          Voice(id: 'fakevoice${(1000 + i).toString().padLeft(10, '0')}', name: 'Voice number $i', gender: 'female'),
      ];
      await _pumpBidirectional(tester, voices: FakeVoicesClient(voices: voices));
      await _open(tester, _outChange);
      expect(find.text('Voice number 0'), findsOneWidget);
      expect(_rows.evaluate().length, lessThan(60));
      // The rest are reached by scrolling.
      await tester.scrollUntilVisible(
        find.text('Voice number 299'),
        2000,
        scrollable: find.descendant(of: _picker, matching: find.byType(Scrollable)).last,
      );
      expect(find.text('Voice number 299'), findsOneWidget);
    });
  });

  testWidgets('voice_not_found is explained', (tester) async {
    await pumpApp(tester);
    await push(const ErrorEvent(code: 'voice_not_found', message: 'raw gateway words', fatal: false));
    expect(find.textContaining(en.errVoiceNotFound), findsOneWidget);
    expect(find.textContaining('raw gateway words'), findsNothing);
  });
}
