// Gateway behaviour over a real WebSocket with FAKE providers (placeholder text, test tones). No real API is called.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import WebSocket from "ws";
import {
  FLAG_END_OF_TURN,
  type ServerMessage,
} from "../../packages/protocol/src/index.ts";
import { SAME_LANGUAGE_MARK } from "../../services/gateway/src/prompt.ts";
import {
  createFakeProviders,
  FAKE_VOICES,
} from "../../services/gateway/src/providers/fake.ts";
import {
  ProviderError,
  type ProviderFactory,
} from "../../services/gateway/src/providers/types.ts";
import { createSiteClient } from "../../services/gateway/src/site.ts";
import {
  ACCESS_TOKEN,
  issueSession,
  listVoices,
  requestSession,
  silence,
  sleep,
  speech,
  startFakeSite,
  startGateway,
  TestClient,
  type FakeSiteReply,
} from "./helpers.ts";

type Started = Awaited<ReturnType<typeof startGateway>>;
let running: Started | undefined;
const start = async (options?: Parameters<typeof startGateway>[0]) =>
  (running = await startGateway(options));
afterEach(async () => {
  await running?.gateway.close();
  running = undefined;
});

const errors = (client: TestClient) =>
  client.messages.filter(
    (m): m is Extract<ServerMessage, { type: "error" }> => m.type === "error",
  );

/** One push-to-talk turn on the outgoing direction: hold, speak, release. */
async function pushToTalk(
  client: TestClient,
  generation: number,
  sequence = 0,
  ms = 600,
) {
  client.send({ v: 1, type: "capture.start", direction: "out", generation });
  const next = client.sendAudio("out", generation, speech(ms), sequence);
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  client.send({ v: 1, type: "capture.pause", direction: "out" });
  return next;
}

test("health needs no credentials; sessions need the access token", async () => {
  const { base } = await start();
  assert.deepEqual(await (await fetch(`${base}/healthz`)).json(), { ok: true });
  assert.equal((await issueSession(base, "wrong-token")).status, 401);
  assert.equal((await issueSession(base, "")).status, 401);
  const issued = await issueSession(base);
  assert.equal(issued.status, 201);
  assert.ok(issued.body.token && issued.body.session_id);
  assert.notEqual(issued.body.token, ACCESS_TOKEN);
});

test("GET /v1/voices needs the access token", async () => {
  const { base } = await start();
  assert.equal((await listVoices(base, "")).status, 401);
  assert.equal((await listVoices(base, "wrong-token")).status, 401);
  const listed = await listVoices(base);
  assert.equal(listed.status, 200);
  assert.deepEqual(listed.body, { voices: FAKE_VOICES });
  assert.equal(FAKE_VOICES.length, 4);
});

/** Fake providers whose voice list counts its calls and fails on demand. */
function countingVoices() {
  const state = { calls: 0, fail: false };
  const factory = {
    ...createFakeProviders({ delayMs: 2 }),
    voices: async () => {
      state.calls++;
      if (state.fail)
        throw new ProviderError("voices_unavailable", "fake refusal");
      return FAKE_VOICES;
    },
  };
  return { state, factory };
}

test("GET /v1/voices is cached", async () => {
  const { state, factory } = countingVoices();
  const { base } = await start({ factory });
  assert.equal((await listVoices(base)).status, 200);
  assert.deepEqual((await listVoices(base)).body, { voices: FAKE_VOICES });
  assert.equal(state.calls, 1);
});

test("GET /v1/voices serves the stale list when the provider fails, 502 when it never succeeded", async () => {
  const { state, factory } = countingVoices();
  const { base, logLines } = await start({ factory, voicesCacheMs: 0 });
  state.fail = true;
  const never = await listVoices(base);
  assert.equal(never.status, 502);
  assert.deepEqual(never.body, { error: "voices_unavailable" });
  state.fail = false;
  assert.equal((await listVoices(base)).status, 200);
  state.fail = true;
  const stale = await listVoices(base);
  assert.equal(stale.status, 200);
  assert.deepEqual(stale.body, { voices: FAKE_VOICES });
  // Every request reached the provider: nothing was served from a fresh cache.
  assert.equal(state.calls, 3);
  assert.equal(
    logLines.filter((l) => l.includes('"voices.failed"')).length,
    2,
  );
  assert.ok(logLines.some((l) => l.includes('"code":"voices_unavailable"')));
});

/** A voice-list request as the reverse proxy forwards it: from loopback, the caller's address in X-Forwarded-For. */
const viaProxy = (base: string, caller?: string) =>
  fetch(`${base}/v1/voices`, {
    headers: {
      authorization: `Bearer ${ACCESS_TOKEN}`,
      ...(caller ? { "x-forwarded-for": caller } : {}),
    },
  }).then((r) => r.status);

test("behind the reverse proxy the request limit is per caller, not one bucket for everyone", async () => {
  const { base } = await start();
  for (let i = 0; i < 20; i++) assert.equal(await viaProxy(base, "203.0.113.5"), 200);
  assert.equal(await viaProxy(base, "203.0.113.5"), 429);
  // Someone else behind the same proxy is not locked out by the first caller.
  assert.equal(await viaProxy(base, "203.0.113.9"), 200);
  // When a proxy appends instead of overwriting, the last entry is the one it added; the rest came from the client.
  assert.equal(await viaProxy(base, "203.0.113.5, 198.51.100.7"), 200);
});

