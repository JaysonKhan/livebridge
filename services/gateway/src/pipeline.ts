// One translation direction: capture frames -> STT -> translation -> TTS -> synthesized frames.
// The two directions of a session are separate instances that share nothing but the client socket.
import {
  encodeFrame,
  FLAG_END_OF_TURN,
  type AudioFrame,
  type CommitStrategy,
  type Direction,
  type DirectionConfig,
  type ServerMessage,
  type SkipReason,
} from "../../../packages/protocol/src/index.ts";
import type { UsageMeter } from "./billing.ts";
import type { EchoGuard } from "./echo.ts";
import type { Logger } from "./log.ts";
import {
  guardTranslation,
  isSameLanguageMark,
  mayBeSameLanguageMark,
  toSpeakable,
} from "./prompt.ts";
import {
  ProviderError,
  type ProviderFactory,
  type StreamingSTT,
  type StreamingTTS,
  type StreamingTranslator,
} from "./providers/types.ts";

export interface PipelineDeps {
  direction: Direction;
  config: DirectionConfig;
  factory: ProviderFactory;
  translationModel: string;
  /** Voice the client chose for this direction; absent = the gateway's configured voice. */
  voiceId?: string;
  glossary: { source: string; target: string }[];
  /** Shared by both directions of a session; absent = our own speech coming back is not filtered. */
  echo?: EchoGuard;
  log: Logger;
  emit(message: ServerMessage): void;
  /** Sends one binary frame to the client and returns how many bytes are still buffered towards it. */
  sendAudio(frame: Buffer): number;
  /** Called whenever `ready` changes so the session can re-announce per-direction state. */
  onReadyChanged(): void;
  /** Delay before reconnect attempt n (0-based). Overridable for tests. */
  retryDelayMs?: (attempt: number) => number;
  /** Account sessions only: counts the audio speech-to-text accepted and the text sent to synthesis. */
  meter?: UsageMeter;
  /** Called when speech-to-text recognised something: a non-empty partial or a non-empty committed segment. */
  onSpeech?(): void;
}

interface Turn {
  id: number;
  text: string;
  generation: number;
  sttCommitMs?: number;
}

const MAX_CONTEXT_TURNS = 4;
const MAX_RECONNECT_ATTEMPTS = 6;
/** Synthesized audio may queue towards a slow client for this long before the turn is abandoned. */
const CONGESTION_GRACE_MS = 1_500;
const CONGESTION_AUDIO_SECONDS = 2;
const OVERFLOW_WARNING_INTERVAL_MS = 1_000;
/** A replaced speech-to-text session still delivers what it says for this long, then it is closed. */
const RETIRE_TIMEOUT_MS = 15_000;
/**
 * Captured audio that may wait for a swapped-in speech-to-text session to open: 10 s. Opening usually takes under
 * half a second, but the provider has been seen to take almost 8 s; speech said meanwhile is sent late rather than
 * lost. Older audio is dropped.
 */
const MAX_OPENING_AUDIO_BYTES = 320_000;

const nowMs = () => performance.now();
const jitteredBackoff = (attempt: number) =>
  Math.min(8_000, 500 * 2 ** attempt) * (0.5 + Math.random() / 2);

export class DirectionPipeline {
  ready = false;
  private readonly deps: PipelineDeps;
  private readonly translator: StreamingTranslator;
  private stt: StreamingSTT | null = null;
  private tts: StreamingTTS | null = null;
  private generation = 0;
  private capturing = false;
  private lastSequence = -1;
  private turnCounter = 0;
  private synthSequence = 0;
  private dropped = 0;
  private commitRequestedAt: number | null = null;
  private lastOverflowWarning = -Infinity;
  private readonly queue: Turn[] = [];
  private working = false;
  private cancel = new AbortController();
  private readonly context: { source: string; target: string }[] = [];
  private reconnectTimer: NodeJS.Timeout | null = null;
  private closed = false;
  private fallbackAnnounced = false;
  /** The strategy speech-to-text opens with, reconnects included; `turn.mode` changes it. */
  private commitStrategy: CommitStrategy;
  /**
   * Moved on when a speech-to-text session starts opening and on an outage: an open that finishes under an older
   * value is stale and closed.
   */
  private sttEpoch = 0;
  /**
   * While a session swapped in by `turn.mode` opens: the audio captured and the commit asked for since, which belong
   * to it, not to the session it replaces.
   */
  private opening: { audio: Uint8Array[]; bytes: number; commitAt: number | null } | null = null;
  /** Replaced speech-to-text sessions, until they are closed, and when their last commit was asked for. */
  private readonly retiring = new Map<
    StreamingSTT,
    { commitRequestedAt: number | null; timer: NodeJS.Timeout }
  >();

