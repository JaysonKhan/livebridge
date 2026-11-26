// The voices of an ElevenLabs account, in the gateway's own shape. `GET /v2/voices` per
// https://elevenlabs.io/docs/api-reference/voices/search (read 2026-11-26). The key needs the "voices read"
// permission; `npm run probe` checks the live service.
import { ProviderError, type Voice } from "./types.ts";

const PAGE_SIZE = 100;
/** A stop for a provider that keeps answering `has_more`. */
const MAX_PAGES = 20;
const REQUEST_TIMEOUT_MS = 10_000;

const text = (value: unknown) =>
  typeof value === "string" && value ? value : undefined;

function toVoice(raw: Record<string, any>): Voice | null {
  const id = text(raw.voice_id);
  const name = text(raw.name);
  if (!id || !name) return null;
  const labels: Record<string, unknown> = raw.labels ?? {};
  const previews: Record<string, string> = {};
  for (const entry of Array.isArray(raw.verified_languages) ? raw.verified_languages : []) {
    const language = text(entry?.language);
    const sample = text(entry?.preview_url);
    if (language && sample) previews[language] ??= sample;
  }
  const voice: Voice = { id, name };
  // Absent members stay absent, so the JSON carries no nulls.
  const set = <K extends keyof Voice>(key: K, value: Voice[K] | undefined) => {
    if (value !== undefined) voice[key] = value;
  };
  set("gender", text(labels.gender));
  set("age", text(labels.age));
  set("accent", text(labels.accent));
  set("language", text(labels.language));
  set("use_case", text(labels.use_case));
  set("description", text(raw.description));
  set("category", text(raw.category));
  set("preview_url", text(raw.preview_url));
  if (Object.keys(previews).length) voice.previews = previews;
  return voice;
}

export async function listElevenLabsVoices(options: {
  apiKey: string;
  baseUrl: string;
  excludedCategories: readonly string[];
  signal?: AbortSignal;
}): Promise<Voice[]> {
  const voices: Voice[] = [];
  let token: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const url = new URL("/v2/voices", options.baseUrl);
    url.searchParams.set("page_size", String(PAGE_SIZE));
    url.searchParams.set("include_total_count", "false");
    if (token) url.searchParams.set("next_page_token", token);
    const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
    let body: {
      voices?: Record<string, any>[];
      has_more?: boolean;
      next_page_token?: string | null;
    };
    try {
      const response = await fetch(url, {
        headers: { "xi-api-key": options.apiKey },
        signal: options.signal
          ? AbortSignal.any([options.signal, timeout])
          : timeout,
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new ProviderError(
          "voices_unavailable",
          `voice list refused (${response.status})`,
        );
      }
      body = await response.json();
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      throw new ProviderError("voices_unavailable", "voice list request failed");
    }
    for (const raw of body.voices ?? []) {
      const voice = toVoice(raw);
      if (voice && !options.excludedCategories.includes(voice.category ?? ""))
        voices.push(voice);
    }
    token = body.has_more ? (body.next_page_token ?? undefined) : undefined;
    if (!token) break;
  }
  return voices;
}