test("without a forwarding proxy the request limit is per connecting address", async () => {
  const { base } = await start();
  for (let i = 0; i < 20; i++) assert.equal(await viaProxy(base), 200);
  assert.equal(await viaProxy(base), 429);
  // The limit covers session creation too: one budget per caller for both routes.
  assert.equal((await issueSession(base)).status, 429);
});

test("realtime socket rejects missing, unknown and reused session tokens", async () => {
  const { base } = await start({ env: { MAX_SESSIONS: "2" } });
  await assert.rejects(TestClient.open(base, ""), /401/);
  await assert.rejects(TestClient.open(base, "made-up-token"), /401/);
  // The long-lived access token is not a session token.
  await assert.rejects(TestClient.open(base, ACCESS_TOKEN), /401/);
  const { body } = await issueSession(base);
  const client = await TestClient.open(base, body.token!);
  await assert.rejects(TestClient.open(base, body.token!), /401/);
  await client.close();
});

test("session concurrency is bounded and the slot is released on disconnect", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  assert.equal((await issueSession(base)).status, 429);
  await client.close();
  await sleep(20);
  assert.equal((await issueSession(base)).status, 201);
});

test("session.ready reports mock providers and per-direction readiness", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  const ready = await client.configure();
  assert.equal(ready.providers.mock, true);
  assert.deepEqual(ready.directions.out, {
    enabled: true,
    ready: true,
    speak: true,
    synth_sample_rate: 24000,
  });
  assert.equal(ready.directions.in.ready, true);
});

test("push-to-talk turn: caption, translation, owner-voice audio on OUT only, then metrics", async () => {
  const { base } = await start({
    fake: { transcripts: ["Salom, ishlar qalay?"] },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);

  const metrics = await client.message("metrics");
  const final = await client.message("caption.final");
  assert.deepEqual(
    [final.direction, final.turn_id, final.text, final.lang],
    ["out", 1, "Salom, ishlar qalay?", "uz"],
  );
  const deltas = client.messages.filter((m) => m.type === "translation.delta");
  const translation = await client.message("translation.final");
  assert.equal(deltas.map((d) => d.text).join(""), translation.text);
  assert.equal(translation.text, "(uz→en) Salom, ishlar qalay?");
  assert.equal(translation.lang, "en");

  assert.ok(client.frames.length >= 2);
  for (const frame of client.frames) {
    assert.deepEqual(
      [frame.kind, frame.direction, frame.generation, frame.turnId],
      ["synthesized", "out", 1, 1],
    );
  }
  const sequences = client.frames.map((f) => f.sequence);
  assert.deepEqual(
    sequences,
    [...sequences].sort((a, b) => a - b),
  );
  const last = client.frames.at(-1)!;
  assert.equal(last.flags, FLAG_END_OF_TURN);
  assert.equal(
    client.frames.filter((f) => f.flags === FLAG_END_OF_TURN).length,
    1,
  );
  const audioMs =
    (client.frames.reduce((n, f) => n + f.payload.byteLength, 0) / 2 / 24000) *
    1000;
  assert.equal(metrics.audio_ms, Math.round(audioMs));
  assert.ok(
    metrics.stt_commit_ms !== undefined &&
      metrics.translate_total_ms !== undefined,
  );
  assert.ok(
    metrics.tts_first_audio_ms !== undefined &&
      metrics.tts_first_audio_ms <= metrics.tts_total_ms!,
  );
  // The answering translation model is reported per turn (for the local analytics log).
  assert.equal(metrics.model, "gemini-3.5-flash-lite");
  assert.deepEqual(errors(client), []);
});

test("very short turn and release with no speech: nothing is invented", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  await client.configure();
  // Released without speaking.
  client.send({ v: 1, type: "capture.start", direction: "out", generation: 1 });
  const next = client.sendAudio("out", 1, silence(400));
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.sync();
  await sleep(60);
  assert.equal(
    client.messages.filter((m) => m.type === "caption.final").length,
    0,
  );
  assert.equal(client.frames.length, 0);
  // A 60 ms blip is still one turn, exactly once.
  client.sendAudio("out", 1, speech(60), next);
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.message("metrics");
  assert.equal(
    client.messages.filter((m) => m.type === "caption.final").length,
    1,
  );
});

test("two releases produce two turns in order, never a duplicate", async () => {
  const { base } = await start({ fake: { transcripts: ["bir", "bir"] } });
  const client = await TestClient.connect(base);
  await client.configure();
  const next = await pushToTalk(client, 1);
  await pushToTalk(client, 1, next);
  await client.waitFor(
    (c) => c.messages.filter((m) => m.type === "metrics").length === 2,
    "two metrics",
  );
  const finals = client.messages.filter((m) => m.type === "caption.final");
  // The same sentence said twice is two turns with distinct ids.
  assert.deepEqual(
    finals.map((f) => [f.turn_id, f.text]),
    [
      [1, "bir"],
      [2, "bir"],
    ],
  );
  const turnOrder = client.frames.map((f) => f.turnId);
  assert.deepEqual(
    turnOrder,
    [...turnOrder].sort((a, b) => a - b),
  );
  // An extra commit with nothing pending adds nothing.
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.sync();
  await sleep(60);
  assert.equal(
    client.messages.filter((m) => m.type === "caption.final").length,
    2,
  );
});

