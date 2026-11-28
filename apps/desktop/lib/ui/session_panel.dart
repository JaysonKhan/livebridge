import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

  /// On large screens the session content stops at this width and stays centred, so the controls, the push-to-talk
  /// bar and the caption lines do not stretch across the whole display.
  static const maxContentWidth = 1600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: const _SessionContent(),
      ),
    );
  }
}

class _SessionContent extends StatelessWidget {
  const _SessionContent();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusRow(),
          SizedBox(height: 8),
          _Controls(),
          SizedBox(height: 8),
          TalkArea(),
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

/// The outgoing speech controls: the turn-mode switch above the talk panel.
class TalkArea extends StatelessWidget {
  const TalkArea({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: TurnModeSwitch()),
        SizedBox(height: 8),
        PttButton(),
      ],
    );
  }
}

/// Hold to talk or automatic, during a session too: the setting is the setup's turn mode, and a running session
/// takes a change at once.
class TurnModeSwitch extends ConsumerWidget {
  const TurnModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automatic = ref.watch(setupProvider.select((s) => s.outCommit != OutCommit.manual));
    final notifier = ref.read(setupProvider.notifier);
    final l = context.l10n;
    final t = context.tokens;
    // Windows: the toggle button gives the label its style and colour (black on the mint fill in the dark theme).
    final style = t.isWindows ? null : Theme.of(context).textTheme.labelLarge;
    Widget label(Key key, IconData icon, String text) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: style)),
      ],
    );
    final hold = label(const Key('mode-hold'), Icons.touch_app_outlined, l.turnModeHold);
    final auto = label(const Key('mode-auto'), Icons.hearing, l.turnModeAuto);
    return Semantics(
      container: true,
      label: l.turnModeLabel,
      child: t.isWindows
          ? _WindowsSegments(automatic: automatic, hold: hold, auto: auto, onChanged: notifier.setAutomatic)
          : CupertinoSlidingSegmentedControl<bool>(
              groupValue: automatic,
              padding: const EdgeInsets.all(2),
              children: {
                false: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: hold),
                true: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: auto),
              },
              onValueChanged: (v) => v == null ? null : notifier.setAutomatic(v),
            ),
    );
  }
}

/// Windows: two toggle buttons side by side; the chosen one has the accent fill and a check mark, so the choice is not
/// shown by colour alone (as [PlatformToggle]).
class _WindowsSegments extends StatelessWidget {
  const _WindowsSegments({required this.automatic, required this.hold, required this.auto, required this.onChanged});

  final bool automatic;
  final Widget hold;
  final Widget auto;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget segment(bool value, Widget child) {
      final selected = value == automatic;
      return Semantics(
        selected: selected,
        child: OutlinedButton(
          style: selected ? FilledButtonTheme.of(context).style : null,
          onPressed: () => onChanged(value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[const Icon(Icons.check, size: 16), const SizedBox(width: 6)],
              Flexible(child: child),
            ],
          ),
        ),
      );
    }

    return Wrap(spacing: 4, runSpacing: 4, children: [segment(false, hold), segment(true, auto)]);
  }
}

