# LiveBridge realtime protocol v1

Source of truth: `src/frame.ts` and `src/messages.ts` (TypeScript, used by the gateway) and the Swift mirror in
`apps/desktop/native/LiveBridgeAudio/Sources/LiveBridgeAudioCore/FrameCodec.swift`. Both codecs are tested against
the same byte-exact fixtures in `fixtures/frames.json` (regenerate with `npm run fixtures`).

## Endpoints

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /healthz` | none | `{"ok":true}` |
| `POST /v1/sessions` | `Authorization: Bearer <GATEWAY_ACCESS_TOKEN>` | → `201 {session_id, token, expires_in: 60, ws_path}`. `401` bad token, `429` session limit or rate limit (20/min per address). |
| `WSS /v1/realtime` | `Authorization: Bearer <session token>` | One socket per call, both directions multiplexed. The token is single-use and expires after 60 s. |

## Binary audio frame

28-byte header in network byte order, then PCM signed 16-bit little-endian mono.

| Bytes | Field |
|---|---|
| 0 | version = 1 |
| 1 | kind: 1 capture (client → gateway), 2 synthesized (gateway → client) |
| 2 | direction: 0 `out` (owner → remote), 1 `in` (remote → owner) |
| 3 | flags: bit 0 END_OF_TURN (last synthesized frame of a turn; payload may be empty). Other bits must be 0. |
| 4–7 | generation u32 |
| 8–11 | sequence u32, strictly increasing per kind + direction within a generation |
| 12–19 | sender's monotonic timestamp, microseconds u64 (never compared across machines) |
| 20–23 | turn id u32 (0 for capture) |
| 24–27 | payload size u32 — must equal the remaining length, be even, and be ≤ 192 000 |
| 28… | PCM |

Capture is always 16 kHz mono, sent as 20 ms frames (640 bytes). The synthesized sample rate is announced per
direction in `session.ready`. A frame that fails validation is answered with an `error` (`bad_frame`); more than 50
invalid frames close the session.

## JSON control messages

Every message has `"v": 1` and `"type"`.

Client → gateway: `session.configure`, `capture.start`, `capture.pause`, `capture.stop`, `turn.commit`,
`turn.cancel`, `playback.start`, `playback.end`, `ping`.

Gateway → client: `session.ready`, `caption.partial`, `caption.final`, `translation.delta`, `translation.final`,
`metrics`, `error`, `pong`.

Exact fields: the zod schema `clientMessage` and the `ServerMessage` type in `src/messages.ts`.

## State and ordering rules

1. The first message must be `session.configure`. Audio or any other control before `session.ready` → `bad_state`.
   A session is configured once.
2. `session.ready` reports each direction as `ready` only when its provider sessions are really open, and is sent
   again whenever that changes (provider drop, reconnect). `providers.mock: true` means fake providers.
3. Capture frames are accepted only between `capture.start` and `capture.pause`/`stop`, only for the direction's
   current generation, and only with a higher sequence than the last accepted frame. Everything else is counted in
   `metrics.dropped_frames` and never reaches speech-to-text.
4. Push-to-talk: `capture.start` → frames → `turn.commit` → `capture.pause`. Sent on one socket, so the commit always
   follows the last frame.
5. **Generation fencing.** The client owns the generation. `turn.cancel` (or a `capture.start`) with a higher
   generation cancels everything in flight for that direction; the gateway then tags every later message and frame
   with the new generation, and the client drops anything carrying an older one. Generations never go backwards.
6. Turn ids are assigned by the gateway, one per committed transcript, monotonically per direction. A partial
   caption carries the id the next commit will get. An empty commit produces no turn.
7. Provider completion and playback completion are different facts: the END_OF_TURN frame means the gateway has
   sent all audio; `playback.start` / `playback.end` are the client's own observations of its output device.
8. After a reconnect nothing is replayed: the client moves both directions to a new generation, clears its queues
   and opens a fresh session.

## Backpressure

| Queue | Bound | On overflow |
|---|---|---|
| Client capture → network | 25 frames (500 ms) in flight | new frames dropped, `capture_backlog` warning |
| Gateway → speech-to-text while (re)connecting | 500 ms | oldest audio dropped, `capture_overflow` error |
| Gateway → client synthesized audio | > 2 s of audio buffered for > 1.5 s | turn aborted, `synthesis_congested` |
| Client playback queue | 30 s per direction | turn cancelled, `playback_overflow` |

## Error codes

`bad_message`, `bad_frame`, `bad_state`, `unauthorized`, `session_limit`, `session_expired`, `capture_overflow`,
`synthesis_congested`, `translation_failed`, `translation_rejected`, `tts_failed`,
`provider_unavailable`. `fatal: true` means the gateway closes the socket after the message.
