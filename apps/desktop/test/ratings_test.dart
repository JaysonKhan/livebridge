import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';

import 'fake_live_bridge.dart';
import 'harness.dart';

Finder good(String dir, int id) => find.byKey(Key('rate-good-$dir-$id'));
Finder bad(String dir, int id) => find.byKey(Key('rate-bad-$dir-$id'));

void main() {
  testWidgets('rating buttons appear only once a turn has its final translation', (tester) async {
    await pumpApp(tester);
    await push(cap(Direction.out, 1, CaptionKind.finalText, 'Salom'));
    await push(cap(Direction.out, 1, CaptionKind.translationDelta, 'Hel'));
    expect(good('out', 1), findsNothing);
    await push(cap(Direction.out, 1, CaptionKind.translationFinal, 'Hello'));
    expect(good('out', 1), findsOneWidget);
    expect(bad('out', 1), findsOneWidget);
  });

  testWidgets('a tap sends rateTurn with the lane direction and turn id; a second tap sends none', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 7, 'Salom', 'Hello');
    await pushFinishedTurn(Direction.incoming, 3, 'How are you?', 'Qalaysiz?');

    await tester.tap(good('out', 7));
    await tester.pump();
    expect(fake.calls, contains('rateTurn(out,7,good)'));
    expect(find.descendant(of: good('out', 7), matching: find.byIcon(Icons.thumb_up)), findsOneWidget);

    await tester.tap(good('out', 7));
    await tester.pump();
    expect(fake.calls, contains('rateTurn(out,7,none)'));
    expect(find.descendant(of: good('out', 7), matching: find.byIcon(Icons.thumb_up_outlined)), findsOneWidget);

    await tester.tap(bad('incoming', 3));
    await tester.pump();
    expect(fake.calls, contains('rateTurn(in,3,bad)'));
    expect(find.descendant(of: bad('incoming', 3), matching: find.byIcon(Icons.thumb_down)), findsOneWidget);
    expect(fake.calls.where((c) => c.startsWith('rateTurn')), hasLength(3));
  });

  testWidgets('switching from good to bad sends bad', (tester) async {
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 2, 'Salom', 'Hello');
    await tester.tap(good('out', 2));
    await tester.pump();
    await tester.tap(bad('out', 2));
    await tester.pump();
    expect(fake.calls.where((c) => c.startsWith('rateTurn')), ['rateTurn(out,2,good)', 'rateTurn(out,2,bad)']);
  });

  testWidgets('the buttons carry semantic labels', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    expect(find.bySemanticsLabel(en.rateGood), findsOneWidget);
    expect(find.bySemanticsLabel(en.rateBad), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a failing rateTurn leaves the rating unchanged and shows the error', (tester) async {
    await pumpApp(tester, bridge: _FailingRate());
    await pushFinishedTurn(Direction.out, 1, 'Salom', 'Hello');
    await tester.tap(good('out', 1));
    await tester.pump();
    expect(find.text('no_analytics: Not available'), findsOneWidget);
    expect(find.descendant(of: good('out', 1), matching: find.byIcon(Icons.thumb_up_outlined)), findsOneWidget);
  });
}

class _FailingRate extends FakeLiveBridge {
  @override
  Future<void> rateTurn(Direction direction, int turnId, String rating) async =>
      throw PlatformException(code: 'no_analytics', message: 'Not available');
}
