import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';
import '../bridge/models.dart';
import 'diagnostics.dart';
import 'providers.dart';
import 'setup_state.dart';

const Object _keep = Object();
const int _maxTurnsPerLane = 200;

/// One spoken turn in a caption lane: the original text and its translation.
class CaptionTurn {
  const CaptionTurn({
    required this.id,
    required this.startedAt,
    this.original = '',
    this.originalFinal = false,
    this.translation = '',
    this.translationFinal = false,
    this.skipped,
    this.rating,
  });

  final int id;

  /// When the turn first appeared.
  final DateTime startedAt;
  final String original;
  final bool originalFinal;
  final String translation;
  final bool translationFinal;

  /// Set when the gateway left the turn untranslated and unspoken; such a turn is finished.
  final SkipReason? skipped;

  /// The owner's rating of the translation, if any.
  final TurnRating? rating;

  bool get isLive => skipped == null && !(originalFinal && translationFinal);

  CaptionTurn copyWith({
    String? original,
    bool? originalFinal,
    String? translation,
    bool? translationFinal,
    SkipReason? skipped,
    Object? rating = _keep,
  }) => CaptionTurn(
    id: id,
    startedAt: startedAt,
    original: original ?? this.original,
    originalFinal: originalFinal ?? this.originalFinal,
    translation: translation ?? this.translation,
    translationFinal: translationFinal ?? this.translationFinal,
    skipped: skipped ?? this.skipped,
    rating: identical(rating, _keep) ? this.rating : rating as TurnRating?,
  );
}

/// Partial replaces in place, final commits, translation deltas append and the translation final replaces.
/// A turn is stamped with [now] (default: the current time) when it first appears.
List<CaptionTurn> applyCaption(List<CaptionTurn> turns, CaptionEvent e, {DateTime? now}) {
  final i = turns.indexWhere((t) => t.id == e.turnId);
  final cur = i >= 0 ? turns[i] : CaptionTurn(id: e.turnId, startedAt: now ?? DateTime.now());
  final next = switch (e.kind) {
    CaptionKind.partial => cur.originalFinal ? cur : cur.copyWith(original: e.text),
    CaptionKind.finalText => cur.copyWith(original: e.text, originalFinal: true),
    CaptionKind.translationDelta => cur.translationFinal ? cur : cur.copyWith(translation: cur.translation + e.text),
    CaptionKind.translationFinal => cur.copyWith(translation: e.text, translationFinal: true),
    CaptionKind.skipped => cur.copyWith(skipped: e.skipReason ?? SkipReason.sameLanguage),
  };
  final list = [...turns];
  if (i >= 0) {
    list[i] = next;
  } else {
    list.add(next);
  }
  return list.length > _maxTurnsPerLane ? list.sublist(list.length - _maxTurnsPerLane) : list;
}

class SessionState {
  const SessionState({
    this.engine = EngineState.idle,
    this.outReady = false,
    this.inReady = false,
    this.capturing = false,
    this.mock = false,
    this.bypass = false,
    this.outgoingMuted = false,
    this.incomingAudioMuted = false,
    this.message,
    this.pttHeld = false,
    this.outCommit,
    this.outTurns = const [],
    this.inTurns = const [],
    this.metrics,
    this.meters,
    this.error,
  });

  final EngineState engine;
  final bool outReady;
  final bool inReady;
  final bool capturing;
  final bool mock;
  final bool bypass;
  final bool outgoingMuted;
  final bool incomingAudioMuted;
  final String? message;
  final bool pttHeld;

  /// The outgoing turn mode in force in the running session, as the host last reported it.
  final OutCommit? outCommit;
  final List<CaptionTurn> outTurns;
  final List<CaptionTurn> inTurns;
  final MetricsEvent? metrics;
  final MetersEvent? meters;
  final ErrorEvent? error;

  /// A session exists (anything but idle).
  bool get running => engine != EngineState.idle;

  /// The engine accepts push-to-talk.
  bool get canPtt => engine == EngineState.ready || engine == EngineState.active;

  /// A press of the talk button would send the microphone: the outgoing direction is ready, not muted, no bypass.
  bool get canHold => canPtt && outReady && !outgoingMuted && !bypass;

