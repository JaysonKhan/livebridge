# LiveBridge AI — implementation status

**Updated:** 2026-11-27 (release 1.2.0: accounts, Google sign-in, top up, own keys; account mode run for real) · **Spec:** `livebridge_ai_claude_implementation.md` v1.0

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
real audio; the gateway runs on the server behind HTTPS (since 2026-11-26) but no call has gone through it yet; no Zoom / Meet / Upwork call has been made; no human has reviewed
translation quality or the cloned voice; all test speech so far was synthetic. By the spec's definition
(M0–M4 on real hardware with real calls) **the MVP is not accepted yet**.

## Blockers — what is needed from the owner

| # | Needed | Unblocks |
|---|---|---|
| 1 | ~~API keys~~ — **done** (speech-only ElevenLabs key + Gemini key in `.env`) | — |
| 2 | ~~Install BlackHole 2ch~~ — **done**, loopback and content verified | — |
| 3 | Launch the release app from Finder and approve **Microphone** and **System Audio Recording** | incoming direction with real audio |
| 4 | Listen to `bench-out/probe-outgoing-en.wav`, `probe-outgoing-ru.wav`, `probe-incoming-uz.wav`; read `bench-out/translations-*.jsonl` | voice and translation quality gate |
| 5 | ~~Decisions in `docs/deployment.md`~~ — **done 2026-11-26**: Node.js installed, the gateway deployed with `./deploy.sh`, its own hostname with a certificate and the nginx vhost | — (in the app, set **Gateway URL** to the gateway's HTTPS address) |
| 6 | A consenting second participant (and an Upwork contact) | platform acceptance (M4) |
| 7 | Optional: sign with the Apple Development identity instead of ad-hoc | stable permissions, no Keychain prompt after each rebuild |
| 8 | ~~Confirm the incoming voice id is a stock voice~~ — **dropped 2026-11-25**: both voice slots now default to the author's own voice, published by the author in the ElevenLabs Voice Library (`docs/privacy.md`) | — |

## Accounts and paid service (design `docs/specs/2026-11-26-accounts-paid-service-voices-design.md`)

| Step | State |
|---|---|
| 1. Voice choice | in the app (see Verified) |
| 2. The site (accounts, Google sign-in, device sign-in for the app, wallet, packages, checkout) | live on jaysonkhan.com |
| 3. The gateway's account and own-keys modes | deployed on the hosted gateway (`360bd10`): the site authorises account tokens over its local socket, usage is reported every 10 seconds, session caps, idle timeout |
| 4. The desktop app | **released in 1.2.0** (2026-11-27, merged as PR #2). Onboarding with Google sign-in through the site's device sign-in (code + browser; no Apple sign-in yet), the three ways to connect (account, own keys, own gateway; an existing saved token opens as own gateway), balance chip and top-up sheet, banners for empty balance / billing / idle / continued on another device / busy service, Start blocked on a known empty balance, access token refreshed in the background, secrets (refresh token, provider keys, static token) kept in the Keychain / Credential Manager. Both native hosts carry the new contract (`docs/bridge-contract.md`) |

Checks for step 4 on this Mac: `flutter analyze` clean, `flutter test` 443 passed, `swift test` 40 run (1 skipped), 0 failures,
`apps/desktop/native/livebridge_core/tests/run.sh` 2 262 checks, 0 failed; the Windows workflow passed on the release
commit. **Real run (2026-11-26, release build, real site, hosted gateway):** an existing install opened in own-gateway
mode; Sign in with Google signed the app in; account-mode sessions translated, usage was reported every 10 seconds and
the balance fell (19 021 → 18 652 units); Top up opened the checkout page; sign-out returned to the start screen.
**Not run yet:** a purchase from the app, own-keys mode on the hosted gateway, and the remaining rows in
`docs/manual-qa.md` (declined and expired sign-in, empty balance, the other banners, offline launch).

## Bug reports and statistics on by default (plan `docs/plans/2026-11-27-bug-reports.md`, not released yet)

| Part | State |
|---|---|
| Diagnostic log in the app (memory + rolling `diagnostics.log`, every line redacted) | done; a test drives all three connection modes and asserts no speech, key or token reaches it |
| "Report a problem" (bug icon on the main screen and the onboarding; description, e-mail, log on by default with a preview) | done; account e-mail prefilled in it and in feedback |
| Statistics sharing on by default (an earlier "off" kept) | done in the app and both hosts; docs say so |
| Windows: Bluetooth / USB endpoints told apart | done (topology connector); compiled only by the Windows workflow |
| Site endpoint `POST /api/services/v1/bug-reports/`, admin inbox, Telegram note with the log file | **deployed 2026-11-27** with the site's `./deploy.sh` (migration applied, health 200) |
| Real report from the app reaching the site and the admin group | **done 2026-11-27**: the real app (this Mac, ephemeral settings) sent one through the bug icon; the site stored it (version, OS, platform, devices, log) and the admin-group note was delivered |

## Environment (M0)

| Item | Finding |
|---|---|
| Mac | MacBook Air, Apple M2 (arm64), macOS 26.6.2, Tashkent |
| Toolchain | Xcode 27.2 / Swift 6.4.2, Flutter 3.47.0 / Dart 3.13.0, Node 25.9.0 |
| Not installed | Docker |
| Virtual microphone | BlackHole 2ch installed (`BlackHole2ch_UID`, 2 in / 2 out, 48 kHz); default devices unchanged |
| Audio devices | built-in microphone (48 kHz), built-in speakers (48 kHz), iPhone Continuity microphone |
| Repository | local git repo initialised, **nothing committed**; `.env` is git-ignored |
| Server | gateway deployed 2026-11-26: Node 24, systemd service on localhost, nginx with its own hostname and Let's Encrypt certificate in front |

## Milestones

| Milestone | Status | Notes |
|---|---|---|
| **M0** capability spike | **Done except tap audio** | Real probes pass (27 checks, 0 failed, 3 skipped for the restricted key). Mic capture, playback and BlackHole loopback verified on hardware. Tap runs but silent (permission). |
| **M1** audio routing + local UI | **Done** | Virtual-mic route verified through BlackHole: only translated speech arrives on its input, silence otherwise. |
| **M2** backend vertical slice (OUT) | **Done on real providers, not in a real call** | PTT → Scribe → Gemini → owner's clone → BlackHole, measured end to end and the BlackHole output transcribed. A real Zoom listener is blocked (6). |
| **M3** IN pipeline | **Code complete; verified on real providers at the gateway only** | en→uz and ru→uz run in the benchmark (60 turns) with the stock voice. Real tapped audio is blocked (3). |
| **M4** platform acceptance | **Not started** | Routing guide is from documentation, not tested calls. |
| **M5** hands-free / low latency | **Partly** | Model chosen by measurement; warm sockets; `vad` / `turn_prediction` commit confirmed live at the STT level, not end to end. Not built: echo detection, clause-level streaming into TTS, translated-only monitoring. |
| **M6** hardening / packaging | **Mostly** | Reconnect (exercised), rate limit, bounded queues, session caps, 60-minute soak (fake providers), release `.app`, infra files. Not done: Docker build, signing/notarisation, a 60-minute run on real providers. |

## Verified — commands and actual results

| What | Command | Result |
|---|---|---|
| TypeScript typecheck | `npm run typecheck` | clean |
| Protocol, gateway, adapters (mock servers), bench harness | `npm test` | **97 passed, 0 failed** |
| Swift engine unit tests | `swift test` | **29 passed**, 1 skipped (the live-collector test below) |
| Flutter analysis / widget tests | `flutter analyze`, `flutter test` | no issues / **232 passed** |
| App end to end (fake providers) | `flutter test integration_test/session_test.dart -d macos` | passed — real UI, engine and microphone |
| Release build | `flutter build macos --release` | `JK - LiveBridge.app`, 48 MB, ad-hoc signed, macOS 14.2+ |
| **Live API probe** | `npm run probe` | 32 checks: 0 failed, 1 skipped (key lacks `user_read`). Voices: 108 in the account on 2 pages, 106 offered by the gateway, a sample fetched with no key, three voices of each category spoken by the realtime model |
| **Gateway on the server** | `LIVEBRIDGE_SSH_HOST=<server> ./deploy.sh`, then the public address from this Mac | first deploy 2026-11-26: gates passed, service active; over HTTPS (HTTP/2, valid certificate): `/healthz` 200, `401` without the token, `GET /v1/voices` 106 voices, other paths 404 |
| **Hosted vs local gateway** (the design's latency check) | the same 6 recorded turns (uz→en and en→uz, 3 sentences each, real providers) through a gateway on this Mac and through the one on the server | end of speech → first translated audio at the Mac, median **1029 ms local, 809 ms hosted**; every hosted turn faster (731–897 ms vs 1004–1267 ms). STT 261 → 150 ms, first translated text 484 → 366 ms, first synthesized audio 193 → 80 ms. A small sample; not yet a real call |
| **Voice sample player on a device** | `flutter test integration_test/sample_player_test.dart -d macos --dart-define=LB_SAMPLE_URL=…` | passed — a real sample played 9.3 s to its end; a dead address ended as idle; a second sample replaced the first |
| **Chosen voices with the real providers** | a session with `voices` through the gateway, recorded speech both ways, then the same with none | chosen stock voices: median pitch 218 / 218 Hz; defaults: 122 / 165 Hz; 4 turns, 0 errors |
| **Voice choice in the app, end to end** | the app on this Mac against the gateway with the real key (no speech captured) | 106 voices in the picker, filter and two samples, a voice chosen per direction → the gateway received exactly those two ids and opened the outgoing synthesizer with the chosen one; after **Default** none were sent |
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
| First two-person test, both in one room (2026-11-25, automatic mode): 12 of the other speaker's 21 turns were also picked up by the owner's microphone in the same second; English landing in the Uzbek→English lane was translated *back* into Uzbek and spoken into the call | Speech already in a lane's target language is captioned but not translated or spoken (the model answers with a mark; 21 of 22 sample sentences right on the primary model, 22 of 22 on the fallback — the miss: English in an Uzbek→Russian lane is skipped instead of translated). Our own synthesized speech coming back is recognised by its text and dropped. Speech-to-text cannot be used for this: with a forced language it reports the forced one, not the spoken one (measured). **Not solved:** a third language (e.g. Turkish) leaking into the other lane, and a room shared by both speakers in general |

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
| Any pair of 90 languages instead of Uzbek ↔ English / Russian only (two lists in the app; default unchanged) | Owner's request (2026-11-25). The list is Eleven v4's documented 91 languages minus Kamba, which realtime speech-to-text rejects; Fula and Lingala need the ISO 639-3 code on the speech-to-text side (all checked live, code by code). **Measured only for Uzbek ↔ English / Russian**: other pairs are untested for quality and latency, and the consent sentence exists in English and Russian only. The statistics collector accepts any pair since its update on 2026-11-25 |
| The interface follows the platform: Windows 11 / Fluent on Windows, macOS on the Mac, one teal/mint brand accent on both (`lib/ui/theme/`, `lib/ui/adaptive/`) | Owner's request (2026-11-26). Values from Microsoft's WinUI theme resources and Apple's HIG; brand shades chosen for ≥ 4.5:1 text contrast. macOS gets a unified transparent title bar with the header beside the traffic lights; Windows 11 paints its title bar in the page colour. Every interface language is checked for clipped text by `test/layout_overflow_test.dart`. Dragging the window by the macOS header is implemented but was not tried by hand |
| Opt-in statistics and feedback go to a collector on the author's site (`docs/telemetry-api.md`) | Off by default, numbers only. **The collector is not deployed yet** — until it is, uploads fail quietly and are retried |
| Cancel = close and reopen that direction's TTS socket | The dialogue socket documents no per-turn cancel |
| Cancel fences speech-to-text too: push-to-talk commits the audio already sent and drops every transcript still owed for it; `vad` / `turn_prediction` move to a fresh STT session if audio was captured | Speech-to-text documents no way to drop sent audio, its transcripts carry no segment id, and a commit under `vad` is undocumented. The fresh session costs one handshake, only after a cancel; audio meanwhile waits (≤ 500 ms). Covered on mock servers only, **not tried against the live API** |
| Hold to talk ↔ automatic during a session (`setOutCommit` → `turn.mode`): the gateway opens a speech-to-text session with the new commit strategy; what was said before the switch is committed at once by the old session (which still delivers its answers), what is captured after it waits for the new one, in order (up to 10 s) (`docs/plans/2026-11-27-ptt-mode-switch.md`) | Measured live on 2026-11-27: a manual commit **is** honoured under `vad` and `turn_prediction`, but takes ≈ 300 ms against ≈ 250 ms in a `manual` session (median of the typical runs). So hold to talk keeps a `manual` session and nothing is added to a turn; the swap costs one provider handshake at switch time only. From the Mac (local gateway) that handshake took 0.4 s in 5 of 8 switches, 1.3 s, 6 s and 7.7 s in the others — speech said meanwhile is translated late, not lost; not yet measured from the hosted gateway. A gateway without the `turn.mode` feature keeps the session's mode and the app says so |
| Riverpod; settings via the native bridge (UserDefaults + Keychain) | One Flutter plugin with native code, `audioplayers`, only to play voice samples; on macOS it is linked as a Swift package, so still no CocoaPods |
| Voices are chosen in the app from the gateway's ElevenLabs account: `GET /v1/voices` (cached 10 minutes), optional `voices` in `session.configure`, a picker with search, filters and samples (`docs/specs/2026-11-26-accounts-paid-service-voices-design.md`, step 1) | Owner's design of 2026-11-26. The app reads the list itself over HTTP — one implementation for both platforms; the native hosts only copy the two ids into the configure message. The list is read each time a picker opens and at no other time: the setup column shows a chosen voice by the name saved with the choice, so the access token is never sent to an address that is still being typed |
| A library voice its owner has switched off (`sharing.status: copied_disabled`) is left out of the list; the provider's `voice_not_found` and `voice_disabled` reach the app as error `voice_not_found` | Found by speaking with all 108 voices of the account once: 106 worked, the 2 refused ones were exactly the switched-off ones. The provider accepts any voice id when a session opens and refuses it only when a turn is spoken, so the app is told in words at that turn |
| App is **not sandboxed** | Process taps and private aggregate devices; personal-use build |
| systemd service behind nginx on port 8201 (Docker files provided too) | Matches the server's conventions |
| Setup guide in Uzbek, UI in simple English | Spec allowed either |

## Windows (supported since 2026-11-26)

Built in stages with the owner from 2026-11-25 (1. captions, 2. incoming audio, 3. bidirectional through VB-CABLE),
by GitHub Actions on `windows-latest` (the development Mac cannot build Windows code). The owner ran the Windows app
on a real Windows PC and reported on 2026-11-26 that it works; from then on Windows is a supported platform. The
installer is published with the releases from 1.1.0 on.

| Piece | State |
|---|---|
| `apps/desktop/native/livebridge_core` — portable C++17: frame codec, ring buffer, JSON, analytics log, the engine's session logic (twin of `Engine.swift`), resampler and multi-source mixer, telemetry uploader | **tested on both platforms**: 1 850 checks with clang on the Mac (also under address/UB and thread sanitizers) and the same five test programs built by MSVC and run on Windows in CI on every push to `main` |
| Windows platform layer (`apps/desktop/windows/runner/`): engine thread, WASAPI microphone capture, render sinks for the headphones and the VB-CABLE virtual microphone, per-process loopback capture of the meeting app (mixed when several), process and device lists, test tone, meters, WinHTTP gateway socket, statistics upload and feedback, Save dialogs, settings (token in the Credential Manager) | compiles on CI with `/W4 /WX`, no warnings; **run on a real PC by the owner** (2026-11-26, his report: works) |
| Interface on Windows (VB-CABLE detection, Windows wording, privacy hint, Fluent look) | done; widget tests force the Windows variant, and the overflow tests render every language in the Windows look |
| Installer (Inno Setup, per user, Start menu "JK - LiveBridge", Visual C++ runtime bundled) | built by CI on every push to `main`; installed and run by the owner; attached to the GitHub release from 1.1.0 |
| Known limits | per-app capture of the meeting needs Windows 11 or Windows 10 build 20348+ (older builds: the app says so; captions with your own microphone still work); the installer is not code-signed (SmartScreen asks once); which capture format the loopback client accepted on the owner's PC was not recorded |

Facts taken from Microsoft's documentation for the audio layer (2026-11-25):

- Shared-mode streams can be opened in our own format: `AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM` inserts "a channel
  matrixer and a sample rate converter" between the supplied format and the mix format
  (`AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY` for the better converter); check with `IAudioClient::IsFormatSupported`.
- Per-process loopback (`ActivateAudioInterfaceAsync` + `VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK`,
  `AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS`): the target process **and its child processes**; documented minimum
  "Windows 10 Build 20348" (one page says 20438); silence when the target renders nothing. Which wave formats that
  client accepts is not documented — to be found out on the owner's PC.
- Processes that are producing audio: `IAudioSessionManager2::GetSessionEnumerator` →
  `IAudioSessionControl2::GetProcessId`, state `AudioSessionStateActive`.
- WebSocket client: WinHTTP (`WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET`, `WinHttpWebSocketCompleteUpgrade`), Windows 8+.
- Not documented and still open: whether desktop apps get a microphone prompt and which error a denied microphone
  returns.

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
