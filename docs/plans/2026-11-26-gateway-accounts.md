# Gateway account and own-keys modes — implementation plan (step 3 of the accounts design)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The hosted gateway serves people who signed in with an account (it checks the token with the site, counts
usage and charges the account's balance) and people who bring their own provider keys, without slowing a turn down.

**Architecture:** `POST /v1/sessions` reads a `mode` from its JSON body. Account mode asks the site to authorize the
bearer token over the site's local Gunicorn socket (signed with a shared secret); keys mode builds a provider factory
from the keys in the body for that one session. An admission object enforces the caps. In account mode each
direction pipeline adds audio milliseconds and synthesized characters to a per-session meter; a reporter sends the
increments to the site every 10 seconds, off the audio path, and pushes the remaining balance to the client.

**Tech stack:** Node 24 + TypeScript (run directly, no build) + zod + `node --test`; `node:http` over a unix socket for
the site; systemd + nginx on the server (unchanged nginx).

**Spec:** `docs/specs/2026-11-26-accounts-paid-service-voices-design.md` — "Three ways to connect", "Hosted gateway",
"Billing units", "Voices" (account-mode list), "Latency check". The site's side of every call is in the site's API
contract, handed to you with this plan (it lives outside this repo).

## Global constraints

- Latency first: nothing added here may run on the per-frame or per-turn path except integer additions. Site calls
  happen once at session creation and every 10 seconds in the background; a slow or failed report never delays audio.
- Billing units are computed by the site. The gateway reports raw counters only: `stt_ms_out`, `stt_ms_in` (audio
  milliseconds forwarded to speech-to-text per lane), `tts_chars` (characters sent to speech synthesis).
- Reports every 10 seconds and at the end, each with a sequence number; a retried report resends the identical body.
- Balance reaches zero → fatal `balance_exhausted`. Three reports in a row fail → fatal `billing_unavailable`.
- No speech on either lane for 10 minutes → fatal `idle_timeout`.
- Keys and tokens are never logged, never written to disk, and live in memory for one session only; a test asserts
  that none of them reaches the log.
- Protocol version stays 1. A request with no body still means today's static-token mode, byte for byte.
- Server details (addresses, socket paths, other services) never go into this repo; they live in the server's `.env`.
- Never run bare `python`; use `python3`. No key or token is printed. `.env`, `bench-out/` and `dist/` are never committed.
- Commit messages are the owner's: no `Co-Authored-By` and no tool attribution. Style: `Gateway: what changed`.
- Work on a branch cut from `main`. Nothing is pushed, merged or deployed without the owner saying so.

## What the app can rely on (the app plan builds against exactly this)

`POST /v1/sessions`

| Mode | Request | Success | Failures |
|---|---|---|---|
| token | no body, or `{"mode":"token"}`; `Authorization: Bearer <static token>` | `201 {session_id, token, expires_in, ws_path}` (as today) | `401 unauthorized` (also when no static token is configured) |
| account | `{"mode":"account"}`; `Authorization: Bearer lba_…` | the same `201` plus `"account": {"balance_units": N}` | `401 invalid_token` (refresh, retry once); `402 balance_empty`; `503 billing_unavailable` (site unreachable); `503 accounts_unavailable` (not configured) |
| keys | `{"mode":"keys","elevenlabs_api_key":"…","gemini_api_key":"…"}`, no `Authorization` | the same `201` as token | `400 bad_request` (missing or malformed key) |

