# Bug reports with a diagnostic log — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a user can press a bug icon, describe a problem and send it to the developer together with a diagnostic log
of the app since launch; the report reaches the site and the owner's Telegram admin group. Numbers-only statistics
become on by default.

**Architecture:** the diagnostic log lives in Dart (one implementation for macOS and Windows): an in-memory record of
this run plus a small rolling file, fed by a recorder that listens to the bridge events, the setup and connection
state, the HTTP clients and Flutter's error hooks. Every line passes one redaction function. The report is sent from
Dart over HTTPS to a new site endpoint next to the existing feedback endpoint, which stores it, rate-limits it and
announces it in the admin group with the log as a file. The native hosts change only a little: `telemetryStatus`
reports the app and OS version, sharing is on when no choice was saved, and Windows tells Bluetooth endpoints apart.

**Tech stack:** Flutter 3.47 / Dart 3.13 + Riverpod 3 (`dart:io` `HttpClient`, no new packages) · Swift 6 · C++17
(portable core + Win32 runner) · Django 4.2 + DRF on the site.

**Spec:** the task brief from the session that started this one (no separate design doc). Contracts touched:
`docs/telemetry-api.md` (new endpoint, default on), `docs/bridge-contract.md` (`telemetryStatus`, `transport`,
`telemetryEnabled` default), `docs/privacy.md`.

## Global constraints

- The log never holds transcript or translation text, API keys, tokens, the refresh token or the static gateway token.
  Captions and meters stay out. A test asserts it (Task A3).
- The e-mail appears in the log only in account mode; the gateway appears as its host only.
- Statistics stay numbers only; an explicit earlier `telemetryEnabled: false` stays off; the switch stays visible.
- Both repos are public: no server IPs, paths, other project names or cost figures.
- Dart: `dart format lib test` (width 120 comes from `analysis_options.yaml`). Strings in all four ARB files
  (en, uz, ru, tr), then `flutter gen-l10n`.
- Site work on branch `livebridge-bug-reports` in `/Users/mac/JaysonServer/jaysonkhan_v2`; deploy only on the
  owner's word, via `./deploy.sh`.
- Commits read as the owner's: no `Co-Authored-By` or tool attribution. Nothing pushed, merged, deployed or released
  without the owner's word. Never run bare `python`.

## Decisions taken here (the brief left them open)

- **E-mail prefill** ("prefilled with the account's e-mail, remembered and selected by default"): in account mode both
  dialogs open with the account's e-mail already in the field; the person may clear or change it. Nothing new is
  stored: the account remembers the address. Other modes: empty and optional, as today.
