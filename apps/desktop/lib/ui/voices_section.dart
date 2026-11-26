import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/setup_state.dart';
import 'setup_panel.dart';
import 'theme/tokens.dart';
import 'voice_picker.dart';

/// The two synthesized voices of a session: the one that speaks my translation and the one that speaks theirs.
///
/// It shows what was chosen from what is saved with the choice and never asks the gateway itself: the access token
/// travels only when the owner opens a picker (or starts a session), to the address as it stands at that moment.
class VoicesSection extends ConsumerWidget {
  const VoicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mode = ref.watch(setupProvider.select((s) => s.mode));
    final hasToken = ref.watch(setupProvider.select((s) => s.accessToken.trim().isNotEmpty));
    final out = ref.watch(setupProvider.select((s) => (id: s.outVoiceId, name: s.outVoiceName)));
    final incoming = ref.watch(setupProvider.select((s) => (id: s.inVoiceId, name: s.inVoiceName)));
    String current(({String? id, String? name}) voice) => voice.id == null ? l.voiceDefault : voice.name ?? voice.id!;

    return SectionCard(
      title: l.sectionVoices,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VoiceChoice(
            name: 'voice-out',
            label: l.voiceOut,
            current: current(out),
            // Only the bidirectional mode speaks my translation into the call.
            onChange: hasToken && mode == SessionMode.bidirectional
                ? () => showVoicePicker(context, direction: Direction.out)
                : null,
          ),
          const SizedBox(height: 12),
          _VoiceChoice(
            name: 'voice-in',
            label: l.voiceIn,
            current: current(incoming),
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
