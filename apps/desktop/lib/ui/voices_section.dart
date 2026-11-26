import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/providers.dart';
import '../state/setup_state.dart';
import 'setup_panel.dart';
import 'theme/tokens.dart';
import 'voice_picker.dart';

typedef _Gateway = ({String url, String token});

_Gateway _gateway(SetupState s) => (url: s.gatewayUrl.trim(), token: s.accessToken.trim());

/// The two synthesized voices of a session: the one that speaks my translation and the one that speaks theirs.
class VoicesSection extends ConsumerStatefulWidget {
  const VoicesSection({super.key});

  @override
  ConsumerState<VoicesSection> createState() => _VoicesSectionState();
}

class _VoicesSectionState extends ConsumerState<VoicesSection> {
  /// The gateway the chosen voices' names are read from. It follows the address and token fields once they have
  /// been left alone for a moment: every different pair is a request, and the gateway counts requests per minute.
  late _Gateway _settled = _gateway(ref.read(setupProvider));
  Timer? _settling;

  @override
  void dispose() {
    _settling?.cancel();
    super.dispose();
  }

  void _follow(_Gateway next) {
    _settling?.cancel();
    // No token until now (the settings were just loaded, or its first character was typed): nothing to wait for.
    if (_settled.token.isEmpty) return setState(() => _settled = next);
    _settling = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _settled = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(setupProvider.select(_gateway), (_, next) => _follow(next));
    final l = context.l10n;
    final mode = ref.watch(setupProvider.select((s) => s.mode));
    final hasToken = ref.watch(setupProvider.select((s) => s.accessToken.trim().isNotEmpty));
    final outId = ref.watch(setupProvider.select((s) => s.outVoiceId));
    final inId = ref.watch(setupProvider.select((s) => s.inVoiceId));
    // The list is read here only to put a name to a chosen voice; the picker reads it itself when it opens.
    final voices = (outId != null || inId != null) && _settled.token.isNotEmpty
        ? ref.watch(voicesProvider(_settled)).value
        : null;
    String current(String? id) =>
        id == null ? l.voiceDefault : voices?.where((v) => v.id == id).firstOrNull?.name ?? id;

    return SectionCard(
      title: l.sectionVoices,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VoiceChoice(
            name: 'voice-out',
            label: l.voiceOut,
            current: current(outId),
            // Only the bidirectional mode speaks my translation into the call.
            onChange: hasToken && mode == SessionMode.bidirectional
                ? () => showVoicePicker(context, direction: Direction.out)
                : null,
          ),
          const SizedBox(height: 12),
          _VoiceChoice(
            name: 'voice-in',
            label: l.voiceIn,
            current: current(inId),
            onChange: hasToken && mode != SessionMode.captions
                ? () => showVoicePicker(context, direction: Direction.incoming)
                : null,
          ),
          if (!hasToken) ...[
            const SizedBox(height: 8),
            Text(
              l.voiceNeedsToken,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One direction's voice: what it is for, the current choice and the button that opens the picker. Without
/// [onChange] the row keeps its text and dims.
class _VoiceChoice extends StatelessWidget {
  const _VoiceChoice({required this.name, required this.label, required this.current, required this.onChange});

  /// Prefix of the row's keys (`<name>-current`, `<name>-change`).
  final String name;
  final String label;
  final String current;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final enabled = onChange != null;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall!.copyWith(color: enabled ? t.textSecondary : t.textDisabled)),
                const SizedBox(height: 2),
                Text(
                  current,
                  key: Key('$name-current'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium!.copyWith(color: enabled ? t.textPrimary : t.textDisabled),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(key: Key('$name-change'), onPressed: onChange, child: Text(context.l10n.voiceChange)),
        ],
      ),
    );
  }
}
