// Binary audio frame v1. Header is network byte order (big-endian); payload is PCM signed 16-bit little-endian mono.
//
//  0      version (1)
//  1      kind: 1 capture (client -> gateway), 2 synthesized (gateway -> client)
//  2      direction: 0 out (owner -> remote), 1 in (remote -> owner)
//  3      flags: bit0 END_OF_TURN (last synthesized frame of a turn, payload may be empty); other bits must be 0
//  4-7    generation u32   (fences stale frames after cancel / reconnect)
//  8-11   sequence u32     (strictly increasing per kind+direction within a generation)
//  12-19  monotonic timestamp, microseconds u64 (sender's own clock; never compared across machines)
//  20-23  turn id u32      (0 for unsegmented capture)
//  24-27  payload size u32 (bytes; must equal the remaining length and be even)
//  28+    PCM payload

export const FRAME_VERSION = 1;
export const FRAME_HEADER_BYTES = 28;
/** 2 s of 48 kHz mono s16le. Anything larger is rejected. */
export const MAX_PAYLOAD_BYTES = 192_000;
export const FLAG_END_OF_TURN = 0x01;
const KNOWN_FLAGS = FLAG_END_OF_TURN;

export type Direction = "out" | "in";
export type FrameKind = "capture" | "synthesized";

export interface AudioFrame {
  kind: FrameKind;
  direction: Direction;
  flags: number;
  generation: number;
  sequence: number;
  timestampUs: bigint;
  turnId: number;
  payload: Uint8Array;
}

export type FrameErrorCode =
  | "too_short"
  | "bad_version"
  | "bad_kind"
  | "bad_direction"
  | "bad_flags"
  | "length_mismatch"
  | "payload_too_large"
  | "odd_payload";

export class FrameError extends Error {
  readonly code: FrameErrorCode;
  constructor(code: FrameErrorCode) {
    super(`invalid audio frame: ${code}`);
    this.code = code;
  }
}

export function encodeFrame(frame: AudioFrame): Buffer {
  const size = frame.payload.byteLength;
  if (size > MAX_PAYLOAD_BYTES) throw new FrameError("payload_too_large");
  if (size % 2 !== 0) throw new FrameError("odd_payload");
  if ((frame.flags & ~KNOWN_FLAGS) !== 0) throw new FrameError("bad_flags");
  const buf = Buffer.allocUnsafe(FRAME_HEADER_BYTES + size);
  buf.writeUInt8(FRAME_VERSION, 0);
  buf.writeUInt8(frame.kind === "capture" ? 1 : 2, 1);
  buf.writeUInt8(frame.direction === "out" ? 0 : 1, 2);
  buf.writeUInt8(frame.flags, 3);
  buf.writeUInt32BE(frame.generation >>> 0, 4);
  buf.writeUInt32BE(frame.sequence >>> 0, 8);
  buf.writeBigUInt64BE(frame.timestampUs, 12);
  buf.writeUInt32BE(frame.turnId >>> 0, 20);
  buf.writeUInt32BE(size, 24);
  buf.set(frame.payload, FRAME_HEADER_BYTES);
  return buf;
}

export function decodeFrame(data: Uint8Array): AudioFrame {
  if (data.byteLength < FRAME_HEADER_BYTES) throw new FrameError("too_short");
  const buf = Buffer.from(data.buffer, data.byteOffset, data.byteLength);
  if (buf.readUInt8(0) !== FRAME_VERSION) throw new FrameError("bad_version");
  const kind = buf.readUInt8(1);
  if (kind !== 1 && kind !== 2) throw new FrameError("bad_kind");
  const direction = buf.readUInt8(2);
  if (direction !== 0 && direction !== 1) throw new FrameError("bad_direction");
  const flags = buf.readUInt8(3);
  if ((flags & ~KNOWN_FLAGS) !== 0) throw new FrameError("bad_flags");
  const size = buf.readUInt32BE(24);
  if (size > MAX_PAYLOAD_BYTES) throw new FrameError("payload_too_large");
  if (size !== buf.byteLength - FRAME_HEADER_BYTES)
    throw new FrameError("length_mismatch");
  if (size % 2 !== 0) throw new FrameError("odd_payload");
  return {
    kind: kind === 1 ? "capture" : "synthesized",
    direction: direction === 0 ? "out" : "in",
    flags,
    generation: buf.readUInt32BE(4),
    sequence: buf.readUInt32BE(8),
    timestampUs: buf.readBigUInt64BE(12),
    turnId: buf.readUInt32BE(20),
    payload: buf.subarray(FRAME_HEADER_BYTES),
  };
}
