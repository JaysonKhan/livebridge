import '../bridge/models.dart';
import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import 'session_state.dart';
import 'time_format.dart';

/// `livebridge-YYYY-MM-DD-HHmm.md`, from the local time.
String exportFileName(DateTime now) => 'livebridge-${formatDate(now)}-${formatHourMinute(now).replaceAll(':', '')}.md';

/// Both directions merged in the order the turns first appeared. Turns that never got a final text are skipped.
List<(Direction, CaptionTurn)> _finishedTurnsInOrder(List<CaptionTurn> outTurns, List<CaptionTurn> inTurns) {
  final all = <(Direction, CaptionTurn)>[
    for (final t in outTurns) (Direction.out, t),
    for (final t in inTurns) (Direction.incoming, t),
  ].where((e) => e.$2.originalFinal || e.$2.translationFinal).toList();
  // Stable on ties (List.sort is not): the original index breaks them.
  final order = {for (var i = 0; i < all.length; i++) all[i]: i};
  all.sort((a, b) {
    final c = a.$2.startedAt.compareTo(b.$2.startedAt);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return all;
}

/// The Markdown transcript of the session so far.
String buildConversationMarkdown({
  required AppLocalizations l,
  required DateTime exportedAt,
  required TargetLang targetLang,
  required SessionMode mode,
  required List<CaptionTurn> outTurns,
  required List<CaptionTurn> inTurns,
}) {
  final b = StringBuffer()
    ..writeln('# ${l.exportDocTitle}')
    ..writeln()
    ..writeln('- ${l.exportDocExported(formatDateTime(exportedAt))}')
    ..writeln('- ${l.exportDocLanguages(l.languagePair(targetLang))}')
    ..writeln('- ${l.exportDocMode(l.modeTitle(mode))}');
  final turns = _finishedTurnsInOrder(outTurns, inTurns);
  if (turns.isEmpty) {
    b
      ..writeln()
      ..writeln(l.exportDocNoTurns);
  }
  for (final (direction, turn) in turns) {
    b
      ..writeln()
      ..writeln('### ${formatTime(turn.startedAt)} · ${l.laneTitle(direction)}')
      ..writeln();
    if (turn.original.isNotEmpty) b.writeln('- **${l.exportDocOriginal}:** ${turn.original}');
    if (turn.translation.isNotEmpty) b.writeln('- **${l.exportDocTranslation}:** ${turn.translation}');
    final rating = turn.rating;
    if (rating != null) {
      final text = rating == TurnRating.good ? l.exportDocRatingGood : l.exportDocRatingBad;
      b.writeln('- **${l.exportDocRating}:** $text');
    }
  }
  return b.toString();
}
