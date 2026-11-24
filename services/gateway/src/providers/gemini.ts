// Gemini streaming translation over REST `streamGenerateContent?alt=sse` (v1beta), with the API key in a header
// rather than the URL.
//
// Shaped by live measurements on 2026-11-24 (see docs/benchmark.md):
//  - A new TLS connection per request cost ~1 s at the median from the owner's network, and Node's fetch drops
//    idle connections after 4 s. Requests therefore go through a keep-alive agent and the connection is warmed
//    before speech ends.
//  - First-token time has a heavy tail (seconds) and models intermittently answer 503 "high demand". A slow attempt
//    is hedged with a second request; a model that keeps failing is skipped for a while.
import http from "node:http";
import https from "node:https";
import { buildTranslationPrompt } from "../prompt.ts";
import type {
  StreamingTranslator,
  TranslateRequest,
  TranslateResult,
} from "./types.ts";
import { ProviderError } from "./types.ts";

export interface GeminiConfig {
  apiKey: string;
  baseUrl: string;
  fallbackModel: string;
  thinkingLevel: string;
  /** Whole-request limit for one attempt. */
  timeoutMs: number;
  /** An attempt with no translated text by then is abandoned. Defaults to `timeoutMs`. */
  firstTokenTimeoutMs?: number;
  /**
   * If the first attempt has produced no text by then, a second request on the same model is started in parallel
   * and whichever answers first is used. Unset = no hedging. The fallback model is for attempts that fail.
   */
  hedgeAfterMs?: number;
  /** Called whenever a second attempt is started: reason is the first attempt's error code, `slow`, or `circuit_open`. */
  onFallback?: (from: string, to: string, reason: string) => void;
}

interface Chunk {
  candidates?: {
    content?: { parts?: { text?: string; thought?: boolean }[] };
    finishReason?: string;
  }[];
}

/** After this many consecutive transient failures a model is skipped for a while instead of retried every turn. */
const CIRCUIT_FAILURES = 2;
const CIRCUIT_OPEN_MS = 60_000;
/** A connection idle for longer than this may have been closed by the server; warm it again before it is needed. */
const WARM_AFTER_IDLE_MS = 20_000;

export class GeminiTranslator implements StreamingTranslator {
  private readonly config: GeminiConfig;
  private readonly health = new Map<
    string,
    { failures: number; downUntil: number }
  >();
  private readonly agent: http.Agent;
  private readonly secure: boolean;
  private lastActivity = 0;

  constructor(config: GeminiConfig) {
    this.config = config;
    this.secure = config.baseUrl.startsWith("https:");
    this.agent = this.secure
      ? new https.Agent({ keepAlive: true, maxSockets: 4 })
      : new http.Agent({ keepAlive: true, maxSockets: 4 });
  }

  /** Makes sure a live connection exists (cheap metadata request, no tokens). Safe to call often. */
  warm(model: string) {
    if (Date.now() - this.lastActivity < WARM_AFTER_IDLE_MS) return;
    this.lastActivity = Date.now();
    const request = this.request(
      "GET",
      `${this.config.baseUrl}/models/${encodeURIComponent(model)}`,
      AbortSignal.timeout(5_000),
    );
    request.on("response", (response) => response.resume());
    request.on("error", () => {});
    request.end();
  }

  translate(
    req: TranslateRequest,
    onDelta: (text: string) => void,
    signal: AbortSignal,
  ): Promise<TranslateResult> {
    const fallback =
      this.config.fallbackModel && this.config.fallbackModel !== req.model
        ? this.config.fallbackModel
        : null;
    // Circuit breaker: a primary that keeps failing (e.g. 503 "high demand") costs every turn a wasted round trip.
    if (fallback && Date.now() < (this.health.get(req.model)?.downUntil ?? 0)) {
      this.config.onFallback?.(req.model, fallback, "circuit_open");
      return this.call(fallback, req, onDelta, signal).then((text) => ({
        text,
        model: fallback,
      }));
    }
    // Up to three attempts: the requested model, a hedge on the same model if it is slow, and the fallback model
    // if an attempt fails outright.
    const MAX_ATTEMPTS = 3;

    return new Promise((resolve, reject) => {
      const attempts: { model: string; abort: AbortController }[] = [];
      let winner: number | null = null;
      let running = 0;
      let done = false;
      const finish = (settle: () => void) => {
        if (done) return;
        done = true;
        clearTimeout(hedge);
        for (const attempt of attempts) attempt.abort.abort();
        settle();
      };

      const start = (model: string, reason: string | null) => {
        if (done || winner !== null || attempts.length >= MAX_ATTEMPTS) return;
        const index = attempts.length;
        if (reason) this.config.onFallback?.(req.model, model, reason);
        const abort = new AbortController();
        attempts.push({ model, abort });
        running++;
        this.call(
          model,
          req,
          (delta) => {
            // The first attempt to produce text wins; the others are cancelled so nothing is shown or spoken twice.
            if (winner === null) {
              winner = index;
              clearTimeout(hedge);
              attempts.forEach((other, i) => i !== index && other.abort.abort());
            }
            if (winner === index && !done) onDelta(delta);
          },
          AbortSignal.any([signal, abort.signal]),
        ).then(
          (text) => {
            running--;
            if (winner !== null && winner !== index) return;
            this.health.delete(model);
            finish(() => resolve({ text, model }));
          },
          (error) => {
            running--;
            if (done) return;
            // Once text has streamed it may be on screen: never retry. A user cancel ends everything.
            if (winner === index || signal.aborted) return finish(() => reject(error));
            if (winner !== null) return; // an attempt that lost the race, cancelled above
            const transient = error instanceof ProviderError && !error.permanent;
            if (transient) {
              this.noteFailure(model);
              const tried = (name: string) => attempts.filter((attempt) => attempt.model === name).length;
              if (fallback && tried(fallback) === 0) start(fallback, error.code);
              // A stalled request is worth one more try on the same model; a refusal (503) is not.
              else if (error.code === "timeout" && tried(req.model) < 2) start(req.model, error.code);
            }
            if (running === 0) finish(() => reject(error));
          },
        );
      };

      // A slow answer is usually one slow backend, not a slow model: race a second request on the same model.
      const hedge =
        this.config.hedgeAfterMs === undefined
          ? undefined
          : setTimeout(() => start(req.model, "slow"), this.config.hedgeAfterMs);
      start(req.model, null);
    });
  }

