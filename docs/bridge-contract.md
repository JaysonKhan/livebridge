# Flutter ↔ Swift bridge contract

The Swift audio engine owns devices, audio buffers, playback and the gateway WebSocket. Flutter only sends low-rate
commands and receives captions, state and throttled meters. No PCM ever crosses this bridge.

## MethodChannel `livebridge/control`

All arguments and results are standard-codec maps/lists. A failed call throws `PlatformException(code, message)`.

| Method | Arguments | Result |
|---|---|---|
| `listDevices` | — | `List<Map>`: `uid` String, `name` String, `inputChannels` int, `outputChannels` int, `sampleRate` double, `transport` String (`builtin`, `usb`, `bluetooth`, `virtual`, `aggregate`, `other`), `isDefaultInput` bool, `isDefaultOutput` bool |
| `listAudioProcesses` | — | `List<Map>`: `pid` int, `bundleId` String, `name` String, `isPlaying` bool — processes that currently own an audio object |
| `loadSettings` | — | `Map` of the last saved `start` config keys (missing keys absent). `accessToken` comes from the Keychain, the rest from UserDefaults |
| `saveSettings` | same keys as the `start` config, all optional | — |
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