test("incoming direction commits by silence and never produces OUT audio", async () => {
  const { base } = await start({ fake: { transcripts: ["How are you?"] } });
  const client = await TestClient.connect(base);
  await client.configure();
  client.send({ v: 1, type: "capture.start", direction: "in", generation: 1 });
  const next = client.sendAudio("in", 1, speech(700));
  // Speech arrives over time in reality; give the partial caption a moment before the pause that ends the turn.
  await sleep(30);
  client.sendAudio("in", 1, silence(400), next);
  const metrics = await client.message("metrics");
  assert.equal(metrics.direction, "in");
  const translation = await client.message("translation.final");
  assert.deepEqual(
    [translation.direction, translation.lang, translation.text],
    ["in", "uz", "(en→uz) How are you?"],
  );
  assert.ok(
    client.messages.some(
      (m) => m.type === "caption.partial" && m.direction === "in",
    ),
  );
  assert.ok(
    client.frames.length > 0 &&
      client.frames.every((f) => f.direction === "in"),
  );
  assert.ok(
    client.messages.every((m) => !("direction" in m) || m.direction === "in"),
  );
});

test("captions-only direction transcribes and translates but synthesizes nothing", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  const ready = await client.configure({
    out: { speak: false },
    in: { enabled: false },
  });
  assert.equal(ready.directions.out.speak, false);
  assert.equal(ready.directions.in.enabled, false);
  await pushToTalk(client, 1);
  const metrics = await client.message("metrics");
  await client.message("translation.final");
  assert.equal(metrics.audio_ms, undefined);
  assert.equal(client.frames.length, 0);
  // Audio for a direction that is off is refused, not silently processed.
  client.sendFrame({
    direction: "in",
    generation: 1,
    sequence: 0,
    payload: speech(20),
  });
  await client.waitFor(
    (c) => errors(c).some((e) => e.code === "bad_state"),
    "bad_state error",
  );
});

test("cancel fences the old generation: no further audio, no end-of-turn, no metrics", async () => {
  const { base } = await start({
    fake: {
      delayMs: 15,
      transcripts: ["a long sentence that takes a while to synthesize, really"],
    },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);
  await client.waitFor((c) => c.frames.length >= 2, "first synthesized frames");
  client.send({ v: 1, type: "turn.cancel", direction: "out", generation: 2 });
  await client.sync();
  const framesAtCancel = client.frames.length;
  await sleep(250);
  assert.equal(client.frames.length, framesAtCancel);
  assert.ok(client.frames.every((f) => f.flags === 0));
  assert.equal(client.messages.filter((m) => m.type === "metrics").length, 0);

  // The next turn runs normally in the new generation.
  await pushToTalk(client, 2);
  const metrics = await client.message("metrics");
  assert.equal(metrics.generation, 2);
  assert.ok(
    client.frames
      .slice(framesAtCancel)
      .every((f) => f.generation === 2 && f.turnId === metrics.turn_id),
  );
});

test("cancel before translation finishes drops the turn entirely", async () => {
  const { base } = await start({ fake: { delayMs: 40 } });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);
  await client.message("caption.final");
  client.send({ v: 1, type: "turn.cancel", direction: "out", generation: 2 });
  await client.sync();
  await sleep(300);
  assert.equal(
    client.messages.filter((m) => m.type === "translation.final").length,
    0,
  );
  assert.equal(client.frames.length, 0);
});

test("stale-generation, duplicate, reordered and out-of-window frames never reach speech-to-text", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  await client.configure();
  const chunk = speech(20);
  // Outside a capture window.
  client.sendFrame({
    direction: "out",
    generation: 1,
    sequence: 0,
    payload: chunk,
  });
  client.send({ v: 1, type: "capture.start", direction: "out", generation: 5 });
  // Old generation.
  for (let i = 0; i < 10; i++)
    client.sendFrame({
      direction: "out",
      generation: 4,
      sequence: i,
      payload: chunk,
    });
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.sync();
  await sleep(60);
  assert.equal(
    client.messages.filter((m) => m.type === "caption.final").length,
    0,
  );

  // 10 good frames, each sent twice, plus one that arrives out of order.
  for (let i = 0; i < 10; i++) {
    client.sendFrame({
      direction: "out",
      generation: 5,
      sequence: i,
      payload: chunk,
    });
    client.sendFrame({
      direction: "out",
      generation: 5,
      sequence: i,
      payload: chunk,
    });
  }
  client.sendFrame({
    direction: "out",
    generation: 5,
    sequence: 3,
    payload: chunk,
  });
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  const final = await client.message("caption.final");
  // The fake STT reports how much speech it actually received: 10 × 20 ms, not 21 × 20 ms.
  assert.match(final.text, /\(200 ms\)/);
  assert.equal(
    (await client.message("metrics")).dropped_frames,
    1 + 10 + 10 + 1,
  );
  // A generation cannot move backwards.
  client.send({ v: 1, type: "capture.start", direction: "out", generation: 4 });
  client.send({ v: 1, type: "turn.cancel", direction: "out", generation: 5 });
  await client.waitFor(
    (c) => errors(c).filter((e) => e.code === "bad_state").length === 2,
    "two bad_state errors",
  );
});