- **Log size:** this run in memory, capped at 192 KB (oldest lines dropped, with a marker); file `diagnostics.log`
  rotated to `diagnostics.1.log` past 256 KB (at most ~512 KB on disk); a report carries at most 200 KB of log —
  the earlier runs' tail first, then this run. Folder: the one the analytics log uses (`~/Library/Application
  Support/LiveBridge` on macOS, `%APPDATA%\LiveBridge` on Windows). No file under ephemeral settings
  (`LIVEBRIDGE_EPHEMERAL_SETTINGS=1`) or in tests.
- **Version and OS** come from the native uploader (`telemetryStatus.appVersion` / `osVersion`), so the report and the
  statistics agree; arch is `Abi.current()`.
- **Report transport:** Dart `HttpClient` to `<telemetry endpoint>/bug-reports/` (the endpoint `telemetryStatus`
  already returns), so forks that move the collector move reports too. `install_id` only when sharing is on, as for
  feedback.
- **Consent:** `consent_dialog.dart` is the call-consent dialog (the other participant agreed) and is unrelated to
  statistics. The statistics explanation dialog lives in `analytics_section.dart` (`_TelemetryBlock`): switching on
  still shows it, switching off still needs no dialog. With the default on, that explanation moves into the docs and
  the switch's place stays where it is.
- **Windows Bluetooth:** the endpoint's topology connector names the driver the endpoint hangs off
  (`…bthenum…` / `…bthhfenum…` / `…usb…`). The classification is a pure function in the portable core (tested on the
  Mac); the COM call is a few lines in the runner (compiled only by the Windows workflow).

## Review focus

1. **A secret inside an error message** — a provider error, a `PlatformException` message or an exception string can
   carry a key or token: the line must show `[secret]`, not the value (Task A2 redaction test, Task A3 app test).
2. **Device names with quotes, newlines or emoji** (Bluetooth names are user-set) — one log line per event, the name
   quoted, nothing that breaks the line (Task A2 test `one line per entry`).
3. **The log file cannot be written** (read-only folder, disk full) — the app keeps working and the report still
   carries this run from memory (Task A2 test `unwritable folder`).
4. **Sending while offline or rate-limited** — the dialog stays open with the text kept and a worded error; nothing is
   queued (Task A5 tests).
5. **An oversized report** (a long run, a huge device list) — the app trims the log to 200 KB before sending; the site
   answers 413 to anything past its cap and 400 to a bad device object (Task S1, Task A5 tests).

---

## Site (`/Users/mac/JaysonServer/jaysonkhan_v2`, branch `livebridge-bug-reports`)

### Task S1: bug-report endpoint, model and rate limit

**Files:**
- Modify: `backend/apps/apptelemetry/models.py` (new `AppBugReport` after `AppFeedback`)
- Create: `backend/apps/apptelemetry/migrations/0003_appbugreport.py` (`makemigrations apptelemetry`)
- Modify: `backend/apps/apptelemetry/validation.py` (new `parse_bug_report`)
- Modify: `backend/apps/apptelemetry/ratelimit.py` (`BUG_REPORT_PER_ADDRESS = Limit('bug_addr', 5, HOUR)`)
- Modify: `backend/apps/apptelemetry/repositories.py`, `services.py` (`create_bug_report`, `_notify_owner_bug_report`)
- Modify: `backend/presentation/api/services_views.py` (`BugReportView`), `backend/presentation/api/urls.py`
  (`services/v1/bug-reports/`, name `services_bug_report`)
- Test: `backend/apps/apptelemetry/tests/test_bug_report_api.py`, `tests/helpers.py` (`BUG_REPORT_URL`)

**Interfaces:**
- Produces: `AppBugReport(app, install FK null, message ≤2000, email, app_version ≤32, os_version ≤64,
  platform ≤32, ui_language ≤8, connection_mode ≤16, device_info JSONField default dict, log TextField,
  created_at)`; `parse_bug_report(data) -> dict` raising `EnvelopeError`; `TelemetryService.create_bug_report(fields)
  -> AppBugReport` (calls `_notify_owner_bug_report(report)`, which fire-and-forgets
  `NotificationService().log_service_bug_report(report)` from Task S2).
- Wire: request body ≤ 320 KB (`BUG_REPORT_MAX_BODY_BYTES`), `log` ≤ 256 KB encoded (`LOG_MAX_BYTES`), `devices`
  a JSON object ≤ 16 KB encoded (`DEVICES_MAX_BYTES`), `connection_mode` ∈ `account|keys|gateway|none` (else ''),
  `platform` optional string ≤ 32. Responses `201 {"ok": true}`, `400 {"error": code}`, `413 {"error":
  "too_large"}`, `429 {"error": "rate_limited"}` + `Retry-After`.

- [ ] **Step 1: Write the failing tests** in `test_bug_report_api.py` (pattern of `test_feedback_api.py`):
  - `test_happy_path_stores_everything_and_links_a_known_install` — 201 `{'ok': True}`; every field stored;
    `device_info == devices`; `log` kept verbatim; `_notify_owner_bug_report` called once with the row.
  - `test_minimal_report` — only `app` + `message` → 201, `email == ''`, `log == ''`, `device_info == {}`.
  - `test_message_rules` — missing / blank / 2001 chars → 400 `bad_message`; 2000 chars → 201.
  - `test_envelope_rules` — non-object → `bad_json`; other app → `unknown_app`; bad install id → `bad_install_id`;
    bad e-mail → `bad_email`.
  - `test_devices_must_be_a_small_object` — `devices=[1]` → 400 `bad_devices`; an object over 16 KB → 400
    `bad_devices`.
  - `test_log_rules` — `log=42` → 400 `bad_log`; a 257 KB log → 400 `bad_log`; body over 320 KB → 413 `too_large`.
  - `test_unknown_connection_mode_is_blanked` — `connection_mode='weird'` → stored ''.
  - `test_rate_limit_is_five_per_address_per_hour` — sixth → 429 with `Retry-After`; another address → 201;
    feedback from the same address is still accepted (separate counter).
  - `test_get_is_not_allowed` — 405.
- [ ] **Step 2: Run them, expect failures** —
  `backend/venv/bin/python backend/manage.py test apptelemetry.tests.test_bug_report_api --settings=config.settings.dev`
  → errors (no URL / model).
- [ ] **Step 3: Implement** model + migration, `parse_bug_report` (reuse `parse_uuid4`, `validate_email`,
  `optional_str`, `ui_language`), the limit, repository `create_bug_report(**fields)`, service, view (copy of
  `FeedbackView` with the bigger body cap; oversized body → 413 here, as for telemetry), URL.
- [ ] **Step 4: Run the app's tests** — `… manage.py test apptelemetry --settings=config.settings.dev` → all pass.
- [ ] **Step 5: Commit** — `feat(apptelemetry): LiveBridge bug reports — endpoint, model, rate limit`.

### Task S2: owner's Telegram note with the log as a file, and the admin view

**Files:**
- Modify: `backend/apps/interactions/notifications/service.py` (`log_service_bug_report`)
- Modify: `backend/apps/core/bot_i18n.py` (`adm.bug_report_new`, uz + ru)
- Modify: `backend/apps/apptelemetry/admin.py` (`AppBugReportAdmin`)
- Test: `backend/apps/apptelemetry/tests/test_bug_report_api.py` (`BugReportNotificationTest`, `BugReportAdminTest`)

**Interfaces:**
- Consumes: `AppBugReport` (Task S1); `NotificationService._send_to_admin_group`, `TelegramBotAPI.send_document`.
- Produces: `NotificationService.log_service_bug_report(report) -> None`.

- [ ] **Step 1: Write the failing tests:**
  - `test_note_has_summary_but_no_email` — patch `_send_to_admin_group` and `TelegramBotAPI`: the text has the app,
    version, OS, connection mode, the chosen mic / headphones names from `device_info` and the message (escaped,
    ≤ 500 chars of it); it never contains the e-mail; the button links to
    `/apptelemetry/appbugreport/<pk>/change/`.
  - `test_log_goes_as_a_document` — `send_document` called once with the admin group id, a file whose name is
    `livebridge-report-<pk>.txt` and whose content is the device JSON plus the log; the temporary file is gone
    afterwards; nothing is sent as a document when the log and devices are both empty.
  - `test_admin_change_page_renders` — a staff superuser (admin IP allowed as in the other admin tests) opens the
    change page: 200, the log text is on the page.
- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement.** Summary via `t('adm.bug_report_new', lang, …)`; then write the document to a
  `tempfile.NamedTemporaryFile(suffix='.txt')`, `send_document(group_id, path, caption=f'#{pk}')`, delete it. The
  admin is read-only like `AppFeedbackAdmin` (list: preview, connection mode, version, OS, has e-mail, has log,
  created; detail shows the log in a `<pre>` and the device JSON pretty-printed, both escaped).
- [ ] **Step 4: Run** `… test apptelemetry interactions --settings=config.settings.dev` → pass; also
  `… manage.py check --settings=config.settings.dev`.
- [ ] **Step 5: Commit** — `feat(apptelemetry): bug report note in the admin group with the log file; admin view`.
  Update the site's `CLAUDE.md` "My Services" bullet (endpoint, limit, note) in the same commit.

---

## App (this repo, `apps/desktop`)

### Task A1: native hosts — versions in `telemetryStatus`, Bluetooth on Windows

**Files:**
- Modify: `native/LiveBridgeAudio/Sources/LiveBridgeAudioCore/TelemetryUploader.swift` (`status()` adds
  `appVersion`, `osVersion`; `osVersion` shared with the upload body)
- Modify: `native/livebridge_core/src/telemetry_uploader.cpp` + header (`status()` adds the same two keys)
- Create: `native/livebridge_core/include/livebridge/device_transport.h`, `src/device_transport.cpp`
- Modify: `windows/runner/audio_devices.cpp` (read the topology connector, use the classifier),
  `windows/runner/CMakeLists.txt` / `native/livebridge_core/CMakeLists.txt` (new source)
- Modify: `lib/bridge/models.dart` (`TelemetryStatus.appVersion`, `osVersion`)
- Test: `native/LiveBridgeAudio/Tests/LiveBridgeAudioCoreTests/CoreTests.swift`, `test/models_test.dart`,
  `native/livebridge_core/tests/telemetry_tests.cpp`, `native/livebridge_core/tests/core_tests.cpp`

**Interfaces:**
- Produces: `telemetryStatus` map keys `appVersion` String (e.g. `1.2.0+3`) and `osVersion` String (e.g.
  `macOS 26.6.2`, `Windows 11 (build 26100)`); `std::string livebridge::TransportFromConnectorId(const std::string&
  connector_id)` → `"bluetooth"` when the lower-cased id contains `bthenum`, `bthhfenum` or `bthledevice`, `"usb"`
  when it contains `usb`, else `"other"`. The runner reports `virtual` first (by name, as today), else the
  classifier's answer.

- [ ] **Step 1: Failing tests** — Dart `TelemetryStatus.fromMap` reads both keys; Swift `testStatusCarriesAppAndOsVersion`; C++ `status has appVersion and osVersion`
  and `TransportFromConnectorId` cases: `{2}.\\?\BTHENUM#{0000110b-…}` → bluetooth,
  `{2}.\\?\bthhfenum#bthhfpaudio#…` → bluetooth, `{2}.\\?\USB#VID_046D…` → usb, `{2}.\\?\HDAUDIO#FUNC_01…` → other,
  `""` → other.
