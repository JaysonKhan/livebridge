// The REAL provider adapters against local MOCK provider servers (tests/integration/mock-providers.ts).
// These verify the adapters against the documented wire protocols. They are not evidence about the live APIs.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import type { ServerMessage } from "../../packages/protocol/src/index.ts";
import { ElevenLabsRealtimeSTT } from "../../services/gateway/src/providers/elevenlabs-stt.ts";
import { ElevenLabsDialogueTTS } from "../../services/gateway/src/providers/elevenlabs-tts.ts";
import { GeminiTranslator } from "../../services/gateway/src/providers/gemini.ts";
import {
  ProviderError,
  type TranslateRequest,
} from "../../services/gateway/src/providers/types.ts";
import { sleep, speech, startGateway, TestClient } from "./helpers.ts";
import {
  MOCK_API_KEY,
  MOCK_GEMINI_KEY,
  startMockElevenLabs,
  startMockGemini,
  type ElevenLabsBehaviour,
  type GeminiModelBehaviour,
} from "./mock-providers.ts";

const cleanup: (() => unknown)[] = [];
afterEach(async () => {
  for (const fn of cleanup.splice(0).reverse()) await fn();
});

async function eleven(behaviour: ElevenLabsBehaviour = {}) {
  const mock = await startMockElevenLabs(behaviour);
  cleanup.push(() => mock.close());
  return mock;
}

function sttAdapter(
  base: string,
  commit: "manual" | "vad" = "manual",
  apiKey = MOCK_API_KEY,
) {
  const events = {
    partials: [] as string[],
    committed: [] as string[],
    disconnects: [] as ProviderError[],
  };
  const stt = new ElevenLabsRealtimeSTT(
    { apiKey, baseUrl: base, model: "scribe_v3_live", vadSilenceSecs: 0.6 },
    {
      language: "uz",
      commit,
      events: {
        onPartial: (t) => events.partials.push(t),
        onCommitted: (t) => events.committed.push(t),
        onDisconnected: (e) => events.disconnects.push(e),
      },
    },
  );
  cleanup.push(() => stt.close());
  return { stt, events };
}

const until = async (probe: () => boolean, what: string) => {
  for (let i = 0; i < 300; i++) {
    if (probe()) return;
    await sleep(10);
  }
  assert.fail(`timed out waiting for ${what}`);
};

// ---------- Speech-to-text ----------

test("STT: documented handshake, 100 ms chunks, commit flushes the remainder, events delivered", async () => {
  const mock = await eleven({ transcripts: ["Salom dunyo"], partials: true });
  const { stt, events } = sttAdapter(mock.base);
  await stt.open();
  const query = mock.stt.queries[0]!;
  assert.deepEqual(
    [
      query.get("model_id"),
      query.get("audio_format"),
      query.get("language_code"),
      query.get("commit_strategy"),
    ],
    ["scribe_v3_live", "pcm_16000", "uz", "manual"],
  );
  assert.equal(query.get("vad_silence_threshold_secs"), null);

  // 13 frames of 20 ms = 260 ms -> two 100 ms chunks while streaming, 60 ms left for the commit.
  for (let i = 0; i < 13; i++) assert.equal(stt.sendAudio(speech(20)), 0);
  stt.commit();
  await until(() => events.committed.length === 1, "committed transcript");
  assert.deepEqual(
    mock.stt.chunks.map((c) => [c.bytes, c.commit, c.sample_rate]),
    [
      [3200, false, 16000],
      [3200, false, 16000],
      // 60 ms of speech left, padded with silence: the provider needs 0.3 s of uncommitted audio (260 → 320 ms).
      [3840, true, 16000],
    ],
  );
  assert.deepEqual(events.committed, ["Salom dunyo"]);
  assert.deepEqual(events.partials, ["partial 1", "partial 2"]);
  assert.deepEqual(events.disconnects, []);
});

test("STT: vad strategy sends the silence threshold", async () => {
  const mock = await eleven();
  const { stt } = sttAdapter(mock.base, "vad");
  await stt.open();
  assert.equal(mock.stt.queries[0]!.get("commit_strategy"), "vad");
  assert.equal(mock.stt.queries[0]!.get("vad_silence_threshold_secs"), "0.6");
});

