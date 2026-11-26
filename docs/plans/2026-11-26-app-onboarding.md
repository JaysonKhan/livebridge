# App onboarding, Google sign-in and the account — implementation plan (step 4 of the accounts design)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On first launch the app offers "Sign in with Google" (through jaysonkhan.com's device sign-in) or the
person's own keys, then shows the balance, lets them top up, and runs sessions on the hosted gateway in the chosen
mode — on macOS and Windows.

**Architecture:** Dart owns the account: it talks to the site's app API over HTTPS (`dart:io`, like `voices_client.dart`),
keeps the access token in memory and the refresh token in the Keychain / Credential Manager through the existing
settings methods, and hands each `start` a fresh access token plus a `connection` mode. Both native hosts only build
the right `POST /v1/sessions` request, accept a newer access token for reconnects, store the new secret items, and turn
the gateway's `account.balance` message into a `balance` event. Browser pages open with `url_launcher`.

**Tech stack:** Flutter + Riverpod 3 (`apps/desktop`), `url_launcher` (new, official); Swift package
`LiveBridgeAudio` + `macos/Runner` (macOS host); C++17 `livebridge_core` + `windows/runner` (Windows host).

**Spec:** `docs/specs/2026-11-26-accounts-paid-service-voices-design.md` — "Three ways to connect", "Site" (sign-in from
the app), "App: onboarding and account", "Voices" (choice per mode), "Documents". The gateway side is
`docs/plans/2026-11-26-gateway-accounts.md`, section "What the app can rely on" — build against exactly that. The
site's app API contract is handed to you with this plan (it lives outside this repo); its essentials are below.

## Global constraints

- Hosted gateway `https://bridge.jaysonkhan.com`, site `https://jaysonkhan.com`; both overridable for tests with
  `--dart-define=LIVEBRIDGE_GATEWAY=…` / `LIVEBRIDGE_SITE=…`.
- Apple sign-in is not built (no Apple Developer Program yet). Only the Google button.
- Secrets — refresh token, provider keys, static gateway token — live only in the Keychain / Credential Manager; the
  access token (15 minutes) lives only in memory. Nothing secret is logged, printed or committed.
- The app refreshes one request at a time and saves the new refresh token before using the new access token (the site
  signs the device out when a retired refresh token is presented).
- Existing installs with a saved static token become "own gateway" and never see the onboarding screen.
- Nothing here touches the audio path or adds a round trip to a turn; at most one refresh before `start`.
- Every new string exists in uz, ru, tr and en ARB files; `flutter gen-l10n` regenerates the Dart.
- Before anything is shown to the owner: screenshots of the real app in uz, ru, tr and en, light and dark, macOS and
  Windows looks, window chrome included — onboarding (closed, keys open, own gateway open), waiting for the browser,
  main screen with the chip and its menu, top-up sheet, empty balance, `balance_exhausted` banner — checked for
  clipping and overlap.
- Dart: `dart format lib test` (page width 120 comes from `analysis_options.yaml`; never pass `--line-length`).
- Never run bare `python`; use `python3`. `.env`, `bench-out/` and `dist/` are never committed.
- Commit messages are the owner's: no `Co-Authored-By` and no tool attribution. Style: `App: …`, `macOS host: …`,
  `Windows host: …`, `Docs: …`.
- Work on a branch cut from `main`. Nothing is pushed, merged or released without the owner saying so. macOS is built
  and verified first; the Windows host gets the same change and must pass the Windows workflow.

## Site app API essentials (`https://jaysonkhan.com/api/livebridge/v1/`, JSON, errors `{"error": code}`)