- [ ] **Step 2: Run** `swift test` (in `native/LiveBridgeAudio`) and `native/livebridge_core/tests/run.sh` → fail.
- [ ] **Step 3: Implement.** Windows: `IMMDevice::Activate(IDeviceTopology)` → `GetConnector(0)` →
  `GetDeviceIdConnectedTo` (free with `CoTaskMemFree`); any failure leaves `other`.
- [ ] **Step 4: Run both again** → pass.
- [ ] **Step 5: Commit** — `Hosts: telemetryStatus carries the app and OS version; Windows tells Bluetooth devices`.

### Task A2: `DiagnosticLog` — memory, rolling file, redaction

**Files:**
- Create: `lib/state/diagnostic_log.dart`
- Test: `test/diagnostic_log_test.dart`

**Interfaces:**
- Produces:
  - `String redact(String text, {Iterable<String> secrets = const []})` — replaces each given secret of ≥ 6 chars,
    `Bearer <x>`, JWT-shaped `eyJ….….…`, `AIza[0-9A-Za-z_-]{20,}`, `sk_[0-9A-Za-z]{20,}` and any run of ≥ 32
    `[A-Za-z0-9_\-+/=]` with `[secret]`; turns newlines and tabs into spaces; caps at 400 chars.
  - `class DiagnosticLog` — `DiagnosticLog.memory({DateTime Function()? now})`;
    `static Future<DiagnosticLog> open(Directory dir, {DateTime Function()? now})` (reads the earlier runs' tail from
    `diagnostics.1.log` + `diagnostics.log`, writes a run header); `void add(String category, String message)`;
    `Iterable<String> Function()? secrets` (setter; values redacted by value); `String text({int maxBytes =
    200 * 1024})`; `Future<void> flush()`; `static Directory? defaultFolder()` (macOS / Windows paths above; null
    under ephemeral settings or on other platforms).
  - Line format: `HH:mm:ss.SSS <category padded to 9> <message>`; run header `=== LiveBridge run started
    <ISO-8601 local with offset>`.