test("malformed input is rejected without killing the session; a flood of bad frames closes it", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  // Audio and controls before configuration.
  client.sendFrame({
    direction: "out",
    generation: 1,
    sequence: 0,
    payload: speech(20),
  });
  client.send({ v: 1, type: "turn.commit", direction: "out" });
  await client.waitFor(
    (c) => errors(c).filter((e) => e.code === "bad_state").length === 2,
    "bad_state before configure",
  );
  await client.configure();
  client.sendRaw('{"v":1,"type":"capture.start"}');
  client.sendRaw("not json at all");
  client.sendRaw(new Uint8Array([1, 2, 3]));
  client.sendRaw(Buffer.concat([Buffer.from([9]), Buffer.alloc(40)]));
  // A synthesized-kind frame is not something a client may send.
  client.sendFrame({
    kind: "synthesized",
    direction: "out",
    generation: 1,
    sequence: 0,
    payload: speech(20),
  });
  client.send({ v: 1, type: "session.configure" } as never);
  await client.waitFor(
    (c) => errors(c).filter((e) => e.code === "bad_frame").length === 3,
    "three bad_frame errors",
  );
  await client.waitFor(
    (c) => errors(c).filter((e) => e.code === "bad_message").length === 3,
    "three bad_message errors",
  );
  assert.ok(errors(client).every((e) => !e.fatal));
  // Still usable.
  await pushToTalk(client, 1);
  await client.message("metrics");

  for (let i = 0; i < 60; i++) client.sendRaw(new Uint8Array([0]));
  await client.waitFor((c) => c.closed, "socket closed after bad-frame flood");
  assert.ok(errors(client).some((e) => e.code === "bad_frame" && e.fatal));
});

test("oversized frames are refused at the socket", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  await client.configure();
  client.sendRaw(Buffer.alloc(400_000));
  await client.waitFor((c) => c.closed, "socket closed");
});

test("a translation model outside the allowed list is refused", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  client.send({
    v: 1,
    type: "session.configure",
    capture_format: { encoding: "pcm_s16le", sample_rate: 16000, channels: 1 },
    directions: {
      out: {
        enabled: true,
        source_lang: "uz",
        target_lang: "en",
        speak: true,
        commit: "manual",
      },
      in: {
        enabled: false,
        source_lang: "en",
        target_lang: "uz",
        speak: false,
        commit: "vad",
      },
    },
    translation_model: "some-other-model",
  });
  await client.waitFor(
    (c) => errors(c).some((e) => e.code === "bad_message"),
    "bad_message",
  );
  assert.equal(
    client.messages.filter((m) => m.type === "session.ready").length,
    0,
  );
  assert.equal(
    (await client.configure({ translation_model: "gemini-3.5-flash-lite" }))
      .directions.out.ready,
    true,
  );
});

test("a malformed voice id is refused as bad_message", async () => {
  const { base } = await start();
  const client = await TestClient.connect(base);
  client.send({
    v: 1,
    type: "session.configure",
    capture_format: { encoding: "pcm_s16le", sample_rate: 16000, channels: 1 },
    directions: {
      out: {
        enabled: true,
        source_lang: "uz",
        target_lang: "en",
        speak: true,
        commit: "manual",
      },
      in: {
        enabled: true,
        source_lang: "en",
        target_lang: "uz",
        speak: true,
        commit: "vad",
      },
    },
    voices: { out: "bad id" },
  });
  await client.waitFor(
    (c) => errors(c).some((e) => e.code === "bad_message"),
    "bad_message",
  );
  // No direction becomes ready: the message was refused whole, not configured without the voice.
  await sleep(50);
  await client.sync();
  assert.equal(
    client.messages.filter((m) => m.type === "session.ready").length,
    0,
  );
});

for (const [name, output, reason] of [
  ["empty", "   ", "empty"],
  ["runaway", "word ".repeat(200), "excessive"],
  ["structured", '{"answer": "4"}', "malformed"],
] as const) {
  test(`${name} translation output is rejected: original caption stays, nothing is spoken`, async () => {
    const { base } = await start({ fake: { translate: () => output } });
    const client = await TestClient.connect(base);
    await client.configure();
    await pushToTalk(client, 1);
    const error = await client.waitFor(
      (c) => errors(c).find((e) => e.code === "translation_rejected"),
      "translation_rejected",
    );
    assert.match(error.message, new RegExp(reason));
    assert.equal(error.turn_id, 1);
    await client.sync();
    assert.equal(
      client.messages.filter((m) => m.type === "caption.final").length,
      1,
    );
    assert.equal(
      client.messages.filter((m) => m.type === "translation.final").length,
      0,
    );
    assert.equal(client.frames.length, 0);
  });
}

