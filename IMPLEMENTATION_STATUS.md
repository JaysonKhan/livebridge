# LiveBridge AI — implementation status

**Updated:** 2026-11-25 (default voice, opt-in statistics and feedback) · **Spec:** `livebridge_ai_claude_implementation.md` v1.0

## Where it stands

The system works end to end **with the real providers on real audio hardware**: recorded Uzbek speech → Swift audio
engine → gateway → Scribe v3 Live → Gemini → Eleven v4 Turbo in the owner's cloned voice → playback through the HAL.
Measured: translated speech becomes audible a median **1.35–1.41 s** after the speaker stops (24 turns, slowest
1.81 s); the gateway benchmark over 120 turns gives **p50 1333 ms / p95 2490 ms** with no failed turns
(`docs/benchmark.md`).

BlackHole 2ch is now installed and verified: the translated speech written to it comes out of its microphone side
and nothing else does (recorded and transcribed: four turns in, the same four English sentences out; silent when
idle).

**Still not done, and not claimable:** no meeting app has been pointed at the BlackHole microphone yet, so no remote
participant has heard it; the process tap has only delivered silence (permission), so the incoming direction is untested with
real audio; nothing is deployed to the server; no Zoom / Meet / Upwork call has been made; no human has reviewed
translation quality or the cloned voice; all test speech so far was synthetic. By the spec's definition
(M0–M4 on real hardware with real calls) **the MVP is not accepted yet**.

## Blockers — what is needed from the owner

| # | Needed | Unblocks |
|---|---|---|
| 1 | ~~API keys~~ — **done** (speech-only ElevenLabs key + Gemini key in `.env`) | — |
| 2 | ~~Install BlackHole 2ch~~ — **done**, loopback and content verified | — |
| 3 | Launch the release app from Finder and approve **Microphone** and **System Audio Recording** | incoming direction with real audio |
| 4 | Listen to `bench-out/probe-outgoing-en.wav`, `probe-outgoing-ru.wav`, `probe-incoming-uz.wav`; read `bench-out/translations-*.jsonl` | voice and translation quality gate |
| 5 | Decisions in `docs/deployment.md`: hostname + DNS record, Node.js on the server, go-ahead to deploy | "use my existing server" — the gateway runs only on localhost today |
| 6 | A consenting second participant (and an Upwork contact) | platform acceptance (M4) |
| 7 | Optional: sign with the Apple Development identity instead of ad-hoc | stable permissions, no Keychain prompt after each rebuild |
| 8 | ~~Confirm the incoming voice id is a stock voice~~ — **dropped 2026-11-25**: both voice slots now default to the author's own voice, published by the author in the ElevenLabs Voice Library (`docs/privacy.md`) | — |

## Environment (M0)

| Item | Finding |
|---|---|
| Mac | MacBook Air, Apple M2 (arm64), macOS 26.6.2, Tashkent |
| Toolchain | Xcode 27.2 / Swift 6.4.2, Flutter 3.47.0 / Dart 3.13.0, Node 25.9.0 |
| Not installed | Docker |
| Virtual microphone | BlackHole 2ch installed (`BlackHole2ch_UID`, 2 in / 2 out, 48 kHz); default devices unchanged |
| Audio devices | built-in microphone (48 kHz), built-in speakers (48 kHz), iPhone Continuity microphone |
| Repository | local git repo initialised, **nothing committed**; `.env` is git-ignored |
| Server | conventions read from local documentation only; no SSH connection was made |

## Milestones

| Milestone | Status | Notes |
|---|---|---|
| **M0** capability spike | **Done except tap audio** | Real probes pass (27 checks, 0 failed, 3 skipped for the restricted key). Mic capture, playback and BlackHole loopback verified on hardware. Tap runs but silent (permission). |
| **M1** audio routing + local UI | **Done** | Virtual-mic route verified through BlackHole: only translated speech arrives on its input, silence otherwise. |
| **M2** backend vertical slice (OUT) | **Done on real providers, not in a real call** | PTT → Scribe → Gemini → owner's clone → BlackHole, measured end to end and the BlackHole output transcribed. A real Zoom listener is blocked (6). |
| **M3** IN pipeline | **Code complete; verified on real providers at the gateway only** | en→uz and ru→uz run in the benchmark (60 turns) with the stock voice. Real tapped audio is blocked (3). |
| **M4** platform acceptance | **Not started** | Routing guide is from documentation, not tested calls. |
| **M5** hands-free / low latency | **Partly** | Model chosen by measurement; warm sockets; `vad` / `turn_prediction` commit confirmed live at the STT level, not end to end. Not built: echo detection, clause-level streaming into TTS, translated-only monitoring. |
| **M6** hardening / packaging | **Mostly** | Reconnect (exercised), rate limit, bounded queues, session caps, 60-minute soak (fake providers), release `.app`, infra files. Not done: Docker build, deployment, signing/notarisation, a 60-minute run on real providers. |

## Verified — commands and actual results