- [ ] **Step 1: Failing tests:**
  - `redacts keys, tokens and given secrets` — inputs with an `sk_…` key, an `AIza…` key, a 43-char url-safe
    refresh token, `Bearer abc.def`, a JWT and a given secret `dev-token-1` → none of them in the output, `[secret]`
    present; a UUID and `gemini-3.5-flash-lite` survive.
  - `one line per entry` — a message with `\n`, `\t`, quotes and an emoji stays one line.
  - `memory cap drops the oldest lines with a marker` — add > 192 KB → `text()` ≤ 200 KB, starts with the header,
    contains `earlier lines dropped`, ends with the newest line.
  - `file rotates past 256 KB and the next run sees the earlier run` — `open` on a temp dir, add 300 KB, flush;
    `diagnostics.1.log` exists; a second `open` → its `text()` contains a line of the first run before the second
    run's header.
  - `report text is capped` — `text(maxBytes: 1000).length` (UTF-8 bytes) ≤ 1000 and keeps the newest line.
  - `unwritable folder` — `open` on a path under a file (not a directory) → no throw; `add` works; `text()` has the
    line.
- [ ] **Step 2: Run** `flutter test test/diagnostic_log_test.dart` → fail.
- [ ] **Step 3: Implement** (append with a `RandomAccessFile` opened in append mode; write errors switch the file off
  for the rest of the run).
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** — `App: diagnostic log in memory and a small rolling file, every line redacted`.