test("STT: a wrong API key fails open() permanently", async () => {
  const mock = await eleven();
  const { stt } = sttAdapter(mock.base, "manual", "wrong-key");
  await assert.rejects(
    stt.open(),
    (e) => e instanceof ProviderError && e.code === "http_401" && e.permanent,
  );
});

test("STT: quota error at session start is permanent; a mid-session provider error is a retryable disconnect", async () => {
  const refused = await eleven({ sttStartError: "quota_exceeded" });
  await assert.rejects(
    sttAdapter(refused.base).stt.open(),
    (e) =>
      e instanceof ProviderError && e.code === "quota_exceeded" && e.permanent,
  );

  const mock = await eleven();
  const { stt, events } = sttAdapter(mock.base);
  await stt.open();
  mock.sendSttError("rate_limited");
  await until(() => events.disconnects.length === 1, "disconnect");
  assert.deepEqual(
    [events.disconnects[0]!.code, events.disconnects[0]!.permanent],
    ["rate_limited", false],
  );
});

test("STT: a dropped connection is reported once, and close() is silent", async () => {
  const mock = await eleven();
  const { stt, events } = sttAdapter(mock.base);
  await stt.open();
  mock.dropStt();
  await until(() => events.disconnects.length === 1, "disconnect");
  await sleep(30);
  assert.equal(events.disconnects.length, 1);

  const second = sttAdapter(mock.base);
  await second.stt.open();
  second.stt.close();
  await sleep(30);
  assert.deepEqual(second.events.disconnects, []);
});

test("STT: audio captured while disconnected is bounded to ~500 ms and the excess is reported as dropped", async () => {
  const mock = await eleven();
  const { stt } = sttAdapter(mock.base);
  let dropped = 0;
  for (let i = 0; i < 40; i++) dropped += stt.sendAudio(speech(20)); // 800 ms before the socket exists
  assert.equal(dropped, 300 * 32);
  await stt.open();
  stt.commit();
  await until(() => mock.stt.chunks.some((c) => c.commit), "commit chunk");
  assert.equal(
    mock.stt.chunks.reduce((n, c) => n + c.bytes, 0),
    500 * 32,
  );
});

// ---------- Text-to-speech ----------

function ttsAdapter(base: string, apiKey = MOCK_API_KEY) {
  const stats = { markerMissing: 0 };
  const tts = new ElevenLabsDialogueTTS({
    apiKey,
    baseUrl: base,
    model: "eleven_v4_turbo",
    voiceId: "voice-owner",
    language: "en",
    outputFormat: "pcm_24000",
    idleAfterAudioMs: 400,
    onMarkerMissing: () => stats.markerMissing++,
  });
  cleanup.push(() => tts.close());
  return { tts, stats };
}

async function collect(
  tts: ElevenLabsDialogueTTS,
  text: string,
  signal = new AbortController().signal,
) {
  const chunks: Buffer[] = [];
  await tts.synthesize(text, (pcm) => chunks.push(Buffer.from(pcm)), signal);
  return chunks;
}

test("TTS: registers one voice, sends input + flush, delivers whole samples and resolves on the turn marker", async () => {
  const mock = await eleven();
  const { tts, stats } = ttsAdapter(mock.base);
  await tts.open();
  assert.equal(tts.sampleRate, 24000);
  const query = mock.tts.queries[0]!;
  assert.deepEqual(
    [
      query.get("model_id"),
      query.get("output_format"),
      query.get("language_code"),
    ],
    ["eleven_v4_turbo", "pcm_24000", "en"],
  );

  const chunks = await collect(tts, "Hello there.");
  assert.deepEqual(mock.tts.messages, [
    { voices: ["voice-owner"] },
    {
      inputs: [
        { text: "Hello there.", voice_id: "voice-owner", new_turn: true },
      ],
    },
    { flush: true },
  ]);
  // Provider chunks of 4801 + 4799 + 4800 bytes arrive re-aligned to 16-bit samples with nothing lost.
  assert.ok(chunks.every((c) => c.length % 2 === 0));
  assert.deepEqual(
    chunks.map((c) => c.length),
    [4800, 4800, 4800],
  );
  assert.equal(stats.markerMissing, 0);

  // The same warm socket serves the next turn.
  const second = await collect(tts, "Second turn.");
  assert.equal(mock.tts.connections, 1);
  assert.ok(second.every((c) => c.every((byte) => byte === 2)));
});

