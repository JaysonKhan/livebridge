import { z } from "zod";

const csv = (s: string) =>
  s
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);

/**
 * "JaysonKhan - Natural Uzbek Voice": the project author's own voice, published by the author in the ElevenLabs
 * Voice Library. Used for both directions unless .env names other voices.
 */
export const DEFAULT_VOICE_ID = "ehTFHBkERkWR22A3sR8M";

/** Empty = the feature is off; anything else must be long enough to be a real secret. */
const optionalSecret = z
  .string()
  .default("")
  .refine((v) => v === "" || v.length >= 32, "must be empty or at least 32 characters");

/** An empty value (as in .env.example) means "not set". */
const optionalCap = z.preprocess(
  (v) => (v === "" ? undefined : v),
  z.coerce.number().int().min(1).optional(),
);

const schema = z
  .object({
    HOST: z.string().default("127.0.0.1"),
    PORT: z.coerce.number().int().min(0).max(65535).default(8201),
    /** `fake` = deterministic in-process providers (test tones, placeholder text). Never a real translation. */
    PROVIDER_MODE: z.enum(["real", "fake"]).default("real"),
    /**
     * Long-lived client credential for POST /v1/sessions (token mode). Lives in the macOS Keychain on the client.
     * Empty switches token mode off.
     */
    GATEWAY_ACCESS_TOKEN: optionalSecret,
    /** Unix socket of the site that holds accounts and balances. Empty = accounts off. */
    SITE_SOCKET_PATH: z.string().default(""),
    /** Host header sent on the site socket. */
    SITE_HOST: z.string().default("jaysonkhan.com"),
    /** Shared secret that authenticates this gateway to the site. Empty = accounts off. */
    LIVEBRIDGE_GATEWAY_SECRET: optionalSecret,
    /** Comma-separated voice ids an account session may use (GET /v1/voices lists only these). */
    ACCOUNT_VOICE_IDS: z.string().default(""),

    ELEVENLABS_API_KEY: z.string().default(""),
    /** Voice of your outgoing English / Russian speech. */
    ELEVENLABS_OWNER_VOICE_ID: z.string().default(DEFAULT_VOICE_ID),
    /**
     * Voice of the incoming speech when the client does not choose one in session.configure. May be the same voice;
     * never a clone of the remote participant.
     */
    ELEVENLABS_INCOMING_VOICE_ID: z.string().default(DEFAULT_VOICE_ID),
    /** Regional hosts exist (api.us / api.eu.residency / ...); http(s) here, ws(s) is derived. */
    ELEVENLABS_BASE_URL: z.string().url().default("https://api.elevenlabs.io"),
    STT_MODEL: z.string().default("scribe_v3_live"),
    /** Server-side silence threshold for the `vad` / `turn_prediction` commit strategies (provider range 0.192–3.0). */
    STT_VAD_SILENCE_SECS: z.coerce.number().min(0.192).max(3).default(0.6),
    TTS_MODEL: z.string().default("eleven_v4_turbo"),
    /** Raw PCM only: the client plays s16le directly and no incremental decoder is implemented. */
    TTS_OUTPUT_FORMAT: z
      .string()
      .regex(/^pcm_\d+$/, "only pcm_<rate> formats are supported")
      .default("pcm_24000"),
    /** Comma-separated voice categories (`cloned`, `generated`, ...) left out of `GET /v1/voices`. */
    VOICES_EXCLUDED_CATEGORIES: z.string().default(""),

    TRANSLATION_PROVIDER: z.literal("gemini").default("gemini"),
    GEMINI_API_KEY: z.string().default(""),
    GEMINI_BASE_URL: z
      .string()
      .url()
      .default("https://generativelanguage.googleapis.com/v1beta"),
    TRANSLATION_MODEL: z.string().default("gemini-3.5-flash-lite"),
    /** Same provider, same privacy terms. Empty disables fallback. */
    TRANSLATION_FALLBACK_MODEL: z.string().default("gemini-3.8-flash"),
    /** Models a client may request in session.configure. Defaults to primary + fallback. */
    TRANSLATION_ALLOWED_MODELS: z.string().default(""),
    TRANSLATION_THINKING_LEVEL: z
      .enum(["minimal", "low", "medium", "high"])
      .default("low"),
    TRANSLATION_TIMEOUT_MS: z.coerce.number().int().min(1000).default(8000),
    /** A translation attempt that has produced no text by then is abandoned. */
    TRANSLATION_FIRST_TOKEN_TIMEOUT_MS: z.coerce
      .number()
      .int()
      .min(500)
      .default(4000),
    /** No text by then -> a second request races the first (measured median first token is ~0.9 s). 0 disables. */
    TRANSLATION_HEDGE_AFTER_MS: z.coerce.number().int().min(0).default(1200),

    MAX_SESSIONS: z.coerce.number().int().min(1).default(1),
    /** Cap on account sessions; unset = MAX_SESSIONS (accounts are off anyway until the site is configured). */
    MAX_ACCOUNT_SESSIONS: optionalCap,
    /**
     * Cap on own-keys sessions; unset or 0 = own keys off. Off unless chosen: otherwise a stranger with junk keys
     * could hold a self-hosted gateway's only slot.
     */
    MAX_KEYS_SESSIONS: z.preprocess((v) => (v === "" ? undefined : v), z.coerce.number().int().min(0).default(0)),
    /** Slots of the total that only account sessions may take. */
    PAID_RESERVED_SESSIONS: z.coerce.number().int().min(0).default(0),
    /** No speech on either lane for this long ends the session. 0 disables. */
    IDLE_TIMEOUT_MINUTES: z.coerce.number().int().min(0).default(10),
    /** How often an account session reports usage to the site. At most 60: it bounds an empty account's overrun. */
    USAGE_REPORT_SECONDS: z.coerce.number().int().min(2).max(60).default(10),
    MAX_SESSION_MINUTES: z.coerce.number().int().min(1).default(120),
    /** Content persistence is not implemented; anything but `false` is refused so nobody assumes it works. */
    STORE_CONTENT: z.literal("false").default("false"),
  })
  .superRefine((env, ctx) => {
    if (env.PROVIDER_MODE !== "real") return;
    for (const key of [
      "ELEVENLABS_API_KEY",
      "ELEVENLABS_OWNER_VOICE_ID",
      "ELEVENLABS_INCOMING_VOICE_ID",
      "GEMINI_API_KEY",
    ] as const) {
      if (!env[key])
        ctx.addIssue({
          code: "custom",
          path: [key],
          message: "required when PROVIDER_MODE=real",
        });
    }
  });

