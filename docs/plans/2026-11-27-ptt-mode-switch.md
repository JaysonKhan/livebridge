# Push-to-talk area: mode switch and live waveform (variant D) — plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development for every code task.

**Goal:** Above the talk bar, a segmented switch "Bosib turib | Avtomatik" (hold to talk / automatic) that works
during a running session without restarting it. The bar becomes a live waveform panel: brand-teal bars that move
with the real microphone level whenever the microphone is actually being sent, flat muted bars otherwise.

**Architecture:** The app's outgoing turn mode (`outCommit`) stays the one setting; the switch and the setup list
both change it. During a session the app pushes every change to the host (`setOutCommit`); the host adjusts the
capture window and tells the gateway (`turn.mode`); the gateway swaps the direction's speech-to-text session to the
new commit strategy. Hold mode keeps running on a `manual` speech-to-text session, automatic mode on `vad` /
`turn_prediction` — exactly what each mode runs on today.

## Decision record

**Why not "always turn detection, gate the microphone in hold mode"** (the simpler idea, no gateway change):
measured on 2026-11-27 against the live speech-to-text API (`scribe_v3_live`, a 4.2 s English clip ending in speech,
`commit: true` on the last chunk, 10 runs per strategy, interleaved):

| Session strategy | Commit → committed transcript, typical runs | Median |
|---|---|---|
| `manual` | 237, 241, 242, 244, 264, 268 ms | ≈ 250 ms |
| `vad` | 285, 298, 299, 304, 312 ms | ≈ 300 ms |
| `turn_prediction` | 240, 285, 292, 300, 306, 307, 308, 325, 331 ms | ≈ 305 ms |

(Network outliers of 0.5–4.9 s occurred in every strategy and are left out of the typical runs.)

So a manual commit **is honoured** under `vad` and `turn_prediction` (no duplicate transcript follows, and without
the commit the detector waits for trailing silence), but it is about 50 ms slower than in a `manual` session. Hold
to talk is the default mode, so that idea would slow the main path. A pause inside a long hold would also split the
phrase. Rejected: latency first.

**Chosen:** the gateway swaps the speech-to-text session on a mode change. Per-turn latency is unchanged in both
modes. The swap itself costs one provider handshake from the gateway, at switch time only, and audio keeps flowing
to the old session until the new one is open (make before break), so nothing said around the switch is lost and the
direction never stops being ready.

**Older gateways** do not announce `turn.mode`. The host then keeps the running session's mode, emits
`mode_switch_unsupported` and the app moves the switch back with a message (stop and start to change the mode).

## Contract changes

### Protocol (`packages/protocol/src/messages.ts`, version stays 1)

- Client → gateway: `{ v: 1, type: "turn.mode", direction, commit }` — `commit` one of `manual`, `vad`,
  `turn_prediction`. The direction uses this strategy for the rest of the session (reconnects included). The same
  strategy again does nothing.
- Gateway behaviour: a new speech-to-text session with the new strategy is opened; until it is open, captured audio
  still goes to the old one. Then the new session takes over and the old one is committed — whatever was said under
  the old strategy becomes a turn — and closed after its answer (at most 8 s later). If the new session cannot be
  opened, the direction goes through the normal provider-down path (reconnects use the new strategy).
- `session.ready` gains `features: string[]`; `"turn.mode"` in it = the message is accepted.

### Bridge (`docs/bridge-contract.md`)

- Method `setOutCommit` `{commit}` — the outgoing turn mode of the running session and its reconnects.
  - Leaving `manual` while the talk button is held = a release: the phrase is committed.
  - Entering `manual`: the hands-free capture window is paused; what was being said is committed by the gateway.
  - Entering `vad` / `turn_prediction`: the capture window opens as at session start (same conditions: direction
    ready, not muted, no bypass).
  - No session: nothing happens. Not connected yet / reconnecting: the next `session.configure` carries it.
  - Gateway without `turn.mode`: the mode in force stays, a non-fatal `error` `mode_switch_unsupported` follows a
    `state` event that shows the mode in force.