test("translator failure: explicit error, caption kept, no audio, next turn still works", async () => {
  let calls = 0;
  const { base } = await start({
    fake: {
      translate: (req) => {
        if (++calls === 1) throw new Error("boom");
        return `ok ${req.text}`;
      },
    },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  const next = await pushToTalk(client, 1);
  await client.waitFor(
    (c) => errors(c).find((e) => e.code === "translation_failed"),
    "translation_failed",
  );
  assert.equal(client.frames.length, 0);
  await pushToTalk(client, 1, next);
  assert.equal((await client.message("metrics")).turn_id, 2);
});

test("speech already in the target language is captioned but neither translated nor spoken; the next turn works", async () => {
  // The other participant's English reached the owner's microphone: the model answers with the mark.
  const { base, logLines } = await start({
    fake: {
      transcripts: ["What about those projects?", "Narxi qancha?"],
      translate: (req) =>
        req.text === "Narxi qancha?" ? "How much is it?" : SAME_LANGUAGE_MARK,
    },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  const next = await pushToTalk(client, 1);
  const skipped = await client.message("turn.skipped");
  assert.deepEqual(
    [skipped.direction, skipped.turn_id, skipped.reason],
    ["out", 1, "same_language"],
  );
  assert.equal(
    (await client.message("caption.final")).text,
    "What about those projects?",
  );
  await client.sync();
  // The mark itself is never shown, and nothing was synthesized or measured for the turn.
  assert.ok(
    !client.messages.some((m) =>
      ["translation.delta", "translation.final", "metrics"].includes(m.type),
    ),
  );
  assert.equal(client.frames.length, 0);

  await pushToTalk(client, 1, next);
  assert.equal((await client.message("metrics")).turn_id, 2);
  assert.equal(
    (await client.message("translation.final")).text,
    "How much is it?",
  );
  assert.ok(client.frames.every((f) => f.turnId === 2));
  assert.deepEqual(errors(client), []);
  assert.ok(logLines.some((l) => l.includes('"turn.skipped"') && l.includes("same_language")));
});

test("our own translated speech coming back on the other direction is not translated again", async () => {
  const { base } = await start({
    fake: {
      transcripts: [
        "Narxi qancha?",
        // The far end plays our translation on loudspeakers and its microphone sends it back.
        "How much does it cost?",
        "It costs ten dollars.",
      ],
      translate: (req) =>
        req.source === "uz" ? "How much does it cost?" : `uz: ${req.text}`,
    },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);
  await client.message("metrics", (m) => m.direction === "out");
  const outFrames = client.frames.length;

  client.send({ v: 1, type: "capture.start", direction: "in", generation: 1 });
  let next = client.sendAudio("in", 1, speech(700));
  await sleep(30);
  next = client.sendAudio("in", 1, silence(400), next);
  const skipped = await client.message("turn.skipped");
  assert.deepEqual(
    [skipped.direction, skipped.turn_id, skipped.reason],
    ["in", 1, "echo"],
  );
  assert.equal(
    (await client.message("caption.final", (m) => m.direction === "in")).text,
    "How much does it cost?",
  );
  await client.sync();
  assert.equal(client.frames.length, outFrames);

  // A real reply right after it is interpreted as usual.
  next = client.sendAudio("in", 1, speech(700), next);
  await sleep(30);
  client.sendAudio("in", 1, silence(400), next);
  const translation = await client.message(
    "translation.final",
    (m) => m.direction === "in",
  );
  assert.deepEqual(
    [translation.turn_id, translation.text],
    [2, "uz: It costs ten dollars."],
  );
  assert.deepEqual(errors(client), []);
});

test("audio tags and stage directions in a translation are captioned but not sent to synthesis", async () => {
  const { base } = await start({
    fake: { translate: () => "Hello there. [laughs]" },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);
  const metrics = await client.message("metrics");
  assert.equal(
    (await client.message("translation.final")).text,
    "Hello there. [laughs]",
  );
  // The fake TTS speaks 40 ms per character: "Hello there." is 12 characters, the tag adds nothing.
  assert.equal(metrics.audio_ms, 500);
});

test("unavailable providers: direction is reported not ready, never as connected", async () => {
  const { base } = await start({ fake: { failOpen: { tts: true } } });
  const client = await TestClient.connect(base);
  const ready = await client.configure({ in: { enabled: false } });
  assert.equal(ready.directions.out.ready, false);
  assert.ok(
    errors(client).some(
      (e) => e.code === "provider_unavailable" && e.direction === "out",
    ),
  );
  // Captured audio has nowhere to go and is reported as dropped, not buffered forever.
  client.send({ v: 1, type: "capture.start", direction: "out", generation: 1 });
  client.sendAudio("out", 1, speech(100));
  await client.waitFor(
    (c) => errors(c).some((e) => e.code === "capture_overflow"),
    "capture_overflow",
  );
});

test("no transcript, translation or token ever appears in the logs", async () => {
  const secretSentence = "Maoshim oyiga uch ming dollar";
  const { base, logLines } = await start({
    fake: { transcripts: [secretSentence] },
  });
  const { body } = await issueSession(base);
  const client = await TestClient.open(base, body.token!);
  await client.configure();
  await pushToTalk(client, 1);
  await client.message("metrics");
  client.send({
    v: 1,
    type: "playback.end",
    direction: "out",
    turn_id: 1,
    generation: 1,
  });
  await client.close();
  await sleep(20);
  const log = logLines.join("\n");
  assert.ok(logLines.length >= 3);
  for (const forbidden of [
    secretSentence,
    "Maoshim",
    "(uz→en)",
    body.token!,
    ACCESS_TOKEN,
  ]) {
    assert.ok(!log.includes(forbidden), `log leaked: ${forbidden}`);
  }
});

test("closing the session stops all work: no frames after close, provider sessions released", async () => {
  const { base, gateway } = await start({
    fake: { delayMs: 15, transcripts: ["x".repeat(60)] },
  });
  const client = await TestClient.connect(base);
  await client.configure();
  await pushToTalk(client, 1);
  await client.waitFor((c) => c.frames.length >= 1, "first frame");
  await client.close();
  const frames = client.frames.length;
  await sleep(200);
  assert.equal(client.frames.length, frames);
  // The gateway shuts down promptly with nothing left open.
  await gateway.close();
  running = undefined;
  await assert.rejects(fetch(`${base}/healthz`));
});

test("a raw WebSocket without the upgrade path or token gets no session", async () => {
  const { port } = await start();
  const ws = new WebSocket(`ws://127.0.0.1:${port}/elsewhere`);
  const status = await new Promise((resolve) => {
    ws.once("unexpected-response", (_req, res) => resolve(res.statusCode));
    ws.once("error", () => resolve("error"));
  });
  assert.equal(status, 404);
});

// ---- session modes: static token, account (authorized by the owner's site), own provider keys ----

const SITE_SECRET = "site-secret-" + "Z9".repeat(20);
const ACCOUNT_TOKEN = "lba_account-token-Q7vX2mKp9sLw4RtY8nBc";
const OTHER_ACCOUNT_TOKEN = "lba_other-account-token-H3jD6fZq1uVe";
const REFUSED_TOKEN = "lba_refused-token-Pz5Nq8Wc3Jt6Xs1Gh";
const ELEVENLABS_KEY = "sk_el-own-key-Wq8Zr2Tn5Yp1Lm4Kx7Vb";
const GEMINI_KEY = "AIza-own-gemini-key-Fj3Hs9Dk2Ga6Pq0Rt";
const KEYS_REQUEST = {
  mode: "keys",
  elevenlabs_api_key: ELEVENLABS_KEY,
  gemini_api_key: GEMINI_KEY,
};
const TOKEN_REPLY_KEYS = ["session_id", "token", "expires_in", "ws_path"];

type Account = { account_id: string; balance_units: number; has_purchase: boolean };
const ACCOUNTS: Record<string, Account> = {
  [ACCOUNT_TOKEN]: { account_id: "acc-1", balance_units: 500, has_purchase: true },
  [OTHER_ACCOUNT_TOKEN]: { account_id: "acc-2", balance_units: 300, has_purchase: false },
};

/** A site that knows the given access tokens and refuses every other one, as the real one does. */
const authorizeFrom =
  (accounts: Record<string, Account>) =>
  (_path: string, body: any): FakeSiteReply => {
    const account = accounts[body?.access_token];
    return account
      ? { status: 200, body: account }
      : { status: 401, body: { error: "invalid_token" } };
  };

let runningSite: Awaited<ReturnType<typeof startFakeSite>> | undefined;
afterEach(async () => {
  await runningSite?.close();
  runningSite = undefined;
});

/** A gateway whose accounts are authorized by a fake site. */
async function startWithSite(
  handle: (path: string, body: any) => FakeSiteReply = authorizeFrom(ACCOUNTS),
  options: Parameters<typeof startGateway>[0] = {},
) {
  const site = (runningSite = await startFakeSite({ secret: SITE_SECRET, handle }));
  const client = createSiteClient({
    socketPath: site.socketPath,
    host: site.host,
    secret: SITE_SECRET,
  });
  return { site, ...(await start({ ...options, site: client })) };
}

/** Fake providers that count what each session builds from them. */
function countingFactory() {
  const built = { stt: 0, tts: 0, translator: 0 };
  const inner = createFakeProviders({ delayMs: 2 });
  const factory: ProviderFactory = {
    ...inner,
    stt: (options) => (built.stt++, inner.stt(options)),
    tts: (options) => (built.tts++, inner.tts(options)),
    translator: () => (built.translator++, inner.translator()),
  };
  return { built, factory };
}

test("token mode: no body or {mode:token} with the static token is today's reply, byte for byte", async () => {
  const { base } = await start({ env: { MAX_SESSIONS: "3" } });
  for (const body of [undefined, "", { mode: "token" }]) {
    const issued = await requestSession(base, body, ACCESS_TOKEN);
    assert.equal(issued.status, 201);
    assert.match(
      issued.text,
      /^\{"session_id":"[0-9a-f-]{36}","token":"[A-Za-z0-9_-]{43}","expires_in":60,"ws_path":"\/v1\/realtime"\}$/,
    );
  }
  const wrong = await requestSession(base, { mode: "token" }, "wrong-token");
  assert.equal(wrong.status, 401);
  assert.deepEqual(wrong.body, { error: "unauthorized" });
});

test("token mode: with no static token configured, sessions and the voice list are refused", async () => {
  const { base } = await start({ env: { GATEWAY_ACCESS_TOKEN: "" } });
  for (const token of [undefined, "", "anything"]) {
    const refused = await requestSession(base, undefined, token);
    assert.equal(refused.status, 401);
    assert.deepEqual(refused.body, { error: "unauthorized" });
  }
  assert.equal((await listVoices(base, "")).status, 401);
  assert.equal((await listVoices(base, "anything")).status, 401);
});

test("account mode: the site authorizes it; the reply and the socket carry the balance", async () => {
  const { base, site } = await startWithSite();
  const issued = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  assert.equal(issued.status, 201);
  assert.deepEqual(Object.keys(issued.body), [...TOKEN_REPLY_KEYS, "account"]);
  assert.deepEqual(issued.body.account, { balance_units: 500 });
  assert.deepEqual(site.failures, []);
  assert.deepEqual(
    site.requests.map((r) => [r.path, r.body]),
    [["/internal/livebridge/v1/authorize/", { access_token: ACCOUNT_TOKEN }]],
  );

  const client = await TestClient.open(base, issued.body.token!);
  await client.configure();
  const balance = await client.message("account.balance");
  assert.equal(balance.balance_units, 500);
  await client.sync();
  const types = client.messages.map((m) => m.type);
  // Right after the first session.ready, and only once.
  assert.equal(types.indexOf("account.balance"), types.indexOf("session.ready") + 1);
  assert.equal(types.filter((t) => t === "account.balance").length, 1);
});

test("account mode: a token the site refuses is 401 invalid_token; no token at all never reaches the site", async () => {
  const { base, site } = await startWithSite();
  const refused = await requestSession(base, { mode: "account" }, REFUSED_TOKEN);
  assert.equal(refused.status, 401);
  assert.deepEqual(refused.body, { error: "invalid_token" });
  assert.equal(site.requests.length, 1);
  for (const token of [undefined, ""]) {
    const missing = await requestSession(base, { mode: "account" }, token);
    assert.equal(missing.status, 401);
    assert.deepEqual(missing.body, { error: "invalid_token" });
  }
  assert.equal(site.requests.length, 1);
  assert.deepEqual(site.failures, []);
});

test("account mode: an empty balance is 402 balance_empty and holds no slot", async () => {
  const { base } = await startWithSite(
    authorizeFrom({
      [ACCOUNT_TOKEN]: { account_id: "acc-1", balance_units: 0, has_purchase: true },
      [OTHER_ACCOUNT_TOKEN]: { account_id: "acc-2", balance_units: -5, has_purchase: true },
    }),
  );
  for (const token of [ACCOUNT_TOKEN, OTHER_ACCOUNT_TOKEN]) {
    const empty = await requestSession(base, { mode: "account" }, token);
    assert.equal(empty.status, 402);
    assert.deepEqual(empty.body, { error: "balance_empty" });
  }
  // MAX_SESSIONS=1 and the refusals took nothing.
  assert.equal((await issueSession(base)).status, 201);
});

test("account mode: a missing site socket is 503 billing_unavailable, well within the site timeout", async () => {
  const site = createSiteClient({
    socketPath: join(tmpdir(), `lbs-none-${randomBytes(4).toString("hex")}`, "s"),
    host: "site.test",
    secret: SITE_SECRET,
  });
  const { base } = await start({ site });
  const began = performance.now();
  const unreachable = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  const elapsed = performance.now() - began;
  assert.equal(unreachable.status, 503);
  assert.deepEqual(unreachable.body, { error: "billing_unavailable" });
  assert.ok(elapsed < 3500, `took ${Math.round(elapsed)} ms`);
  // MAX_SESSIONS=1 and the failure took nothing.
  assert.equal((await issueSession(base)).status, 201);
});

test("account mode: any other site failure is 503 billing_unavailable", async () => {
  const { base, site } = await startWithSite(() => ({ status: 500, body: "<html>oops</html>" }));
  const failed = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  assert.equal(failed.status, 503);
  assert.deepEqual(failed.body, { error: "billing_unavailable" });
  assert.deepEqual(site.failures, []);
});

test("account mode: without a site the gateway answers 503 accounts_unavailable", async () => {
  const { base } = await start();
  const off = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  assert.equal(off.status, 503);
  assert.deepEqual(off.body, { error: "accounts_unavailable" });
});

test("keys mode: the session's providers are built by providersFor from exactly those keys", async () => {
  const own = countingFactory();
  const gatewayOwn = countingFactory();
  const asked: { elevenlabs: string; gemini: string }[] = [];
  const { base } = await start({
    env: { MAX_SESSIONS: "2" },
    factory: gatewayOwn.factory,
    providersFor: (keys) => {
      asked.push({ ...keys });
      return own.factory;
    },
  });
  const issued = await requestSession(base, KEYS_REQUEST);
  assert.equal(issued.status, 201);
  assert.deepEqual(Object.keys(issued.body), TOKEN_REPLY_KEYS);
  assert.deepEqual(asked, [{ elevenlabs: ELEVENLABS_KEY, gemini: GEMINI_KEY }]);
  // Any Authorization header is ignored in keys mode.
  assert.equal((await requestSession(base, KEYS_REQUEST, "not-a-token")).status, 201);

  const client = await TestClient.open(base, issued.body.token!);
  await client.configure();
  await pushToTalk(client, 1);
  await client.message("metrics");
  assert.equal(own.built.stt, 2);
  assert.ok(own.built.tts >= 1 && own.built.translator >= 1);
  assert.deepEqual(gatewayOwn.built, { stt: 0, tts: 0, translator: 0 });
  assert.ok(!client.messages.some((m) => m.type === "account.balance"));
});

test("keys mode: a missing or malformed key is 400 bad_request", async () => {
  const asked: unknown[] = [];
  const { base } = await start({
    providersFor: (keys) => (asked.push(keys), createFakeProviders()),
  });
  for (const body of [
    { mode: "keys" },
    { mode: "keys", elevenlabs_api_key: ELEVENLABS_KEY },
    { mode: "keys", gemini_api_key: GEMINI_KEY },
    { mode: "keys", elevenlabs_api_key: "short", gemini_api_key: GEMINI_KEY },
    { mode: "keys", elevenlabs_api_key: `${ELEVENLABS_KEY} x`, gemini_api_key: GEMINI_KEY },
  ]) {
    const bad = await requestSession(base, body);
    assert.equal(bad.status, 400);
    assert.deepEqual(bad.body, { error: "bad_request" });
  }
  assert.deepEqual(asked, []);
});

test("a body over 4 KB or that is not a session request is 400 bad_request", async () => {
  const { base } = await start();
  const oversized = await requestSession(
    base,
    JSON.stringify({ mode: "token", pad: "x".repeat(5 * 1024) }),
    ACCESS_TOKEN,
  );
  assert.equal(oversized.status, 400);
  assert.deepEqual(oversized.body, { error: "bad_request" });
  assert.equal(
    (await requestSession(base, '{"mode":"token"}'.padEnd(4097), ACCESS_TOKEN)).status,
    400,
  );
  for (const body of ["not json", "[]", '{"mode":"nope"}']) {
    const bad = await requestSession(base, body, ACCESS_TOKEN);
    assert.equal(bad.status, 400);
    assert.deepEqual(bad.body, { error: "bad_request" });
  }
  // Exactly 4 KB is accepted.
  assert.equal(
    (await requestSession(base, '{"mode":"token"}'.padEnd(4096), ACCESS_TOKEN)).status,
    201,
  );
});

test("the same account twice: the first socket gets session_replaced and closes, the second runs, no slot leaks", async () => {
  const { base } = await startWithSite();
  const first = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  const one = await TestClient.open(base, first.body.token!);
  await one.configure();

  // MAX_SESSIONS=1 is full, yet the account's new session takes over its old slot.
  const second = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  assert.equal(second.status, 201);
  const replaced = await one.waitFor(
    (c) => errors(c).find((e) => e.code === "session_replaced"),
    "session_replaced",
  );
  assert.equal(replaced.fatal, true);
  await one.waitFor((c) => c.closed, "first socket closed");

  const two = await TestClient.open(base, second.body.token!);
  await two.configure();
  await two.message("account.balance");
  assert.ok(!two.closed);
  await two.close();
  await sleep(20);

  // Both are gone and the only slot is free again: another account gets it, and then it is full.
  assert.equal(
    (await requestSession(base, { mode: "account" }, OTHER_ACCOUNT_TOKEN)).status,
    201,
  );
  assert.equal((await issueSession(base)).status, 429);
});

test("replacing an account session that has not connected yet voids its token", async () => {
  const { base } = await startWithSite();
  const first = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  const second = await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN);
  assert.equal(second.status, 201);
  await assert.rejects(TestClient.open(base, first.body.token!), /401/);
  const client = await TestClient.open(base, second.body.token!);
  await client.configure();
});

test("a full cap is 429 session_limit: per mode and in total", async () => {
  const { base } = await startWithSite(undefined, {
    env: { MAX_SESSIONS: "2", MAX_KEYS_SESSIONS: "1", MAX_ACCOUNT_SESSIONS: "1" },
  });
  assert.equal((await requestSession(base, KEYS_REQUEST)).status, 201);
  const keysFull = await requestSession(base, KEYS_REQUEST);
  assert.equal(keysFull.status, 429);
  assert.deepEqual(keysFull.body, { error: "session_limit" });
  assert.equal((await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN)).status, 201);
  const accountsFull = await requestSession(base, { mode: "account" }, OTHER_ACCOUNT_TOKEN);
  assert.equal(accountsFull.status, 429);
  assert.deepEqual(accountsFull.body, { error: "session_limit" });
  const totalFull = await issueSession(base);
  assert.equal(totalFull.status, 429);
  assert.deepEqual(totalFull.body, { error: "session_limit" });
});

test("a WebSocket handshake that fails after taking the session token gives the slot back", async () => {
  const { base, port } = await start();
  const { body } = await issueSession(base);
  // A valid session token on an upgrade the socket server cannot accept (no Sec-WebSocket-Key).
  const status = await new Promise((resolve, reject) => {
    const req = request({
      port,
      path: "/v1/realtime",
      headers: {
        connection: "Upgrade",
        upgrade: "websocket",
        authorization: `Bearer ${body.token}`,
      },
    });
    req.on("response", (res) => (res.resume(), resolve(res.statusCode)));
    req.on("error", reject);
    req.end();
  });
  assert.equal(status, 400);
  await sleep(20);
  // MAX_SESSIONS=1: the slot came back.
  assert.equal((await issueSession(base)).status, 201);
});

test("no access token, provider key, static token or site secret reaches the log in any mode", async () => {
  const { base, logLines, site } = await startWithSite(undefined, {
    env: { MAX_SESSIONS: "3" },
    fake: { transcripts: ["bir", "ikki", "uch"] },
  });
  const issued = [
    await requestSession(base, undefined, ACCESS_TOKEN),
    await requestSession(base, { mode: "account" }, ACCOUNT_TOKEN),
    await requestSession(base, KEYS_REQUEST),
  ];
  assert.equal((await requestSession(base, { mode: "account" }, REFUSED_TOKEN)).status, 401);
  for (const { status, body } of issued) {
    assert.equal(status, 201);
    const client = await TestClient.open(base, body.token!);
    await client.configure();
    await pushToTalk(client, 1);
    await client.message("metrics");
    await client.close();
  }
  await sleep(20);
  assert.deepEqual(site.failures, []);
  const log = logLines.join("\n");
  for (const mode of ["token", "account", "keys"])
    assert.ok(log.includes(`"mode":"${mode}"`), `no ${mode} session in the log`);
  for (const forbidden of [
    ACCESS_TOKEN,
    ACCOUNT_TOKEN,
    REFUSED_TOKEN,
    ELEVENLABS_KEY,
    GEMINI_KEY,
    SITE_SECRET,
    ...issued.map((i) => i.body.token!),
  ]) {
    assert.ok(!log.includes(forbidden), `log leaked: ${forbidden}`);
  }
});
