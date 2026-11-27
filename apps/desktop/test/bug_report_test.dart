import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/bug_report_client.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/state/providers.dart';

import 'analytics_test.dart' show openAnalytics, tapVisible;
import 'fake_live_bridge.dart';
import 'harness.dart';

Finder get _icon => find.byKey(const Key('report-problem'));
Finder get _send => find.byKey(const Key('report-send'));
Finder get _message => find.byKey(const Key('report-message'));
Finder get _email => find.byKey(const Key('report-email'));

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_icon);
  await tester.pumpAndSettle();
}

Future<void> _describe(WidgetTester tester, String text) async {
  await tester.enterText(_message, text);
  await tester.pump();
}

bool _sendEnabled(WidgetTester tester) => tester.widget<FilledButton>(_send).onPressed != null;

String _field(WidgetTester tester, Finder f) => tester.widget<TextField>(f).controller!.text;

Future<void> _hang(Duration _) => Completer<void>().future;

const _status = TelemetryStatus(
  enabled: true,
  installId: '3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11',
  endpoint: 'https://collector.test/api/services/v1',
  appVersion: '1.2.1+4',
  osVersion: 'macOS 26.6.2',
);

void main() {
  group('Report a problem', () {
    testWidgets('the bug icon sits at the right of the main header and opens the dialog', (tester) async {
      await pumpApp(tester);
      final header = tester.getRect(find.byKey(const Key('platform-header')));
      final icon = tester.getRect(_icon);
      expect(icon.left, greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('language-picker'))).right));
      expect(header.right - icon.right, lessThan(40));
      expect(tester.widget<IconButton>(_icon).tooltip, en.reportButton);
      await _open(tester);
      expect(find.text(en.reportMessageLabel), findsOneWidget);
    });

    testWidgets('the onboarding has it too', (tester) async {
      await pumpApp(tester, onboarding: true, overrides: [delayProvider.overrideWithValue(_hang)]);
      await _open(tester);
      expect(find.text(en.reportMessageLabel), findsOneWidget);
    });

    testWidgets('Send is off until a description is written', (tester) async {
      await pumpApp(tester);
      await _open(tester);
      expect(_sendEnabled(tester), isFalse);
      await _describe(tester, '   ');
      expect(_sendEnabled(tester), isFalse);
      await _describe(tester, 'No sound in my AirPods');
      expect(_sendEnabled(tester), isTrue);
      await tester.enterText(_email, 'not-an-email');
      await tester.pump();
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('sends the description, e-mail, versions, devices and log', (tester) async {
      await pumpApp(tester, bridge: FakeLiveBridge()..telemetry = _status);
      await push(readyState);
      await _open(tester);
      await _describe(tester, 'No sound in my AirPods');
      await tester.enterText(_email, 'me@example.com');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();

      final sent = fakeReports.sent.single;
      expect(sent.endpoint, Uri.parse('https://collector.test/api/services/v1/bug-reports/'));
      final body = sent.body;
      expect(body['app'], 'livebridge');
      expect(body['message'], 'No sound in my AirPods');
      expect(body['email'], 'me@example.com');
      expect(body['install_id'], _status.installId);
      expect([body['app_version'], body['os_version']], ['1.2.1+4', 'macOS 26.6.2']);
      expect(body['platform'], isNotEmpty);
      expect([body['ui_language'], body['connection_mode']], ['en', 'gateway']);
      expect(((body['devices']! as Map)['mic']! as Map)['name'], 'MacBook Microphone');
      expect(body['log'], contains('state     ready out in'));
      expect(find.text(en.reportSent), findsOneWidget);
      expect(_message, findsNothing);
    });

    testWidgets('with sharing off the report carries no install id', (tester) async {
      await pumpApp(
        tester,
        bridge: FakeLiveBridge()
          ..telemetry = const TelemetryStatus(enabled: false, installId: '3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11'),
      );
      await _open(tester);
      await _describe(tester, 'Crash on start');
      await tester.tap(_send);
      await tester.pumpAndSettle();
      final sent = fakeReports.sent.single;
      expect(sent.body.containsKey('install_id'), isFalse);
      expect(sent.body.containsKey('email'), isFalse);
      // The address the app was built with when the native side gives none.
      expect(sent.endpoint, Uri.parse('https://jaysonkhan.com/api/services/v1/bug-reports/'));
    });

    testWidgets('without the log neither the log nor the devices are sent', (tester) async {
      await pumpApp(tester);
      await _open(tester);
      await _describe(tester, 'Crash on start');
      await tester.tap(find.byKey(const Key('report-include-log')));
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      final body = fakeReports.sent.single.body;
      expect(body.containsKey('log'), isFalse);
      expect(body.containsKey('devices'), isFalse);
    });

    testWidgets('the preview shows exactly what will be sent', (tester) async {
      await pumpApp(tester);
      await push(readyState);
      await _open(tester);
      await tester.tap(find.byKey(const Key('report-preview')));
      await tester.pumpAndSettle();
      final shown = tester.widget<SelectableText>(find.byKey(const Key('report-preview-text'))).data!;
      expect(shown, contains('state     ready out in'));
      expect(shown, contains('"MacBook Microphone"'));
      await tester.tap(find.text(en.close));
      await tester.pumpAndSettle();
      await _describe(tester, 'Crash on start');
      await tester.tap(_send);
      await tester.pumpAndSettle();
      final body = fakeReports.sent.single.body;
      expect(shown, contains(body['log']! as String));
      expect(shown, contains(const JsonEncoder.withIndent('  ').convert(body['devices'])));
    });

    testWidgets('rate limit and offline keep the dialog open with the text', (tester) async {
      await pumpApp(tester);
      await _open(tester);
      await _describe(tester, 'Crash on start');
      fakeReports.error = const BugReportException('rate_limited');
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.text(en.feedbackRateLimited), findsOneWidget);
      expect(_field(tester, _message), 'Crash on start');

      fakeReports.error = const BugReportException('network');
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.text(en.reportFailed), findsOneWidget);
      expect(_field(tester, _message), 'Crash on start');
      expect(fakeReports.sent, hasLength(2));
    });

    testWidgets('fields are locked while sending', (tester) async {
      await pumpApp(tester);
      await _open(tester);
      await _describe(tester, 'Crash on start');
      fakeReports.gate = Completer<void>();
      await tester.tap(_send);
      await tester.pump();
      expect(tester.widget<TextField>(_message).enabled, isFalse);
      expect(_sendEnabled(tester), isFalse);
      fakeReports.gate!.complete();
      await tester.pumpAndSettle();
      expect(_message, findsNothing);
    });
  });

  group('e-mail prefill', () {
    Future<void> openFeedback(WidgetTester tester) async {
      await openAnalytics(tester);
      await tapVisible(tester, find.byKey(const Key('feedback-button')));
    }

    testWidgets('account mode prefills the account e-mail in both dialogs', (tester) async {
      final bridge = FakeLiveBridge()..settings = {'connectionMode': 'account', 'accountRefreshToken': 'lbr_x'};
      await pumpApp(tester, bridge: bridge, overrides: [delayProvider.overrideWithValue(_hang)]);
      await _open(tester);
      expect(_field(tester, _email), 'person@example.com');
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      await openFeedback(tester);
      expect(_field(tester, find.byKey(const Key('feedback-email'))), 'person@example.com');
    });

    for (final settings in [
      {'connectionMode': 'keys', 'elevenlabsApiKey': 'sk_x', 'geminiApiKey': 'g'},
      {'connectionMode': 'gateway', 'accessToken': 't'},
    ]) {
      testWidgets('${settings['connectionMode']} mode leaves it empty', (tester) async {
        await pumpApp(tester, bridge: FakeLiveBridge()..settings = settings);
        await _open(tester);
        expect(_field(tester, _email), isEmpty);
        await tester.tap(find.text(en.cancel));
        await tester.pumpAndSettle();
        await openFeedback(tester);
        expect(_field(tester, find.byKey(const Key('feedback-email'))), isEmpty);
      });
    }
  });
}
