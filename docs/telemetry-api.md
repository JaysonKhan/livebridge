# Telemetry, feedback and bug-report API (v1)

The contract between the LiveBridge app (client) and the collector on the developer's site (server). The server side
lives in a different repository; this file is the single source of truth for both.

**Principles**

- **On by default, numbers only.** The app uploads the numbers-only records unless the user switches off "Share
  anonymous statistics". An explicit "off" is kept across updates. (Up to release 1.2.0 the default was off.) Feedback
  and bug reports are sent only when the user writes and submits them.
- **Numbers only (statistics).** Timings, counts, error codes, text lengths, ratings. Never transcript or translation
  text, never audio, never device names, never the gateway address or any key. A bug report is the one place that
  carries more — device names, the gateway's host and the diagnostic log — and only after the user has seen it; it
  never carries speech, translations, keys or tokens either.
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

## `POST /api/services/v1/bug-reports/`

Sent only when the user presses **Send** in **Report a problem** (the bug icon in the window header). The user sees
the description, the e-mail and — behind "Show what will be sent" — exactly the device object and the log before
sending; "Include the diagnostic log" (on by default) leaves out both when unticked.

```json
{
  "app": "livebridge",
  "install_id": "3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11",
  "message": "AirPods'da tarjima eshitilmayapti, noutbuk karnayidan chiqyapti.",
  "email": "optional@example.com",
  "app_version": "1.2.1+4",
  "os_version": "Windows 11 (build 26100)",
  "platform": "windows_x64",
  "ui_language": "uz",
  "connection_mode": "account",
  "devices": {
    "mic": {"name": "Headset (AirPods Hands-Free)", "transport": "bluetooth", "sampleRate": 16000,
            "inputChannels": 1, "outputChannels": 0, "isDefaultInput": true, "isDefaultOutput": false},
    "headphones": {"name": "Speakers (Realtek(R) Audio)", "transport": "other", "sampleRate": 48000,
                   "inputChannels": 0, "outputChannels": 2, "isDefaultInput": false, "isDefaultOutput": true},
    "virtualMic": null,
    "sources": ["Zoom.exe"],
    "mode": "incoming", "myLang": "uz", "targetLang": "en", "outCommit": "manual",
    "devices": [{"name": "…", "transport": "…", "sampleRate": 48000, "inputChannels": 0, "outputChannels": 2,
                 "isDefaultInput": false, "isDefaultOutput": true}]
  },
  "log": "=== LiveBridge run started 2026-11-27T10:00:00.000+05:00\n10:00:01.120 state     connecting\n…"
}
```

| Field | Rule |
|---|---|
| `app` | required |
| `message` | required, 1–2000 characters |
| `install_id` | optional UUID v4 (sent only while statistics sharing is on) |
| `email` | optional, ≤ 254; in account mode the form starts with the account's address, which the user may change or remove |
| `app_version` ≤ 32, `os_version` ≤ 64, `platform` ≤ 32 (`macos_arm64`, `windows_x64`, …), `ui_language` | optional; a value that breaks the rule is stored empty |
| `connection_mode` | optional: `account`, `keys` (own provider keys), `gateway` (own gateway) or `none`; anything else is stored empty |
| `devices` | optional JSON object, ≤ 16 KB encoded (as Python's `json.dumps` writes it: ASCII escapes, so a non-ASCII letter counts six bytes): the chosen microphone, headphones and virtual microphone (name, transport, sample rate, channels, default flags), the chosen meeting-app process names, mode, languages, turn mode, and the device list. A list that would not fit keeps its first entries and `devicesOmitted` gives the number left out. No device ids |
| `log` | optional string, ≤ 256 KB (UTF-8); the client sends at most 200 KB: the end of earlier runs, then this run |

The **diagnostic log** holds, one line per event: the app and OS version, platform and system language; the
connection mode, the account's e-mail (account mode only) and the gateway's host (never a path, query or token); the
device list and the chosen devices; settings (interface language, statistics on/off, microphone permission); every
Start (mode, languages, devices, meeting apps, whether voices were chosen); engine state changes and their status
messages (reconnect attempts show here); error events with their codes; failed requests to the site and the gateway
(path, HTTP status and error code only); per-turn timings; and Flutter and platform exceptions (the first line and a
few stack frames). It never holds what was said (captions are not recorded at all), translations, audio levels,
the balance, API keys, tokens or the refresh token: every line passes a redaction step that replaces the own
gateway's token and anything shaped like a key or token with `[secret]` (tested). The log lives in memory and in
`diagnostics.log` (+ one previous file, together at most ~512 KB) next to the analytics log; it is sent only with a
report.

Responses: `201 {"ok": true}`, `400 {"error": "..."}` (`bad_json`, `unknown_app`, `bad_message`, `bad_install_id`,
`bad_email`, `bad_devices`, `bad_log`), `413 {"error": "too_large"}` (body over 320 KB), `429 {"error":
"rate_limited"}` + `Retry-After`. The client shows the failure and queues nothing.

## Server obligations

- Do not store raw IP addresses with records or feedback. A salted hash that rotates daily may be used for rate
  limiting and for de-duplicating abuse. No cookies, no third-party trackers on the ingestion path.
- Rate limits (suggested): 60 telemetry requests per address per hour, 20 000 records per install per day, 5 feedback
  messages per address per hour, 5 bug reports per address per hour.
- Public pages show **aggregates only**, and a breakdown (per language, per version, per model) only when at least
  5 installs contributed to it. Feedback text, bug reports (with their logs and device lists) and per-install data
  are visible to the owner only. The owner's notification of a new report (a private Telegram group: summary + the log
  as a file) carries no e-mail address: the report's own is left out and any in the text or the log is hidden.
- Raw records are kept for 180 days, aggregates may be kept longer.

## Client behaviour

- Preference `telemetryEnabled` (default `true`: absent means on — unless `analyticsEnabled` is `false`, then off; a
  saved `false` stays off). While on, the app has an `install_id` (created the first time); when switched off it stops
  uploading (the id is kept so re-enabling continues the same install; "Clear log" does not touch the server).
  Switching on in the app first shows what is sent; switching off needs no confirmation. When sharing starts **by
  default** on an install that never shared, uploading begins at the current end of the local log: records written
  before that moment are never sent.
- Uploads happen after a session ends and at app start, from the local numbers-only log, in batches of at most 500
  records, resuming where the last successful upload stopped. A failed upload is retried the next time.
- Feedback and bug reports are sent immediately on submit; failure is shown to the user and nothing is queued.
