// JSON control messages, protocol version 1. Every message carries `v` and `type`.
import { z } from "zod";
import type { Direction } from "./frame.ts";
import { LANGS, type Lang } from "./languages.ts";

export const PROTOCOL_VERSION = 1;
export const COMMIT_STRATEGIES = ["manual", "vad", "turn_prediction"] as const;
export type CommitStrategy = (typeof COMMIT_STRATEGIES)[number];
/** Capture audio is always this format in v1; synthesized format is announced in `session.ready`. */
export const CAPTURE_SAMPLE_RATE = 16_000;
/** Shape of a provider voice id. Anything else is refused, never forwarded to the provider. */
export const VOICE_ID_PATTERN = /^[A-Za-z0-9]{10,40}$/;

const v = z.literal(PROTOCOL_VERSION);
const direction = z.enum(["out", "in"]);
const u32 = z.number().int().min(0).max(0xffff_ffff);
const lang = z.enum(LANGS);
const voiceId = z.string().regex(VOICE_ID_PATTERN);

const directionConfig = z.object({
  enabled: z.boolean(),
  source_lang: lang,
  target_lang: lang,
  /** false = captions only for this direction (no synthesized audio is produced). */
  speak: z.boolean(),
  commit: z.enum(COMMIT_STRATEGIES),
});
export type DirectionConfig = z.infer<typeof directionConfig>;

const glossaryEntry = z.object({
  source: z.string().min(1).max(80),
  target: z.string().min(1).max(80),
});

export const clientMessage = z.discriminatedUnion("type", [
  z.object({
    v,
    type: z.literal("session.configure"),
    capture_format: z.object({
      encoding: z.literal("pcm_s16le"),
      sample_rate: z.literal(CAPTURE_SAMPLE_RATE),
      channels: z.literal(1),
    }),
    directions: z.object({ out: directionConfig, in: directionConfig }),
    /** Must be one of the gateway's allowed models; omitted = gateway default. */
    translation_model: z.string().max(80).optional(),
    glossary: z.array(glossaryEntry).max(50).optional(),
    /** Synthesized voice per direction; an omitted one = the gateway's configured voice for that direction. */
    voices: z.object({ out: voiceId.optional(), in: voiceId.optional() }).optional(),
  }),
  z.object({ v, type: z.literal("capture.start"), direction, generation: u32 }),
  z.object({ v, type: z.literal("capture.pause"), direction }),
  z.object({ v, type: z.literal("capture.stop"), direction }),
  z.object({ v, type: z.literal("turn.commit"), direction }),
  /** Cancels everything in flight for the direction and moves it to `generation` (must be greater than the current). */
  z.object({ v, type: z.literal("turn.cancel"), direction, generation: u32 }),
  z.object({
    v,
    type: z.literal("playback.start"),
    direction,
    turn_id: u32,
    generation: u32,
  }),
  z.object({
    v,
    type: z.literal("playback.end"),
    direction,
    turn_id: u32,
    generation: u32,
  }),
  z.object({ v, type: z.literal("ping"), t: z.number() }),
]);
export type ClientMessage = z.infer<typeof clientMessage>;
export type SessionConfigure = Extract<
  ClientMessage,
  { type: "session.configure" }
>;

/** A direction never translates a language into itself. */
export function directionConfigError(
  name: Direction,
  cfg: DirectionConfig,
): string | null {
  if (!cfg.enabled) return null;
  if (cfg.source_lang === cfg.target_lang)
    return `${name}: source and target language are the same`;
  return null;
}

export interface DirectionReady {
  enabled: boolean;
  /** True only after the provider sockets for this direction are actually open. */
  ready: boolean;
  speak: boolean;
  synth_sample_rate: number;
}

export type ErrorCode =
  | "bad_message"
  | "bad_frame"
  | "bad_state"
  | "unauthorized"
  | "session_limit"
  | "session_expired"
  | "capture_overflow"
  | "synthesis_congested"
  | "translation_failed"
  | "translation_rejected"
  | "tts_failed"
  | "voice_not_found"
  | "provider_unavailable"
  | "balance_exhausted"
  | "billing_unavailable"
  | "idle_timeout"
  | "session_replaced";

