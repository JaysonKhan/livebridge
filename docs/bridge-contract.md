# Flutter ↔ Swift bridge contract

The Swift audio engine owns devices, audio buffers, playback and the gateway WebSocket. Flutter only sends low-rate
commands and receives captions, state and throttled meters. No PCM ever crosses this bridge.

## MethodChannel `livebridge/control`

All arguments and results are standard-codec maps/lists. A failed call throws `PlatformException(code, message)`.

| Method | Arguments | Result |
|---|---|---|
| `listDevices` | — | `List<Map>`: `uid` String, `name` String, `inputChannels` int, `outputChannels` int, `sampleRate` double, `transport` String (`builtin`, `usb`, `bluetooth`, `virtual`, `aggregate`, `other`), `isDefaultInput` bool, `isDefaultOutput` bool |
| `listAudioProcesses` | — | `List<Map>`: `pid` int, `bundleId` String, `name` String, `isPlaying` bool — processes that currently own an audio object |
| `loadSettings` | — | `Map` of everything saved so far (missing keys absent): the `start` config keys plus the preference keys below. `accessToken` comes from the Keychain, the rest from UserDefaults |
| `saveSettings` | any subset of the `start` config keys and preference keys | — (the given keys are **merged** into what is stored; a `null` value removes a key) |
| `saveTextFile` | `suggestedName` String, `content` String | String? — shows the system Save dialog and writes UTF-8 text; returns the saved path, or `null` if the user cancelled |
| `rateTurn` | `direction` String, `turnId` int, `rating` String (`good`, `bad`, `none`) | — (records the owner's judgement of a translation in the analytics log; no text is stored) |
| `analyticsSummary` | — | `Map`, see "Analytics" below |
| `analyticsExport` | — | String? — Save dialog for the raw analytics file (JSON Lines); saved path or `null` |
| `analyticsClear` | — | — (deletes the analytics file) |
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
| `setBypass` | `enabled` bool | — (physical mic straight to the virtual mic, no server) |
| `panic` | — | — (clears every queue, silences the virtual mic, closes the session) |

### `start` config

| Key | Type | Meaning |
|---|---|---|
| `gatewayUrl` | String | e.g. `http://127.0.0.1:8201` or `https://bridge.example.com` |
| `accessToken` | String | long-lived client token (from Keychain on the Dart side or typed in settings) |
| `micUid` | String | physical microphone |
| `headphonesUid` | String | physical output for incoming Uzbek audio |
| `virtualMicUid` | String? | BlackHole 2ch; `null` = no outgoing audio is possible |
| `sourcePids` | List<int> | meeting app processes to tap; empty = incoming direction off |
| `targetLang` | String | `en` or `ru` (the remote participant's language) |
| `mode` | String | `captions`, `incoming`, `bidirectional` |
| `outCommit` | String | `manual` (push-to-talk), `vad`, `turn_prediction` |
| `translationModel` | String? | must be allowed by the gateway |

### Preference keys (stored with the settings, not part of `start`)

| Key | Type | Meaning |
|---|---|---|
| `uiLanguage` | String | `uz`, `ru`, `tr` or `en`; absent = follow the system language if supported, else English |
| `analyticsEnabled` | bool | default `true`; `false` stops writing the analytics log |
| `captionFontSize` | double | caption text size |
| `showOriginal` / `showTranslated` | bool | caption line visibility |

Mode semantics: `captions` — both directions transcribe and translate, nothing is synthesized, no virtual mic needed.
`incoming` — captions both ways plus Uzbek audio in the headphones. `bidirectional` — also synthesizes the owner's
clone into the virtual mic.

## EventChannel `livebridge/events`

Each event is a map with a `type` key.

| `type` | Fields |
|---|---|
| `state` | `state` (`idle`, `connecting`, `ready`, `active`, `degraded`, `stopping`), `outReady` bool, `inReady` bool, `capturing` bool (PTT held or hands-free capture running), `mock` bool (gateway is using fake providers), `bypass` bool, `outgoingMuted` bool, `incomingAudioMuted` bool, `message` String? |
| `caption` | `direction` (`out`, `in`), `turnId` int, `kind` (`partial`, `final`, `translationDelta`, `translationFinal`), `text` String |
| `meters` | `mic` double, `source` double (dBFS, −120 = silence), `outQueueMs` double, `inQueueMs` double — about 10 per second |
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