| What | Command | Result |
|---|---|---|
| TypeScript typecheck | `npm run typecheck` | clean |
| Protocol, gateway, adapters (mock servers), bench harness | `npm test` | **74 passed, 0 failed** |
| Swift engine unit tests | `swift test` | **26 passed**, 1 skipped (the live-collector test below) |
| Flutter analysis / widget tests | `flutter analyze`, `flutter test` | no issues / **119 passed** |
| App end to end (fake providers) | `flutter test integration_test/session_test.dart -d macos` | passed — real UI, engine and microphone |
| Release build | `flutter build macos --release` | `livebridge.app`, 44 MB, ad-hoc signed, macOS 14.2+ |
| **Live API probe** | `npm run probe` | 27 checks: 0 failed, 3 skipped (key lacks `user_read` / `voices_read`) |
| **Real benchmark** | `npm run bench -- --rounds 3 --models gemini-3.5-flash-lite` | 120 turns, 0 failed, first audio p50 1333 / p95 2490 ms |
| **Real end to end on hardware** | `lbaudio session --mic-file …` | 24 turns, 0 errors, median 1350–1407 ms, max 1806 ms, owner's voice |
| 60-minute soak (fake providers) | `tests/soak.sh 60` | 1090 turns, 0 errors, no drift, no memory growth |
| **BlackHole loopback** | `lbaudio loopback --uid BlackHole2ch_UID` | tone written to the output read back from the input at −9.0 dBFS (expected −9), 0 underruns |
| **Translated speech through BlackHole** | `lbaudio session … --virtual-mic BlackHole2ch_UID` while `lbaudio mic --uid BlackHole2ch_UID --out …` records its input | 4 turns, 0 errors, 1249–1989 ms; input silent (−120 dBFS) when idle, −19.6 dBFS peak in speech; the recording transcribes to exactly the 4 English translations |
| Panic stop | `lbaudio session … --panic-during-turn 2` | 87.8 ms to idle (one run) |
| Gateway killed and restarted mid-session | manual | recovered after 4 retries; interrupted turn not replayed |
| Statistics upload and feedback against a real collector (run locally, not the production site) | `LIVEBRIDGE_COLLECTOR_URL=http://127.0.0.1:8011/api/services/v1 swift test --filter LiveCollector` | 6 records accepted, nothing sent twice, feedback stored; the public page rendered the figures |

Tests that use fakes or mock servers say so in their titles and file headers. No automated test calls a real API;
the probe, the benchmark and `lbaudio session` against a real gateway do.

## What the live runs changed

| Found by measuring | Fix |
|---|---|
| Every translation opened a new HTTPS connection (~1 s from this network) | keep-alive agent, connection warmed when speech starts |
| First translated text sometimes stalled for seconds (once 21 s); 13 of 90 turns failed | second request raced after 1.2 s on the same model; an attempt is abandoned at 4 s; fallback model for outright failures |
| `gemini-3.8-flash` answered 503 "high demand" or took 1.6–2.4 s | **primary is now `gemini-3.5-flash-lite`** (fastest and most available of five sampled), 3.8-flash is the fallback; circuit breaker skips a failing model for 60 s |
| Synthesized speech was cut mid-word when the provider paused > 1.5 s | idle limit raised to 6 s; the provider's end-of-turn marker is the real signal (confirmed reliable) |
| The benchmark lost everything on one dropped connection | retries, results written turn by turn |
| First use in the app: a quick tap on push-to-talk closed the STT session (the provider requires ≥ 0.3 s of uncommitted audio and closes the socket otherwise) | short turns are padded with silence to 0.32 s; an empty press is answered locally without a round trip |
| After a reconnect the gateway restarts turn numbering | the engine keeps caption ids unique across reconnects |
| The app froze on a macOS Keychain prompt after a rebuild | Keychain access moved off the UI thread; tests no longer touch the Keychain |

The owner's `.env` was edited once by this work: the two model lines were switched to the measured choice
(`TRANSLATION_MODEL=gemini-3.5-flash-lite`, `TRANSLATION_FALLBACK_MODEL=gemini-3.8-flash`). Secrets were not read
into any output.

## Decisions (and deviations from the spec's defaults)

