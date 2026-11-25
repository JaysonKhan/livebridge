import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

Finder get exportButton => find.byKey(const Key('export-button'));
bool exportEnabled() => tt.widget<OutlinedButton>(exportButton).onPressed != null;

void main() {
  testWidgets('the button is disabled until there is a turn', (tester) async {
    await pumpApp(tester);
    expect(exportEnabled(), isFalse);
    await push(cap(Direction.out, 1, CaptionKind.partial, 'sal'));
    expect(exportEnabled(), isTrue);
  });

  testWidgets('the first export asks for confirmation; cancelling saves nothing and shows nothing', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(find.text(en.exportConsentTitle), findsOneWidget);
    expect(find.text(en.exportConsentBody), findsOneWidget);
    expect(fake.calls, isNot(contains('saveTextFile')));

    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(fake.calls, isNot(contains('saveTextFile')));
    expect(find.byType(SnackBar), findsNothing);

    // Cancelling did not count as consent: the next export asks again.
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(find.text(en.exportConsentTitle), findsOneWidget);
  });

  testWidgets('confirming saves a .md file with both texts and shows the saved path', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 1, 'Salom, dunyo', 'Hello, world');
    await pushFinishedTurn(Direction.incoming, 1, 'How are you?', 'Qalaysiz?');
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.exportConsentConfirm));
    await tester.pumpAndSettle();

    expect(fake.count('saveTextFile'), 1);
    expect(fake.savedFileName, matches(RegExp(r'^livebridge-\d{4}-\d{2}-\d{2}-\d{4}\.md$')));
    final doc = fake.savedFileContent!;
    for (final text in ['Salom, dunyo', 'Hello, world', 'How are you?', 'Qalaysiz?']) {
      expect(doc, contains(text));
    }
    expect(find.text('Saved to ${fake.saveTextFileResult}'), findsOneWidget);
  });

  testWidgets('later exports in the same run do not ask again', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.exportConsentConfirm));
    await tester.pumpAndSettle();
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(find.text(en.exportConsentTitle), findsNothing);
    expect(fake.count('saveTextFile'), 2);
  });

  testWidgets('a cancelled Save dialog (null) shows no confirmation', (tester) async {
    await pumpApp(tester, bridge: FakeLiveBridge()..saveTextFileResult = null);
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.exportConsentConfirm));
    await tester.pumpAndSettle();
    expect(fake.count('saveTextFile'), 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Saved to'), findsNothing);
  });

  testWidgets('a failing save puts an entry in the error strip', (tester) async {
    await pumpApp(
      tester,
      bridge: FakeLiveBridge()..saveTextFileError = PlatformException(code: 'write_failed', message: 'Disk full'),
    );
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.exportConsentConfirm));
    await tester.pumpAndSettle();
    expect(find.text('write_failed: Disk full'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the export includes the rating the owner gave', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 4, 'Salom', 'Hello');
    await tester.tap(find.byKey(const Key('rate-good-out-4')));
    await tester.pump();
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.exportConsentConfirm));
    await tester.pumpAndSettle();
    expect(fake.savedFileContent, contains('- **Your rating:** good'));
  });
}
