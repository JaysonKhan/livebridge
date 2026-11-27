import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/ui/analytics_section.dart' show statsPageUrl;

import 'analytics_test.dart' show openAnalytics, tapVisible;
import 'fake_live_bridge.dart';
import 'harness.dart';

const _tall = Size(1280, 4000);

Finder get _switch => find.byKey(const Key('telemetry-switch'));
bool _switchOn(WidgetTester t) => t.widget<SwitchListTile>(_switch).value;
Finder get _sendBtn => find.byKey(const Key('feedback-send'));
bool _canSend(WidgetTester t) => t.widget<FilledButton>(_sendBtn).onPressed != null;

Future<void> _openFeedback(WidgetTester tester) async {
  await openAnalytics(tester);
  await tapVisible(tester, find.byKey(const Key('feedback-button')));
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

void main() {
  group('statistics sharing', () {
    testWidgets('is on when nothing was saved, and saves nothing', (tester) async {
      await pumpApp(tester, size: _tall);
      await openAnalytics(tester);
      expect(_switchOn(tester), isTrue);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('an earlier "off" stays off', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'telemetryEnabled': false}, size: _tall);
      await openAnalytics(tester);
      expect(_switchOn(tester), isFalse);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('switching the default off saves false with no dialog', (tester) async {
      await pumpApp(tester, size: _tall);
      await openAnalytics(tester);
      await tapVisible(tester, _switch);
      expect(find.text(en.telemetryDialogTitle), findsNothing);
      expect(fake.savedPrefs.last, {'telemetryEnabled': false});
      expect(_switchOn(tester), isFalse);
    });

    testWidgets('turning it on asks first; Cancel leaves it off and saves nothing', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'telemetryEnabled': false}, size: _tall);
      await openAnalytics(tester);
      await tapVisible(tester, _switch);

      expect(find.text(en.telemetryDialogTitle), findsOneWidget);
      expect(find.text(en.telemetryDialogSent), findsOneWidget);
      expect(find.text(en.telemetryDialogNever), findsOneWidget);
      expect(find.text(en.telemetryDialogWhere), findsOneWidget);
      expect(find.text(en.telemetryDialogOff), findsOneWidget);
      expect(find.textContaining('jaysonkhan.com'), findsWidgets);
      expect(fake.savedPrefs, isEmpty);

      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      expect(_switchOn(tester), isFalse);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('Confirm saves telemetryEnabled true; turning it off saves false with no dialog', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'telemetryEnabled': false}, size: _tall);
      await openAnalytics(tester);
      final before = fake.count('telemetryStatus');

      await tapVisible(tester, _switch);
      await tester.tap(find.text(en.confirm));
      await tester.pumpAndSettle();
      expect(fake.savedPrefs.last, {'telemetryEnabled': true});
      expect(_switchOn(tester), isTrue);
      expect(fake.count('telemetryStatus'), greaterThan(before), reason: 'status refreshed after toggling');

      await tapVisible(tester, _switch);
      expect(find.text(en.telemetryDialogTitle), findsNothing);
      expect(fake.savedPrefs.last, {'telemetryEnabled': false});
      expect(_switchOn(tester), isFalse);
    });

    testWidgets('a saved true is restored at startup', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'telemetryEnabled': true}, size: _tall);
      await openAnalytics(tester);
      expect(_switchOn(tester), isTrue);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('is disabled, with a hint, while local analytics is off', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..summary = const AnalyticsSummary(enabled: false), size: _tall);
      await openAnalytics(tester);
      expect(tester.widget<SwitchListTile>(_switch).onChanged, isNull);
      expect(find.text(en.telemetryNeedsAnalytics), findsOneWidget);
      await tester.tap(_switch, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text(en.telemetryDialogTitle), findsNothing);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('the hint is not shown while analytics is on', (tester) async {
      await pumpApp(tester, size: _tall);
      await openAnalytics(tester);
      expect(tester.widget<SwitchListTile>(_switch).onChanged, isNotNull);
      expect(find.text(en.telemetryNeedsAnalytics), findsNothing);
    });

    testWidgets('the status block shows pending count, last upload, last error and the install ID', (tester) async {
      const id = '3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11';
      await pumpApp(
        tester,
        bridge: FakeLiveBridge()
          ..telemetry = const TelemetryStatus(
            enabled: true,
            installId: id,
            pendingRecords: 7,
            lastUploadAt: '2026-11-24T18:30:00',
            lastError: 'HTTP 503',
          ),
        size: _tall,
      );
      await openAnalytics(tester);
      expect(find.text('Records waiting to upload: 7'), findsOneWidget);
      expect(find.text('Last upload: 2026-11-24 18:30'), findsOneWidget);
      expect(find.text('Last upload error: HTTP 503'), findsOneWidget);
      expect(find.text(id), findsOneWidget);
    });

    testWidgets('with no upload yet: "never", no error line and no install ID', (tester) async {
      await pumpApp(tester, size: _tall);
      await openAnalytics(tester);
      expect(find.text('Records waiting to upload: 0'), findsOneWidget);
      expect(find.text('Last upload: never'), findsOneWidget);
      expect(find.textContaining('Last upload error'), findsNothing);
      expect(find.textContaining(en.telemetryInstallId), findsNothing);
    });

    testWidgets('the status reloads when the section opens and after a session ends', (tester) async {
      await pumpApp(tester, size: _tall);
      // Once at launch: the diagnostic log records the app's version from it.
      expect(fake.count('telemetryStatus'), 1);
      await openAnalytics(tester);
      expect(fake.count('telemetryStatus'), 2);
      await push(readyState);
      await push(const StateEvent(state: EngineState.idle));
      await tester.pumpAndSettle();
      expect(fake.count('telemetryStatus'), 3);
    });

    testWidgets('shows the public statistics address and Copy puts it on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpApp(tester, size: _tall);
      await openAnalytics(tester);
      expect(statsPageUrl, 'https://jaysonkhan.com/services/livebridge/');
      expect(find.text(statsPageUrl), findsOneWidget);
      await tapVisible(tester, find.text(en.copy));
      expect(copied, statsPageUrl);
      expect(find.text(en.copied), findsOneWidget);
    });
  });

  group('feedback', () {
    testWidgets('Send is disabled until a message is typed', (tester) async {
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      expect(find.text(en.feedbackNote), findsOneWidget);
      expect(_canSend(tester), isFalse);
      await _type(tester, 'feedback-message', '   ');
      expect(_canSend(tester), isFalse);
      await _type(tester, 'feedback-message', 'Great');
      expect(_canSend(tester), isTrue);
    });

    testWidgets('a message over 2000 characters cannot be sent', (tester) async {
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'a' * 2000);
      expect(find.text('2000/2000'), findsOneWidget);
      expect(_canSend(tester), isTrue);
      await _type(tester, 'feedback-message', 'a' * 2001);
      expect(find.text('2001/2000'), findsOneWidget);
      expect(_canSend(tester), isFalse);
    });

    testWidgets('an e-mail without "@" is rejected; empty is fine', (tester) async {
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Hello');
      await _type(tester, 'feedback-email', 'not-an-email');
      expect(_canSend(tester), isFalse);
      expect(find.text(en.feedbackEmailInvalid), findsOneWidget);
      await _type(tester, 'feedback-email', 'me@example.com');
      expect(_canSend(tester), isTrue);
      expect(find.text(en.feedbackEmailInvalid), findsNothing);
      await _type(tester, 'feedback-email', '');
      expect(_canSend(tester), isTrue);
    });

    testWidgets('star taps set and clear the rating, and the stars have labels', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.bySemanticsLabel(en.feedbackStar(3)), findsOneWidget);

      await tester.tap(find.byKey(const Key('feedback-star-3')));
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNWidgets(3));
      expect(find.byIcon(Icons.star_border), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNWidgets(5));

      await tester.tap(find.byKey(const Key('feedback-star-5')));
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNothing);
      semantics.dispose();
    });

    testWidgets('success sends message, e-mail and rating, closes the dialog and confirms', (tester) async {
      final bridge = FakeLiveBridge()..feedbackGate = Completer<void>();
      await pumpApp(tester, bridge: bridge, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', '  Tarjima tez  ');
      await _type(tester, 'feedback-email', ' me@example.com ');
      await tester.tap(find.byKey(const Key('feedback-star-4')));
      await tester.pump();

      await tester.tap(_sendBtn);
      await tester.pump();
      expect(fake.feedbacks, hasLength(1));
      expect(fake.feedbacks.single.message, 'Tarjima tez');
      expect(fake.feedbacks.single.email, 'me@example.com');
      expect(fake.feedbacks.single.rating, 4);
      expect(_canSend(tester), isFalse, reason: 'disabled while the call runs');

      bridge.feedbackGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback-message')), findsNothing);
      expect(find.text(en.feedbackSent), findsOneWidget);
    });

    testWidgets('an empty e-mail and no rating are sent as null', (tester) async {
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Hi');
      await tester.tap(_sendBtn);
      await tester.pumpAndSettle();
      expect(fake.feedbacks.single.email, isNull);
      expect(fake.feedbacks.single.rating, isNull);
    });

    testWidgets('rate_limited keeps the dialog and the text and says so', (tester) async {
      await pumpApp(
        tester,
        bridge: FakeLiveBridge()..feedbackError = PlatformException(code: 'rate_limited'),
        size: _tall,
      );
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Keep me');
      await _type(tester, 'feedback-email', 'me@example.com');
      await tester.tap(find.byKey(const Key('feedback-star-2')));
      await tester.pump();
      await tester.tap(_sendBtn);
      await tester.pumpAndSettle();

      expect(find.text(en.feedbackRateLimited), findsOneWidget);
      expect(find.text(en.feedbackFailed), findsNothing);
      expect(find.text('Keep me'), findsOneWidget);
      expect(find.text('me@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(2));
      expect(_canSend(tester), isTrue, reason: 'the user can try again');
      expect(find.text(en.feedbackSent), findsNothing);
    });

    testWidgets('any other failure shows the generic message and keeps the text', (tester) async {
      await pumpApp(
        tester,
        bridge: FakeLiveBridge()..feedbackError = PlatformException(code: 'feedback_failed'),
        size: _tall,
      );
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Keep me');
      await tester.tap(_sendBtn);
      await tester.pumpAndSettle();

      expect(find.text(en.feedbackFailed), findsOneWidget);
      expect(find.text(en.feedbackRateLimited), findsNothing);
      expect(find.text('Keep me'), findsOneWidget);

      // A retry that works clears the error and closes the dialog.
      fake.feedbackError = null;
      await tester.tap(_sendBtn);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback-message')), findsNothing);
      expect(fake.feedbacks, hasLength(2));
    });

    testWidgets('works with statistics sharing off', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..settings = {'telemetryEnabled': false}, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Hi');
      await tester.tap(_sendBtn);
      await tester.pumpAndSettle();
      expect(fake.count('sendFeedback'), 1);
      expect(fake.savedPrefs, isEmpty);
    });

    testWidgets('Cancel closes without sending', (tester) async {
      await pumpApp(tester, size: _tall);
      await _openFeedback(tester);
      await _type(tester, 'feedback-message', 'Never mind');
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feedback-message')), findsNothing);
      expect(fake.count('sendFeedback'), 0);
    });
  });
}
