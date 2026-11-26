import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'adaptive/adaptive_switch.dart';
import 'adaptive/platform_tag.dart';
import 'adaptive/platform_toggle.dart';
import 'caption_lane.dart';
import 'export_button.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class SessionPanel extends ConsumerWidget {
  const SessionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusRow(),
          SizedBox(height: 8),
          _Controls(),
          SizedBox(height: 8),
          PttButton(),
          SizedBox(height: 8),
          _CaptionOptions(),
          SizedBox(height: 4),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: CaptionLane(direction: Direction.out)),
                SizedBox(width: 8),
                Expanded(child: CaptionLane(direction: Direction.incoming)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends ConsumerWidget {
  const _StatusRow();

  static IconData _icon(EngineState s) => switch (s) {
    EngineState.idle => Icons.pause_circle_outline,
    EngineState.connecting => Icons.sync,
    EngineState.ready => Icons.check_circle_outline,
    EngineState.active => Icons.graphic_eq,
    EngineState.degraded => Icons.warning_amber_rounded,
    EngineState.stopping => Icons.stop_circle_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PlatformTag(icon: _icon(s.engine), label: l.stateChip(l.engineState(s.engine))),
        if (s.message != null && s.message!.isNotEmpty) Text(s.message!),
        _Readiness(label: s.outReady ? l.outReady : l.outNotReady, ready: s.outReady),
        _Readiness(label: s.inReady ? l.inReady : l.inNotReady, ready: s.inReady),
        if (s.capturing || s.engine == EngineState.active) const _Capturing(),
        _Latency(metrics: s.metrics),
      ],
    );
  }
}

class _Readiness extends StatelessWidget {
  const _Readiness({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return PlatformTag(icon: ready ? Icons.check_circle : Icons.hourglass_empty, label: label);
  }
}

class _Capturing extends StatelessWidget {
  const _Capturing();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: PlatformTag(icon: Icons.mic, label: context.l10n.capturing, status: context.tokens.critical, bold: true),
    );
  }
}

class _Latency extends StatelessWidget {
  const _Latency({required this.metrics});

  final MetricsEvent? metrics;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = metrics;
    final e2e = m?.e2eMs;
    final text = e2e != null ? l.latencyValue(e2e) : l.latencyNone;
    String? line(String Function(int) format, int? v) => v == null ? null : format(v);
    final breakdown = m == null
        ? l.latencyNoMeasurements
        : [
            m.direction == Direction.out ? l.latencyLastTurnOut : l.latencyLastTurnIn,
            line(l.latencyStt, m.sttCommitMs),
            line(l.latencyTranslateFirst, m.translateFirstMs),
            line(l.latencyTranslateTotal, m.translateTotalMs),
            line(l.latencyTtsFirst, m.ttsFirstAudioMs),
            line(l.latencyTtsTotal, m.ttsTotalMs),
            line(l.latencyAudioLength, m.audioMs),
            if (m.model != null) l.latencyModel(m.model!),
          ].whereType<String>().join('\n');
    return Tooltip(
      message: breakdown,
      child: PlatformTag(icon: Icons.timer_outlined, label: text),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  Future<void> _toggleBypass(BuildContext context, WidgetRef ref, bool on) async {
    final notifier = ref.read(sessionProvider.notifier);
    if (!on) {
      await notifier.setBypass(false);
      return;
    }
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.bypassDialogTitle),
        content: Text(l.bypassDialogBody),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l.bypassTurnOn)),
        ],
      ),
    );
    if (ok == true) await notifier.setBypass(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: const Key('panic-button'),
          // The accent button shape and states, in the critical red.
          style: accentButtonStyle(
            context.tokens,
            Theme.of(context).textTheme,
            fill: scheme.error,
            onFill: scheme.onError,
          ),
          onPressed: s.running ? notifier.panic : null,
          icon: const Icon(Icons.front_hand),
          label: Text(l.panicStop),
        ),
        _LabeledSwitch(
          switchKey: const Key('mute-out'),
          label: l.muteOutgoing,
          value: s.outgoingMuted,
          onChanged: s.running ? notifier.setOutgoingMuted : null,
        ),
        _LabeledSwitch(
          switchKey: const Key('mute-in'),
          label: l.muteIncoming,
          value: s.incomingAudioMuted,
          onChanged: s.running ? notifier.setIncomingAudioMuted : null,
        ),
        _LabeledSwitch(
          switchKey: const Key('bypass-switch'),
          label: l.bypassLabel,
          value: s.bypass,
          onChanged: s.running ? (on) => _toggleBypass(context, ref, on) : null,
        ),
      ],
    );
  }
}