  constructor(deps: PipelineDeps) {
    this.deps = deps;
    this.translator = deps.factory.translator();
    this.commitStrategy = deps.config.commit;
  }

  get speaks() {
    return this.deps.config.speak;
  }

  /** Opens the provider sessions. Never throws: failures are reported and, when transient, retried. */
  open(): Promise<void> {
    return this.connect(0);
  }

  /** Returns an error string when the request is invalid in the current state. */
  captureStart(generation: number): string | null {
    if (generation < this.generation)
      return `generation ${generation} is older than ${this.generation}`;
    if (generation > this.generation) this.advance(generation);
    this.capturing = true;
    // Speech is about to start: make sure the translation connection is already open when it ends.
    this.translator.warm?.(this.deps.translationModel);
    return null;
  }

  capturePause() {
    this.capturing = false;
  }

  captureStop() {
    this.capturing = false;
    this.stt?.discardPending();
  }

  commit() {
    if (this.opening) {
      this.opening.commitAt = nowMs();
      return;
    }
    this.commitRequestedAt = nowMs();
    this.stt?.commit();
  }

  /** The direction commits with this strategy from now on. The same strategy again does nothing. */
  setCommit(commit: CommitStrategy) {
    if (commit === this.commitStrategy) return;
    this.commitStrategy = commit;
    // Not connected right now: the next connect opens with it.
    if (this.stt) void this.swap();
  }

  cancelTo(generation: number): string | null {
    if (generation <= this.generation)
      return `generation ${generation} is not newer than ${this.generation}`;
    this.advance(generation);
    return null;
  }

  onCaptureFrame(frame: AudioFrame) {
    // Stale generations, frames outside a capture window, duplicates and reordered frames never reach the provider.
    if (
      frame.generation !== this.generation ||
      !this.capturing ||
      frame.sequence <= this.lastSequence
    ) {
      this.dropped++;
      return;
    }
    this.lastSequence = frame.sequence;
    const opening = this.opening;
    if (!opening) return this.feed(frame.payload);
    opening.audio.push(frame.payload);
    opening.bytes += frame.payload.byteLength;
    while (opening.bytes > MAX_OPENING_AUDIO_BYTES) {
      opening.bytes -= opening.audio.shift()!.byteLength;
      this.overflowed();
    }
  }

  private feed(pcm: Uint8Array) {
    const overflow = this.stt ? this.stt.sendAudio(pcm) : pcm.byteLength;
    this.deps.meter?.addStt(this.deps.direction, pcm.byteLength - overflow);
    if (overflow > 0) this.overflowed();
  }

  private overflowed() {
    this.dropped++;
    const now = nowMs();
    if (now - this.lastOverflowWarning >= OVERFLOW_WARNING_INTERVAL_MS) {
      this.lastOverflowWarning = now;
      this.error(
        "capture_overflow",
        "speech-to-text is not keeping up; some captured audio was dropped",
      );
    }
  }

  close() {
    this.closed = true;
    this.capturing = false;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.cancel.abort(new Error("closed"));
    this.queue.length = 0;
    this.stt?.close();
    this.tts?.close();
    this.stt = null;
    this.tts = null;
    this.opening = null;
    for (const session of this.retiring.keys()) this.dropRetired(session);
  }

  private async connect(attempt: number) {
    const { config, factory, direction } = this.deps;
    const epoch = ++this.sttEpoch;
    let stt: StreamingSTT | null = null;
    try {
      if (config.speak && !this.tts) {
        const tts = factory.tts({
          voice: direction === "out" ? "owner" : "incoming",
          language: config.target_lang,
          voiceId: this.deps.voiceId,
        });
        await tts.open();
        if (this.closed) return tts.close();
        this.tts = tts;
      }
      const commit = this.commitStrategy;
      const session = this.createStt(commit);
      stt = session;
      await session.open();
      if (this.closed || epoch !== this.sttEpoch) return session.close();
      this.stt = session;
      this.setReady(true);
      this.translator.warm?.(this.deps.translationModel);
      // `turn.mode` arrived while this session was opening.
      if (commit !== this.commitStrategy) void this.swap();
    } catch (error) {
      stt?.close();
      this.providerDown(error, attempt);
    }
  }