### Task A3: the recorder — what goes into the log

**Files:**
- Create: `lib/state/diagnostics.dart` (providers + recorder + `describe…` helpers)
- Modify: `lib/main.dart` (open the file log, Flutter / platform error hooks, override the provider)
- Modify: `lib/ui/app.dart` (watch `diagnosticRecorderProvider`)
- Modify: `lib/state/session_state.dart` (`start` logs the start; `reportError` logs app errors)
- Modify: `lib/bridge/account_client.dart`, `lib/bridge/voices_client.dart` (optional
  `void Function(String what, int? status, String code)? onFailure`), `lib/state/providers.dart`,
  `lib/state/connection_state.dart` (wire `onFailure` to the log)
- Test: `test/diagnostics_test.dart`, `test/account_client_test.dart`, `test/voices_test.dart`

**Interfaces:**
- Consumes: `DiagnosticLog`, `redact` (Task A2); `TelemetryStatus.appVersion` / `osVersion` (Task A1).
- Produces: `final diagnosticLogProvider = Provider<DiagnosticLog>((ref) => DiagnosticLog.memory())`;
  `final diagnosticRecorderProvider = Provider<void>(…)`; `Map<String, Object?> describeDevices(SetupState s)` —
  `{mic, headphones, virtualMic, sources, mode, myLang, targetLang, outCommit, devices}` where each device is
  `{name, transport, sampleRate, inputChannels, outputChannels, isDefaultInput, isDefaultOutput}` (no uid) and
  `sources` are process names. Task A5 sends this map as `devices`.
- Logged (category → content): `app` (version, OS, `Platform.operatingSystemVersion`, `Abi.current()`, UI language,
  statistics on/off); `connection` (mode; e-mail only in account mode; gateway host; sign-in phase and failure code;
  notice code); `devices` (the whole list after load and after each change); `selection` (mic, headphones, virtual mic
  with transport / rate / channels, source process names, mode, languages, commit); `start` (the same plus connection
  and gateway host); `state` (engine state and flags when they change, the scrubbed status message — reconnect
  attempts show here); `error` (code, fatal, direction, scrubbed message); `turn` (direction, id, e2e, stt,
  translate first/total, tts first/total, audio, model); `http` (`site|gateway <path without query> → <status|->
  <code>`); `exception` (first line of the error + the top 5 frames). Not logged: captions, meters, balance.