| Call | Request | Answer |
|---|---|---|
| `POST device/start/` | `{device_id (8–64 of A-Z a-z 0-9 _ -), device_name (≤ 80)}` | `201 {device_code, user_code, verification_uri, verification_uri_complete, expires_in: 600, interval: 5}`; `429 rate_limited` |
| `POST device/token/` | `{device_code}` | `200 {access_token, refresh_token, token_type, expires_in: 900}`; `400` `authorization_pending` / `slow_down` (+5 s) / `expired_token` / `access_denied` / `invalid_grant` |
| `POST token/refresh/` | `{refresh_token}` | `200` same pair; `401 invalid_grant` → signed out |
| `POST logout/` | bearer | `204` |
| `GET me/` | bearer | `200 {account_id, email, name, balance_units, units_per_minute, rates: {stt_units_per_second, tts_units_per_char}, has_purchase}` |
| `GET packages/` | — | `200 [{code, price_cents, currency, units, minutes}]` |
| `POST checkout/` | bearer, `{package}` | `201 {url}`; `429 rate_limited`; `503 checkout_unavailable` |

Bearer calls answer `401 invalid_token` when the access token is stale: refresh, retry once. The verification page
is under `/en/`; swap the prefix to the interface language (`uz` → `/uz/`, `ru` → `/ru/`, `tr` and `en` → `/en/`).

## Review focus

1. **Two refreshes at once, or a lost refresh answer.** One refresh is in flight at a time; every caller awaits it;
   the new refresh token is saved before the access token is used. (Test in Task 3.)
2. **Saving the start settings in account mode.** `saveSettings` must never write the short-lived access token or the
   provider keys into the static-token slot. (Test in Task 4.)
3. **The access token expires mid-call and the connection drops.** Dart refreshes in the background and calls
   `updateAccessToken`; the host's automatic reconnect after 20 minutes uses the new token. (Tests in Tasks 1 and 4.)
4. **The person closes the browser or presses Cancel there.** After `expired_token` or `access_denied` the waiting view
   returns to the sign-in screen with a sentence saying what happened. (Test in Task 5.)
5. **Offline at launch in account mode.** `me/` fails: the chip shows no minutes, Start is not blocked by an unknown
   balance (the gateway answers 402 if it is really empty), and a retry happens when the window regains focus. (Test in
   Task 6.)

---

### Task 1: macOS host — connection modes, secret items, reconnect token, balance event

**Files:**
- Modify: `apps/desktop/native/LiveBridgeAudio/Sources/LiveBridgeAudioCore/Engine.swift` (config, server message,
  `updateAccessToken`), `…/GatewayTransport.swift` (request + status mapping), `apps/desktop/macos/Runner/MainFlutterWindow.swift`
  (Keychain items, new method)
- Test: `apps/desktop/native/LiveBridgeAudio/Tests/LiveBridgeAudioCoreTests/CoreTests.swift`

**Interfaces:**
- `start` config gains `connection` (`token` default, `account`, `keys`), `elevenlabsApiKey`, `geminiApiKey`.
  `accessToken` is required for `token` and `account`; both keys are required for `keys`.
