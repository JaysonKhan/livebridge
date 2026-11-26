import type { Config } from "../config.ts";
import type { Logger } from "../log.ts";
import { ElevenLabsRealtimeSTT } from "./elevenlabs-stt.ts";
import { ElevenLabsDialogueTTS } from "./elevenlabs-tts.ts";
import { GeminiTranslator } from "./gemini.ts";
import type { ProviderFactory } from "./types.ts";

export function createRealProviders(
  config: Config,
  log: Logger,
): ProviderFactory {
  return {
    mock: false,
    names: {
      stt: config.STT_MODEL,
      translation: config.TRANSLATION_MODEL,
      tts: config.TTS_MODEL,
    },
    synthSampleRate: config.synthSampleRate,
    stt: (options) =>
      new ElevenLabsRealtimeSTT(
        {
          apiKey: config.ELEVENLABS_API_KEY,
          baseUrl: config.ELEVENLABS_BASE_URL,
          model: config.STT_MODEL,
          vadSilenceSecs: config.STT_VAD_SILENCE_SECS,
        },
        options,
      ),
    translator: () =>
      new GeminiTranslator({
        apiKey: config.GEMINI_API_KEY,
        baseUrl: config.GEMINI_BASE_URL,
        fallbackModel: config.TRANSLATION_FALLBACK_MODEL,
        thinkingLevel: config.TRANSLATION_THINKING_LEVEL,
        timeoutMs: config.TRANSLATION_TIMEOUT_MS,
        firstTokenTimeoutMs: config.TRANSLATION_FIRST_TOKEN_TIMEOUT_MS,
        hedgeAfterMs: config.TRANSLATION_HEDGE_AFTER_MS || undefined,
        onFallback: (from, to, reason) =>
          log.warn("translation.fallback", { from, to, reason }),
      }),
    tts: (options) =>
      new ElevenLabsDialogueTTS({
        apiKey: config.ELEVENLABS_API_KEY,
        baseUrl: config.ELEVENLABS_BASE_URL,
        model: config.TTS_MODEL,
        // Unless the session chose a voice, the owner's clone only speaks the owner's own outgoing speech.
        voiceId:
          options.voiceId ??
          (options.voice === "owner"
            ? config.ELEVENLABS_OWNER_VOICE_ID
            : config.ELEVENLABS_INCOMING_VOICE_ID),
        language: options.language,
        outputFormat: config.TTS_OUTPUT_FORMAT,
        onMarkerMissing: () =>
          log.warn("tts.turn_marker_missing", { voice: options.voice }),
      }),
  };
}
