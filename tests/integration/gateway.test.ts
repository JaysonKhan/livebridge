// Gateway behaviour over a real WebSocket with FAKE providers (placeholder text, test tones). No real API is called.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import WebSocket from "ws";
import {
  FLAG_END_OF_TURN,
  type ServerMessage,
} from "../../packages/protocol/src/index.ts";
import {
  ACCESS_TOKEN,
  issueSession,
  silence,
  sleep,
  speech,
  startGateway,
  TestClient,
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