/**
 * Why a committed turn was neither translated nor spoken.
 * `same_language`: the speech was already in the target language (usually the other side's voice reaching this
 * direction's microphone). `echo`: our own synthesized speech came back.
 */
export type SkipReason = "same_language" | "echo";

export type ServerMessage =
  | {
      v: 1;
      type: "session.ready";
      session_id: string;
      /** `mock: true` means deterministic fake providers — never a real translation. */
      providers: {
        stt: string;
        translation: string;
        tts: string;
        mock: boolean;
      };
      directions: { out: DirectionReady; in: DirectionReady };
      max_session_seconds: number;
    }
  | {
      v: 1;
      type: "caption.partial";
      direction: Direction;
      turn_id: number;
      generation: number;
      text: string;
    }
  | {
      v: 1;
      type: "caption.final";
      direction: Direction;
      turn_id: number;
      generation: number;
      text: string;
      lang: Lang;
    }
  | {
      v: 1;
      type: "translation.delta";
      direction: Direction;
      turn_id: number;
      generation: number;
      text: string;
    }
  | {
      v: 1;
      type: "translation.final";
      direction: Direction;
      turn_id: number;
      generation: number;
      text: string;
      lang: Lang;
    }
  | {
      /** Follows the turn's `caption.final`. Nothing else is sent for the turn. */
      v: 1;
      type: "turn.skipped";
      direction: Direction;
      turn_id: number;
      generation: number;
      reason: SkipReason;
    }
  | {
      v: 1;
      type: "metrics";
      direction: Direction;
      turn_id: number;
      generation: number;
      /** Server monotonic milliseconds. Absent stages did not run. */
      stt_commit_ms?: number;
      translate_first_ms?: number;
      translate_total_ms?: number;
      tts_first_audio_ms?: number;
      tts_total_ms?: number;
      audio_ms?: number;
      /** Translation model that answered this turn (the fallback when it was used). */
      model?: string;
      dropped_frames: number;
    }
  | {
      v: 1;
      type: "error";
      code: ErrorCode;
      message: string;
      direction?: Direction;
      turn_id?: number;
      /** fatal = the gateway closes the socket after this message. */
      fatal: boolean;
    }
  | {
      /** Account mode only: right after the first `session.ready` and after every successful usage report. */
      v: 1;
      type: "account.balance";
      balance_units: number;
    }
  | { v: 1; type: "pong"; t: number };

export function parseClientMessage(
  raw: string,
): ClientMessage | { error: string } {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return { error: "not JSON" };
  }
  const parsed = clientMessage.safeParse(json);
  if (!parsed.success)
    return {
      error: parsed.error.issues
        .map((i) => `${i.path.join(".")}: ${i.message}`)
        .join("; "),
    };
  if (parsed.data.type === "session.configure") {
    for (const name of ["out", "in"] as const) {
      const err = directionConfigError(name, parsed.data.directions[name]);
      if (err) return { error: err };
    }
  }
  return parsed.data;
}

/** Shape of a provider API key in the session request: printable ASCII, no whitespace. */
const API_KEY_PATTERN = /^[\x21-\x7e]{16,256}$/;
const apiKey = z.string().regex(API_KEY_PATTERN);

/** Body of `POST /v1/sessions`. No body at all means `{ mode: "token" }`. */
export const sessionRequest = z.discriminatedUnion("mode", [
  z.object({ mode: z.literal("token") }),
  z.object({ mode: z.literal("account") }),
  z.object({
    mode: z.literal("keys"),
    elevenlabs_api_key: apiKey,
    gemini_api_key: apiKey,
  }),
]);
export type SessionRequest = z.infer<typeof sessionRequest>;

/** Errors name the offending field only, never its value: keys are secrets. */
export function parseSessionRequest(
  body: string,
): SessionRequest | { error: string } {
  if (body === "") return { mode: "token" };
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return { error: "not JSON" };
  }
  const parsed = sessionRequest.safeParse(json);
  if (!parsed.success)
    return {
      error: parsed.error.issues
        .map((i) => `${i.path.join(".")}: ${i.message}`)
        .join("; "),
    };
  return parsed.data;
}