test("TTS: aborting a turn drops the connection, and the next turn gets only its own audio", async () => {
  const mock = await eleven({
    ttsChunks: Array(10).fill(4800),
    ttsChunkDelayMs: 20,
  });
  const { tts } = ttsAdapter(mock.base);
  await tts.open();
  const abort = new AbortController();
  const received: Buffer[] = [];
  const turn = tts.synthesize(
    "A long first sentence.",
    (pcm) => received.push(Buffer.from(pcm)),
    abort.signal,
  );
  await until(() => received.length >= 2, "first chunks");
  abort.abort(new Error("cancelled"));
  await assert.rejects(turn, /cancelled/);
  const atAbort = received.length;
  await sleep(120);
  assert.equal(received.length, atAbort);

  const next = await collect(tts, "Second sentence.");
  assert.equal(mock.tts.connections, 2);
  // Turn audio is filled with a per-connection turn counter: a fresh socket starts at 1 again, and no byte of the
  // aborted turn (which stopped arriving above) is mixed in.
  assert.equal(next.length, 10);
  assert.ok(next.every((c) => c.every((byte) => byte === 1)));
});

test("TTS: a missing end-of-turn marker ends the turn by watchdog, is counted, and recycles the socket", async () => {
  const mock = await eleven({ omitTurnMarker: true });
  const { tts, stats } = ttsAdapter(mock.base);
  await tts.open();
  const started = Date.now();
  const chunks = await collect(tts, "No marker.");
  assert.equal(chunks.length, 3);
  assert.ok(Date.now() - started >= 350);
  assert.equal(stats.markerMissing, 1);
  await collect(tts, "Again.");
  assert.equal(mock.tts.connections, 2);
});

test("TTS: a provider error payload rejects the turn permanently; a wrong key fails open()", async () => {
  const mock = await eleven({ ttsError: "voice_not_found" });
  const { tts } = ttsAdapter(mock.base);
  await tts.open();
  await assert.rejects(
    collect(tts, "Hello"),
    (e) =>
      e instanceof ProviderError && e.code === "voice_not_found" && e.permanent,
  );
  await assert.rejects(
    ttsAdapter(mock.base, "wrong-key").tts.open(),
    (e) => e instanceof ProviderError && e.code === "http_401" && e.permanent,
  );
});

test("TTS: refuses overlapping turns instead of mixing them", async () => {
  const mock = await eleven({ ttsChunkDelayMs: 20 });
  const { tts } = ttsAdapter(mock.base);
  await tts.open();
  const first = collect(tts, "one");
  await assert.rejects(collect(tts, "two"), /another turn is in flight/);
  await first;
});

// ---------- Translation ----------

async function gemini(
  models: Record<string, GeminiModelBehaviour>,
  timeoutMs = 2000,
) {
  const mock = await startMockGemini(models);
  cleanup.push(() => mock.close());
  const fallbacks: string[] = [];
  const translator = new GeminiTranslator({
    apiKey: MOCK_GEMINI_KEY,
    baseUrl: mock.base,
    fallbackModel: "fallback-model",
    thinkingLevel: "low",
    timeoutMs,
    onFallback: (from, to, reason) => fallbacks.push(`${from}>${to}:${reason}`),
  });
  return { mock, translator, fallbacks };
}

const request: TranslateRequest = {
  source: "uz",
  target: "en",
  text: "Men Flutter dasturchisiman.",
  context: [{ source: "Salom", target: "Hello" }],
  glossary: [],
  model: "primary-model",
};
const run = async (
  translator: GeminiTranslator,
  signal = new AbortController().signal,
) => {
  const deltas: string[] = [];
  const result = await translator.translate(
    request,
    (t) => deltas.push(t),
    signal,
  );
  return { deltas, result };
};

