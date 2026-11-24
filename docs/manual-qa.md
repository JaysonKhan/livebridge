# Manual acceptance matrix

Status as of 2026-11-24 (after the first live-API runs). **PASS** = observed on this Mac. **PASS (mock)** = observed with fake providers or mock
provider servers — the wiring works, real translation is unproven. **BLOCKED** = cannot be tested yet; the blocker is
named. Nothing is marked PASS on the strength of a simulation of a real call.

| Scenario | Expected | Status | Evidence / blocker |
|---|---|---|---|
| UZ → EN, UZ → RU | Remote hears the translation in the owner's clone; raw mic not transmitted | **PARTIAL — real providers, no real call** | Real: recorded Uzbek speech → Scribe → Gemini → owner's clone → played on the output device, 24 turns, correct translations, median 1.35–1.41 s. Through BlackHole: 4 turns written to the BlackHole output; its input side (what a meeting app reads) was recorded and transcribes to exactly the 4 English translations, and is silent (−120 dBFS) when idle — no Uzbek original on it. Not done: no meeting app or participant has listened yet, so "remote hears it" is unproven. Mic frames leave the Mac only while push-to-talk is held. |
| EN → UZ, RU → UZ | UZ caption + Uzbek in headphones; remote does not hear it | **PARTIAL — gateway only** | Real providers at the gateway: 60 benchmark turns en→uz / ru→uz with the stock voice, 0 failed. Not done on hardware: System Audio Recording permission (the tap delivered silence). Mock: IN turns produce only IN-direction frames, played on the headphones sink, never the virtual-mic sink. |
| Zoom Desktop | Real call with virtual mic | **BLOCKED** | participant |
| Zoom Web | Real call | **BLOCKED** | same |
| Google Meet | Real browser call, device switching | **BLOCKED** | same |
| Upwork Zoom | Real call from Upwork Messages | **BLOCKED** | same + Upwork contact |
| Upwork native video | Real call; device selection available? | **BLOCKED / unverified** | same; whether Upwork's native meeting offers a microphone selector is unknown |
| Captions-only | Works without virtual mic; no synthesized audio | **PASS (mock)** | App integration test: real UI + engine + microphone, no BlackHole on this Mac, captions shown, no playback devices opened. Gateway test: captions-only direction produces zero audio frames. |
| PTT and mute | Nothing transmitted while muted; no duplicate turn after release | **PASS (mock)** | Gateway: frames outside a capture window are dropped; two releases → exactly two turns; extra commit adds nothing. Engine: muted/bypassed outgoing frames are discarded on arrival. Not yet exercised by hand in the UI with real providers. |
| Panic stop | Queue discarded, no new audio, playback stops ≤250 ms | **PASS (mock)** | 87.8 ms panic → idle on real hardware (one run); app integration test returns to idle. |
| Network loss / TTS failure | Explicit error, silence on virtual mic, captions if available, no stale replay | **PASS (mock)** | Mock-server tests: dropped STT socket → direction announced not ready → reconnect → only post-reconnect audio reaches the provider; TTS error → `tts_failed`, caption kept; aborted turn's audio never reaches the next turn. Client side on hardware: gateway killed mid-turn → "Connection lost — reconnecting", 4 retries, recovered when it came back, the interrupted turn was not replayed, next turn audible (2 runs, fake providers). A real Wi-Fi drop is untested. |
| Original bypass | Only deliberate action; obvious UI; no server | **PASS (unit) / hardware unverified** | Widget tests: confirmation + full-width banner. Engine routes mic → virtual-mic sink locally. Not run on hardware: needs BlackHole. |
| Feedback / overlap | No runaway loop; warn and offer PTT | **BLOCKED** | Needs BlackHole + a real call. Design: only selected processes are tapped (the app's own playback is not), the route check refuses shared devices; automatic echo detection is not implemented. |
| 60-minute call | No unbounded queue/memory growth, no leaked sockets | **PASS (fake providers)** | `tests/soak.sh 60`: 1090 turns in 53 min on real audio hardware, 0 errors, latency identical at start and end (p50 186 → 185 ms), gateway and engine memory flat, no gateway warnings. Not run on real providers. |
| Privacy | Nothing captured before start / after stop; nothing persisted; no secrets in code/logs | **PASS (mock)** | Log-content tests (transcripts and tokens never appear); `STORE_CONTENT` must be false; token in Keychain; no content written to disk. Provider-side retention is outside this project (docs/privacy.md). |

## Native smoke checks

| Check | Status | Note |
|---|---|---|
| Device enumeration (stable UIDs, rates, channels) | PASS | 3 devices listed, unit test |
| Microphone permission granted | PASS | when launched from this shell the process inherits the terminal app's grant; a Finder-launched LiveBridge.app will prompt once |
| Microphone permission denied | NOT RUN | needs the owner to deny once in System Settings |
| Process tap permission denied / not granted | OBSERVED | tap runs but delivers silence; the app shows a flat source meter |
| Process tap with permission granted | BLOCKED | owner must approve the System Audio Recording prompt |
| Device unplug mid-session | NOT RUN | engine stops with `device_removed` (code path only) |
| Sample-rate mismatch | PASS | 24 kHz → 48 kHz playback and 48 kHz → 16 kHz capture verified on hardware and in unit tests |
| Start/stop cycles | PASS (mock) | 25 turns + repeated sessions, no leaked devices |
| BlackHole loopback (`lbaudio loopback`) | PASS | tone read back at −9.0 dBFS (expected −9), 0 underruns |
| Bluetooth reconnect, app switching | NOT RUN | |

## To unblock, in order

1. Launch the release app from Finder, approve Microphone and System Audio Recording, check the source meter moves.
2. Listen to the voice samples in `bench-out/` and review `bench-out/translations-*.jsonl`.
3. One real call per platform with a consenting second participant; fill this table with PASS/FAIL and what was heard.