export type Env = z.infer<typeof schema>;

export interface Config extends Env {
  MAX_ACCOUNT_SESSIONS: number;
  accountsEnabled: boolean;
  accountVoiceIds: string[];
  allowedTranslationModels: string[];
  voicesExcludedCategories: string[];
  synthSampleRate: number;
}

export function loadConfig(
  source: Record<string, string | undefined> = process.env,
): Config {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    // Names and reasons only — never echo values, they may be secrets.
    const lines = parsed.error.issues.map(
      (i) => `  ${i.path.join(".")}: ${i.message}`,
    );
    throw new Error(`invalid configuration:\n${lines.join("\n")}`);
  }
  const env = parsed.data;
  const allowed = csv(env.TRANSLATION_ALLOWED_MODELS);
  return {
    ...env,
    MAX_ACCOUNT_SESSIONS: env.MAX_ACCOUNT_SESSIONS ?? env.MAX_SESSIONS,
    accountsEnabled: Boolean(env.SITE_SOCKET_PATH && env.LIVEBRIDGE_GATEWAY_SECRET),
    accountVoiceIds: csv(env.ACCOUNT_VOICE_IDS),
    allowedTranslationModels: allowed.length
      ? allowed
      : [env.TRANSLATION_MODEL, env.TRANSLATION_FALLBACK_MODEL].filter(Boolean),
    voicesExcludedCategories: csv(env.VOICES_EXCLUDED_CATEGORIES),
    synthSampleRate: Number(env.TTS_OUTPUT_FORMAT.slice(4)),
  };
}