  private createStt(commit: CommitStrategy): StreamingSTT {
    const session = this.deps.factory.stt({
      language: this.deps.config.source_lang,
      commit,
      events: {
        onPartial: (text) => this.onPartial(session, text),
        onCommitted: (text) => this.onCommitted(session, text),
        onDisconnected: (error) => {
          if (this.stt === session) this.providerDown(error, 0);
          // A replaced session that drops owes nothing more.
          else this.dropRetired(session);
        },
      },
    });
    return session;
  }

  /**
   * Make before break: the new session opens while the old one finishes what was said before `turn.mode`; what is
   * captured after it waits for the new one. Nothing said around the switch is lost or split, and the direction never
   * stops being ready.
   */
  private async swap() {
    const epoch = ++this.sttEpoch;
    const started = nowMs();
    // A swap that replaces one still opening keeps what is already waiting.
    this.opening ??= { audio: [], bytes: 0, commitAt: null };
    const next = this.createStt(this.commitStrategy);
    try {
      await next.open();
    } catch (error) {
      next.close();
      // A newer swap, an outage or a close owns the outcome now.
      if (this.closed || epoch !== this.sttEpoch) return;
      return this.providerDown(error, 0);
    }
    if (this.closed || epoch !== this.sttEpoch) return next.close();
    const old = this.stt;
    const waiting = this.opening;
    this.opening = null;
    this.stt = next;
    if (old) this.retire(old);
    this.deps.log.info("stt.swapped", {
      direction: this.deps.direction,
      commit: this.commitStrategy,
      ms: Math.round(nowMs() - started),
    });
    for (const pcm of waiting?.audio ?? []) this.feed(pcm);
    if (waiting?.commitAt != null) {
      this.commitRequestedAt = waiting.commitAt;
      next.commit();
    }
  }

  /**
   * Whatever was said under the old strategy becomes a turn: the old session is committed, and every answer it still
   * gives is delivered until it is closed — after RETIRE_TIMEOUT_MS, or at a cancel. Its answers are not counted: under
   * `vad` the provider's own end of turn may arrive too, and nothing tells it from the answer to this commit.
   */
  private retire(old: StreamingSTT) {
    this.retiring.set(old, {
      commitRequestedAt: this.commitRequestedAt,
      timer: setTimeout(() => this.dropRetired(old), RETIRE_TIMEOUT_MS),
    });
    this.commitRequestedAt = null;
    old.commit();
  }

  private dropRetired(session: StreamingSTT) {
    const retired = this.retiring.get(session);
    if (!retired) return;
    clearTimeout(retired.timer);
    this.retiring.delete(session);
    session.close();
  }

  private providerDown(error: unknown, attempt: number) {
    if (this.closed) return;
    // A swap still opening is superseded: the reconnect opens with the current strategy.
    this.sttEpoch++;
    this.opening = null;
    const code = error instanceof ProviderError ? error.code : "unknown";
    const permanent = error instanceof ProviderError && error.permanent;
    this.stt?.close();
    this.stt = null;
    this.setReady(false);
    this.deps.log.warn("provider.down", {
      direction: this.deps.direction,
      code,
      attempt,
      permanent,
    });
    if (permanent || attempt >= MAX_RECONNECT_ATTEMPTS) {
      this.error(
        "provider_unavailable",
        `speech provider unavailable (${code}); restart the session after fixing it`,
      );
      return;
    }
    this.error(
      "provider_unavailable",
      `speech provider connection lost (${code}); reconnecting`,
    );
    const delay = (this.deps.retryDelayMs ?? jitteredBackoff)(attempt);
    // Audio captured during the outage is not replayed: the next session starts from current speech only.
    this.reconnectTimer = setTimeout(
      () => void this.connect(attempt + 1),
      delay,
    );
  }

  private setReady(ready: boolean) {
    if (this.ready === ready) return;
    this.ready = ready;
    this.deps.onReadyChanged();
  }

  private advance(generation: number) {
    this.generation = generation;
    this.lastSequence = -1;
    this.commitRequestedAt = null;
    this.queue.length = 0;
    this.cancel.abort(new Error("cancelled"));
    this.cancel = new AbortController();
    this.stt?.fence();
    // A replaced session's answers belong to the old generation, and so does what waits for a session still opening.
    for (const session of this.retiring.keys()) this.dropRetired(session);
    if (this.opening) this.opening = { audio: [], bytes: 0, commitAt: null };
  }