| Decision | Why |
|---|---|
| Primary translation model `gemini-3.5-flash-lite`, not the spec's `gemini-3.8-flash` | Spec §4.2: choose by measured latency. Quality still needs the owner's review |
| Swift engine is a standalone package (`LiveBridgeAudioCore` + `lbaudio` CLI) linked into the Runner | Testable and drivable without Flutter; PCM never crosses the Dart bridge |
| HAL IO procs, lock-free SPSC ring buffers, 10 ms worker polling | No locks, allocation, logging or network on the IO thread |
| Process tap on **selected processes only**, tap-only private aggregate device | Never captures the whole system; the app's own playback is excluded by construction |
| Gateway on `node:http` + `ws` + `zod`, **not Fastify** | Three routes; spec allowed "or existing compatible server stack" |
| TypeScript run directly by Node (type stripping) | No build step; needs Node ≥ 22.18 on the server |
| Each committed turn is translated as a unit, then synthesized | Protects negation and meaning; output is validated before anything is spoken |
| TTS input has `[bracketed]` spans removed | Eleven v4 reads them as audio tags |
| Both voice slots default to the author's public Voice Library voice (`ehTFHBkERkWR22A3sR8M`); the "voices must differ" rule is gone | Owner's decision (2026-11-25): the voice is published by the owner and works in all four languages. The disclosure sentence now says "a synthesized voice". **Not verified:** that the id works for another account without first adding the voice from the Voice Library (ElevenLabs' docs do not say) |
| Opt-in statistics and feedback go to a collector on the author's site (`docs/telemetry-api.md`) | Off by default, numbers only. **The collector is not deployed yet** — until it is, uploads fail quietly and are retried |
| Cancel = close and reopen that direction's TTS socket | The dialogue socket documents no per-turn cancel |
| Riverpod; settings via the native bridge (UserDefaults + Keychain) | No Flutter plugin with native code, so no CocoaPods |
| App is **not sandboxed** | Process taps and private aggregate devices; personal-use build |
| systemd service behind nginx on port 8201 (Docker files provided too) | Matches the server's conventions |
| Setup guide in Uzbek, UI in simple English | Spec allowed either |

## Known gaps and risks

| Area | Gap / risk | Consequence |
|---|---|---|
| Speech tested | Almost all test speech is synthesized. First real sample (owner, in the app, 2026-11-25): "Bir, bir, bir, meni eshityapsanmi?" was heard as "Ber, ber, ber, …" and translated "Give, give, give, do you hear me?", 1189 ms end to end | Real Uzbek (accent, dialect, speed, code-switching) is unmeasured; short isolated words are a known weak spot |
| Translation latency | p50 626 ms first text vs the 150–500 ms stage target; Google availability swung during the session | End-to-end p50 has little margin under 1.5 s; a bad provider hour will exceed it |
| Technical terms | "BLoC" recognised as "Blog"/"Block" | Needs a keyterm list (the provider supports it, at extra cost); not implemented |
| Network | ~2 of 45 ElevenLabs handshakes failed from this network | A turn can lose its audio (caption still shown); a server-side gateway should be steadier — unmeasured |
| Tap permission | A silent tap gives no error from Core Audio | App shows a flat source meter, not an explicit "permission missing" message |
| Original audio | Meeting app keeps playing to the headphones | Original and translation are heard together |
| Echo | No automatic echo detection | Headphones required; hands-free without them will loop |
| Browser calls | Tap is per process, not per tab | Use a dedicated browser window |
| Ad-hoc signing | Signature changes on every rebuild | macOS re-asks for permissions and the Keychain prompts once after a rebuild |
| Client reconnect | Exercised only against a local gateway restart | A real Wi-Fi drop is untested |
| Device changes | Unplug → session stops; a sample-rate change mid-session is not detected | Wrong-speed audio until restart if a device's rate changes mid-call |
| Push-to-talk | In-app only (Space); no pre-roll | Window must be focused; speak after pressing |
| Hedging | A slow turn sends a second translation request | Small extra token use; never duplicate speech (tested) |
| Ban rules | If the server bans on HTTP errors in a shared access log | Gateway `429`/`401` could count toward a ban — check before going live (`docs/deployment.md`) |
| Soak | 60 minutes on fake providers only | Long-call behaviour on real providers (cost, session limits) unproven |
| Docker | Image never built | Compose file untested |
| Not built | Glossary/keyterm UI, source-language auto-detect, caption overlay, budget warning, translated-only monitoring | Roadmap |
| Added 2026-11-25 at the owner's request | Opt-in sharing of the numbers-only log and a feedback form, sent to a collector on the owner's site (`docs/telemetry-api.md`) — **the collector is built locally in another repository and is not deployed yet, so uploads currently fail and are retried**; interface in uz / ru / tr / en; on-demand conversation export; local numbers-only analytics log with per-turn ratings; meeting-source list filtered to apps; echo hold in automatic turn modes | These change the original "no export, no analytics" stance: both are explicit or content-free (`docs/privacy.md`). Translations of the interface text have not been reviewed by native speakers |

## Next commands, in order

```bash
# 1. App with real audio
npm run gateway                       # from the repo root, reads .env
open apps/desktop/build/macos/Build/Products/Release/livebridge.app    # approve both permission prompts

# 2. One real call per platform with a consenting participant; fill in docs/manual-qa.md

# 3. Server (only after approval): docs/deployment.md, ./deploy.sh, then `npm run bench` there
```

## Rollback

Nothing outside this folder was changed: no server, no system audio setting, no default device, no driver. A test
token and test preferences written by an early integration run were removed again. To remove the project: delete
this folder; to remove app data later: delete the Keychain item `com.jaysonkhan.livebridge` and
`defaults delete com.jaysonkhan.livebridge`. To stop API spend: revoke the two keys in the providers' consoles.