  SessionState copyWith({
    EngineState? engine,
    bool? outReady,
    bool? inReady,
    bool? capturing,
    bool? mock,
    bool? bypass,
    bool? outgoingMuted,
    bool? incomingAudioMuted,
    Object? message = _keep,
    bool? pttHeld,
    OutCommit? outCommit,
    List<CaptionTurn>? outTurns,
    List<CaptionTurn>? inTurns,
    Object? metrics = _keep,
    Object? meters = _keep,
    Object? error = _keep,
  }) => SessionState(
    engine: engine ?? this.engine,
    outReady: outReady ?? this.outReady,
    inReady: inReady ?? this.inReady,
    capturing: capturing ?? this.capturing,
    mock: mock ?? this.mock,
    bypass: bypass ?? this.bypass,
    outgoingMuted: outgoingMuted ?? this.outgoingMuted,
    incomingAudioMuted: incomingAudioMuted ?? this.incomingAudioMuted,
    message: identical(message, _keep) ? this.message : message as String?,
    pttHeld: pttHeld ?? this.pttHeld,
    outCommit: outCommit ?? this.outCommit,
    outTurns: outTurns ?? this.outTurns,
    inTurns: inTurns ?? this.inTurns,
    metrics: identical(metrics, _keep) ? this.metrics : metrics as MetricsEvent?,
    meters: identical(meters, _keep) ? this.meters : meters as MetersEvent?,
    error: identical(error, _keep) ? this.error : error as ErrorEvent?,
  );
}

class SessionNotifier extends Notifier<SessionState> {
  LiveBridge get _bridge => ref.read(bridgeProvider);

  @override
  SessionState build() {
    final sub = ref.watch(bridgeProvider).events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    return const SessionState();
  }

  /// The outgoing turn mode setting changed. The setup is locked during a session, so a change then comes from the
  /// session switch: the running session takes it at once. Leaving hold to talk while the button is held is a release,
  /// which the host does itself.
  void outCommitChanged(OutCommit next) {
    if (!state.running) return;
    if (next != OutCommit.manual && state.pttHeld) state = state.copyWith(pttHeld: false);
    unawaited(guard('setOutCommit', () => _bridge.setOutCommit(next)));
  }

  void _onEvent(BridgeEvent e) {
    switch (e) {
      case final StateEvent s:
        state = state.copyWith(
          engine: s.state,
          outReady: s.outReady,
          inReady: s.inReady,
          capturing: s.capturing,
          mock: s.mock,
          bypass: s.bypass,
          outgoingMuted: s.outgoingMuted,
          incomingAudioMuted: s.incomingAudioMuted,
          message: s.message,
          pttHeld: s.state == EngineState.ready || s.state == EngineState.active ? state.pttHeld : false,
          outCommit: s.outCommit,
        );
      case final CaptionEvent c:
        state = c.direction == Direction.out
            ? state.copyWith(outTurns: applyCaption(state.outTurns, c))
            : state.copyWith(inTurns: applyCaption(state.inTurns, c));
      case final MetersEvent m:
        state = state.copyWith(meters: m);
      case final MetricsEvent m:
        state = state.copyWith(metrics: m);
      case final ErrorEvent err:
        state = err.fatal ? _idleWith(error: err) : state.copyWith(error: err);
        // An older gateway keeps the mode the session started with; so does the setting.
        final inForce = state.outCommit;
        if (err.code == 'mode_switch_unsupported' && inForce != null) {
          ref.read(setupProvider.notifier).setOutCommit(inForce);
        }
      case DevicesChangedEvent():
        unawaited(ref.read(setupProvider.notifier).refreshDevices());
      case BalanceEvent():
        break; // The connection keeps the account's balance.
    }
  }

  /// Back to idle, keeping captions so the owner can still read them.
  SessionState _idleWith({ErrorEvent? error}) =>
      SessionState(outTurns: state.outTurns, inTurns: state.inTurns, metrics: state.metrics, error: error);

  void reportError(ErrorEvent e) {
    recordAppError(ref.read(diagnosticLogProvider), e);
    state = state.copyWith(error: e);
  }

  void reportException(Exception e, String method) => reportError(
    e is PlatformException
        ? ErrorEvent(code: e.code, message: e.message ?? '$method failed')
        : ErrorEvent(code: method, message: e.toString()),
  );