class _LabeledSwitch extends StatelessWidget {
  const _LabeledSwitch({required this.switchKey, required this.label, required this.value, required this.onChanged});

  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdaptiveSwitch(key: switchKey, value: value, onChanged: onChanged),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value ? context.l10n.switchOn(label) : context.l10n.switchOff(label),
              style: TextStyle(color: onChanged == null ? context.tokens.textDisabled : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Press-and-hold push-to-talk. The Space key does the same through the same notifier.
class PttButton extends ConsumerWidget {
  const PttButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(pttEnabledProvider);
    final held = ref.watch(sessionProvider.select((s) => s.pttHeld));
    final manual = ref.watch(setupProvider.select((s) => s.outCommit == OutCommit.manual));
    final notifier = ref.read(sessionProvider.notifier);
    final l = context.l10n;
    final t = context.tokens;
    final hint = held
        ? l.pttHintHeld
        : enabled
        ? l.pttHintReady
        : manual
        ? l.pttHintWaiting
        : l.pttHintOff;
    return Semantics(
      button: true,
      enabled: enabled,
      label: l.pttSemantics,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: enabled ? (_) => notifier.pttDown() : null,
          onPointerUp: (_) => notifier.pttUp(),
          onPointerCancel: (_) => notifier.pttUp(),
          child: AnimatedContainer(
            key: const Key('ptt-button'),
            // Only the press animates; reduced motion switches at once.
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 64,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: !enabled
                  ? Color.alphaBlend(t.controlFillDisabled, t.card)
                  : held
                  ? t.accent
                  : t.pttIdleFill,
              borderRadius: BorderRadius.circular(t.pttRadius),
              border: Border.all(
                color: !enabled
                    ? t.controlStroke
                    : held
                    ? t.accent
                    : t.pttIdleBorder,
              ),
              // The one glow in the app: soft mint under the held control.
              boxShadow: [BoxShadow(color: held ? t.pttGlow : t.pttGlow.withValues(alpha: 0), blurRadius: 24)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  held ? Icons.mic : Icons.mic_none,
                  size: 24,
                  color: !enabled
                      ? t.textDisabled
                      : held
                      ? t.onAccent
                      : t.accentText,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: !enabled
                          ? t.textDisabled
                          : held
                          ? t.onAccent
                          : t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionOptions extends ConsumerWidget {
  const _CaptionOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOriginal = ref.watch(setupProvider.select((s) => s.showOriginal));
    final showTranslated = ref.watch(setupProvider.select((s) => s.showTranslated));
    final size = ref.watch(setupProvider.select((s) => s.captionFontSize));
    final notifier = ref.read(setupProvider.notifier);
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PlatformToggle(label: l.showOriginal, value: showOriginal, onChanged: notifier.setShowOriginal),
        PlatformToggle(label: l.showTranslated, value: showTranslated, onChanged: notifier.setShowTranslated),
        IconButton(
          tooltip: l.captionsSmaller,
          icon: const Icon(Icons.text_decrease),
          onPressed: () => notifier.changeFontSize(-2),
        ),
        Text(l.captionSize(size.round())),
        IconButton(
          tooltip: l.captionsLarger,
          icon: const Icon(Icons.text_increase),
          onPressed: () => notifier.changeFontSize(2),
        ),
        const ExportButton(),
      ],
    );
  }
}
