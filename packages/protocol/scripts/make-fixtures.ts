// Regenerates packages/protocol/fixtures/frames.json — the byte-exact fixtures the TypeScript and Swift codecs both test against.
import { writeFileSync } from "node:fs";
import {
  encodeFrame,
  FRAME_HEADER_BYTES,
  type AudioFrame,
} from "../src/frame.ts";

const pcm = (samples: number[]) => {
  const b = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => b.writeInt16LE(s, i * 2));
  return b;
};

const valid: { name: string; frame: AudioFrame }[] = [
  {
    name: "capture_out_20ms_silence",
    frame: {
      kind: "capture",
      direction: "out",
      flags: 0,
      generation: 1,
      sequence: 0,
      timestampUs: 0n,
      turnId: 0,
      payload: Buffer.alloc(640),
    },
  },
  {
    name: "capture_in_samples",
    frame: {
      kind: "capture",
      direction: "in",
      flags: 0,
      generation: 7,
      sequence: 4_000_000_000,
      timestampUs: 0x0102030405060708n,
      turnId: 0,
      payload: pcm([0, 1, -1, 32767, -32768, 256]),
    },
  },
  {
    name: "synth_out_turn",
    frame: {
      kind: "synthesized",
      direction: "out",
      flags: 0,
      generation: 3,
      sequence: 12,
      timestampUs: 123_456_789n,
      turnId: 42,
      payload: pcm([100, -100, 200, -200]),
    },
  },
  {
    name: "synth_in_end_of_turn_empty",
    frame: {
      kind: "synthesized",
      direction: "in",
      flags: 1,
      generation: 0xffffffff,
      sequence: 0xffffffff,
      timestampUs: 0xffffffffffffffffn,
      turnId: 0xffffffff,
      payload: Buffer.alloc(0),
    },
  },
];

const base = encodeFrame(valid[2]!.frame);
const mutate = (fn: (b: Buffer) => Buffer | void) => {
  const b = Buffer.from(base);
  return fn(b) ?? b;
};
const invalid = [
  {
    name: "too_short",
    error: "too_short",
    hex: base.subarray(0, FRAME_HEADER_BYTES - 1).toString("hex"),
  },
  {
    name: "bad_version",
    error: "bad_version",
    hex: mutate((b) => void b.writeUInt8(2, 0)).toString("hex"),
  },
  {
    name: "bad_kind",
    error: "bad_kind",
    hex: mutate((b) => void b.writeUInt8(3, 1)).toString("hex"),
  },
  {
    name: "bad_direction",
    error: "bad_direction",
    hex: mutate((b) => void b.writeUInt8(2, 2)).toString("hex"),
  },
  {
    name: "bad_flags",
    error: "bad_flags",
    hex: mutate((b) => void b.writeUInt8(0x80, 3)).toString("hex"),
  },
  {
    name: "length_mismatch_truncated",
    error: "length_mismatch",
    hex: base.subarray(0, base.length - 2).toString("hex"),
  },
  {
    name: "length_mismatch_trailing",
    error: "length_mismatch",
    hex: Buffer.concat([base, Buffer.alloc(2)]).toString("hex"),
  },
  {
    name: "payload_too_large",
    error: "payload_too_large",
    hex: mutate((b) => void b.writeUInt32BE(192_002, 24)).toString("hex"),
  },
  {
    name: "odd_payload",
    error: "odd_payload",
    hex: mutate(
      (b) => (b.writeUInt32BE(7, 24), b.subarray(0, FRAME_HEADER_BYTES + 7)),
    ).toString("hex"),
  },
];

const out = {
  version: 1,
  valid: valid.map(({ name, frame }) => ({
    name,
    hex: encodeFrame(frame).toString("hex"),
    kind: frame.kind,
    direction: frame.direction,
    flags: frame.flags,
    generation: frame.generation,
    sequence: frame.sequence,
    timestampUs: frame.timestampUs.toString(),
    turnId: frame.turnId,
    payloadHex: Buffer.from(frame.payload).toString("hex"),
  })),
  invalid,
};
writeFileSync(
  new URL("../fixtures/frames.json", import.meta.url),
  JSON.stringify(out, null, 2) + "\n",
);
console.log(
  `wrote ${out.valid.length} valid + ${out.invalid.length} invalid frame fixtures`,
);
