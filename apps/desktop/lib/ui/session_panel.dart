import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'caption_lane.dart';
import 'export_button.dart';

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
        Chip(avatar: Icon(_icon(s.engine), size: 18), label: Text(l.stateChip(l.engineState(s.engine)))),
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
    return Chip(avatar: Icon(ready ? Icons.check_circle : Icons.hourglass_empty, size: 18), label: Text(label));
  }
}

class _Capturing extends StatelessWidget {
  const _Capturing();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Chip(
        backgroundColor: c.errorContainer,
        avatar: Icon(Icons.mic, size: 18, color: c.onErrorContainer),
        label: Text(
          context.l10n.capturing,
          style: TextStyle(color: c.onErrorContainer, fontWeight: FontWeight.bold),
        ),
      ),
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
      child: Chip(avatar: const Icon(Icons.timer_outlined, size: 18), label: Text(text)),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
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
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: const Key('panic-button'),
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
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
          Switch(key: switchKey, value: value, onChanged: onChanged),
          Text(value ? context.l10n.switchOn(label) : context.l10n.switchOff(label)),
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
    final scheme = Theme.of(context).colorScheme;
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
            duration: const Duration(milliseconds: 80),
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !enabled
                  ? scheme.surfaceContainerHighest
                  : held
                  ? scheme.primary
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline, width: held ? 3 : 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(held ? Icons.mic : Icons.mic_none, color: held ? scheme.onPrimary : null),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hint,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: held ? scheme.onPrimary : null),
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
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(label: Text(l.showOriginal), selected: showOriginal, onSelected: notifier.setShowOriginal),
        FilterChip(label: Text(l.showTranslated), selected: showTranslated, onSelected: notifier.setShowTranslated),
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