test("translation: streams deltas across split SSE writes, ignores thinking parts, sends the documented body", async () => {
  const { mock, translator, fallbacks } = await gemini({
    "primary-model": { pieces: ["I am a ", "Flutter ", "developer."] },
  });
  const { deltas, result } = await run(translator);
  assert.deepEqual(deltas, ["I am a ", "Flutter ", "developer."]);
  assert.deepEqual(result, {
    text: "I am a Flutter developer.",
    model: "primary-model",
  });
  assert.deepEqual(fallbacks, []);

  const sent = mock.requests[0]!;
  assert.equal(sent.apiKey, MOCK_GEMINI_KEY);
  assert.ok(
    !sent.url.includes(MOCK_GEMINI_KEY),
    "API key must not be in the URL",
  );
  assert.match(sent.url, /primary-model:streamGenerateContent\?alt=sse$/);
  assert.match(
    sent.body.systemInstruction.parts[0].text,
    /Translate Uzbek to English/,
  );
  assert.deepEqual(JSON.parse(sent.body.contents[0].parts[0].text), {
    text: "Men Flutter dasturchisiman.",
    context: [{ source: "Salom", target: "Hello" }],
    glossary: [],
  });
  assert.deepEqual(sent.body.generationConfig.thinkingConfig, {
    thinkingLevel: "low",
  });
  assert.equal(sent.body.store, false);
  assert.equal(sent.body.tools, undefined);
});

test("translation: rate limit, server error and timeout fall back to the approved model and say so", async () => {
  for (const [behaviour, reason, timeoutMs] of [
    [{ status: 429 }, "http_429", 2000],
    [{ status: 503 }, "http_503", 2000],
    [{ hang: true }, "timeout", 150],
  ] as const) {
    const { mock, translator, fallbacks } = await gemini(
      { "primary-model": behaviour, "fallback-model": { pieces: ["Hello"] } },
      timeoutMs,
    );
    const { result } = await run(translator);
    assert.deepEqual(result, { text: "Hello", model: "fallback-model" });
    assert.deepEqual(fallbacks, [`primary-model>fallback-model:${reason}`]);
    assert.deepEqual(
      mock.requests.map((r) => r.model),
      ["primary-model", "fallback-model"],
    );
  }
});

test("translation: a rejected request (bad model / key) is permanent and is not retried on the fallback", async () => {
  const { mock, translator, fallbacks } = await gemini({
    "primary-model": { status: 400 },
    "fallback-model": { pieces: ["Hello"] },
  });
  await assert.rejects(
    run(translator),
    (e) => e instanceof ProviderError && e.code === "http_400" && e.permanent,
  );
  assert.deepEqual(fallbacks, []);
  assert.equal(mock.requests.length, 1);
});

test("translation: truncated or filtered output is an error, never a half sentence", async () => {
  for (const finishReason of ["MAX_TOKENS", "SAFETY"]) {
    const { translator, mock } = await gemini({
      "primary-model": { pieces: ["I am"], finishReason },
      "fallback-model": { pieces: ["x"] },
    });
    await assert.rejects(
      run(translator),
      (e) => e instanceof ProviderError && e.code === `finish_${finishReason}`,
    );
    assert.equal(mock.requests.length, 1);
  }
});

test("translation: a stream that dies after text was shown is not retried (no duplicated prefix)", async () => {
  const { translator, mock, fallbacks } = await gemini({
    "primary-model": {
      pieces: ["I am a ", "Flutter ", "developer."],
      dieAfter: 2,
    },
    "fallback-model": { pieces: ["x"] },
  });
  const deltas: string[] = [];
  await assert.rejects(
    translator.translate(
      request,
      (t) => deltas.push(t),
      new AbortController().signal,
    ),
    (e) => e instanceof ProviderError && e.code === "stream_interrupted",
  );
  assert.ok(deltas.length >= 1);
  assert.deepEqual(fallbacks, []);
  assert.equal(mock.requests.length, 1);
});

