# Accounts, paid service, onboarding and voice choice — design

Status: **approved by the owner on 2026-11-26**. Each step gets its own plan. Step 1 (voices) shipped in 1.1.0.

Amended 2026-11-26 while planning step 2, after reading the site's code: web sign-in is Google's redirect flow, not
its script; customers are their own account records, not the site's staff `User`; app tokens are opaque, not JWT;
the trial is granted when an account first connects the app. The reasons are in the approaches table.

This design spans two repositories: this one (desktop app, gateway, protocol) and the owner's site (a Django project,
`jaysonkhan.com`), which gains accounts, a balance and payments.

## Intent

Today a person needs their own ElevenLabs and Gemini keys and a running gateway before the app does anything. Most
people will not do that. They should be able to open the app, sign in, and talk — paying from inside the app when the
free trial runs out. People who do have their own keys keep a path that needs no account. Everyone can choose how the
two synthesized voices sound.

## Goals

1. First launch to a working call without visiting a provider console: sign in with Google, 5 free minutes, then
   packages bought from the app.
2. Own-keys path: paste an ElevenLabs key and a Gemini key into the app; no account, no gateway to run.
3. Choose the outgoing voice (my translated speech) and the incoming voice (the other person, translated for me):
   filter the list, listen to samples, pick.
4. No added delay per turn. Measured before and after (see "Latency check").

## Not now

- Sign in with Apple (needs an Apple Developer Program membership; planned once that exists).
- Local payment providers, subscriptions, team accounts, low-balance e-mails.
- Linking the site's Telegram visitors with service accounts.
- Browsing the whole ElevenLabs shared voice library; samples synthesized in the user's own language.
- Mobile apps.

## What would make this a failure even if it works

- Turns get slower.
- Provider keys, access tokens, audio or text are stored on the server or appear in any log.
- An account can keep spending the service's provider budget after its balance is gone.
- Self-hosting (own gateway address + static token) stops working.
- The first screen offers more than one obvious thing to do.

## Constraints

- **Gateway today:** one static access token, one session at a time, provider keys and both voice ids in its
  environment, no usage counting, three routes (`GET /healthz`, `POST /v1/sessions`, WebSocket `/v1/realtime`). It has
  never been deployed to a server.
- **App today:** the gateway address and token are typed into the setup panel; the token lives in the Keychain (macOS)
  or Credential Manager (Windows). Session creation and credential storage are native code, twice: Swift on macOS, C++
  on Windows. The interface exists in uz / ru / tr / en and in two looks; every screen is checked visually in all of
  them.
- **Site today:** visitors sign in with Telegram only (a session pointing at a Telegram record, not a Django user);
  the Django `User` model (e-mail login) is used by staff only; Django REST Framework with JWT is installed; there is
  no payment code and no balance.
- Both repositories are public: no secrets, server addresses or cost figures in either.
- Production deploys go through the deploy scripts only, and each one needs the owner's approval.
- The provider plan caps how many sessions can run at once.
- The payment provider (Polar, merchant of record) reviews the account and expects public terms, privacy and refund
  pages.

## Approaches considered

| Decision | Picked | Alternatives and why not |
|---|---|---|
| Where own keys run | **The hosted gateway, keys sent per session** | A gateway bundled into the app: every provider hop would cross the user's home connection (about 105 ms each from the owner's location, against about 4 ms from the server), the installer grows by a Node runtime, and two platforms need a process manager. Self-host only: not a path for non-developers. |
| Sign-in from a desktop app | **Device code: the app opens the browser and polls** | Loopback redirect: a local HTTP listener on two platforms and firewall prompts on Windows. Custom URL scheme: registration in both installers, breaks when the app is run from a download folder. |
| Where the balance lives | **A ledger on the site** | Polar's own meters and credits: they do not block usage when the balance runs out, and the gateway needs an answer within seconds. |
| What a balance counts | **Real usage (seconds heard, characters spoken)** | Wall-clock minutes: a captions-only hour would cost the same as a fully voiced one. |
| Which voices are offered | **The voices of the ElevenLabs account in effect** | The shared library: thousands of voices, some unusable on some plans, and adding one to an account is rate-limited per month. |
| Who a customer is on the site | **A separate account record keyed by the Google identity** (amended) | The site's staff `User` model: its e-mail is unique, so a customer whose Google address matches a staff login could not sign up, and Django's login and logout clear the whole session, including the Telegram visitor key that shares the cookie. The Telegram record: has no e-mail. |
| Google sign-in on the web | **Google's redirect flow, code exchanged by the server** (amended) | Google's sign-in script: the site's content security policy lives in the web server's configuration and would have to be changed by hand on the server, and it puts third-party script on the page. |
| App tokens | **Opaque random tokens, stored hashed** (amended) | JWT: a signed token stays valid until it expires, so "Sign out" on the account page would not take effect at once; the gateway asks the site for the balance anyway, so a self-contained token saves nothing. |

