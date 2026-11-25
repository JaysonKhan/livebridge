// ElevenLabs realtime speech-to-text (Scribe v3 Live).
// Wire protocol per https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime and the
// realtime guides (checked 2026-11-24). Not yet exercised against the live API in this repo — see
// IMPLEMENTATION_STATUS.md for which behaviours are documented-only.
import WebSocket from "ws";
import type { Lang } from "../../../../packages/protocol/src/index.ts";
import type { SttOptions, StreamingSTT } from "./types.ts";
import { ProviderError } from "./types.ts";

export interface ElevenLabsSttConfig {
  apiKey: string;
  /** https://api.elevenlabs.io or a regional host. */
  baseUrl: string;
  model: string;
  vadSilenceSecs: number;
}

/** Realtime speech-to-text rejects these two ISO 639-1 codes and takes the ISO 639-3 ones (observed 2026-11-25). */
const STT_LANGUAGE_CODE: Partial<Record<Lang, string>> = { ff: "ful", ln: "lin" };
const SAMPLE_RATE = 16_000;
/** Provider guidance is 0.1–1 s per chunk; 100 ms keeps partial captions responsive. */
const CHUNK_BYTES = (SAMPLE_RATE * 2) / 10;
/** ~500 ms of audio may wait while the socket is (re)connecting; older audio is dropped, never replayed late. */
const MAX_QUEUED_BYTES = SAMPLE_RATE;
/** The provider closes after 15 s without client messages; silence keeps a warm session alive between turns. */
const KEEPALIVE_AFTER_MS = 8_000;
const OPEN_TIMEOUT_MS = 8_000;
/**
 * Observed live: a commit with less than 0.3 s of uncommitted audio is answered with `commit_throttled` and the
 * session is closed. A quick tap on push-to-talk must not cost a reconnect, so short turns are padded with silence.
 */
const MIN_COMMIT_BYTES = SAMPLE_RATE * 2 * 0.32;
const PERMANENT = new Set([
  "auth_error",
  "quota_exceeded",
  "unaccepted_terms",
  "invalid_request",
]);
const SILENCE_CHUNK = Buffer.alloc(CHUNK_BYTES).toString("base64");

export class ElevenLabsRealtimeSTT implements StreamingSTT {
  private readonly config: ElevenLabsSttConfig;
  private readonly options: SttOptions;
  private ws: WebSocket | null = null;
  private started = false;
  private closed = false;
  private pending = Buffer.alloc(0);
  private lastSentAt = 0;
  /** Audio sent to the provider since the last commit (keep-alive silence included — it counts there too). */
  private uncommittedBytes = 0;
  private keepalive: NodeJS.Timeout | null = null;

  constructor(config: ElevenLabsSttConfig, options: SttOptions) {
    this.config = config;
    this.options = options;
  }