test("translation: cancelling aborts the request and never triggers the fallback", async () => {
  const { translator, mock, fallbacks } = await gemini({
    "primary-model": { hang: true },
    "fallback-model": { pieces: ["x"] },
  });
  const abort = new AbortController();
  const pending = run(translator, abort.signal);
  await until(() => mock.requests.length === 1, "request");
  abort.abort(new Error("cancelled"));
  await assert.rejects(pending);
  await sleep(30);
  assert.deepEqual(fallbacks, []);
  assert.equal(mock.requests.length, 1);
});

// ---------- Whole gateway on the real adapters, mock provider servers behind them ----------

async function realStack(
  elevenBehaviour: ElevenLabsBehaviour,
  models: Record<string, GeminiModelBehaviour>,
) {
  const el = await eleven(elevenBehaviour);
  const gm = await startMockGemini(models);
  cleanup.push(() => gm.close());
  const started = await startGateway({
    env: {
      PROVIDER_MODE: "real",
      ELEVENLABS_API_KEY: MOCK_API_KEY,
      ELEVENLABS_OWNER_VOICE_ID: "voice-owner",
      ELEVENLABS_INCOMING_VOICE_ID: "voice-stock",
      ELEVENLABS_BASE_URL: el.base,
      GEMINI_API_KEY: MOCK_GEMINI_KEY,
      GEMINI_BASE_URL: gm.base,
    },
  });
  cleanup.push(() => started.gateway.close());
  const client = await TestClient.connect(started.base);
  return { el, gm, client, ...started };
}

const readiness = (client: TestClient) =>
  client.messages
    .filter(
      (m): m is Extract<ServerMessage, { type: "session.ready" }> =>
        m.type === "session.ready",
    )
    .map((m) => m.directions.out.ready);

test("end to end on the real adapters (mock servers): one push-to-talk turn through STT, translation and TTS", async () => {
  const { el, gm, client, logLines } = await realStack(
    { transcripts: ["Salom, ishlar qalay?"] },
    { "gemini-3.5-flash-lite": { pieces: ["Hello, ", "how are you?"] } },
  );
  const ready = await client.configure();
  assert.deepEqual(ready.providers, {
    stt: "scribe_v3_live",
    translation: "gemini-3.5-flash-lite",
    tts: "eleven_v4_turbo",
    mock: false,
  });
  assert.deepEqual(
    [ready.directions.out.ready, ready.directions.in.ready],
    [true, true],
  );
  // Two STT and two TTS provider sessions, each direction with its own language and its own voice.
  assert.deepEqual(
    el.stt.queries
      .map((q) => `${q.get("language_code")}/${q.get("commit_strategy")}`)
      .sort(),
    ["en/vad", "uz/manual"],
  );
  assert.deepEqual(el.tts.queries.map((q) => q.get("language_code")).sort(), [
    "en",
    "uz",
  ]);
  const voices = el.tts.messages
    .filter((m) => m.voices)
    .map((m) => (m.voices as string[])[0]);
  assert.deepEqual(voices.sort(), ["voice-owner", "voice-stock"]);

  client.send({ v: 1, type: "capture.start", direction: "out", generation: 1 });
  client.sendAudio("out", 1, speech(500));
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  const metrics = await client.message("metrics");
  assert.equal(
    (await client.message("caption.final")).text,
    "Salom, ishlar qalay?",
  );
  assert.equal(
    (await client.message("translation.final")).text,
    "Hello, how are you?",
  );
  assert.equal(
    client.frames.reduce((n, f) => n + f.payload.byteLength, 0),
    14400,
  );
  assert.ok(
    client.frames.every((f) => f.direction === "out" && f.turnId === 1),
  );
  assert.equal(metrics.audio_ms, 300);
  // Only the owner voice spoke, and only the translated text was sent to synthesis.
  const inputs = el.tts.messages.filter((m) => m.inputs);
  assert.deepEqual(inputs, [
    {
      inputs: [
        {
          text: "Hello, how are you?",
          voice_id: "voice-owner",
          new_turn: true,
        },
      ],
    },
  ]);
  assert.equal(gm.requests.length, 1);
  const log = logLines.join("\n");
  for (const forbidden of ["Salom", "Hello", MOCK_API_KEY, MOCK_GEMINI_KEY])
    assert.ok(!log.includes(forbidden), `log leaked ${forbidden}`);
});

