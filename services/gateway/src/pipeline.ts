// One translation direction: capture frames -> STT -> translation -> TTS -> synthesized frames.
// The two directions of a session are separate instances that share nothing but the client socket.
import {
  encodeFrame,
  FLAG_END_OF_TURN,
  type AudioFrame,
  type Direction,
  type DirectionConfig,
  type ServerMessage,
} from "../../../packages/protocol/src/index.ts";
import type { Logger } from "./log.ts";
import { guardTranslation, toSpeakable } from "./prompt.ts";
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
  glossary: { source: string; target: string }[];
  log: Logger;
  emit(message: ServerMessage): void;
  /** Sends one binary frame to the client and returns how many bytes are still buffered towards it. */
  sendAudio(frame: Buffer): number;
  /** Called whenever `ready` changes so the session can re-announce per-direction state. */
  onReadyChanged(): void;
  /** Delay before reconnect attempt n (0-based). Overridable for tests. */
  retryDelayMs?: (attempt: number) => number;
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
  private lastOverflowWarning = 0;
  private readonly queue: Turn[] = [];
  private working = false;
  private cancel = new AbortController();
  private readonly context: { source: string; target: string }[] = [];
  private reconnectTimer: NodeJS.Timeout | null = null;
  private closed = false;
  private fallbackAnnounced = false;

  constructor(deps: PipelineDeps) {
    this.deps = deps;
    this.translator = deps.factory.translator();
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
    this.commitRequestedAt = nowMs();
    this.stt?.commit();
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
    const overflow = this.stt
      ? this.stt.sendAudio(frame.payload)
      : frame.payload.byteLength;
    if (overflow > 0) {
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
  }

  private async connect(attempt: number) {
    const { config, factory, direction } = this.deps;
    let stt: StreamingSTT | null = null;
    try {
      if (config.speak && !this.tts) {
        const tts = factory.tts({
          voice: direction === "out" ? "owner" : "incoming",
          language: config.target_lang,
        });
        await tts.open();
        if (this.closed) return tts.close();
        this.tts = tts;
      }
      const session = factory.stt({
        language: config.source_lang,
        commit: config.commit,
        events: {
          onPartial: (text) => this.onPartial(session, text),
          onCommitted: (text) => this.onCommitted(session, text),
          onDisconnected: (error) => {
            if (this.stt === session) this.providerDown(error, 0);
          },
        },
      });
      stt = session;
      await session.open();
      if (this.closed) return session.close();
      this.stt = session;
      this.setReady(true);
      this.translator.warm?.(this.deps.translationModel);
    } catch (error) {
      stt?.close();
      this.providerDown(error, attempt);
    }
  }

  private providerDown(error: unknown, attempt: number) {
    if (this.closed) return;
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
    this.stt?.discardPending();
  }

  private onPartial(source: StreamingSTT, text: string) {
    if (source !== this.stt) return;
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
    if (source !== this.stt) return;
    const { direction, emit, config } = this.deps;
    const sttCommitMs =
      this.commitRequestedAt === null
        ? undefined
        : Math.round(nowMs() - this.commitRequestedAt);
    this.commitRequestedAt = null;
    const text = raw.trim();
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
    this.queue.push({ id, text, generation: this.generation, sttCommitMs });
    void this.pump();
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