  private onPartial(source: StreamingSTT, text: string) {
    if (source !== this.stt) return;
    if (text) this.deps.onSpeech?.();
    // In an always-open direction this is the first sign that someone is speaking.
    this.translator.warm?.(this.deps.translationModel);
    const { direction, emit } = this.deps;
    emit({
      v: 1,
      type: "caption.partial",
      direction,
      turn_id: this.turnCounter + 1,
      generation: this.generation,
      text,
    });
  }

  private onCommitted(source: StreamingSTT, raw: string) {
    let requestedAt: number | null;
    const retired = this.retiring.get(source);
    if (retired) {
      requestedAt = retired.commitRequestedAt;
      retired.commitRequestedAt = null;
    } else if (source === this.stt) {
      requestedAt = this.commitRequestedAt;
      this.commitRequestedAt = null;
    } else return;
    const { direction, emit, config } = this.deps;
    const sttCommitMs =
      requestedAt === null ? undefined : Math.round(nowMs() - requestedAt);
    const text = raw.trim();
    if (text) this.deps.onSpeech?.();
    if (!text) {
      // Nothing was said: clear any partial caption that is still showing, and translate nothing.
      emit({
        v: 1,
        type: "caption.partial",
        direction,
        turn_id: this.turnCounter + 1,
        generation: this.generation,
        text: "",
      });
      return;
    }
    // Each commit becomes exactly one turn with a fresh local id, so a repeated sentence is still a new turn and a
    // repeated provider event can never be confused with one.
    const id = ++this.turnCounter;
    emit({
      v: 1,
      type: "caption.final",
      direction,
      turn_id: id,
      generation: this.generation,
      text,
      lang: config.source_lang,
    });
    // Our own synthesized speech heard again by a microphone is never translated a second time.
    if (this.deps.echo?.isEcho(text)) return this.skip(id, this.generation, "echo");
    this.queue.push({ id, text, generation: this.generation, sttCommitMs });
    void this.pump();
  }

  /** The turn stays on screen as a caption, marked as not translated; nothing is spoken. */
  private skip(turnId: number, generation: number, reason: SkipReason) {
    const { direction, emit, log } = this.deps;
    log.info("turn.skipped", { direction, reason });
    emit({ v: 1, type: "turn.skipped", direction, turn_id: turnId, generation, reason });
  }

  private async pump() {
    if (this.working) return;
    this.working = true;
    try {
      for (let turn = this.queue.shift(); turn; turn = this.queue.shift()) {
        if (turn.generation === this.generation)
          await this.runTurn(turn, this.cancel.signal);
      }
    } finally {
      this.working = false;
    }
  }

  private async runTurn(turn: Turn, cancelled: AbortSignal) {
    const { direction, emit, config, log } = this.deps;
    const tag = {
      direction,
      turn_id: turn.id,
      generation: turn.generation,
    } as const;
    const started = nowMs();
    let firstDelta: number | undefined;
    // Streamed text is held back while it could still turn out to be the same-language mark.
    let held: string | null = "";

    let translated;
    try {
      translated = await this.translator.translate(
        {
          source: config.source_lang,
          target: config.target_lang,
          text: turn.text,
          context: this.context,
          glossary: this.deps.glossary,
          model: this.deps.translationModel,
        },
        (text) => {
          if (cancelled.aborted) return;
          firstDelta ??= nowMs();
          if (held !== null) {
            held += text;
            if (mayBeSameLanguageMark(held)) return;
            text = held;
            held = null;
          }
          emit({ v: 1, type: "translation.delta", ...tag, text });
        },
        cancelled,
      );
    } catch (error) {
      if (cancelled.aborted) return;
      const code = error instanceof ProviderError ? error.code : "unknown";
      log.warn("translation.failed", { direction, code });
      this.error(
        "translation_failed",
        `translation failed (${code}); the original caption is shown`,
        turn.id,
      );
      return;
    }
    if (cancelled.aborted) return;

    // Speech that is already in the target language is the other side of the call reaching this direction's
    // microphone (or needs no interpreter): it is not translated back and not spoken.
    if (isSameLanguageMark(translated.text))
      return this.skip(turn.id, turn.generation, "same_language");

    const guarded = guardTranslation(turn.text, translated.text);
    if (!guarded.ok) {
      log.warn("translation.rejected", { direction, reason: guarded.reason });
      this.error(
        "translation_rejected",
        `translation rejected (${guarded.reason}); nothing was spoken`,
        turn.id,
      );
      return;
    }
    if (translated.model !== this.deps.translationModel && !this.fallbackAnnounced) {
      // Said once per session; every use is in the gateway log.
      this.fallbackAnnounced = true;
      this.error(
        "provider_unavailable",
        `translation is now using the fallback model ${translated.model}`,
        turn.id,
      );
    }
    emit({
      v: 1,
      type: "translation.final",
      ...tag,
      text: guarded.text,
      lang: config.target_lang,
    });
    this.context.push({ source: turn.text, target: guarded.text });
    if (this.context.length > MAX_CONTEXT_TURNS) this.context.shift();

    const metrics: Extract<ServerMessage, { type: "metrics" }> = {
      v: 1,
      type: "metrics",
      ...tag,
      stt_commit_ms: turn.sttCommitMs,
      translate_first_ms:
        firstDelta === undefined ? undefined : Math.round(firstDelta - started),
      translate_total_ms: Math.round(nowMs() - started),
      model: translated.model,
      dropped_frames: this.dropped,
    };

    const speakable = this.tts ? toSpeakable(guarded.text) : "";
    if (this.tts && speakable)
      Object.assign(
        metrics,
        await this.speak(this.tts, speakable, turn, cancelled),
      );
    if (!cancelled.aborted) emit(metrics);
  }