The owner chose the first row by its speed; the other rows are the builder's calls and open to correction.

## Design

### Three ways to connect

| Mode | For | Stored in the app | Gateway | Who pays the providers |
|---|---|---|---|---|
| **Account** | most people | account refresh token | hosted | the service, from the account's balance |
| **Own keys** | people with provider accounts | ElevenLabs key, Gemini key | hosted | the user, directly |
| **Own gateway** | self-hosters (today's behaviour) | gateway address, static token | theirs | theirs |

All secrets stay in the Keychain / Credential Manager. Existing installs with a saved static token become "own
gateway" and never see the onboarding screen.

### Hosted gateway

- Reachable under the site's host (a path proxied to the gateway, HTTP and WebSocket), so no new DNS record or
  certificate is needed. A subdomain is equally fine if the owner prefers one.
- `POST /v1/sessions` takes a JSON body with `mode`:
  - `"token"` (default when the body is empty — today's behaviour): `Authorization: Bearer <static token>`. Only
    accepted when a static token is configured.
  - `"account"`: `Authorization: Bearer <account access token>`. The gateway asks the site to authorize it and gets
    the account id and balance. Empty balance → `402 balance_empty`. A second live session for the same account →
    `409 session_active`.
  - `"keys"`: body carries `elevenlabs_api_key` and `gemini_api_key`. They are kept in memory for that session only.
- Limits: a total session cap, plus separate caps for account and own-keys sessions and the existing per-address
  rate limit. When full → `429 session_limit`; the app says the service is busy.
  - A two-way session holds four provider connections for its whole life (two speech-to-text, two synthesis), and
    they stay open — opening them per turn would add delay. The total cap is therefore a setting derived from the
    provider plan: half of its realtime speech-to-text limit, minus a small margin. Own-keys sessions use the user's
    own provider limits but still count toward a cap of their own.
  - A session with no speech on either lane for 10 minutes ends with `idle_timeout`, so idle sessions do not hold
    slots; the app restarts with one click.
  - Accounts that have only trial balance cannot take the last slots: a share of the cap is kept for accounts that
    have bought a package.
- **Counting (account mode only):** per session the gateway counts audio milliseconds forwarded to speech-to-text
  (per lane) and characters sent to speech synthesis. Every 10 seconds and at the end it reports the increments to
  the site with a sequence number (so a retry is not charged twice) and receives the remaining balance.
  - Balance reaches zero → the session ends with the fatal error `balance_exhausted`.
  - The site cannot be reached three reports in a row → the session ends with `billing_unavailable`.
  - Worst-case overrun is about 10 seconds of usage.
- The client receives the remaining balance when the session becomes ready and after every report (a new
  `account.balance` message), so the app can show it.
- Keys and tokens are never written to logs; a test asserts it.

### Billing units

- One package minute = **6000 units**.
- Speech-to-text: **12 units per second of audio, per lane**. Speech synthesis: **5 units per character**.
  Translation is included in these.
- A minute voiced in both directions costs about 6000 units; a captions-only minute (two lanes) about 1440, roughly a
  quarter.
- The gateway reports raw counters; the site turns them into units. Rates are site settings, so a price change needs
  no gateway deploy.
- The app shows "≈ N min" for the current mode.

### Site

- **Accounts.** A "Sign in with Google" button on a new account page sends the person to Google and back; the site
  exchanges the code itself and verifies the ID token (audience, issuer, expiry, verified e-mail). The account is
  found by Google's subject id, or created. Accounts are separate from the site's staff logins and from its
  Telegram visitors. The verification code is ported from the owner's other Django project.
- **Sign-in from the app** (shaped like the OAuth device grant):
  1. The app asks the site to start: it gets a secret device code, a short user code (`ABCD-1234`), a verification
     address, a poll interval and a 10-minute expiry.
  2. The app opens the verification address in the system browser and shows the user code.
  3. In the browser the person signs in with Google if needed, sees "Connect JK - LiveBridge on *device name*? Code
     ABCD-1234" and confirms. The explicit confirmation with a visible code is what stops someone from tricking a
     person into connecting an app that is not theirs.
  4. The app polls with the device code until it receives an access token (short-lived) and a refresh token
     (long-lived, rotating, tied to a device record that can be revoked from the account page or by signing out in
     the app).
- **Balance.** One wallet per account and an append-only list of entries (trial, purchase, usage, refund, manual
  adjustment), each with the balance after it. Every change goes through one service module inside a locking
  transaction.
- **Trial.** 5 minutes (30 000 units), granted when an account first connects the app, once per Google account and
  once per device (the device id the app sends when it starts sign-in). A site setting caps how many trials are granted per day; past it,
  new accounts are created without a trial and told so. This keeps trial farming from exhausting the provider
  budget.
- **Packages** (one-time purchases, in US dollars):

  | Package | Price | Units | Voiced minutes |
  |---|---|---|---|
  | Starter | $5 | 360 000 | about 60 |
  | Medium | $15 | 1 200 000 | about 200 |
  | Large | $40 | 3 600 000 | about 600 |

- **Checkout.** The site creates a Polar checkout for a package, tied to the account id, and returns its address; the
  app or the account page opens it in the browser. Google Pay and cards are offered by Polar's page itself. A webhook
  (signature verified) credits the wallet on `order.paid`, once per order id. Built against Polar's sandbox first.
  - Refunds: the wallet keeps one balance, not a remainder per purchase. A refund debits the units that order
    granted, in proportion to the refunded amount, but no more than the current balance.
- **Account page.** E-mail, balance, the three packages, history, connected devices with "Sign out", a way to ask
  for account deletion.
- **For the app** (bearer tokens): who am I and my balance, packages, start a checkout, sign out.
- **For the gateway** (reached through the server's local socket — a request that came through the public web
  server is refused — and signed with a shared secret): authorize an access token, report usage.
- **Legal pages** for the service: terms, privacy, refunds. Drafted by the builder, approved by the owner.
- **Admin.** Accounts, wallets (adjust with a reason), entries read-only, packages.
- The anonymous statistics collector stays as it is and is not linked to accounts.

### Voices

- New gateway route `GET /v1/voices`, authorized the same three ways as session creation. It returns voices in one
  shape: id, name, gender, age, accent, language, use case, description, sample address, and per-language sample
  addresses where the provider has them. Cached for 10 minutes per key.
  - Own keys and own gateway: every voice of that ElevenLabs account.
  - Account mode: only a list the owner has approved (a gateway setting of voice ids). Until he lists any, only the
    provider's stock voices are offered. Voices cloned in the service's own account are never offered unless listed —
    otherwise any customer could speak in them.
- Protocol: `session.configure` gains optional `voices: { out?, in? }`. Ids are checked for shape and, in account
  mode, against the list. Absent → the gateway's configured defaults, as today.
- App, setup panel: a "Voices" group with two rows — "My voice (outgoing)" and "Their voice (incoming)" — each
  showing the chosen voice and a button that opens the picker. A row is disabled when the selected mode speaks
  nothing in that direction.
- Picker: a search field, filters built from the list (gender, age, accent, language, use case), one row per voice
  with a play/stop button, the name and its tags, the current one marked, and a "Default" entry. The sample in the
  session's target language plays when one exists, otherwise the voice's general sample. One sample at a time; it
  stops when the picker closes.
- The choice is remembered per connection mode, since the lists differ.
- Before building: a short test with a real key to confirm that sample addresses play without a key and that every
  listed voice works with the realtime synthesis model in use; voices that do not are left out of the list.

### App: onboarding and account

Shown instead of the main screen while no connection is saved:

```
  (logo)  JK - LiveBridge                         [ O'zbekcha ⌄ ]

                  Real-time interpreter
          Sign in and try 5 minutes for free

              [  G   Sign in with Google  ]

              ▸ I have my own API keys
```

- Expanded, the lower section shows two fields (ElevenLabs key, Gemini key) and "Save and continue", and inside it a
  further collapsed "Own gateway" with today's address and token fields.
- After pressing the Google button: "Continue in your browser — code ABCD-1234", with "Open again" and "Cancel".
- Main screen, header: a chip beside the language picker — the account's e-mail initial and "≈ 54 min" — with a menu:
  Top up, Account page, Sign out. In the other two modes the chip names the mode and offers "Change connection".
- Setup panel: the gateway section becomes a one-line connection summary with "Change"; the translation model field
  stays.
- Top up: a sheet with the three packages; choosing one opens the checkout in the browser, and the app refreshes the
  balance when its window regains focus.
- Start is blocked with "Balance is empty — top up" when it is. A session that ends with `balance_exhausted` shows a
  banner with a Top up button.
- Both native hosts gain: the three modes at session creation, refreshing the access token before it, the `voices`
  field, and the new Keychain / Credential Manager items. `docs/bridge-contract.md` is extended accordingly.

### Documents

- `docs/privacy.md`: on the hosted gateway audio and text pass through and are not stored; an account holds an
  e-mail, a Google id, balance entries and usage counters (seconds and characters, never content); own keys travel
  over TLS and live in memory for one session.
- `README.md`: the three ways to connect.

### Latency check

The same phrases are run through a local gateway and the hosted one, and the per-turn figures the gateway already
reports (`stt_commit_ms`, `translate_*`, `tts_*`) plus microphone-to-first-audio are compared. The hosted gateway
ships as the default only if it is not slower. The estimate from connection times (about 105 ms from the owner's
location to each provider, about 4 ms from the server, about 125 ms to the server) says it should be 100–200 ms
faster per turn; this has not been measured on a real turn.

## Order of work

Each step ships on its own, branching from `main`. In every step the macOS host is built and verified first; the
Windows host gets the same change in the same step and must pass the Windows build, but a Windows release waits
until the owner has run the Windows app on a real PC (it has only been compiled so far).

1. **Voices** — gateway route, protocol field, picker in the app. Works with today's own-gateway mode.
2. **Site** — accounts with Google, sign-in from the app, wallet, packages, Polar (sandbox, then live), legal pages.
3. **Gateway** — account and own-keys modes, counting, limits; first deploy to the server; latency check.
4. **App** — onboarding, account chip, top up, balance states; new macOS and Windows releases.

## What only the owner can do

- An ElevenLabs API key that may read voices (the current key cannot, so the voice list and the pre-build test in
  step 1 need it) and, ideally, read the account (to see the plan's limits).
- Say which ElevenLabs plan the service runs on: it sets the session cap. If the plan allows fewer than about five
  sessions at once, step 3 starts with a decision on upgrading it.
- A Google OAuth web client (id and secret) whose redirect address is the site's Google callback.
- A Polar organisation that has passed review, the three products, an access token and a webhook secret, placed in
  the server's environment.
- Check the ElevenLabs plan (simultaneous sessions) and set a spending cap.
- Approve the legal texts, and each production deploy.

## Left to the builder

Module, model and route names; token lifetimes; cache sizes; the audio plugin used for samples; the proxy layout;
spacing and wording details of the new screens (within the existing theme and the four interface languages).