  private noteFailure(model: string) {
    const health = this.health.get(model) ?? { failures: 0, downUntil: 0 };
    health.failures++;
    if (health.failures >= CIRCUIT_FAILURES)
      health.downUntil = Date.now() + CIRCUIT_OPEN_MS;
    this.health.set(model, health);
  }

  private request(method: string, url: string, signal: AbortSignal) {
    const options = {
      method,
      agent: this.agent,
      signal,
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": this.config.apiKey,
      },
    };
    return this.secure
      ? https.request(url, options)
      : http.request(url, options);
  }

  private async call(
    model: string,
    req: TranslateRequest,
    onDelta: (text: string) => void,
    signal: AbortSignal,
  ) {
    const { system, user } = buildTranslationPrompt(req);
    const url = `${this.config.baseUrl}/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`;
    const stalled = new AbortController();
    const firstToken = setTimeout(
      () => stalled.abort(),
      this.config.firstTokenTimeoutMs ?? this.config.timeoutMs,
    );
    const limit = AbortSignal.timeout(this.config.timeoutMs);
    const failure = (error: unknown, code: string, message: string) => {
      if (signal.aborted) return error;
      if (stalled.signal.aborted || limit.aborted)
        return new ProviderError(
          "timeout",
          "no translation text arrived in time",
        );
      return new ProviderError(code, message);
    };

    try {
      this.lastActivity = Date.now();
      const request = this.request(
        "POST",
        url,
        AbortSignal.any([signal, stalled.signal, limit]),
      );
      const response = await new Promise<http.IncomingMessage>(
        (resolve, reject) => {
          request.on("response", resolve);
          request.on("error", reject);
          request.end(
            JSON.stringify({
              systemInstruction: { parts: [{ text: system }] },
              contents: [{ role: "user", parts: [{ text: user }] }],
              // Thinking tokens count against maxOutputTokens; a low level keeps them near zero for short turns.
              generationConfig: {
                maxOutputTokens: 1024,
                thinkingConfig: { thinkingLevel: this.config.thinkingLevel },
              },
              // Keep request content out of AI Studio logs on projects where storing is the default.
              store: false,
            }),
          );
        },
      ).catch((error) => {
        throw failure(error, "network", "translation request failed");
      });

      const status = response.statusCode ?? 0;
      if (status !== 200) {
        response.resume();
        throw new ProviderError(
          `http_${status}`,
          `translation rejected (${status})`,
          status >= 400 && status < 500 && status !== 429,
        );
      }

      let text = "";
      let finish: string | undefined;
      let buffered = "";
      const decoder = new TextDecoder();
      try {
        for await (const bytes of response) {
          buffered += decoder.decode(bytes as Buffer, { stream: true });
          let newline: number;
          while ((newline = buffered.indexOf("\n")) >= 0) {
            const line = buffered.slice(0, newline).trimEnd();
            buffered = buffered.slice(newline + 1);
            if (!line.startsWith("data: ")) continue;
            let chunk: Chunk;
            try {
              chunk = JSON.parse(line.slice(6));
            } catch {
              continue;
            }
            const candidate = chunk.candidates?.[0];
            for (const part of candidate?.content?.parts ?? []) {
              if (part.thought || !part.text) continue;
              clearTimeout(firstToken);
              text += part.text;
              onDelta(part.text);
            }
            finish = candidate?.finishReason ?? finish;
          }
        }
      } catch (error) {
        throw failure(
          error,
          "stream_interrupted",
          "translation stream interrupted",
        );
      }
      // A truncated or filtered answer is not a faithful translation; surface it instead of speaking half a sentence.
      if (finish !== "STOP") {
        // A stream cut off without a finish reason is a connection problem, not a model verdict.
        if (finish === undefined)
          throw new ProviderError(
            "stream_interrupted",
            "translation stream ended early",
          );
        throw new ProviderError(
          `finish_${finish}`,
          "translation did not complete",
          true,
        );
      }
      return text;
    } finally {
      clearTimeout(firstToken);
      this.lastActivity = Date.now();
    }
  }
}