- `static func sessionRequest(baseURL: URL, config: EngineConfig) -> URLRequest` in `GatewayTransport` — token: no
  body (exactly today's request); account: body `{"mode":"account"}` + bearer; keys: body
  `{"mode":"keys","elevenlabs_api_key":…,"gemini_api_key":…}`, no `Authorization`.
- A refused session request emits the gateway's own `error` string when it is one of `unauthorized`, `invalid_token`,
  `balance_empty`, `session_limit`, `rate_limited`, `billing_unavailable`, `accounts_unavailable`, `bad_request`;
  otherwise `gateway_error` as today.
- Method `updateAccessToken {accessToken: String}` replaces the token used by the next reconnect of the running session.
- Server message `account.balance` → event `{type: "balance", balanceUnits: Int}`.
- Keychain items (service `com.jaysonkhan.livebridge`): `accessToken` → account `gateway-access-token` (unchanged),
  `accountRefreshToken` → `account-refresh-token`, `elevenlabsApiKey` → `elevenlabs-api-key`, `geminiApiKey` →
  `gemini-api-key`. `loadSettings` returns the ones present; `saveSettings` with `null` deletes.

- [ ] **Step 1: Write the failing tests** — config parses each mode and refuses keys mode without a key; the three
  requests have the exact bodies and headers above; HTTP 402 `{"error":"balance_empty"}` maps to `balance_empty`, 503
  with an unknown string maps to `gateway_error`; `account.balance` becomes the `balance` event; after
  `updateAccessToken`, the reconnect request carries the new token.
- [ ] **Step 2: Run** `cd apps/desktop/native/LiveBridgeAudio && swift test` — fail.
- [ ] **Step 3: Implement**, then the Runner's Keychain items and `updateAccessToken` routing.
- [ ] **Step 4: Run** `swift test` and `cd apps/desktop && flutter build macos --debug` — pass.
- [ ] **Step 5: Commit** `macOS host: account and own-keys sessions`

### Task 2: Windows host — the same

**Files:**
- Modify: `apps/desktop/native/livebridge_core/src/engine.cpp` (+ header) for `account.balance`,
  `apps/desktop/windows/runner/gateway_socket.cpp`/`.h` (request + status mapping), `…/win_engine_host.cpp` (config,
  `updateAccessToken`), `…/settings_store.cpp` (Credential Manager targets `JK-LiveBridge/account-refresh-token`,
  `JK-LiveBridge/elevenlabs-api-key`, `JK-LiveBridge/gemini-api-key`; `JK-LiveBridge/gateway-access-token` unchanged),
  `…/livebridge_channels.cpp` (method routing)
- Test: `apps/desktop/native/livebridge_core/tests/engine_tests.cpp`

**Interfaces:** identical to Task 1 (same keys, codes, event and method).

- [ ] **Step 1: Write the failing core tests** — `account.balance` → `balance` event with `balanceUnits`; the
  error-code allowlist mapping.
- [ ] **Step 2: Implement** core, then runner (the request bodies mirror `sessionRequest` in Task 1).
- [ ] **Step 3: Verify** — the Windows workflow passes on the branch (CTest runs there; there is no cmake on the Mac).
  Do not push to trigger it before the owner agrees; until then report "Windows not yet built".
- [ ] **Step 4: Commit** `Windows host: account and own-keys sessions`

### Task 3: Account client

**Files:**
- Create: `apps/desktop/lib/bridge/account_client.dart`
- Test: `apps/desktop/test/account_client_test.dart` (a `dart:io` `HttpServer` on `127.0.0.1:0` as the site)

**Interfaces:**
- Produces: `abstract class AccountClient` and `HttpAccountClient(Uri siteBase)` with
  `Future<DeviceStart> startDevice({required String deviceId, required String deviceName})`,
  `Future<DevicePoll> pollDevice(String deviceCode)` (`sealed DevicePoll`: `DevicePending`, `DeviceSlowDown`,
  `DeviceGranted(TokenPair)`, `DeviceExpired`, `DeviceDenied`),
  `Future<TokenPair> refresh(String refreshToken)`, `Future<AccountInfo> me(String accessToken)`,
  `Future<List<Package>> packages()`, `Future<Uri> checkout(String accessToken, String packageCode)`,
  `Future<void> logout(String accessToken)`.
  Errors: `AccountSignedOut` (refresh `invalid_grant`), `AccountTokenStale` (`401 invalid_token`), `AccountError(String
  code)` (`network`, `rate_limited`, `checkout_unavailable`, anything else). `TokenPair {accessToken, refreshToken,
  expiresAt}`; `AccountInfo {email, name, balanceUnits, unitsPerMinute, sttUnitsPerSecond, ttsUnitsPerChar,
  hasPurchase}`; `Package {code, priceCents, units, minutes}`. Timeouts 10 s.
- Produces: `class TokenKeeper` (same file) — `Future<String> accessToken()` refreshes when under 60 s remain, one
  refresh at a time, calling `onRefreshed(TokenPair)` (which saves the refresh token) and awaiting it before returning.

- [ ] **Step 1: Write the failing tests** — each poll answer maps to its class; `slow_down` is surfaced (the caller adds
  5 s); `me/` 401 → `AccountTokenStale`; refresh 401 → `AccountSignedOut`; two concurrent `accessToken()` calls cause
  one refresh request and both get the same token; `onRefreshed` completes before the token is returned; a dropped
  connection → `AccountError('network')`.
- [ ] **Step 2: Run** `cd apps/desktop && flutter test test/account_client_test.dart` — fail.
- [ ] **Step 3: Implement.** **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `App: client for the site's account API`

### Task 4: Connection state and the start path

**Files:**
- Create: `apps/desktop/lib/state/connection_state.dart`
- Modify: `apps/desktop/lib/bridge/models.dart` (`StartConfig`, `BalanceEvent`), `apps/desktop/lib/bridge/live_bridge.dart`
  (`updateAccessToken`), `apps/desktop/lib/state/setup_state.dart`, `apps/desktop/lib/state/session_state.dart`,
  `apps/desktop/lib/state/route_check.dart`, `apps/desktop/lib/state/providers.dart`, `apps/desktop/pubspec.yaml`
  (`url_launcher`), `apps/desktop/test/fake_live_bridge.dart`
- Test: `apps/desktop/test/connection_test.dart`

**Interfaces:**
- `enum ConnectionMode { account, keys, gateway }`; `connectionProvider` (`NotifierProvider<ConnectionNotifier,
  ConnectionState>`); `ConnectionState { ConnectionMode? mode /* null = onboarding */, bool loaded, SignInPhase signIn,
  AccountInfo? account, List<Package> packages, String? notice }`; `sealed SignInPhase`: `SignInIdle`,
  `SignInWaiting(String userCode, Uri page, DateTime expiresAt)`, `SignInFailed(String reason /* expired | denied |
  network | rate_limited */)`.
- `ConnectionNotifier`: `beginSignIn()`, `openPageAgain()`, `cancelSignIn()`, `saveKeys(String elevenlabs, String gemini)`,
  `saveGateway(String url, String token)`, `changeConnection()` (mode → null, saved secrets kept), `signOut()`
  (logout, delete the refresh token, mode → null), `refreshAccount()`, `topUp(String packageCode)`,
  `openAccountPage()`, `Future<StartAuth> authForStart()` (account: a fresh access token from `TokenKeeper`),
  `int? minutesLeft(SessionMode mode)`.
- Minutes estimate per mode, from `me/`: `bidirectional` = `units_per_minute`; `captions` = `2 × 60 ×
  stt_units_per_second`; `incoming` = captions + (`units_per_minute` − captions) / 2. `balance / that`, rounded down.
- Saved keys: preferences `connectionMode` (`account` / `keys` / `gateway`), `deviceId` (24 chars from `[A-Za-z0-9]`,
  `Random.secure`, created once); secret items `accountRefreshToken`, `elevenlabsApiKey`, `geminiApiKey` (Task 1/2).
  Device name: `Platform.localHostname`, at most 80 chars.
- Migration on load: `connectionMode` saved → that; else a saved `accessToken` → `gateway`; else onboarding.
- `StartConfig` gains `connection`, `elevenlabsApiKey`, `geminiApiKey`; `toMap()` includes them for `start`, and a new
  `toSettingsMap()` (what `saveSettings` stores) never contains `accessToken`, either key or `connection` — the static
  token is saved only by `saveGateway`.
- During an account session a timer refreshes the access token when under 3 minutes remain and calls
  `bridge.updateAccessToken`. `BalanceEvent(int balanceUnits)` updates `account.balanceUnits`.
- `start` gets `invalid_token` → one refresh and one retry; a second failure or `AccountSignedOut` → mode null with
  `notice` "signed out". Error codes `balance_empty`, `balance_exhausted`, `billing_unavailable`, `idle_timeout`,
  `session_replaced`, `session_limit` reach the session state for Task 6's banners.
- `startBlockers`: gateway mode keeps "enter address / token"; keys mode needs both keys; account mode adds
  `blockBalanceEmpty` only when the balance is known and 0.

- [ ] **Step 1: Write the failing tests** — migration (static token → gateway, no onboarding); `toSettingsMap()` in
  account mode has no `accessToken`; minutes for 54 000 units at the site's defaults (6000 / 12 / 5): bidirectional 9,
  captions 37, incoming 14; sign-in polling honours `interval` and `slow_down`, saves the refresh token and sets mode
  `account`; `expired_token` → `SignInFailed('expired')`; the refresh timer calls `updateAccessToken` on the fake bridge;
  `invalid_token` on start → one retry with a refreshed token; offline `me/` leaves `account` null and Start unblocked.
- [ ] **Step 2: Run** `flutter test test/connection_test.dart` — fail.
- [ ] **Step 3: Implement.** **Step 4: Run** `flutter analyze && flutter test` — pass.
- [ ] **Step 5: Commit** `App: connection modes, sign-in flow and the account on start`

### Task 5: Onboarding screen

**Files:**
- Create: `apps/desktop/lib/ui/onboarding_screen.dart`, `apps/desktop/lib/ui/google_button.dart`
- Modify: `apps/desktop/lib/ui/app.dart` (onboarding while `mode == null`, nothing until `loaded`), the four ARB files
- Test: `apps/desktop/test/onboarding_test.dart`

**Interfaces / content (spec layout):** logo and "JK - LiveBridge" with the language picker on the right; title
"Real-time interpreter"; subtitle "Sign in and try 5 minutes for free"; the Google button (the standard four-colour
"G" drawn from Google's published path with a `CustomPainter`, label "Sign in with Google" per Google's branding
rules, localized); below it a closed expander "I have my own API keys" holding ElevenLabs key and Gemini key fields
(obscured, with show/hide) and "Save and continue", and inside it a closed expander "Own gateway" with address and
token fields and its own "Save and continue". Waiting view: "Continue in your browser", the code in large type
(selectable), "Open again", "Cancel". Failed: one sentence per reason above the button. Use the existing adaptive
widgets (`platform_expander.dart`, `labeled_field.dart`, `pressable.dart`) so macOS and Windows looks follow.

- [ ] **Step 1: Write the failing widget tests** — first launch shows the onboarding; a saved static token shows the
  main screen; pressing Google shows the code from the fake client; `expired_token` returns with the sentence; saving
  keys enters the main screen in keys mode; empty fields keep "Save and continue" disabled.
- [ ] **Step 2: Run** — fail. **Step 3: Implement**, add strings to all four ARB files, `flutter gen-l10n`.
- [ ] **Step 4: Run** `flutter analyze && flutter test` (including `l10n_arb_test.dart`, `layout_overflow_test.dart`) — pass.
- [ ] **Step 5: Commit** `App: onboarding with Google sign-in and own keys`

### Task 6: Account chip, top up, connection summary, banners

**Files:**
- Create: `apps/desktop/lib/ui/account_chip.dart`, `apps/desktop/lib/ui/top_up_sheet.dart`
- Modify: `apps/desktop/lib/ui/home_screen.dart` (chip beside the language picker; refresh `me/` when the window
  becomes active again via `AppLifecycleListener(onResume:)`), `apps/desktop/lib/ui/setup_panel.dart` (the gateway
  section becomes a one-line summary with "Change"; the translation model field stays), `apps/desktop/lib/ui/banners.dart`,
  the four ARB files
- Test: `apps/desktop/test/account_ui_test.dart`

**Content:** account chip = the e-mail's first letter and "≈ N min" (no minutes when unknown); menu: Top up, Account
page, Sign out. Keys / gateway modes: the chip names the mode, menu "Change connection". Top-up sheet: the packages
from `packages/` with price and minutes; choosing one opens the checkout and closes the sheet. Banners:
`balance_empty` / `balance_exhausted` → "Balance is empty — top up" with a Top up button; `billing_unavailable` →
billing could not be reached, try again; `idle_timeout` → ended after 10 minutes without speech, with Start;
`session_replaced` → continued on another device; `session_limit` → the service is busy, try again in a minute.

- [ ] **Step 1: Write the failing widget tests** — chip text for 54 000 units in bidirectional mode is "≈ 9 min";
  menu items per mode; the sheet lists three packages and `topUp('starter')` is called; Start is disabled with the
  empty-balance reason at 0 units; each error code shows its banner.
- [ ] **Step 2: Run** — fail. **Step 3: Implement.** **Step 4: Run** `flutter analyze && flutter test` — pass.
- [ ] **Step 5: Commit** `App: account chip, top up and balance states`

### Task 7: Voices per connection mode

**Files:**
- Modify: `apps/desktop/lib/bridge/voices_client.dart`, `apps/desktop/lib/state/providers.dart`,
  `apps/desktop/lib/ui/voice_picker.dart`, `apps/desktop/lib/ui/voices_section.dart`, `apps/desktop/lib/state/setup_state.dart`
- Test: `apps/desktop/test/voices_test.dart`, `apps/desktop/test/voices_ui_test.dart`

**Interfaces:** `VoicesClient.list({required String gatewayUrl, required VoicesAuth auth})` with `sealed VoicesAuth`:
`BearerAuth(String token)` (static token or account access token), `ProviderKeyAuth(String elevenLabsKey)` (header
`X-ElevenLabs-Api-Key`). Choices per mode: gateway mode keeps `outVoiceId` / `inVoiceId` / `outVoiceName` /
`inVoiceName`; account mode uses the same names prefixed `account` (`accountOutVoiceId`, …), keys mode prefixed `keys`.

- [ ] **Step 1: Write the failing tests** — the right header per mode; switching mode shows that mode's saved voices;
  `401 invalid_key` shows a sentence about the key.
- [ ] **Step 2: Run** — fail. **Step 3: Implement.** **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `App: voices follow the connection mode`

### Task 8: Documents

**Files:** `docs/bridge-contract.md` (start keys, `updateAccessToken`, `balance` event, secret items, new error
codes), `README.md` (three ways to connect), `docs/setup-guide.md`, `docs/manual-qa.md` (sign-in, top up, empty
balance, own keys, migration), `IMPLEMENTATION_STATUS.md` (steps 3 and 4).

- [ ] **Step 1: Update**; no server addresses or costs. **Step 2: Commit** `Docs: accounts in the app`

### Task 9: The whole thing, for real

Needs the gateway from `docs/plans/2026-11-26-gateway-accounts.md` deployed.

- [ ] **Step 1:** Run every gate: `npm test && npm run typecheck`; `cd apps/desktop && flutter analyze && flutter test`;
  `swift test`; `native/livebridge_core/tests/run.sh`.
- [ ] **Step 2:** Release build on the Mac. The owner's install (saved static token) opens on the main screen in own
  gateway mode and translates as before.
- [ ] **Step 3:** With a fresh settings set (a separate macOS user or cleared settings — never delete the owner's
  Keychain items without asking): onboarding → Google → the owner confirms in his browser → main screen with the chip
  and the trial minutes → a short session on the hosted gateway → the balance goes down → Top up opens a Polar
  checkout (no purchase unless the owner makes one) → Sign out returns to onboarding. Own keys: the owner pastes his
  keys once; a session translates.
- [ ] **Step 4:** Screenshots as listed in the global constraints; fix anything clipped before showing them.
- [ ] **Step 5:** Ask the owner before pushing (Windows workflow), merging and releasing. Release `1.2.0`: version bump,
  `scripts/make-dmg.sh` (the DMG window from `scripts/dmg/`), the Windows installer from the release commit's Windows
  build, GitHub Release with install notes.

## What this plan leaves out on purpose

- Apple sign-in (deferred until the Apple Developer Program).
- Buying inside the app without a browser; Polar's page offers cards and Google Pay itself.
- Account deletion in the app: the account page on the site has it.
