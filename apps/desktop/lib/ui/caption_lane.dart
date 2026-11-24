import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';

class CaptionLane extends ConsumerStatefulWidget {
  const CaptionLane({super.key, required this.direction, required this.title});

  final Direction direction;
  final String title;

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
            child: Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Expanded(
            child: turns.isEmpty
                ? const Center(child: Text('No captions yet'))
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: turns.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (_, i) => _TurnView(
                      turn: turns[i],
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
    required this.turn,
    required this.fontSize,
    required this.showOriginal,
    required this.showTranslated,
  });

  final CaptionTurn turn;
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
        if (turn.isLive) const Icon(Icons.more_horiz, size: 18, semanticLabel: 'Still in progress'),
      ],
    );
  }
}