/// The talk panel. Hold to talk: press and hold (the Space key does the same through the same notifier). Automatic:
/// it shows that the microphone is listening. The bars follow the real microphone level only while the microphone is
/// being sent.
class PttButton extends ConsumerWidget {
  const PttButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final talk = ref.watch(talkStateProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final l = context.l10n;
    final t = context.tokens;
    final holdMode = talk == TalkState.holdReady || talk == TalkState.holdHeld;
    final sending = talk.sending;
    final (text, icon) = switch (talk) {
      TalkState.noSession => (l.talkNoSession, Icons.mic_none),
      TalkState.connecting => (l.talkConnecting, Icons.sync),
      TalkState.holdReady => (l.talkHoldReady, Icons.mic_none),
      TalkState.holdHeld => (l.talkHoldHeld, Icons.mic),
      TalkState.listening => (l.talkListening, Icons.mic),
      TalkState.translationPlaying => (l.talkTranslationPlaying, Icons.headphones),
      TalkState.muted => (l.talkMuted, Icons.mic_off),
      TalkState.bypass => (l.talkBypass, Icons.call_split),
    };
    final waiting = talk == TalkState.noSession || talk == TalkState.connecting;
    final fill = sending
        ? t.accent
        : talk == TalkState.holdReady
        ? t.pttIdleFill
        : waiting
        ? Color.alphaBlend(t.controlFillDisabled, t.card)
        : t.card;
    final border = sending
        ? t.accent
        : talk == TalkState.holdReady
        ? t.pttIdleBorder
        : talk == TalkState.bypass
        ? t.caution.foreground
        : t.controlStroke;
    final iconColor = switch (talk) {
      _ when sending => t.onAccent,
      TalkState.holdReady => t.accentText,
      TalkState.muted => t.critical.foreground,
      TalkState.bypass => t.caution.foreground,
      _ => t.textSecondary,
    };
    final textColor = sending
        ? t.onAccent
        : waiting
        ? t.textSecondary
        : t.textPrimary;
    return Semantics(
      button: holdMode,
      enabled: holdMode,
      label: text,
      hint: holdMode ? l.pttSemantics : null,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: holdMode ? (_) => notifier.pttDown() : null,
          onPointerUp: (_) => notifier.pttUp(),
          onPointerCancel: (_) => notifier.pttUp(),
          child: AnimatedContainer(
            key: const Key('ptt-button'),
            // Only the colour change animates; reduced motion switches at once.
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(t.pttRadius),
              border: Border.all(color: border, width: talk == TalkState.bypass ? 1.5 : 1),
              // The one glow in the app: soft mint under the control while the microphone is sent.
              boxShadow: [BoxShadow(color: sending ? t.pttGlow : t.pttGlow.withValues(alpha: 0), blurRadius: 24)],
            ),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  Icon(icon, size: 24, color: iconColor),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55),
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(color: textColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Waveform(live: sending, color: sending ? t.onAccent : t.textDisabled),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Microphone level bars, newest on the right: one bar per `meters` event (about ten a second) while [live]; flat
/// otherwise.
class Waveform extends ConsumerStatefulWidget {
  const Waveform({super.key, required this.live, required this.color});

  final bool live;
  final Color color;

  @override
  ConsumerState<Waveform> createState() => _WaveformState();
}

class _WaveformState extends ConsumerState<Waveform> {
  /// Enough bars for the widest panel.
  static const _history = 160;
  final _levels = List<double>.filled(_history, 0);

  /// dBFS to bar height: speech sits between about -55 and -10 dB.
  static double _level(double db) => ((db + 55) / 45).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(Waveform old) {
    super.didUpdateWidget(old);
    if (old.live && !widget.live) _levels.fillRange(0, _history, 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((s) => s.meters), (_, meters) {
      if (!widget.live || meters == null) return;
      setState(() {
        _levels.setRange(0, _history - 1, _levels, 1);
        _levels[_history - 1] = _level(meters.mic);
      });
    });
    return SizedBox(
      height: 36,
      child: CustomPaint(
        key: const Key('talk-waveform'),
        size: Size.infinite,
        painter: WaveformPainter(levels: List.unmodifiable(_levels), live: widget.live, color: widget.color),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.levels, required this.live, required this.color});

  /// 0–1 per bar, oldest first.
  final List<double> levels;
  final bool live;
  final Color color;

  static const _bar = 3.0;
  static const _gap = 3.0;
  static const _minHeight = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = ((size.width + _gap) / (_bar + _gap)).floor().clamp(0, levels.length);
    final paint = Paint()..color = color;
    var x = size.width - count * (_bar + _gap) + _gap;
    for (var i = levels.length - count; i < levels.length; i++) {
      final h = _minHeight + (size.height - _minHeight) * levels[i];
      final rect = Rect.fromLTWH(x, (size.height - h) / 2, _bar, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(_bar / 2)), paint);
      x += _bar + _gap;
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) => old.live != live || old.color != color || !listEquals(old.levels, levels);
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