- `state` event: `outCommit` (already sent for the analytics log) is documented — the mode in force.
- Preference key `outAutoCommit` (`vad` | `turn_prediction`, default `vad`): the strategy "Avtomatik" stands for.

### App

- `outCommit` stays the one setting. The switch: "Bosib turib" = `manual`, "Avtomatik" = `outAutoCommit`. The setup
  list keeps its three rows and mirrors the switch; choosing VAD or turn prediction there also sets `outAutoCommit`.
- During a session every change of `outCommit` (from either place) is sent with `setOutCommit`. On
  `mode_switch_unsupported` the setting goes back to the state's `outCommit`.
- Space stays push-to-talk and works in hold mode only, as today.

## Panel states

| State | Panel | Bars | Text (uz) |
|---|---|---|---|
| No session | neutral | flat, muted | Sessiya boshlanganda ishlaydi |
| Connecting / reconnecting / outgoing not ready | neutral | flat, muted | Ulanmoqda… |
| Hold, ready | neutral, pressable | flat, muted | Bosib turing yoki Probel |
| Hold, held | teal | live | Gapiring… qo'yib yuborsangiz yuboriladi |
| Automatic, listening | teal | live | Tinglayapman — pauzada o'zi yuboradi |
| Outgoing muted | neutral | flat, muted, mic-off icon | Mikrofon o'chiq — hech narsa yuborilmaydi |
| Bypass on | amber outline | flat | Tarjimasiz — mikrofon to'g'ridan-to'g'ri qo'ng'iroqda |

Bars: one bar per `meters` event (about 10 a second), newest on the right, `mic` dBFS mapped from −60…−10 dB to the
bar height; only while the microphone is being sent. Reduced motion: no easing, the bars still follow the level.

## Tasks

1. **Protocol + gateway** — `turn.mode` parse; `features` in `session.ready`; `DirectionPipeline.setCommit` (make
   before break, retiring session answered once, cancel/close drop it). Tests (fake providers): switch manual→vad
   then speech + silence commits without `turn.commit`; vad→manual then speech is not committed until `turn.commit`;
   speech in flight at the switch is translated; the same strategy opens no new session; a cancel during the swap
   drops the retiring session's transcript; protocol parse accepts/refuses.
2. **macOS host** (`Engine.swift`, `MainFlutterWindow.swift`) — `setOutCommit`, `features`, sync on `session.ready`.
   `swift test`: messages sent for each transition, held release, unsupported gateway, reconnect configure.
3. **Windows host** (`livebridge_core` engine + runner channel) — the same behaviour; core tests mirror task 2.
4. **App state** — `LiveBridge.setOutCommit`, `StateEvent.outCommit`, `SetupState.outAutoCommit` (saved),
   session listener, revert on unsupported. Unit tests.
5. **App UI** — segmented switch + waveform panel, strings in uz/ru/tr/en; widget tests for every state; orphaned
   strings removed.
6. **Docs** — bridge contract, `IMPLEMENTATION_STATUS.md`, README usage line.
7. **Verification** — `npm test`, `npm run typecheck`, `flutter analyze`, `flutter test`, `swift test`,
   `livebridge_core/tests/run.sh`; screenshots of every state in uz/ru/tr/en × light/dark × macOS/Windows looks;
   a real run on the Mac switching modes mid-session (hosted gateway once the owner deploys it; until then a local
   gateway with the real providers).

## Constraints

- Nothing adds latency to a turn. Dart formatted with `dart format lib test` (width 120 from
  `analysis_options.yaml`). Never bare `python`. No secrets printed or committed. Commits read as the owner's, no
  attribution. No push, merge, deploy or release without the owner's word. Work on `claude/ptt-mode-switch` from
  `main`; rebase after the bug-report branch lands.
