// ElevenLabs Text-to-Dialogue streaming-input WebSocket (Eleven v4 Turbo: exactly one registered voice per socket).
// Wire protocol per https://elevenlabs.io/docs/api-reference/text-to-dialogue/ttd-websocket and the realtime
// dialogue guide (checked 2026-11-24). The reference does not list `output_format` values for this endpoint and does
// not say when `is_final_audio_for_turn` is emitted; both need the live probe (IMPLEMENTATION_STATUS.md).
import WebSocket from "ws";
import type { Lang } from "../../../../packages/protocol/src/index.ts";
import type { StreamingTTS } from "./types.ts";
import { ProviderError } from "./types.ts";

export interface ElevenLabsTtsConfig {
  apiKey: string;
  baseUrl: string;
  model: string;
  voiceId: string;
  language: Lang;
  /** pcm_<rate> */
  outputFormat: string;
  /** Overrides the idle limit after audio (tests). */
  idleAfterAudioMs?: number;
  /** Called when a turn ended by the idle watchdog instead of the provider's end-of-turn marker. */
  onMarkerMissing?: () => void;
}

/** The provider closes after 20 s without client messages. */
const KEEPALIVE_MS = 10_000;
const OPEN_TIMEOUT_MS = 8_000;
const FIRST_AUDIO_TIMEOUT_MS = 6_000;
/**
 * Last-resort limit for a turn whose audio stopped without the end-of-turn marker. Live observation: the marker
 * always follows the last audio chunk, and gaps between chunks reached 750 ms on a slow run — a 1.5 s limit cut a
 * turn short mid-word. So this is deliberately far above any normal gap.
 */
const IDLE_AFTER_AUDIO_MS = 6_000;

interface ActiveTurn {
  onAudio: (pcm: Uint8Array) => void;
  resolve: () => void;
  reject: (error: unknown) => void;
  watchdog: NodeJS.Timeout;
  carry: Buffer;
  gotAudio: boolean;
}

export class ElevenLabsDialogueTTS implements StreamingTTS {
  readonly sampleRate: number;
  private readonly config: ElevenLabsTtsConfig;
  private ws: WebSocket | null = null;
  private keepalive: NodeJS.Timeout | null = null;
  private turn: ActiveTurn | null = null;
  private closed = false;

  constructor(config: ElevenLabsTtsConfig) {
    this.config = config;
    this.sampleRate = Number(config.outputFormat.slice(4));
  }

  open(): Promise<void> {
    const url = new URL(
      "/v1/text-to-dialogue/stream-input",
      this.config.baseUrl.replace(/^http/, "ws"),
    );
    url.searchParams.set("model_id", this.config.model);
    url.searchParams.set("output_format", this.config.outputFormat);
    url.searchParams.set("language_code", this.config.language);

    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url, {
        headers: { "xi-api-key": this.config.apiKey },
        handshakeTimeout: OPEN_TIMEOUT_MS,
      });
      this.ws = ws;
      let opened = false;
      const fail = (error: ProviderError) => {
        if (this.ws !== ws) return;
        this.teardown();
        if (!opened) reject(error);
        this.failTurn(error);
      };
      ws.on("open", () => {
        opened = true;
        ws.send(JSON.stringify({ voices: [this.config.voiceId] }));
        this.keepalive = setInterval(
          () => ws.send(JSON.stringify({ keep_alive: true })),
          KEEPALIVE_MS,
        );
        resolve();
      });
      ws.on("message", (data) => this.onMessage(data.toString()));
      ws.on("unexpected-response", (_req, res) => {
        const status = res.statusCode ?? 0;
        fail(
          new ProviderError(
            `http_${status}`,
            `TTS handshake rejected (${status})`,
            status >= 400 && status < 500 && status !== 429,
          ),
        );
      });
      ws.on("error", () =>
        fail(new ProviderError("socket_error", "TTS socket error")),
      );
      ws.on("close", () =>
        fail(new ProviderError("closed", "TTS socket closed")),
      );
    });
  }

  async synthesize(
    text: string,
    onAudio: (pcm: Uint8Array) => void,
    signal: AbortSignal,
  ): Promise<void> {
    if (this.turn)
      throw new Error("synthesize called while another turn is in flight");
    if (signal.aborted) throw signal.reason;
    if (this.ws?.readyState !== WebSocket.OPEN) await this.open();
    if (signal.aborted) throw signal.reason;
    const ws = this.ws!;

    await new Promise<void>((resolve, reject) => {
      const onAbort = () => {
        // The endpoint has no per-turn cancel: drop the connection so no late audio can leak into the next turn.
        this.turn = null;
        clearTimeout(turn.watchdog);
        this.teardown();
        reject(signal.reason);
      };
      const done = (settle: () => void) => {
        signal.removeEventListener("abort", onAbort);
        clearTimeout(turn.watchdog);
        this.turn = null;
        settle();
      };
      const turn: ActiveTurn = {
        onAudio,
        resolve: () => done(resolve),
        reject: (error) => done(() => reject(error)),
        watchdog: setTimeout(() => this.onWatchdog(), FIRST_AUDIO_TIMEOUT_MS),
        carry: Buffer.alloc(0),
        gotAudio: false,
      };
      this.turn = turn;
      signal.addEventListener("abort", onAbort, { once: true });
      ws.send(
        JSON.stringify({
          inputs: [{ text, voice_id: this.config.voiceId, new_turn: true }],
        }),
      );
      // Turns are short, so do not wait for the ~40 character / 8 word server buffer to fill.
      ws.send(JSON.stringify({ flush: true }));
    });
  }

  close() {
    this.closed = true;
    this.teardown();
    this.failTurn(new ProviderError("closed", "TTS closed"));
  }

  private onMessage(raw: string) {
    let msg: {
      audio?: string;
      is_final_audio_for_turn?: boolean;
      error?: string;
      message?: string;
    };
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const turn = this.turn;
    if (typeof msg.error === "string") {
      const error = new ProviderError(msg.error, `TTS ${msg.error}`, true);
      this.teardown();
      this.failTurn(error);
      return;
    }
    if (!turn) return;
    if (typeof msg.audio === "string" && msg.audio) {
      // Deliver whole 16-bit samples only; an odd trailing byte waits for the next chunk.
      const bytes = Buffer.concat([
        turn.carry,
        Buffer.from(msg.audio, "base64"),
      ]);
      const whole = bytes.length - (bytes.length % 2);
      turn.carry = bytes.subarray(whole);
      turn.gotAudio = true;
      clearTimeout(turn.watchdog);
      turn.watchdog = setTimeout(
        () => this.onWatchdog(),
        this.config.idleAfterAudioMs ?? IDLE_AFTER_AUDIO_MS,
      );
      if (whole) turn.onAudio(bytes.subarray(0, whole));
    }
    if (msg.is_final_audio_for_turn) turn.resolve();
  }

  private onWatchdog() {
    const turn = this.turn;
    if (!turn) return;
    // Either way the connection can no longer be trusted to be at a turn boundary.
    this.teardown();
    if (turn.gotAudio) {
      this.config.onMarkerMissing?.();
      turn.resolve();
    } else {
      turn.reject(
        new ProviderError("timeout", "TTS produced no audio in time"),
      );
    }
  }

  private failTurn(error: ProviderError) {
    this.turn?.reject(error);
  }

  private teardown() {
    if (this.keepalive) clearInterval(this.keepalive);
    this.keepalive = null;
    const ws = this.ws;
    this.ws = null;
    if (ws) {
      ws.removeAllListeners();
      ws.on("error", () => {});
      ws.terminate();
    }
  }
}
