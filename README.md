# LiveBridge AI

Personal-use macOS real-time speech interpreter for Zoom, Google Meet and Upwork calls: Uzbek ↔ English by default,
any pair of the 90 languages that both speech models support (`packages/protocol/src/languages.ts`),
outgoing speech in a synthesized voice through a virtual microphone, incoming speech as captions and audio in your language.
Other participants install nothing.

**Read `IMPLEMENTATION_STATUS.md` first** — it says exactly what is verified and what is blocked. In short: it runs
end to end with the real providers on real audio hardware (translated speech audible a median ~1.4 s after the
speaker stops, measured with synthetic speech); the BlackHole driver, the incoming direction with real meeting
audio, the server deployment and any real call are still untested.

## Layout

```text
apps/desktop/                     Flutter UI (lib/), widget tests, integration test
apps/desktop/native/LiveBridgeAudio/   Swift audio engine (library + `lbaudio` CLI + unit tests)
apps/desktop/macos/               Xcode Runner: links the engine, method/event channels, permissions
services/gateway/                 Node/TypeScript gateway: sessions, pipelines, provider adapters, probe, bench
packages/protocol/                Wire protocol: binary frame + JSON messages, shared fixtures
tests/integration/                Gateway and adapter tests (fake providers, mock provider servers)
tests/fixtures/                   Synthetic benchmark sentences
infra/                            Dockerfile, compose, systemd unit, nginx sample
docs/                             Setup guide (Uzbek), deployment, privacy, benchmark, manual QA, bridge contract
```

## Quick start (no keys needed — fake providers)

```bash
npm install
export LB_TOKEN=$(openssl rand -base64 36) && echo "access token: $LB_TOKEN"
PROVIDER_MODE=fake GATEWAY_ACCESS_TOKEN=$LB_TOKEN npm run gateway

cd apps/desktop && flutter build macos --release
open build/macos/Build/Products/Release/livebridge.app
```

In the app: Mode **Captions only**, Gateway URL `http://127.0.0.1:8201`, paste the token, **Start session**, hold
**Space** and speak. You will see placeholder text under a `MOCK PROVIDERS` banner — not a translation.

For real translation: fill `.env` from `.env.example`, run `npm run probe`, then `npm run gateway`.
Full instructions: `docs/setup-guide.md`.

### Voice

Both directions default to **JaysonKhan - Natural Uzbek Voice** (`ehTFHBkERkWR22A3sR8M`) — the author's own voice,
published by the author in the ElevenLabs Voice Library; it speaks English, Russian, Uzbek and Turkish. Voice Library
voices need a paid ElevenLabs plan. If your account rejects the id, add the voice to *My Voices* from the Voice
Library and use the id shown there. To speak in your own voice, put your clone's id in `ELEVENLABS_OWNER_VOICE_ID`.

## Tests

```bash
npm run typecheck && npm test                               # protocol, gateway, adapters vs mock servers, bench harness
(cd apps/desktop/native/LiveBridgeAudio && swift test)      # ring buffer, frame codec fixtures, resampler, devices
(cd apps/desktop && flutter analyze && flutter test)        # UI
# real app + real engine + microphone against a fake gateway (see the header of the test file):
(cd apps/desktop && LIVEBRIDGE_EPHEMERAL_SETTINGS=1 flutter test integration_test/session_test.dart -d macos --dart-define=LB_TOKEN=<token>)
```

## Scope

In: captions, push-to-talk and automatic outgoing speech, incoming Uzbek audio, mute, panic stop, explicit
microphone bypass, interface in Uzbek / Russian / Turkish / English, on-demand export of the conversation text, and
a local numbers-only analytics log (latency, errors, your ratings) with **opt-in** sharing of those numbers and a
feedback form (`docs/telemetry-api.md`, `docs/privacy.md`).
Out (by design): meeting bots, browser extensions, audio recording, automatic answers, covert use, Windows/iOS.

## License

MIT — see `LICENSE`. BlackHole (GPL-3.0) is a separate install and is not part of this repository.
