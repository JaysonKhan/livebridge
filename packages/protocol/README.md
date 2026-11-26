# LiveBridge realtime protocol v1

Source of truth: `src/frame.ts` and `src/messages.ts` (TypeScript, used by the gateway) and the Swift mirror in
`apps/desktop/native/LiveBridgeAudio/Sources/LiveBridgeAudioCore/FrameCodec.swift`. Both codecs are tested against
the same byte-exact fixtures in `fixtures/frames.json` (regenerate with `npm run fixtures`).

## Endpoints

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /healthz` | none | `{"ok":true}` |
| `POST /v1/sessions` | by mode, see [Starting a session](#starting-a-session) | → `201 {session_id, token, expires_in: 60, ws_path}`, plus `account` in account mode. |
| `GET /v1/voices` | one of three, see [Voices](#voices) | → `200 {voices: [{id, name, gender?, age?, accent?, language?, use_case?, description?, category?, preview_url?, previews?}]}`: the voices `session.configure` may name, cached for 10 minutes. `previews` maps a language code to a sample address. |
| `WSS /v1/realtime` | `Authorization: Bearer <session token>` | One socket per call, both directions multiplexed. The token is single-use and expires after 60 s. |

`POST /v1/sessions` and `GET /v1/voices` refuse with a JSON body `{"error": "<code>"}`.

### Starting a session

`POST /v1/sessions` takes an optional JSON body (at most 4 KB) whose `mode` says how the caller is authorized
(`sessionRequest` in `src/messages.ts`). No body at all is token mode, answered byte for byte as before.

| Mode | Request | Success | Failures |
|---|---|---|---|
| token | no body, or `{"mode":"token"}`; `Authorization: Bearer <GATEWAY_ACCESS_TOKEN>` | `201 {session_id, token, expires_in, ws_path}` | `401 unauthorized` (also when the gateway has no static token) |
| account | `{"mode":"account"}`; `Authorization: Bearer lba_…` (the access token from the owner's site) | the same `201` plus `"account": {"balance_units": N}` | `401 invalid_token` (refresh the token, retry once); `402 balance_empty`; `503 billing_unavailable` (the site is unreachable); `503 accounts_unavailable` (accounts are not configured) |
| keys | `{"mode":"keys","elevenlabs_api_key":"…","gemini_api_key":"…"}`, no `Authorization` | the same `201` as token | `400 bad_request` (a key is missing or malformed) |

All modes: `429 rate_limited` (20 requests a minute per caller, shared with `GET /v1/voices`) and
`429 session_limit` (a cap is full; a gateway with own keys switched off answers every keys request this way). A body
over 4 KB or that is not JSON → `400 bad_request`. When an account already has a live session, admitting a new one
closes the old one with the fatal error `session_replaced`.

### Voices

`GET /v1/voices` is authorized by one of:

- `Authorization: Bearer <GATEWAY_ACCESS_TOKEN>` — the gateway's own voice list.
- `Authorization: Bearer lba_…` — an account: only the voices an account session may choose (the approved list).
- `X-ElevenLabs-Api-Key: <key>` — own keys: that ElevenLabs account's voices, cached per key.

Errors: `401 unauthorized` (no or wrong static token, or a key sent to a gateway with own keys switched off),
`401 invalid_token` (the site refused the account token), `401 invalid_key` (the provider refused the key, or it is
malformed), `429 rate_limited`, `502 voices_unavailable` (the provider failed — for example a key without the voices
read permission — and nothing is cached; for an account also when the site cannot be reached).

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

Languages: `source_lang` / `target_lang` of a direction are codes from `src/languages.ts` — the 90 languages that
Eleven v4 can speak and realtime speech-to-text can recognise (`fixtures/languages.json` is the same table, shared
with the app's tests). A direction never translates a language into itself; no language is special.

Voices: `session.configure` may carry `voices: { out?, in? }` — the provider voice id each direction is spoken
with. An id must match `VOICE_ID_PATTERN` (`^[A-Za-z0-9]{10,40}$`), otherwise the message is refused as
`bad_message`. An omitted direction, or no `voices` at all, uses the voice the gateway is configured with.

Gateway → client: `session.ready`, `caption.partial`, `caption.final`, `translation.delta`, `translation.final`,
`turn.skipped`, `metrics`, `error`, `account.balance`, `pong`.

`account.balance` (`balance_units`) is sent in account mode only: right after the first `session.ready` and after
every usage report the site accepted. The units are the site's; a balance of 0 is followed by the fatal error
`balance_exhausted`.

`turn.skipped` (`direction`, `turn_id`, `generation`, `reason`) follows a `caption.final` that is neither translated
nor spoken: `same_language` when the speech was already in the target language (the other side of the call reaching
this direction's microphone), `echo` when the session's own synthesized speech came back. Nothing else is sent for
that turn.

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
`synthesis_congested`, `translation_failed`, `translation_rejected`, `tts_failed`, `voice_not_found`,
`provider_unavailable`, `balance_exhausted`, `billing_unavailable`, `idle_timeout`, `session_replaced`.
`fatal: true` means the gateway closes the socket after the message.

Always fatal:

- `balance_exhausted` — the account's balance reached 0 (account mode).
- `billing_unavailable` — three usage reports in a row failed, so the session cannot be billed (account mode).
- `idle_timeout` — no speech in either direction for the gateway's idle time (10 minutes by default).
- `session_replaced` — the same account started a newer session.

`voice_not_found` is a `tts_failed` with a known cause: the provider account has no usable voice with the id the
direction speaks with — unknown to the account, or switched off by its owner (the provider accepts the id when the
session opens and refuses it when a turn is spoken). The caption and the translation of the turn are still sent.
