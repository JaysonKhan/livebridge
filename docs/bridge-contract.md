# Flutter ↔ Swift bridge contract

The Swift audio engine owns devices, audio buffers, playback and the gateway WebSocket. Flutter only sends low-rate
commands and receives captions, state and throttled meters. No PCM ever crosses this bridge.

## MethodChannel `livebridge/control`

All arguments and results are standard-codec maps/lists. A failed call throws `PlatformException(code, message)`.

| Method | Arguments | Result |
|---|---|---|
| `listDevices` | — | `List<Map>`: `uid` String, `name` String, `inputChannels` int, `outputChannels` int, `sampleRate` double, `transport` String (`builtin`, `usb`, `bluetooth`, `virtual`, `aggregate`, `other`; Windows reports `virtual` (by name), `bluetooth` or `usb` (from the driver the endpoint's topology connector leads to), else `other`), `isDefaultInput` bool, `isDefaultOutput` bool |
| `listAudioProcesses` | — | `List<Map>`: `pid` int, `bundleId` String, `name` String, `isPlaying` bool — processes that currently own an audio object |
| `loadSettings` | — | `Map` of everything saved so far (missing keys absent): the `start` config keys plus the preference keys below. The secret items (see "Secret items") come from the Keychain / Credential Manager under the keys `accessToken`, `accountRefreshToken`, `elevenlabsApiKey` and `geminiApiKey` — each only when present — the rest from UserDefaults / the settings file |
| `saveSettings` | any subset of the `start` config keys and preference keys | — (the given keys are **merged** into what is stored; a `null` value removes a key — for a secret item this deletes it, an absent key leaves it untouched; if a secret cannot be written the call fails with `settings_failed`) |
| `languageNames` | `codes` [String], `locale` String | Map code → name of each language in the interface language `locale`, from the system's locale data (first letter capitalised); a code the system has no name for is left out |
| `saveTextFile` | `suggestedName` String, `content` String | String? — shows the system Save dialog and writes UTF-8 text; returns the saved path, or `null` if the user cancelled |
| `rateTurn` | `direction` String, `turnId` int, `rating` String (`good`, `bad`, `none`) | — (records the owner's judgement of a translation in the analytics log; no text is stored) |
| `analyticsSummary` | — | `Map`, see "Analytics" below |
| `analyticsExport` | — | String? — Save dialog for the raw analytics file (JSON Lines); saved path or `null` |
| `analyticsClear` | — | — (deletes the analytics file) |
| `telemetryStatus` | — | `Map`: `enabled` bool, `installId` String? (present once sharing was ever on), `endpoint` String, `pendingRecords` int (local records not uploaded yet), `lastUploadAt` String? (ISO-8601), `lastError` String?, `appVersion` String (`1.2.0+3`), `osVersion` String (`macOS 26.6.2`, `Windows 11 (build 26100)`) |
| `sendFeedback` | `message` String (1–2000 chars), `email` String?, `rating` int? (1–5) | — ; throws `PlatformException` with code `rate_limited`, `feedback_rejected` or `feedback_failed` |
| `microphonePermission` | — | String: `granted`, `denied`, `undetermined` |
| `requestMicrophonePermission` | — | bool |
| `startMeters` | `micUid` String?, `sourcePids` List<int> | — (setup-screen level meters; no network) |
| `stopMeters` | — | — |
| `testTone` | `uid` String | — (plays a quiet 1 s 440 Hz tone on that output device) |
| `start` | config map (below) | — (returns when the engine has begun connecting; progress arrives as `state` events) |
| `stop` | — | — |
| `pttDown` / `pttUp` | — | — |
| `setOutgoingMuted` | `muted` bool | — |
| `setIncomingAudioMuted` | `muted` bool | — |
| `updateAccessToken` | `accessToken` String | — (replaces the token the next automatic reconnect sends; the running session is not touched. The app calls it after refreshing the account's access token in the background) |
| `setBypass` | `enabled` bool | — (physical mic straight to the virtual mic, no server) |
| `panic` | — | — (clears every queue, silences the virtual mic, closes the session) |

### `start` config

| Key | Type | Meaning |
|---|---|---|
| `gatewayUrl` | String | e.g. `http://127.0.0.1:8201` or `https://bridge.example.com` |
| `connection` | String | how the session is paid for: `token` (default when absent — a static client token on a gateway, the own-gateway mode), `account` (the user's signed-in account on the hosted gateway; `accessToken` is the account's short-lived access token) or `keys` (the user's own ElevenLabs and Gemini keys, sent to the gateway for this session only) |
| `accessToken` | String | required for `token` and `account`, unused for `keys`. `token`: the long-lived client token (kept by the host — Keychain on macOS, Credential Manager on Windows — or typed in settings). `account`: the access token, valid about 15 minutes, held in memory by the app only and never stored |
| `elevenlabsApiKey` / `geminiApiKey` | String | the user's own provider keys; used only with `connection: keys` |
| `micUid` | String | physical microphone |
| `headphonesUid` | String | physical output for incoming Uzbek audio |
| `virtualMicUid` | String? | the virtual cable's playback side — BlackHole 2ch on macOS, CABLE Input (VB-CABLE) on Windows; `null` = no outgoing audio is possible |
| `sourcePids` | List<int> | meeting app processes to tap; empty = incoming direction off |
| `myLang` | String | the owner's language, default `uz` — a code from `packages/protocol/src/languages.ts` (90 languages) |
| `targetLang` | String | the remote participant's language, default `en` — same table; must differ from `myLang` |
| `mode` | String | `captions`, `incoming`, `bidirectional` |
| `outCommit` | String | `manual` (push-to-talk), `vad`, `turn_prediction` |
| `translationModel` | String? | must be allowed by the gateway |
| `outVoiceId` | String? | voice of the owner's translated speech; absent = the gateway's configured voice |
| `inVoiceId` | String? | voice of the remote participant's translated speech; absent = the gateway's configured voice |

On the first connection of a session every refusal is fatal: the session ends with the gateway's code as an `error`
event (`fatal: true`), `session_limit`, `rate_limited`, `gateway_error` and `gateway_unreachable` (no answer) included.
On an automatic reconnect only the terminal refusals end the session that way: `unauthorized`, `invalid_token`,
`balance_empty`, `billing_unavailable`, `accounts_unavailable`, `bad_request`. `session_limit`, `rate_limited`,
`gateway_error` and an unreachable gateway are retried at the next reconnect; when the last attempt fails the session
ends with `gateway_unreachable`. In account mode the gateway also ends a running session with the fatal codes
`balance_exhausted`, `billing_unavailable`, `idle_timeout` (10 minutes without speech) and `session_replaced` (the
account continued on another device).

A voice id is 10 to 40 ASCII letters and digits. Anything else is treated as absent — the start is not refused — and
the host sends `voices: { out?, in? }` in `session.configure` only for the ids that are set.

### Secret items

Secrets are never kept with the other settings and never logged. macOS: Keychain, service
`com.jaysonkhan.livebridge`. Windows: Credential Manager, target `JK-LiveBridge/<item>`.

| Settings key | macOS Keychain account | Windows target |
|---|---|---|
| `accessToken` | `gateway-access-token` | `JK-LiveBridge/gateway-access-token` |
| `accountRefreshToken` | `account-refresh-token` | `JK-LiveBridge/account-refresh-token` |
| `elevenlabsApiKey` | `elevenlabs-api-key` | `JK-LiveBridge/elevenlabs-api-key` |
| `geminiApiKey` | `gemini-api-key` | `JK-LiveBridge/gemini-api-key` |

`accessToken` here is the static gateway token of the own-gateway mode. The account's 15-minute access token is not a
secret item: the app keeps it in memory only.

### Preference keys (stored with the settings, not part of `start`)

| Key | Type | Meaning |
|---|---|---|
| `uiLanguage` | String | `uz`, `ru`, `tr` or `en`; absent = follow the system language if supported, else English |
| `analyticsEnabled` | bool | default `true`; `false` stops writing the analytics log |
| `telemetryEnabled` | bool | default `true` (absent = on, unless `analyticsEnabled` is `false`; a saved `false` stays off; on by default an install that never shared uploads only records written from then on). Upload the numbers-only analytics records to the developer's collector (docs/telemetry-api.md). Needs `analyticsEnabled` |
| `connectionMode` | String | `account`, `keys`, `gateway` (own gateway) or `none` (ask again — shown as the onboarding screen). Absent on an install that predates accounts: a saved static token then means `gateway`, otherwise onboarding |
| `deviceId` | String | random id of this installation, sent to the site when signing in |
| `captionFontSize` | double | caption text size |
| `showOriginal` / `showTranslated` | bool | caption line visibility |
| `outVoiceName` / `inVoiceName` | String? | what the chosen voices are called, saved with `outVoiceId` / `inVoiceId` the moment a voice is picked (so the setup column can show the choice without asking the gateway); `null` removes them |
| `accountOutVoiceId` / `accountInVoiceId` / `accountOutVoiceName` / `accountInVoiceName`, and the same with a `keys` prefix | String? | the same four values for the account and own-keys connection modes (the voice lists differ); `outVoiceId` & co. stay the own gateway's |

Mode semantics: `captions` — both directions transcribe and translate, nothing is synthesized, no virtual mic needed.
`incoming` — captions both ways plus Uzbek audio in the headphones. `bidirectional` — also synthesizes the owner's
clone into the virtual mic.

## EventChannel `livebridge/events`

Each event is a map with a `type` key.

| `type` | Fields |
|---|---|
| `state` | `state` (`idle`, `connecting`, `ready`, `active`, `degraded`, `stopping`), `outReady` bool, `inReady` bool, `capturing` bool (PTT held or hands-free capture running), `mock` bool (gateway is using fake providers), `bypass` bool, `outgoingMuted` bool, `incomingAudioMuted` bool, `message` String? |
| `caption` | `direction` (`out`, `in`), `turnId` int, `kind` (`partial`, `final`, `translationDelta`, `translationFinal`, `skipped`), `text` String. `skipped` follows a `final` when the gateway left the turn untranslated and unspoken; it carries `reason` (`same_language` — the speech was already in the target language, usually the other side's voice in this lane; `echo` — our own synthesized speech came back) and an empty `text` |
| `meters` | `mic` double, `source` double (dBFS, −120 = silence), `outQueueMs` double, `inQueueMs` double — about 10 per second |
| `balance` | `balanceUnits` int — the account's remaining balance, from the gateway's `account.balance`; the app shows it as minutes |
| `metrics` | `direction`, `turnId`, optional ints `e2eMs` (PTT release → first audible sample, client clock), `sttCommitMs`, `translateFirstMs`, `translateTotalMs`, `ttsFirstAudioMs`, `ttsTotalMs`, `audioMs` |
| `error` | `code` String, `message` String, `direction` String?, `fatal` bool |
| `devicesChanged` | — (re-query `listDevices`) |

`translationDelta` text is the incremental piece; `partial` text replaces the previous partial for that turn.

## Analytics

The native side keeps a local log of **numbers only** — timings, counts, error codes, ratings. It never contains
transcript or translation text, and nothing is sent anywhere. One JSON object per line in
`~/Library/Application Support/LiveBridge/analytics.jsonl`.

`analyticsSummary` returns:

| Key | Type | Meaning |
|---|---|---|
| `enabled` | bool | whether logging is on |
| `path` | String | where the log file is |
| `fileSizeBytes` | int | size of the log |
| `sessions` | int | sessions started (mock sessions excluded) |
| `turns` | int | translated turns (both directions) |
| `firstAt` / `lastAt` | String? | ISO-8601 time of the first and last record |
| `e2eMs`, `sttCommitMs`, `translateFirstMs`, `translateTotalMs`, `ttsFirstAudioMs` | Map? | each `{count, p50, p95, max}` in milliseconds; absent when there is no data. `e2eMs` is push-to-talk release → first audible translated sample |
| `errors` | Map<String,int> | error code → count |
| `reconnects` | int | times the gateway connection was lost |
| `emptyTurns` | int | turns that ended with nothing recognised |
| `ratedGood` / `ratedBad` | int | turns the owner marked |

`metrics` events gain an optional `model` String (the translation model that answered the turn).
