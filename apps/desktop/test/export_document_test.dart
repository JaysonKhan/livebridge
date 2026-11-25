import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/l10n/app_localizations.dart';
import 'package:livebridge/state/export_document.dart';
import 'package:livebridge/state/session_state.dart';

DateTime at(int h, int m, int s) => DateTime(2026, 11, 25, h, m, s);

CaptionTurn turn(
  int id,
  DateTime startedAt, {
  String original = '',
  bool originalFinal = true,
  String translation = '',
  bool translationFinal = true,
  TurnRating? rating,
}) => CaptionTurn(
  id: id,
  startedAt: startedAt,
  original: original,
  originalFinal: originalFinal,
  translation: translation,
  translationFinal: translationFinal,
  rating: rating,
);

String build(AppLocalizations l, List<CaptionTurn> out, List<CaptionTurn> incoming) => buildConversationMarkdown(
  l: l,
  exportedAt: DateTime(2026, 11, 25, 14, 30),
  targetLang: TargetLang.en,
  mode: SessionMode.captions,
  outTurns: out,
  inTurns: incoming,
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('buildConversationMarkdown', () {
    test('header names the export time, language pair and mode', () {
      final doc = build(en, [], []);
      expect(doc, startsWith('# LiveBridge AI conversation\n'));
      expect(doc, contains('- Exported: 2026-11-25 14:30'));
      expect(doc, contains('- Languages: Uzbek ↔ English'));
      expect(doc, contains('- Mode: Captions only'));
      expect(doc, contains('No finished turns yet.'));
    });

    test('merges both directions in the order the turns appeared', () {
      final doc = build(
        en,
        [
          turn(1, at(10, 0, 5), original: 'Salom', translation: 'Hello'),
          turn(2, at(10, 0, 30), original: 'Rahmat', translation: 'Thanks'),
        ],
        [
          turn(1, at(10, 0, 2), original: 'Hi there', translation: 'Assalomu alaykum'),
          turn(2, at(10, 0, 20), original: 'Bye', translation: 'Xayr'),
        ],
      );
      final order = ['10:00:02', '10:00:05', '10:00:20', '10:00:30'].map(doc.indexOf).toList();
      expect(order, everyElement(greaterThanOrEqualTo(0)));
      expect([...order]..sort(), order, reason: 'times must be in chronological order');
      expect(doc, contains('### 10:00:02 · Them → you'));
      expect(doc, contains('### 10:00:05 · You → them'));
    });

    test('shows both the original and the translation of a turn', () {
      final doc = build(en, [turn(1, at(9, 1, 2), original: 'Salom', translation: 'Hello')], []);
      expect(doc, contains('- **Original:** Salom'));
      expect(doc, contains('- **Translation:** Hello'));
    });

    test('skips turns that only ever had a partial', () {
      final doc = build(
        en,
        [
          turn(1, at(9, 0, 0), original: 'done', translation: 'finished'),
          turn(2, at(9, 0, 10), original: 'half a sent', originalFinal: false, translationFinal: false),
        ],
        [turn(3, at(9, 0, 5), original: 'typing', originalFinal: false, translation: '...', translationFinal: false)],
      );
      expect(doc, contains('finished'));
      expect(doc, isNot(contains('half a sent')));
      expect(doc, isNot(contains('typing')));
      expect(doc, isNot(contains('09:00:10')));
    });

    test('shows the rating only when the owner set one', () {
      final doc = build(en, [
        turn(1, at(9, 0, 0), original: 'a', translation: 'A', rating: TurnRating.good),
        turn(2, at(9, 0, 1), original: 'b', translation: 'B', rating: TurnRating.bad),
        turn(3, at(9, 0, 2), original: 'c', translation: 'C'),
      ], []);
      expect(doc, contains('- **Your rating:** good'));
      expect(doc, contains('- **Your rating:** bad'));
      expect('Your rating'.allMatches(doc), hasLength(2));
    });

    test('equal timestamps keep the input order', () {
      final doc = build(
        en,
        [turn(1, at(9, 0, 0), original: 'first-out', translation: 'x')],
        [turn(1, at(9, 0, 0), original: 'second-in', translation: 'y')],
      );
      expect(doc.indexOf('first-out'), lessThan(doc.indexOf('second-in')));
    });

    test('labels follow the chosen language', () {
      final uz = lookupAppLocalizations(const Locale('uz'));
      final doc = build(uz, [turn(1, at(9, 0, 0), original: 'Salom', translation: 'Hello')], []);
      expect(doc, contains('# LiveBridge AI suhbati'));
      expect(doc, contains('Siz → suhbatdosh'));
      expect(doc, contains('Faqat subtitr'));
    });
  });

  test('exportFileName is livebridge-YYYY-MM-DD-HHmm.md in local time', () {
    expect(exportFileName(DateTime(2026, 11, 25, 9, 5)), 'livebridge-2026-11-25-0905.md');
    expect(exportFileName(DateTime(2026, 1, 2, 23, 59)), 'livebridge-2026-01-02-2359.md');
  });

  group('turn timestamps', () {
    CaptionEvent ev(CaptionKind k, String t) => CaptionEvent(direction: Direction.out, turnId: 1, kind: k, text: t);

    test('a turn is stamped when it first appears and keeps the stamp', () {
      var turns = applyCaption(const [], ev(CaptionKind.partial, 'sal'), now: at(10, 0, 0));
      turns = applyCaption(turns, ev(CaptionKind.finalText, 'salom'), now: at(10, 0, 5));
      turns = applyCaption(turns, ev(CaptionKind.translationFinal, 'hello'), now: at(10, 0, 9));
      expect(turns.single.startedAt, at(10, 0, 0));
    });

    test('a new turn id gets its own stamp', () {
      var turns = applyCaption(const [], ev(CaptionKind.partial, 'a'), now: at(10, 0, 0));
      turns = applyCaption(
        turns,
        const CaptionEvent(direction: Direction.out, turnId: 2, kind: CaptionKind.partial, text: 'b'),
        now: at(10, 0, 7),
      );
      expect(turns.map((t) => t.startedAt), [at(10, 0, 0), at(10, 0, 7)]);
    });
  });
}
