import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';

class CaptionLane extends ConsumerStatefulWidget {
  const CaptionLane({super.key, required this.direction});

  final Direction direction;

  @override
  ConsumerState<CaptionLane> createState() => _CaptionLaneState();
}

class _CaptionLaneState extends ConsumerState<CaptionLane> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<CaptionTurn> _turns(SessionState s) => widget.direction == Direction.out ? s.outTurns : s.inTurns;

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final turns = ref.watch(sessionProvider.select(_turns));
    final fontSize = ref.watch(setupProvider.select((s) => s.captionFontSize));
    final showOriginal = ref.watch(setupProvider.select((s) => s.showOriginal));
    final showTranslated = ref.watch(setupProvider.select((s) => s.showTranslated));
    ref.listen(sessionProvider.select(_turns), (_, _) => _scrollToEnd());
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      key: Key('lane-${widget.direction.name}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(l.laneTitle(widget.direction), style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: turns.isEmpty
                ? Center(child: Text(l.noCaptions))
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: turns.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, i) => _TurnView(
                      direction: widget.direction,
                      turn: turns[i],
                      onRate: (rating) =>
                          ref.read(sessionProvider.notifier).rateTurn(widget.direction, turns[i].id, rating),
                      fontSize: fontSize,
                      showOriginal: showOriginal,
                      showTranslated: showTranslated,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.direction,
    required this.turn,
    required this.onRate,
    required this.fontSize,
    required this.showOriginal,
    required this.showTranslated,
  });

  final Direction direction;
  final CaptionTurn turn;
  final ValueChanged<TurnRating> onRate;
  final double fontSize;
  final bool showOriginal;
  final bool showTranslated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showOriginal && turn.original.isNotEmpty)
                Text(
                  turn.original,
                  style: TextStyle(
                    fontSize: fontSize * 0.8,
                    color: scheme.onSurfaceVariant,
                    fontStyle: turn.originalFinal ? null : FontStyle.italic,
                  ),
                ),
              if (showTranslated && turn.translation.isNotEmpty)
                Text(
                  turn.translation,
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        if (turn.isLive) Icon(Icons.more_horiz, size: 18, semanticLabel: context.l10n.turnInProgress),
        if (turn.translationFinal) ...[
          _RateButton(
            key: Key('rate-good-${direction.name}-${turn.id}'),
            label: context.l10n.rateGood,
            icon: Icons.thumb_up_outlined,
            activeIcon: Icons.thumb_up,
            active: turn.rating == TurnRating.good,
            onPressed: () => onRate(TurnRating.good),
          ),
          _RateButton(
            key: Key('rate-bad-${direction.name}-${turn.id}'),
            label: context.l10n.rateBad,
            icon: Icons.thumb_down_outlined,
            activeIcon: Icons.thumb_down,
            active: turn.rating == TurnRating.bad,
            onPressed: () => onRate(TurnRating.bad),
          ),
        ],
      ],
    );
  }
}

/// A small thumbs button. The selected state is shown by a filled icon, not by colour alone.
class _RateButton extends StatelessWidget {
  const _RateButton({
    super.key,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        tooltip: label,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(active ? activeIcon : icon),
        onPressed: onPressed,
      ),
    );
  }
}