test("end to end (mock servers): a dropped STT connection is announced as not ready, then recovers without replaying audio", async () => {
  const { el, client } = await realStack(
    { transcripts: ["after reconnect"] },
    { "gemini-3.5-flash-lite": { pieces: ["ok"] } },
  );
  await client.configure({ in: { enabled: false } });
  client.send({ v: 1, type: "capture.start", direction: "out", generation: 1 });
  let sequence = client.sendAudio("out", 1, speech(300));
  await client.sync();
  const chunksBeforeDrop = el.stt.chunks.length;
  el.dropStt();
  await client.waitFor(
    (c) => readiness(c).join() === "true,false,true",
    "ready -> not ready -> ready",
  );
  assert.ok(
    client.messages.some(
      (m) =>
        m.type === "error" && m.code === "provider_unavailable" && !m.fatal,
    ),
  );
  assert.equal(el.stt.connections, 2);

  sequence = client.sendAudio("out", 1, speech(200), sequence);
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.message("metrics");
  // The new provider session received only the 200 ms spoken after the reconnect.
  const after = el.stt.chunks
    .slice(chunksBeforeDrop)
    .reduce((n, c) => n + c.bytes, 0);
  // (200 ms of speech, padded to the provider's 0.3 s commit minimum — nothing from before the drop.)
  assert.equal(after, 320 * 32);
});

test("end to end (mock servers): bad provider credentials leave the direction not ready with an explicit error", async () => {
  const el = await eleven();
  const gm = await startMockGemini({});
  cleanup.push(() => gm.close());
  const started = await startGateway({
    env: {
      PROVIDER_MODE: "real",
      ELEVENLABS_API_KEY: "revoked-key",
      ELEVENLABS_OWNER_VOICE_ID: "voice-owner",
      ELEVENLABS_INCOMING_VOICE_ID: "voice-stock",
      ELEVENLABS_BASE_URL: el.base,
      GEMINI_API_KEY: MOCK_GEMINI_KEY,
      GEMINI_BASE_URL: gm.base,
    },
  });
  cleanup.push(() => started.gateway.close());
  const client = await TestClient.connect(started.base);
  const ready = await client.configure();
  assert.deepEqual(
    [ready.directions.out.ready, ready.directions.in.ready],
    [false, false],
  );
  const failures = client.messages.filter(
    (m) => m.type === "error" && m.code === "provider_unavailable",
  );
  assert.equal(failures.length, 2);
  await sleep(100);
  // Permanent failures are not retried in a loop.
  assert.equal(el.stt.connections + el.tts.connections, 0);
});

// ---------- Translation resilience (added after the first live probe: 503 "high demand" and a 21 s stall) ----------

test("translation: a stalled attempt is abandoned at the first-token limit and answered by the fallback", async () => {
  const mock = await startMockGemini({ "primary-model": { hang: true }, "fallback-model": { pieces: ["Hello"] } });
  cleanup.push(() => mock.close());
  const fallbacks: string[] = [];
  const translator = new GeminiTranslator({
    apiKey: MOCK_GEMINI_KEY,
    baseUrl: mock.base,
    fallbackModel: "fallback-model",
    thinkingLevel: "low",
    timeoutMs: 5000,
    firstTokenTimeoutMs: 120,
    onFallback: (from, to, reason) => fallbacks.push(`${from}>${to}:${reason}`),
  });
  const started = Date.now();
  const { result } = await run(translator);
  assert.deepEqual(result, { text: "Hello", model: "fallback-model" });
  assert.deepEqual(fallbacks, ["primary-model>fallback-model:timeout"]);
  assert.ok(Date.now() - started < 1500, "must not wait for the whole-request timeout");
});