  void dismissError() => state = state.copyWith(error: null);

  void clearMeters() => state = state.copyWith(meters: null);

  /// Runs a bridge call, turning a failure into an error-strip entry.
  Future<void> guard(String method, Future<void> Function() call) async {
    try {
      await call();
    } on Exception catch (e) {
      if (ref.mounted) reportException(e, method);
    }
  }

  Future<void> start(StartConfig config) async {
    final log = ref.read(diagnosticLogProvider);
    for (final line in describeStart(config, ref.read(setupProvider))) {
      log.add('start', line);
    }
    state = SessionState(engine: EngineState.connecting);
    try {
      await _bridge.stopMeters();
      await _bridge.saveSettings(config);
      await _bridge.start(config);
    } on Exception catch (e) {
      if (!ref.mounted) return;
      state = _idleWith();
      reportException(e, 'start');
    }
  }

  Future<void> stop() => guard('stop', _bridge.stop);

  Future<void> panic() => guard('panic', _bridge.panic);

  Future<void> pttDown() async {
    if (state.pttHeld || !state.canHold || ref.read(setupProvider).outCommit != OutCommit.manual) return;
    state = state.copyWith(pttHeld: true);
    await guard('pttDown', _bridge.pttDown);
  }

  Future<void> pttUp() async {
    if (!state.pttHeld) return;
    state = state.copyWith(pttHeld: false);
    await guard('pttUp', _bridge.pttUp);
  }

  Future<void> setOutgoingMuted(bool muted) => guard('setOutgoingMuted', () => _bridge.setOutgoingMuted(muted));

  Future<void> setIncomingAudioMuted(bool muted) =>
      guard('setIncomingAudioMuted', () => _bridge.setIncomingAudioMuted(muted));

  Future<void> setBypass(bool enabled) => guard('setBypass', () => _bridge.setBypass(enabled));

  /// Rates a finished turn; tapping the rating it already has clears it.
  Future<void> rateTurn(Direction direction, int turnId, TurnRating tapped) async {
    final turns = direction == Direction.out ? state.outTurns : state.inTurns;
    final turn = turns.where((t) => t.id == turnId).firstOrNull;
    if (turn == null) return;
    final next = turn.rating == tapped ? null : tapped;
    try {
      await _bridge.rateTurn(direction, turnId, next?.wire ?? 'none');
    } on Exception catch (e) {
      if (ref.mounted) reportException(e, 'rateTurn');
      return;
    }
    if (!ref.mounted) return;
    List<CaptionTurn> rated(List<CaptionTurn> list) => [
      for (final t in list) t.id == turnId ? t.copyWith(rating: next) : t,
    ];
    state = direction == Direction.out
        ? state.copyWith(outTurns: rated(state.outTurns))
        : state.copyWith(inTurns: rated(state.inTurns));
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Push-to-talk works only when a press would send the microphone and the outgoing turn mode is push-to-talk.
final pttEnabledProvider = Provider<bool>((ref) {
  final canHold = ref.watch(sessionProvider.select((s) => s.canHold));
  final manual = ref.watch(setupProvider.select((s) => s.outCommit == OutCommit.manual));
  return canHold && manual;
});

/// What the talk panel shows: whether the microphone is being sent and, when it is not, why.
enum TalkState {
  noSession,
  connecting,
  holdReady,
  holdHeld,
  listening,
  muted,
  bypass;

  /// The microphone goes to the gateway.
  bool get sending => this == holdHeld || this == listening;
}

final talkStateProvider = Provider<TalkState>((ref) {
  final (running, stopping, bypass, muted, ready, held) = ref.watch(
    sessionProvider.select(
      (s) =>
          (s.running, s.engine == EngineState.stopping, s.bypass, s.outgoingMuted, s.canPtt && s.outReady, s.pttHeld),
    ),
  );
  final manual = ref.watch(setupProvider.select((s) => s.outCommit == OutCommit.manual));
  if (!running || stopping) return TalkState.noSession;
  if (bypass) return TalkState.bypass;
  if (muted) return TalkState.muted;
  if (!ready) return TalkState.connecting;
  if (!manual) return TalkState.listening;
  return held ? TalkState.holdHeld : TalkState.holdReady;
});
