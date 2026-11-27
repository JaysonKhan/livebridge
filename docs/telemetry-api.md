# Telemetry, feedback and bug-report API (v1)

The contract between the LiveBridge app (client) and the collector on the developer's site (server). The server side
lives in a different repository; this file is the single source of truth for both.

**Principles**

- **On by default, numbers only.** The app uploads the numbers-only records unless the user switches off "Share
  anonymous statistics". An explicit "off" is kept across updates. (Up to release 1.2.0 the default was off.) Feedback
  and bug reports are sent only when the user writes and submits them.
- **Numbers only.** Timings, counts, error codes, text lengths, ratings. Never transcript or translation text, never
  audio, never device names, never the gateway address or any key.
- **Pseudonymous.** A random `install_id` (UUID v4) generated the first time sharing is on — not derived from hardware,
  account or network. An e-mail address is sent only when it is in the feedback or bug-report form's e-mail field
  (typed by the user, or the signed-in account's address, which the user can remove).
- **The client is open source**, so the endpoints are public and unauthenticated: the server must treat every request
  as untrusted (validation, size limits, rate limits) and the published figures as approximate.
- Sessions against fake/mock providers are never uploaded.

Base URL (default, overridable in the app's settings by forks): `https://jaysonkhan.com/api/services/v1`

## `POST /api/services/v1/telemetry/`

Request: `Content-Type: application/json`, body ≤ 256 KB.

```json
{
  "app": "livebridge",
  "schema": 1,
  "install_id": "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11",
  "app_version": "1.0.0+1",
  "os_version": "macOS 26.6.2",
  "ui_language": "uz",
  "records": [
    {"type": "session_start", "t": "2026-11-25T09:13:10.120Z", "session": 4, "mode": "bidirectional", "myLang": "uz", "targetLang": "en", "outCommit": "manual"},
    {"type": "turn", "t": "2026-11-25T09:13:31.900Z", "session": 4, "direction": "out", "turnId": 1, "e2eMs": 1350, "sttCommitMs": 302, "translateFirstMs": 690, "translateTotalMs": 760, "ttsFirstAudioMs": 238, "ttsTotalMs": 900, "audioMs": 2480, "sourceChars": 36, "translationChars": 34, "model": "gemini-3.5-flash-lite"},
    {"type": "rating", "t": "2026-11-25T09:13:40.000Z", "session": 4, "direction": "out", "turnId": 1, "rating": "good"},
    {"type": "session_end", "t": "2026-11-25T09:16:23.000Z", "session": 4, "durationSec": 193, "turns": 7}
  ]
}
```

| Envelope field | Rule |
|---|---|
| `app` | required; `livebridge` (the only app today) |
| `schema` | required; `1` |
| `install_id` | required; UUID v4 |
| `app_version` | optional string ≤ 32 |
| `os_version` | optional string ≤ 64 |
| `ui_language` | optional; `uz`, `ru`, `tr`, `en` |
| `records` | required array, 1–500 items |

Every record has `type`, `t` (ISO-8601 UTC) and `session` (integer ≥ 0, the client's per-install session counter).
Unknown keys are ignored. Integers are milliseconds / counts and are clamped to 0…600 000.

| `type` | Extra fields |
|---|---|
| `session_start` | `mode` (`captions` \| `incoming` \| `bidirectional`), `myLang` and `targetLang` (the owner's and the remote participant's language: 2–3 lowercase letters, the codes of `packages/protocol/src/languages.ts`; `myLang` is optional and means `uz` when absent), `outCommit` (`manual` \| `vad` \| `turn_prediction`) |
| `turn` | `direction` (`out` \| `in`), `turnId` int; optional ints `e2eMs`, `sttCommitMs`, `translateFirstMs`, `translateTotalMs`, `ttsFirstAudioMs`, `ttsTotalMs`, `audioMs`, `sourceChars`, `translationChars`; optional `model` string ≤ 64 |
| `e2e` | `direction`, `turnId`, `e2eMs` — the end-to-end time of a turn whose `turn` record was written before it was known |
| `empty_turn` | `direction` |
| `error` | `code` (`[a-z0-9_]{1,48}`), optional `direction`, `fatal` bool |
| `reconnect` | — |
| `rating` | `direction`, `turnId`, `rating` (`good` \| `bad` \| `none`; the latest per turn wins) |
| `session_end` | `durationSec` int, `turns` int |

`e2eMs` = push-to-talk release → first audible translated sample (client clock). `direction: out` is the owner
speaking, `in` is the remote participant.

Responses

| Status | Body | Meaning |
|---|---|---|
| `202` | `{"accepted": 4, "ignored": 0}` | stored; `ignored` counts invalid or duplicate records |
| `400` | `{"error": "..."}` | envelope invalid (bad JSON, unknown app, bad install id, no records) |
| `413` | `{"error": "too_large"}` | body over the limit or more than 500 records |
| `429` | `{"error": "rate_limited"}` + `Retry-After` | too many requests |

The server de-duplicates on (`install_id`, `session`, `type`, `direction`, `turnId`, `t`), a missing `direction` or
`turnId` counting as empty / 0: the client resends a batch after a network failure, so a repeated record must not be
counted twice.

## `POST /api/services/v1/feedback/`

```json
{
  "app": "livebridge",
  "install_id": "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11",
  "app_version": "1.0.0+1",
  "ui_language": "uz",
  "message": "Tarjima tez, lekin qisqa so'zlarni noto'g'ri eshitadi.",
  "email": "optional@example.com",
  "rating": 4
}
```

| Field | Rule |
|---|---|
| `app` | required |
| `message` | required, 1–2000 characters |
| `install_id` | optional UUID v4 (sent only if statistics sharing is on) |
| `email` | optional, ≤ 254, only if the user typed it |
| `rating` | optional integer 1–5 |
| `app_version`, `ui_language` | optional |

Responses: `201 {"ok": true}`, `400 {"error": "..."}`, `429 {"error": "rate_limited"}`.

## Server obligations

- Do not store raw IP addresses with records or feedback. A salted hash that rotates daily may be used for rate
  limiting and for de-duplicating abuse. No cookies, no third-party trackers on the ingestion path.
- Rate limits (suggested): 60 telemetry requests per address per hour, 20 000 records per install per day, 5 feedback
  messages per address per hour.
- Public pages show **aggregates only**, and a breakdown (per language, per version, per model) only when at least
  5 installs contributed to it. Feedback text and per-install data are visible to the owner only.
- Raw records are kept for 180 days, aggregates may be kept longer.

## Client behaviour

- Preference `telemetryEnabled` (default `true`: absent means on; a saved `false` stays off). While on, the app has an
  `install_id` (created the first time); when switched off it stops uploading (the id is kept so re-enabling continues
  the same install; "Clear log" does not touch the server). Switching on in the app first shows what is sent;
  switching off needs no confirmation.
- Uploads happen after a session ends and at app start, from the local numbers-only log, in batches of at most 500
  records, resuming where the last successful upload stopped. A failed upload is retried the next time.
- Feedback is sent immediately on submit; failure is shown to the user and nothing is queued.