  open(): Promise<void> {
    const url = new URL(
      "/v1/speech-to-text/realtime",
      this.config.baseUrl.replace(/^http/, "ws"),
    );
    url.searchParams.set("model_id", this.config.model);
    url.searchParams.set("audio_format", `pcm_${SAMPLE_RATE}`);
    url.searchParams.set(
      "language_code",
      STT_LANGUAGE_CODE[this.options.language] ?? this.options.language,
    );
    url.searchParams.set("commit_strategy", this.options.commit);
    if (this.options.commit !== "manual") {
      url.searchParams.set(
        "vad_silence_threshold_secs",
        String(this.config.vadSilenceSecs),
      );
    }

    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url, {
        headers: { "xi-api-key": this.config.apiKey },
        handshakeTimeout: OPEN_TIMEOUT_MS,
      });
      this.ws = ws;
      let settled = false;
      const fail = (error: ProviderError) => {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(error);
        } else if (!this.closed) {
          this.options.events.onDisconnected(error);
        }
        this.teardown();
      };
      const timer = setTimeout(
        () =>
          fail(
            new ProviderError("timeout", "STT session did not start in time"),
          ),
        OPEN_TIMEOUT_MS,
      );

      ws.on("message", (data) => {
        let msg: { message_type?: string; text?: string; error?: string };
        try {
          msg = JSON.parse(data.toString());
        } catch {
          return;
        }
        switch (msg.message_type) {
          case "session_started":
            this.started = true;
            this.uncommittedBytes = 0;
            this.lastSentAt = Date.now();
            this.keepalive = setInterval(() => this.keepAlive(), 2_000);
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              resolve();
            }
            break;
          case "partial_transcript":
            this.options.events.onPartial(msg.text ?? "");
            break;
          case "committed_transcript":
            this.options.events.onCommitted(msg.text ?? "");
            break;
          case "committed_transcript_with_timestamps":
          case "warning":
            break;
          default:
            // Every other documented server message is an error type carrying an `error` string.
            if (msg.message_type && typeof msg.error === "string") {
              // commit_throttled is advisory: the session stays usable.
              if (msg.message_type === "commit_throttled") break;
              fail(
                new ProviderError(
                  msg.message_type,
                  `STT ${msg.message_type}`,
                  PERMANENT.has(msg.message_type),
                ),
              );
            }
        }
      });
      ws.on("unexpected-response", (_req, res) => {
        const status = res.statusCode ?? 0;
        fail(
          new ProviderError(
            `http_${status}`,
            `STT handshake rejected (${status})`,
            status === 401 || status === 403,
          ),
        );
      });
      ws.on("error", () =>
        fail(new ProviderError("socket_error", "STT socket error")),
      );
      ws.on("close", () =>
        fail(new ProviderError("closed", "STT socket closed")),
      );
    });
  }

  sendAudio(pcm: Uint8Array): number {
    if (this.closed) return 0;
    this.pending = this.pending.length
      ? Buffer.concat([this.pending, pcm])
      : Buffer.from(pcm);
    if (this.isOpen()) {
      while (this.pending.length >= CHUNK_BYTES) {
        this.sendChunk(this.pending.subarray(0, CHUNK_BYTES), false);
        this.pending = this.pending.subarray(CHUNK_BYTES);
      }
      return 0;
    }
    const overflow = this.pending.length - MAX_QUEUED_BYTES;
    if (overflow <= 0) return 0;
    const drop = overflow + (overflow % 2);
    this.pending = this.pending.subarray(drop);
    return drop;
  }

  commit() {
    if (!this.isOpen()) return;
    const total = this.uncommittedBytes + this.pending.length;
    if (total === 0) {
      // Nothing was captured (push-to-talk tapped): there is nothing to commit, and saying so needs no round trip.
      queueMicrotask(() => this.closed || this.options.events.onCommitted(""));
      return;
    }
    const padding = Math.max(0, MIN_COMMIT_BYTES - total);
    this.sendChunk(padding ? Buffer.concat([this.pending, Buffer.alloc(padding)]) : this.pending, true);
    this.pending = Buffer.alloc(0);
    this.uncommittedBytes = 0;
  }

  discardPending() {
    this.pending = Buffer.alloc(0);
  }

  close() {
    this.closed = true;
    this.teardown();
  }

  private isOpen() {
    return this.started && this.ws?.readyState === WebSocket.OPEN;
  }

  private sendChunk(pcm: Buffer, commit: boolean) {
    this.send(pcm.toString("base64"), commit, pcm.length);
  }

  private send(audioBase64: string, commit: boolean, bytes: number) {
    this.lastSentAt = Date.now();
    this.uncommittedBytes += bytes;
    this.ws?.send(
      JSON.stringify({
        message_type: "input_audio_chunk",
        audio_base_64: audioBase64,
        commit,
        sample_rate: SAMPLE_RATE,
      }),
    );
  }

  private keepAlive() {
    if (this.isOpen() && Date.now() - this.lastSentAt >= KEEPALIVE_AFTER_MS)
      this.send(SILENCE_CHUNK, false, CHUNK_BYTES);
  }

  private teardown() {
    if (this.keepalive) clearInterval(this.keepalive);
    this.keepalive = null;
    this.started = false;
    const ws = this.ws;
    this.ws = null;
    if (ws) {
      ws.removeAllListeners();
      ws.on("error", () => {});
      ws.terminate();
    }
  }
}