  private async speak(
    tts: StreamingTTS,
    text: string,
    turn: Turn,
    cancelled: AbortSignal,
  ) {
    const { direction, log } = this.deps;
    this.deps.echo?.spoke(direction, turn.id, text);
    const congestion = new AbortController();
    const signal = AbortSignal.any([cancelled, congestion.signal]);
    const frameBytes = Math.floor(tts.sampleRate / 5) * 2; // 200 ms
    const congestedAbove = tts.sampleRate * 2 * CONGESTION_AUDIO_SECONDS;
    const started = nowMs();
    let firstAudio: number | undefined;
    let audioBytes = 0;
    let congestedSince: number | undefined;

    const send = (payload: Uint8Array, flags: number) =>
      this.deps.sendAudio(
        encodeFrame({
          kind: "synthesized",
          direction,
          flags,
          generation: turn.generation,
          sequence: this.synthSequence++,
          timestampUs: process.hrtime.bigint() / 1000n,
          turnId: turn.id,
          payload,
        }),
      );

    this.deps.meter?.addTts(text);
    try {
      await tts.synthesize(
        text,
        (pcm) => {
          if (signal.aborted) return;
          firstAudio ??= nowMs();
          audioBytes += pcm.byteLength;
          let buffered = 0;
          for (let at = 0; at < pcm.byteLength; at += frameBytes)
            buffered = send(pcm.subarray(at, at + frameBytes), 0);
          if (buffered <= congestedAbove) congestedSince = undefined;
          else if (nowMs() - (congestedSince ??= nowMs()) > CONGESTION_GRACE_MS)
            congestion.abort(new Error("congested"));
        },
        signal,
      );
    } catch (error) {
      if (cancelled.aborted) return {};
      if (congestion.signal.aborted) {
        this.error(
          "synthesis_congested",
          "the connection is too slow for translated audio; this turn was cut short",
          turn.id,
        );
      } else {
        const code = error instanceof ProviderError ? error.code : "unknown";
        log.warn("tts.failed", { direction, code });
        // Its own code, so the client can say what to do about it: choose another voice.
        if (code === "voice_not_found" || code === "voice_disabled")
          this.error(
            "voice_not_found",
            "the voice chosen for this direction is not available to the provider account; the translated caption is shown",
            turn.id,
          );
        else
          this.error(
            "tts_failed",
            `speech synthesis failed (${code}); the translated caption is shown`,
            turn.id,
          );
      }
    }
    if (cancelled.aborted) return {};
    // Always close the turn on the client, including after a failure, so it never waits for audio that is not coming.
    send(new Uint8Array(0), FLAG_END_OF_TURN);
    return {
      tts_first_audio_ms:
        firstAudio === undefined ? undefined : Math.round(firstAudio - started),
      tts_total_ms: Math.round(nowMs() - started),
      audio_ms: Math.round((audioBytes / 2 / tts.sampleRate) * 1000),
    };
  }

  private error(
    code: Extract<ServerMessage, { type: "error" }>["code"],
    message: string,
    turnId?: number,
  ) {
    this.deps.emit({
      v: 1,
      type: "error",
      code,
      message,
      direction: this.deps.direction,
      turn_id: turnId,
      fatal: false,
    });
  }
}
