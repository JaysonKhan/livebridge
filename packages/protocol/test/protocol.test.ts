import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  decodeFrame,
  encodeFrame,
  FrameError,
  MAX_PAYLOAD_BYTES,
  parseClientMessage,
} from "../src/index.ts";

const fixtures = JSON.parse(
  readFileSync(new URL("../fixtures/frames.json", import.meta.url), "utf8"),
);

test("valid fixtures decode to the recorded fields and re-encode byte-exactly", () => {
  for (const f of fixtures.valid) {
    const bytes = Buffer.from(f.hex, "hex");
    const frame = decodeFrame(bytes);
    assert.equal(frame.kind, f.kind, f.name);
    assert.equal(frame.direction, f.direction, f.name);
    assert.equal(frame.flags, f.flags, f.name);
    assert.equal(frame.generation, f.generation, f.name);
    assert.equal(frame.sequence, f.sequence, f.name);
    assert.equal(frame.timestampUs.toString(), f.timestampUs, f.name);
    assert.equal(frame.turnId, f.turnId, f.name);
    assert.equal(
      Buffer.from(frame.payload).toString("hex"),
      f.payloadHex,
      f.name,
    );
    assert.equal(encodeFrame(frame).toString("hex"), f.hex, f.name);
  }
});

test("invalid fixtures are rejected with the recorded error code", () => {
  for (const f of fixtures.invalid) {
    assert.throws(
      () => decodeFrame(Buffer.from(f.hex, "hex")),
      (e) => e instanceof FrameError && e.code === f.error,
      f.name,
    );
  }
});

test("decode works on a view with a non-zero byte offset", () => {
  const bytes = Buffer.from(fixtures.valid[2].hex, "hex");
  const padded = Buffer.concat([Buffer.alloc(5), bytes]);
  assert.equal(decodeFrame(padded.subarray(5)).turnId, 42);
});

test("encode refuses oversized and odd payloads", () => {
  const frame = {
    kind: "capture",
    direction: "out",
    flags: 0,
    generation: 1,
    sequence: 1,
    timestampUs: 0n,
    turnId: 0,
  } as const;
  assert.throws(
    () =>
      encodeFrame({ ...frame, payload: new Uint8Array(MAX_PAYLOAD_BYTES + 2) }),
    FrameError,
  );
  assert.throws(
    () => encodeFrame({ ...frame, payload: new Uint8Array(3) }),
    FrameError,
  );
});

const configure = (out: object, inn: object) =>
  JSON.stringify({
    v: 1,
    type: "session.configure",
    capture_format: { encoding: "pcm_s16le", sample_rate: 16000, channels: 1 },
    directions: { out, in: inn },
  });
const outDir = {
  enabled: true,
  source_lang: "uz",
  target_lang: "en",
  speak: true,
  commit: "manual",
};
const inDir = {
  enabled: true,
  source_lang: "en",
  target_lang: "uz",
  speak: true,
  commit: "vad",
};

test("session.configure accepts UZ<->EN/RU and rejects other pairs", () => {
  assert.ok(!("error" in parseClientMessage(configure(outDir, inDir))));
  assert.ok(
    !(
      "error" in
      parseClientMessage(
        configure(
          { ...outDir, target_lang: "ru" },
          { ...inDir, source_lang: "ru" },
        ),
      )
    ),
  );
  assert.ok(
    "error" in
      parseClientMessage(configure({ ...outDir, target_lang: "uz" }, inDir)),
  );
  assert.ok(
    "error" in
      parseClientMessage(
        configure({ ...outDir, source_lang: "en", target_lang: "ru" }, inDir),
      ),
  );
  assert.ok(
    "error" in
      parseClientMessage(configure({ ...outDir, target_lang: "de" }, inDir)),
  );
  // A disabled direction is not checked for language sanity.
  assert.ok(
    !(
      "error" in
      parseClientMessage(
        configure(outDir, { ...inDir, enabled: false, source_lang: "uz" }),
      )
    ),
  );
});

test("malformed control messages are rejected, not thrown", () => {
  for (const raw of [
    "not json",
    "{}",
    '{"v":2,"type":"ping","t":1}',
    '{"v":1,"type":"nope"}',
    '{"v":1,"type":"capture.start","direction":"sideways","generation":1}',
    '{"v":1,"type":"capture.start","direction":"out","generation":-1}',
    '{"v":1,"type":"turn.cancel","direction":"out","generation":4294967296}',
    configure(outDir, inDir).replace("16000", "44100"),
  ]) {
    assert.ok("error" in parseClientMessage(raw), raw);
  }
  assert.deepEqual(parseClientMessage('{"v":1,"type":"ping","t":5}'), {
    v: 1,
    type: "ping",
    t: 5,
  });
});