- [ ] **Step 1: Failing tests** in `diagnostics_test.dart` (use `pumpApp` from `test/harness.dart`, read
  `container.read(diagnosticLogProvider).text()`):
  - `logs state, errors, timings and device changes` — emit `StateEvent(connecting)`, `StateEvent(ready)`,
    `MetricsEvent(e2eMs: 1350, …)`, `ErrorEvent(code: 'gateway_error')`, `DevicesChangedEvent` → each shows up.
  - `logs the chosen devices with transport and rate` — fake devices incl. a Bluetooth mic and the headphones on the
    built-in speakers → a `selection` line names both with `bluetooth` / `builtin` and the sample rates.
  - `never holds what was said, keys or tokens` (the owner's requirement) — account mode with fake site tokens
    (43-char access and refresh tokens), then keys mode with `sk_…` and `AIza…` keys, then gateway mode with a static
    token; caption events with text `SAID-OUT-TEXT` / `SAID-IN-TEXT` and translations `TRANSLATED-TEXT`; an error
    event and a `PlatformException` whose messages contain the token; an HTTP failure; a Flutter error whose message
    holds a key → the log text contains none of these values and none of the caption texts; it does contain the
    account e-mail (account mode only) and the gateway host.
  - `e-mail only in account mode` — after switching to keys mode the new `connection` line has no e-mail.
  - account / voices client: `onFailure` is called with path, status and code on a 401 / 429 / network failure and
    never with a body.
- [ ] **Step 2: Run** `flutter test test/diagnostics_test.dart test/account_client_test.dart test/voices_test.dart` →
  fail.
- [ ] **Step 3: Implement.** The recorder sets `log.secrets` to the static gateway token from `setupProvider`.
  `main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, `DiagnosticLog.open(folder)` or `.memory()`,
  `FlutterError.onError` (log, then `FlutterError.presentError`), `PlatformDispatcher.instance.onError` (log, return
  false), `ProviderScope(overrides: [diagnosticLogProvider.overrideWithValue(log)])`.
- [ ] **Step 4: Run** the three files, then the whole `flutter test` → pass.
- [ ] **Step 5: Commit** — `App: the diagnostic log records devices, state, errors, timings and failures`.

### Task A4: statistics on by default

**Files:**
- Modify: `lib/state/setup_state.dart` (`telemetryEnabled = true` default; a saved `false` stays)
- Modify: `macos/Runner/MainFlutterWindow.swift` (`?? true`), `windows/runner/livebridge_channels.cpp`
  (`sharing == nullptr || sharing->as_bool(true)`)
- Modify: `docs/telemetry-api.md` (principles + client behaviour), `docs/bridge-contract.md` (`telemetryEnabled`
  default, `telemetryStatus` keys, Windows `transport`), `docs/privacy.md`, `README.md` (the "Sharing statistics"
  bullet)
- Test: `test/telemetry_feedback_test.dart`

- [ ] **Step 1: Failing tests** — `statistics are on when nothing was saved`; `an earlier "off" stays off`
  (`telemetryEnabled: false` saved → switch off, nothing saved back); `switching on still explains what is sent`
  (dialog shown, then saved `true`); `switching off saves false without a dialog`.
- [ ] **Step 2: Run** `flutter test test/telemetry_feedback_test.dart` → fail.
- [ ] **Step 3: Implement** the defaults and the docs (plain words: on by default, numbers only, how to switch off,
  an explicit off is kept).
- [ ] **Step 4: Run** the file + `swift test` → pass.
- [ ] **Step 5: Commit** — `Statistics sharing is on by default (numbers only); an earlier "off" stays off`.

### Task A5: "Report a problem" and the e-mail prefill

**Files:**
- Create: `lib/bridge/bug_report_client.dart`
- Create: `lib/ui/bug_report_dialog.dart` (`ReportProblemButton`, `showBugReportDialog`, the preview dialog)
- Modify: `lib/ui/home_screen.dart` (header trailing: `AccountChip`, `LanguagePicker`, `ReportProblemButton`),
  `lib/ui/onboarding_screen.dart` (trailing: `LanguagePicker`, `ReportProblemButton`)
- Modify: `lib/ui/feedback_dialog.dart` (prefill in account mode)
- Modify: `lib/l10n/app_{en,uz,ru,tr}.arb` (+ regenerated `app_localizations*.dart`)
- Modify: `lib/state/providers.dart` (`bugReportClientProvider`)
- Modify: `docs/telemetry-api.md` (the `POST /api/services/v1/bug-reports/` section, mirroring Task S1's wire rules)
- Test: `test/bug_report_test.dart`, `test/fake_bug_report_client.dart`, `test/telemetry_feedback_test.dart`,
  `test/layout_overflow_test.dart`

**Interfaces:**
- Consumes: `describeDevices`, `diagnosticLogProvider` (Task A3); `TelemetryStatus` (Task A1).
- Produces: `abstract class BugReportClient { Future<void> send(Uri endpoint, Map<String, Object?> body); }`,
  `HttpBugReportClient({Duration timeout = const Duration(seconds: 20), onFailure})`,
  `class BugReportException implements Exception { final String code; }` with codes `rate_limited`, `rejected`,
  `network`. Body keys: `app`, `install_id` (only when sharing is on), `message`, `email`, `app_version`,
  `os_version`, `platform`, `ui_language`, `connection_mode` (`account|keys|gateway|none`), `devices`, `log`
  (both only when "Include the diagnostic log" is on).
- Strings (en): `reportButton` "Report a problem"; `reportNote` "Tell us what went wrong. The report goes to the
  developer."; `reportMessageLabel` "What happened?"; `reportIncludeLog` "Include the diagnostic log";
  `reportIncludeLogNote` "Settings, devices, errors and timings since the app started. Never what was said, keys or
  tokens."; `reportShowLog` "Show what will be sent"; `reportPreviewTitle` "What will be sent"; `reportSent` "Report
  sent. Thank you!"; `reportFailed` "The report was not sent. Check the connection and try again." The e-mail label,
  invalid-e-mail text, rate-limit text, Cancel, Send and Copy reuse the feedback / common strings.

- [ ] **Step 1: Failing tests** in `bug_report_test.dart`:
  - `bug icon sits at the right of the main header and opens the dialog`; `onboarding has it too`.
  - `send is off until a description is written`.
  - `sends the description, e-mail, versions, devices and log` — fake client receives the body; `log` contains a
    known `state` line; `devices.mic.name` is the chosen mic; endpoint is `<telemetry endpoint>/bug-reports/`.
  - `without the log nothing of it is sent` — box unticked → no `log`, no `devices`.
  - `preview shows exactly the log that will be sent`.
  - `rate limit and offline keep the dialog open with the text` — `BugReportException('rate_limited')` → rate-limit
    text; `network` → `reportFailed`; the description is still in the field.
  - `account mode prefills the e-mail in both dialogs`; `keys and own-gateway modes leave it empty`.
  - HTTP client against a local `HttpServer`: 201 → ok; 429 → `rate_limited`; 400 / 413 → `rejected`; refused
    connection → `network`; `onFailure` gets status and code.
  - `layout_overflow_test.dart`: the header with the new icon and both dialogs in uz/ru/tr/en, macOS and Windows looks,
    at the narrowest window, have no overflow.
- [ ] **Step 2: Run** `flutter test test/bug_report_test.dart` → fail.
- [ ] **Step 3: Implement**; `flutter gen-l10n`; `dart format lib test`.
- [ ] **Step 4: Run** `flutter analyze && flutter test` → no issues, all pass.
- [ ] **Step 5: Commit** — `App: Report a problem with the diagnostic log; account e-mail prefilled`.

### Task A6: verification, docs and hand-over

- [ ] **Step 1: Gates** — `cd apps/desktop && flutter analyze && flutter test`; `cd native/LiveBridgeAudio && swift
  test`; `native/livebridge_core/tests/run.sh`; `npm test && npm run typecheck` (repo root, unchanged code but cheap);
  `flutter build macos --debug`.
- [ ] **Step 2: Real-app screenshots** — the integration-test screenshot tool from the step-4 notes
  (`accounts-step4-tools/`), copied into `integration_test/`, run with `LIVEBRIDGE_EPHEMERAL_SETTINGS=1`, lifecycle
  forced to `resumed`: main header with the icon, onboarding header, the report dialog (empty, filled, with the
  preview open, an error), the feedback dialog prefilled — uz/ru/tr/en × light/dark × macOS/Windows looks. Delete the
  tool from the repo afterwards; sheets go to the notes folder (they may show the owner's process names — keep local).
- [ ] **Step 3: Docs** — `docs/privacy.md` (what a report carries, that the user sees it first, device names
  included), `IMPLEMENTATION_STATUS.md` (one row), the wiki page `Privacy-and-Security.md` (not published).
- [ ] **Step 4: Hand-over** — release-note lines (statistics on by default, Report a problem) and what waits for the
  owner (site deploy, a real report from the app, Windows workflow after a push, wiki publish) in the notes folder
  and the final report. Nothing pushed, merged, deployed or released.