test("translation: with no separate fallback, a stalled attempt gets exactly one retry on the same model", async () => {
  const mock = await startMockGemini({ "primary-model": { hangFirst: 1, pieces: ["Hello"] } });
  cleanup.push(() => mock.close());
  const fallbacks: string[] = [];
  const translator = new GeminiTranslator({
    apiKey: MOCK_GEMINI_KEY,
    baseUrl: mock.base,
    fallbackModel: "",
    thinkingLevel: "low",
    timeoutMs: 5000,
    firstTokenTimeoutMs: 120,
    onFallback: (from, to, reason) => fallbacks.push(`${from}>${to}:${reason}`),
  });
  assert.deepEqual((await run(translator)).result, { text: "Hello", model: "primary-model" });
  assert.deepEqual(fallbacks, ["primary-model>primary-model:timeout"]);
  assert.equal(mock.requests.length, 2);

  // A non-timeout failure is not retried on the same model.
  const failing = await startMockGemini({ "primary-model": { status: 503 } });
  cleanup.push(() => failing.close());
  const single = new GeminiTranslator({ apiKey: MOCK_GEMINI_KEY, baseUrl: failing.base, fallbackModel: "", thinkingLevel: "low", timeoutMs: 5000 });
  await assert.rejects(run(single), (e) => e instanceof ProviderError && e.code === "http_503");
  assert.equal(failing.requests.length, 1);
});

test("translation: after two consecutive failures the primary is skipped (circuit open) instead of retried every turn", async () => {
  const { mock, translator, fallbacks } = await gemini({ "primary-model": { status: 503 }, "fallback-model": { pieces: ["Hello"] } });
  for (let turn = 0; turn < 4; turn++) assert.equal((await run(translator)).result.model, "fallback-model");
  assert.deepEqual(
    mock.requests.map((r) => r.model),
    ["primary-model", "fallback-model", "primary-model", "fallback-model", "fallback-model", "fallback-model"],
  );
  assert.deepEqual(
    fallbacks.map((f) => f.split(":")[1]),
    ["http_503", "http_503", "circuit_open", "circuit_open"],
  );
});

test("end to end (mock servers): switching to the fallback model is announced once, not on every turn", async () => {
  const { client } = await realStack(
    { transcripts: ["bir", "ikki", "uch"] },
    { "gemini-3.5-flash-lite": { status: 503 }, "gemini-3.8-flash": { pieces: ["ok"] } },
  );
  await client.configure({ in: { enabled: false } });
  let sequence = 0;
  for (let turn = 1; turn <= 3; turn++) {
    client.send({ v: 1, type: "capture.start", direction: "out", generation: 1 });
    sequence = client.sendAudio("out", 1, speech(200), sequence);
    client.send({ v: 1, type: "turn.commit", direction: "out" });
    await client.waitFor((c) => c.messages.filter((m) => m.type === "metrics").length === turn, `metrics ${turn}`);
  }
  const notices = client.messages.filter((m) => m.type === "error" && m.code === "provider_unavailable");
  assert.equal(notices.length, 1);
  assert.match((notices[0] as { message: string }).message, /fallback model gemini-3\.8-flash/);
  assert.equal(client.messages.filter((m) => m.type === "translation.final").length, 3);
});

// ---------- Hedging and connection reuse (added after the first live benchmark) ----------

function hedged(base: string, fallbackModel: string, fallbacks: string[]) {
  return new GeminiTranslator({
    apiKey: MOCK_GEMINI_KEY,
    baseUrl: base,
    fallbackModel,
    thinkingLevel: "low",
    timeoutMs: 5000,
    hedgeAfterMs: 80,
    onFallback: (from, to, reason) => fallbacks.push(`${from}>${to}:${reason}`),
  });
}

test("translation: a slow first attempt is raced by a second request on the same model; the faster answer is used once", async () => {
  const mock = await startMockGemini({ "primary-model": { delayFirstMs: 600, pieces: ["the ", "answer"] }, "fallback-model": { pieces: ["never"] } });
  cleanup.push(() => mock.close());
  const fallbacks: string[] = [];
  const started = Date.now();
  const { deltas, result } = await run(hedged(mock.base, "fallback-model", fallbacks));
  assert.deepEqual(result, { text: "the answer", model: "primary-model" });
  assert.deepEqual(fallbacks, ["primary-model>primary-model:slow"]);
  assert.ok(Date.now() - started < 500, "did not wait for the slow attempt");
  await sleep(700);
  // Only the winner's text was delivered: nothing from the slow attempt, nothing twice, and no fallback model.
  assert.deepEqual(deltas, ["the ", "answer"]);
  assert.deepEqual(mock.requests.map((r) => r.model), ["primary-model", "primary-model"]);
});