All modes: `429 rate_limited` (per caller) and `429 session_limit` (a cap is full). A body over 4 KB or that is not
JSON → `400 bad_request`. When an account already has a live session, admitting a new one closes the old one with the
fatal error `session_replaced` (so the app's automatic reconnect is never refused by its own dead session).

`GET /v1/voices` — authorized by one of: `Authorization: Bearer <static token>`; `Authorization: Bearer lba_…`
(account: only the approved list); header `X-ElevenLabs-Api-Key: <key>` (keys: that account's voices). Errors:
`401 unauthorized` / `401 invalid_token` / `401 invalid_key` (the provider refused the key), `502 voices_unavailable`.

WebSocket, account mode only: `{"v":1,"type":"account.balance","balance_units":N}` right after the first
`session.ready` and after every successful report. New fatal `error` codes: `balance_exhausted`,
`billing_unavailable`, `idle_timeout`, `session_replaced`.

## Review focus

1. **The site is down when a session starts.** Account mode answers `503 billing_unavailable` within 3 s; token and
   keys modes are unaffected. (Test in Task 5.)
2. **A report is lost after the site charged it.** The retry carries the same `seq` and body, the site answers
   `charged_units: 0`, and the meter does not count the usage twice or drop the usage that arrived meanwhile. (Test in
   Task 6.)
3. **A long silence with the session open** (person on hold). After 10 minutes with no recognised speech the session
   ends with `idle_timeout`, its slot frees, and the next start is admitted. (Test in Task 7.)
4. **A trial-only account when the service is nearly full.** It gets `429 session_limit` while a paying account is
   still admitted into the reserved slots. (Test in Task 4.)
5. **Own keys that are wrong.** The session request is accepted (keys are not checked up front), and the pipelines
   fail with the existing provider errors in words; `GET /v1/voices` with a bad key answers `401 invalid_key`. Neither
   path logs the key. (Tests in Tasks 5 and 8.)

---

### Task 1: Protocol — the request body, the balance message and the new error codes

**Files:**
- Modify: `packages/protocol/src/messages.ts`
- Test: `packages/protocol/test/protocol.test.ts`

**Interfaces:**
- Produces: `sessionRequest` (zod) and `type SessionRequest = { mode: "token" } | { mode: "account" } | { mode: "keys";
  elevenlabs_api_key: string; gemini_api_key: string }`; `parseSessionRequest(body: string): SessionRequest | { error:
  string }` (empty string → `{ mode: "token" }`); `ErrorCode` gains `"balance_exhausted" | "billing_unavailable" |
  "idle_timeout" | "session_replaced"`; `ServerMessage` gains `{ v: 1; type: "account.balance"; balance_units: number }`.

- [ ] **Step 1: Write the failing tests** — `parseSessionRequest("")` → `{mode:"token"}`; `{"mode":"account"}` parses;
  keys with both keys parses; keys missing `gemini_api_key` → `error`; a key with a space or longer than 256 chars →
  `error`; an unknown mode → `error`; a non-JSON string → `error`. Key shape: 16–256 printable ASCII without
  whitespace (`/^[\x21-\x7e]{16,256}$/`).
- [ ] **Step 2: Run** `npm test` — the new tests fail.
- [ ] **Step 3: Implement** in `messages.ts` next to `parseClientMessage`.
- [ ] **Step 4: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 5: Commit** `Protocol: session request modes and the account balance message`

### Task 2: Configuration

**Files:**
- Modify: `services/gateway/src/config.ts`, `.env.example`
- Test: `services/gateway/test/unit.test.ts`

**Interfaces:**
- Produces on `Config`: `GATEWAY_ACCESS_TOKEN` may now be `""` (token mode off) — otherwise still at least 32 chars;
  `SITE_SOCKET_PATH: string` (default `""`), `SITE_HOST: string` (default `"jaysonkhan.com"`),
  `LIVEBRIDGE_GATEWAY_SECRET: string` (default `""`, else at least 32 chars), `accountsEnabled: boolean` (both
  previous two set); `ACCOUNT_VOICE_IDS` (csv) → `accountVoiceIds: string[]`; `MAX_ACCOUNT_SESSIONS` and
  `MAX_KEYS_SESSIONS` (default: `MAX_SESSIONS`); `PAID_RESERVED_SESSIONS` (default `0`); `IDLE_TIMEOUT_MINUTES`
  (default `10`, `0` disables); `USAGE_REPORT_SECONDS` (default `10`, min `2`).

- [ ] **Step 1: Write the failing tests** — empty `GATEWAY_ACCESS_TOKEN` loads; a 10-char one is refused; a secret
  under 32 chars is refused and the error text does not contain the value; `accountsEnabled` is false unless both
  `SITE_SOCKET_PATH` and `LIVEBRIDGE_GATEWAY_SECRET` are set; caps default to `MAX_SESSIONS`.
- [ ] **Step 2: Run** `npm test` — fail.
- [ ] **Step 3: Implement**; document each key in `.env.example` with a one-line comment and placeholder values only.
- [ ] **Step 4: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 5: Commit** `Gateway: settings for accounts, own keys and caps`

### Task 3: Site client

**Files:**
- Create: `services/gateway/src/site.ts`
- Test: `services/gateway/test/site.test.ts` (a `node:http` server listening on a temporary unix socket)

**Interfaces:**
- Consumes: `Config.SITE_SOCKET_PATH`, `SITE_HOST`, `LIVEBRIDGE_GATEWAY_SECRET`.
- Produces: `createSiteClient(opts: { socketPath: string; host: string; secret: string; timeoutMs?: number; now?: () =>
  number }): SiteClient` with
  `authorize(accessToken: string): Promise<{ accountId: string; balanceUnits: number; hasPurchase: boolean }>` and
  `usage(report: UsageReport): Promise<{ chargedUnits: number; balanceUnits: number }>`, where `UsageReport = {
  account_id: string; session_id: string; seq: number; stt_ms_out: number; stt_ms_in: number; tts_chars: number }`.
  Failures throw `SiteError` with `code: "invalid_token" | "unknown_account" | "bad_request" | "unavailable"`.

- [ ] **Step 1: Write the failing tests** — the fake site checks every request: path `/internal/livebridge/v1/authorize/`
  or `/internal/livebridge/v1/usage/`, `Host: jaysonkhan.com`, `X-Forwarded-Proto: https`, `Content-Type:
  application/json`, `X-LiveBridge-Timestamp` = unix seconds, `X-LiveBridge-Signature` = hex HMAC-SHA256 of
  `"<timestamp>." + raw body` with the secret, and no `X-Real-IP` / `X-Forwarded-For`. Cases: authorize 200 → mapped
  result; 401 → `invalid_token`; usage 200 → mapped; 404 → `unknown_account`; a server that never answers →
  `unavailable` after `timeoutMs` (default 3000); a missing socket file → `unavailable`.
- [ ] **Step 2: Run** `npm test` — fail.
- [ ] **Step 3: Implement** with `http.request({ socketPath, method: "POST", path, headers })`; the token is only ever in
  the request body; nothing in this module logs.
- [ ] **Step 4: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 5: Commit** `Gateway: signed calls to the site over its local socket`

### Task 4: Admission — caps, reserved slots, one session per account

**Files:**
- Create: `services/gateway/src/admission.ts`
- Test: `services/gateway/test/admission.test.ts`

**Interfaces:**
- Produces: `class Admission` constructed from `{ total, account, keys, paidReserved }` with
  `admit(who: { mode: "token" } | { mode: "keys" } | { mode: "account"; accountId: string; hasPurchase: boolean }):
  { ok: true; ticket: Ticket; replaces?: Ticket } | { ok: false }` and `release(ticket: Ticket): void`.
  `replaces` is the account's earlier ticket; the caller closes that session with `session_replaced`.

- [ ] **Step 1: Write the failing tests** (table-driven): total cap counts all modes; account cap and keys cap are
  separate; with `account: 4, paidReserved: 1`, a trial-only account is refused when 3 account slots are taken while
  a paying one is admitted; a second admit for the same account returns `replaces` and does not use a second slot;
  `release` frees the slot exactly once (double release is harmless).
- [ ] **Step 2: Run** `npm test` — fail.
- [ ] **Step 3: Implement** as a plain class with counters and a `Map<accountId, Ticket>`; no timers, no I/O.
- [ ] **Step 4: Run** `npm test` — pass.
- [ ] **Step 5: Commit** `Gateway: session admission with per-mode caps`

### Task 5: `POST /v1/sessions` in three modes

**Files:**
- Modify: `services/gateway/src/server.ts`, `services/gateway/src/session.ts`, `services/gateway/src/main.ts`,
  `services/gateway/src/providers/real.ts` (only if a key override needs a new parameter)
- Test: `tests/integration/gateway.test.ts` (fake providers, fake site from Task 3's test helpers moved into
  `tests/integration/helpers.ts`)

**Interfaces:**
- Consumes: `parseSessionRequest` (Task 1), `createSiteClient` (Task 3), `Admission` (Task 4).
- Produces: `GatewayOptions` gains `site?: SiteClient` and `providersFor?: (keys: { elevenlabs: string; gemini: string })
  => ProviderFactory` (default: `createRealProviders({ ...config, ELEVENLABS_API_KEY, GEMINI_API_KEY }, log)`; in fake
  mode the fake factory). `SessionDeps` gains `auth: SessionAuth` where `SessionAuth = { mode: "token" } | { mode:
  "keys" } | { mode: "account"; accountId: string; hasPurchase: boolean; balanceUnits: number }`, plus `site?:
  SiteClient` and `onClosed(): void` (releases the admission ticket).

- [ ] **Step 1: Write the failing tests** — empty body + static token → 201 exactly as before; account + good token →
  201 with `account.balance_units`, and the socket then receives `account.balance` after `session.ready`; account +
  token the site refuses → `401 invalid_token`; balance 0 → `402 balance_empty`; site socket missing → `503
  billing_unavailable` in under 3.5 s; accounts not configured → `503 accounts_unavailable`; keys mode → 201 and the
  session's pipelines were built by `providersFor` with exactly those keys; keys missing → `400 bad_request`; the same
  account twice → the first socket receives fatal `session_replaced` and closes, the second is ready; a full cap →
  `429 session_limit`; 5 KB body → `400 bad_request`.
- [ ] **Step 2: Add the secret-leak test** — run account, keys and token sessions through one test logger that keeps
  every line, then assert that no line contains the access token, either provider key or the static token.
- [ ] **Step 3: Run** `npm test` — fail.
- [ ] **Step 4: Implement.** The pending entry carries the session's `SessionAuth` (and the keys' factory for keys
  mode); the upgrade hands both to `Session`. Admission happens at `POST` time and the ticket is released when the
  pending token expires unused or the session closes. Keys are dropped from the pending map the moment the upgrade
  consumes it.
- [ ] **Step 5: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 6: Commit** `Gateway: account and own-keys sessions`

### Task 6: Counting usage and reporting it

**Files:**
- Create: `services/gateway/src/billing.ts`
- Modify: `services/gateway/src/pipeline.ts` (two hook calls), `services/gateway/src/session.ts`
- Test: `services/gateway/test/billing.test.ts` (with `node:test` `mock.timers`)

**Interfaces:**
- Produces: `class UsageMeter` with `addStt(direction: Direction, bytes: number): void` (16 kHz s16le mono, so
  `ms = bytes / 32`), `addTts(text: string): void` (counts code points: `[...text].length`), and `take(): { sttMsOut:
  number; sttMsIn: number; ttsChars: number }` (returns and clears the increment). `class BillingReporter` constructed
  with `{ site, accountId, sessionId, meter, everyMs, onBalance(units: number): void, onFatal(code:
  "balance_exhausted" | "billing_unavailable"): void }`, with `start()` and `async stop(): Promise<void>` (final report,
  up to 3 attempts, then gives up quietly).
- `PipelineDeps` gains `meter?: UsageMeter`: `onCaptureFrame` calls `meter.addStt(direction, payload.byteLength -
  overflow)` after `stt.sendAudio`; `speak` calls `meter.addTts(text)` just before `tts.synthesize`. Nothing else in
  the pipeline changes.

- [ ] **Step 1: Write the failing tests** — 32 000 bytes on `out` → `sttMsOut: 1000`; dropped bytes are not counted;
  `addTts("o'zbek 👋")` counts 8; reporter: one tick sends seq 0 with the increment and calls `onBalance`; a zero
  increment sends nothing; a failed report is retried next tick with the identical body while new usage waits in the
  meter, and the next successful report carries seq 1 with that new usage; three failures in a row → `onFatal
  ("billing_unavailable")`; `balance_units: 0` → `onFatal("balance_exhausted")`; an increment above the site's limits
  (120 000 ms per lane, 20 000 chars) is split across consecutive seqs; `stop()` sends the remainder.
- [ ] **Step 2: Run** `npm test` — fail.
- [ ] **Step 3: Implement.** In account mode `Session` creates the meter, passes it to both pipelines, starts the
  reporter at `session.ready`, sends `account.balance` with the balance from authorization right after the first
  `session.ready`, forwards `onBalance` as `account.balance`, maps `onFatal` to `fail(code, …)`, and calls `stop()`
  from `close()` without awaiting it.
- [ ] **Step 4: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 5: Commit** `Gateway: usage counting and balance reports`

### Task 7: Idle timeout

**Files:**
- Modify: `services/gateway/src/session.ts`, `services/gateway/src/pipeline.ts` (one callback)
- Test: `services/gateway/test/unit.test.ts` or `tests/integration/gateway.test.ts` (`mock.timers`)

**Interfaces:**
- `PipelineDeps` gains `onSpeech(): void`, called on every STT partial and committed text.

- [ ] **Step 1: Write the failing test** — a ready session with no partials for `IDLE_TIMEOUT_MINUTES` receives fatal
  `idle_timeout` and its admission slot is free; a partial at minute 9 pushes the deadline to minute 19; `0` disables.
- [ ] **Step 2: Run** — fail. **Step 3: Implement** with one timer re-armed by `onSpeech`. **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `Gateway: sessions without speech end after ten minutes`

### Task 8: Voices per mode

**Files:**
- Modify: `services/gateway/src/server.ts`, `services/gateway/src/session.ts` (configure check)
- Test: `tests/integration/gateway.test.ts`

**Interfaces:**
- Account-mode list = voices whose id is in `accountVoiceIds` or is one of the two configured default voices; when
  `accountVoiceIds` is empty, the provider's stock voices (`category === "premade"`) plus the two defaults. Keys mode:
  that key's whole list, cached 10 minutes per SHA-256 of the key, at most 50 keys cached (oldest evicted).

- [ ] **Step 1: Write the failing tests** — account bearer → filtered list (a cloned voice not on the list is absent);
  site refuses → `401 invalid_token`; `X-ElevenLabs-Api-Key` → that list from a factory built with the key; provider
  says 401 → `401 invalid_key`; two calls with the same key within 10 minutes ask the provider once; in an account
  session, `session.configure` naming a voice outside the list → `bad_message` and the session does not start.
- [ ] **Step 2: Run** — fail. **Step 3: Implement.** **Step 4: Run** `npm test && npm run typecheck` — pass.
- [ ] **Step 5: Commit** `Gateway: voice list by connection mode`

### Task 9: Server, documents, deploy and the latency check

**Files:**
- Modify: `infra/livebridge-gateway.service` (`RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`), `docs/deployment.md`
  (new `.env` keys and how to add them), `docs/privacy.md` (hosted gateway: audio and text pass through and are not
  stored; account usage counters are seconds and characters, never content; own keys travel over TLS and live in
  memory for one session), `services/gateway/scripts/bench.ts` (a `--mode account|keys|token` option)

- [ ] **Step 1: Ask the owner which ElevenLabs plan the service runs on** (or read it with
  `GET /v1/user/subscription` if the key allows) and propose `MAX_SESSIONS` (half of the plan's realtime
  speech-to-text concurrency, minus a margin of one), `MAX_ACCOUNT_SESSIONS`, `MAX_KEYS_SESSIONS` and
  `PAID_RESERVED_SESSIONS`. Ask him too which voices account users may choose (`ACCOUNT_VOICE_IDS`; until he lists
  any, the stock voices plus the two defaults). Wait for his answers.
- [ ] **Step 2: Give the owner the exact lines to add to the gateway's `.env` on the server himself** —
  `SITE_SOCKET_PATH` (the site's Gunicorn socket; its path is in the workspace's server reference, not here),
  `LIVEBRIDGE_GATEWAY_SECRET` (the same value as in the site's `.env`; give him a one-line command that copies it
  between the two files without printing it), and the caps. Do not edit server files yourself.
- [ ] **Step 3: With the owner's go-ahead**, install the changed unit (`sudo cp … && sudo systemctl daemon-reload`), run
  `LIVEBRIDGE_SSH_HOST=<alias> ./deploy.sh`, and check `healthz`, `git rev-parse HEAD` == `origin/main`, and
  `./deploy.sh --logs` for a clean start.
- [ ] **Step 4: Check every mode for real.** Token mode with the owner's current app: one translated turn. Account
  mode: the owner connects a test device once in his browser (device flow on the site); a session starts, the balance
  message arrives, and after a minute of speech the site's account history shows usage. Keys mode: through the bench
  script with keys the owner supplies at that moment (never stored in a file).
- [ ] **Step 5: Latency check.** The same phrases through `bench.ts` in token and account mode on the hosted gateway:
  per-turn `stt_commit_ms`, `translate_*`, `tts_*` medians within noise of each other; session creation time in
  account mode reported separately. Put the figures in `docs/benchmark.md` (timings only).
- [ ] **Step 6: Commit** `Infra: the gateway reaches the site over its local socket` and `Docs: accounts on the hosted
  gateway`, then report to the owner.

## What this plan leaves out on purpose

- The app side (onboarding, account chip, top up): `docs/plans/2026-11-26-app-onboarding.md`.
- Per-direction prices or a separate translation charge: rates stay site settings.
- Persisting sessions across a gateway restart: a restart ends sessions; the app reconnects.