test("translation: if the first attempt answers before the hedge does, the hedge is discarded", async () => {
  const mock = await startMockGemini({ "primary-model": { delayMs: 160, pieces: ["first"] } });
  cleanup.push(() => mock.close());
  const { deltas, result } = await run(hedged(mock.base, "", []));
  assert.deepEqual(result, { text: "first", model: "primary-model" });
  await sleep(400);
  assert.deepEqual(deltas, ["first"]);
});

test("translation: a hedged model that fails outright still falls through to the fallback model", async () => {
  const mock = await startMockGemini({ "primary-model": { delayMs: 150, status: 503 }, "fallback-model": { pieces: ["rescued"] } });
  cleanup.push(() => mock.close());
  const fallbacks: string[] = [];
  const { deltas, result } = await run(hedged(mock.base, "fallback-model", fallbacks));
  assert.deepEqual(result, { text: "rescued", model: "fallback-model" });
  assert.deepEqual(deltas, ["rescued"]);
  assert.deepEqual(fallbacks.map((f) => f.split(":")[1]), ["slow", "http_503"]);
});

test("translation: hedging works on a single model, and a fast answer never triggers a second request", async () => {
  const slow = await startMockGemini({ "primary-model": { hangFirst: 1, pieces: ["ok"] } });
  cleanup.push(() => slow.close());
  const fallbacks: string[] = [];
  assert.equal((await run(hedged(slow.base, "", fallbacks))).result.text, "ok");
  assert.deepEqual(fallbacks, ["primary-model>primary-model:slow"]);

  const fast = await startMockGemini({ "primary-model": { pieces: ["ok"] } });
  cleanup.push(() => fast.close());
  const translator = hedged(fast.base, "", []);
  for (let i = 0; i < 3; i++) await run(translator);
  await sleep(120);
  assert.equal(fast.requests.length, 3);
});

test("translation: requests reuse one warm connection; warm() opens it ahead of the first translation", async () => {
  const mock = await startMockGemini({ "primary-model": { pieces: ["ok"] } });
  cleanup.push(() => mock.close());
  const sockets = new Set<unknown>();
  mock.server.on("connection", (socket) => sockets.add(socket));
  const translator = hedged(mock.base, "", []);
  translator.warm("primary-model");
  translator.warm("primary-model"); // throttled: no second warm-up while the connection is fresh
  await sleep(50);
  assert.equal(mock.warmups, 1);
  for (let i = 0; i < 4; i++) {
    await run(translator);
    await sleep(30);
  }
  assert.equal(sockets.size, 1, "all requests should share the connection opened by warm()");
});


test("STT: a tap with no audio never reaches the provider, and a very short turn is padded instead of killing the session", async () => {
  const mock = await eleven({ transcripts: ["ha"] });
  const { stt, events } = sttAdapter(mock.base);
  await stt.open();
  // Push-to-talk tapped: nothing captured.
  stt.commit();
  await until(() => events.committed.length === 1, "local empty commit");
  assert.deepEqual(events.committed, [""]);
  assert.equal(mock.stt.chunks.length, 0);
  // 40 ms of speech: under the provider's 0.3 s minimum, which closes the session if sent as is.
  stt.sendAudio(speech(40));
  stt.commit();
  await until(() => events.committed.length === 2, "committed transcript");
  assert.deepEqual(mock.stt.chunks.map((c) => [c.bytes, c.commit]), [[10240, true]]);
  await sleep(50);
  assert.deepEqual(events.disconnects, []);
  // The session is still usable for the next turn.
  for (let i = 0; i < 20; i++) stt.sendAudio(speech(20));
  stt.commit();
  await until(() => events.committed.length === 3, "second transcript");
  assert.deepEqual(events.disconnects, []);
});
