# Privacy, consent and data handling

## What the tool does with speech

| Data | Where it goes | Kept? |
|---|---|---|
| Your microphone audio | Leaves your computer only while push-to-talk is held (or an automatic turn mode is on) during a session you started. Computer → your gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Meeting app audio (the other participant) | Only the processes you selected, only during a session. Computer → gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Transcripts and translations | Gateway → Gemini (translation) → ElevenLabs (speech synthesis) → back to the computer. Shown as captions. | In RAM only; gone when the session or app closes. The last 4 turns per direction are sent with each translation request as context. |
| Gateway access token | macOS login Keychain; on Windows the Credential Manager. | Until you change it. |
| Device choices, language, mode, gateway URL, interface language, the chosen voices (id and name) | macOS UserDefaults; on Windows `%APPDATA%\LiveBridge\settings.json`. | Until changed. No content. |
| Voice list and samples | The list of your ElevenLabs account's voices: gateway → ElevenLabs → the app, each time a voice picker is opened and at no other time. A sample you play is downloaded by the app straight from the provider's public sample storage. | The gateway keeps the list in memory for 10 minutes. Nothing is stored on disk. |
| **Conversation export** (text of both speakers) | Only when you press **Export conversation** and choose where to save. A Markdown file on your disk. | Until you delete the file. |
| **Analytics log** (numbers only) | `~/Library/Application Support/LiveBridge/analytics.jsonl` on a Mac, `%APPDATA%\LiveBridge\analytics.jsonl` on Windows. Shared with the developer unless you switch sharing off (next row). | Until you press **Clear log** (capped at 20 MB plus one previous file). |
| **Shared statistics** (numbers only, **on by default**, switch off in Analytics) | The same numbers-only records, with a random install ID, sent to the developer's collector at `jaysonkhan.com`. | Raw records 180 days on the collector; only aggregates are published. |
| **Feedback** | Only when you write and submit it: your message, optionally your e-mail and a 1–5 rating. | Until the developer deletes it. |
| **Diagnostic log** (no speech, keys or tokens) | In memory and in `diagnostics.log` next to the analytics log (at most about 512 KB with one previous file). Leaves the computer only inside a problem report you send. | Rolls over by itself; deleted with the folder. |
| **Problem report** | Only when you press **Send** in **Report a problem**: your description, the e-mail in the form, the app and OS version, the connection mode and — unless you untick it — the device list and the diagnostic log. You can see exactly what goes before sending. | Until the developer deletes it. |

Nothing is captured before **Start session** and the consent confirmation, and nothing after stop, panic or app
exit. There is no audio recording and no automatic transcript storage: the gateway keeps nothing (`STORE_CONTENT`
must be `false`; any other value stops it at startup), and the app keeps captions in RAM only unless you export them.

### Conversation export

The export contains what **both** people said, with the translations. It is written only on an explicit action, to a
location you pick, and the app asks once per run whether the other participant agreed to it. Treat the file like a
recording: the same consent, confidentiality and platform rules apply.

### Analytics log

To judge speed and quality over time the app logs, per turn: stage timings (speech-to-text, translation, speech
synthesis, end to end), length of the audio, **length** of the texts in characters, the model that answered, error
codes, reconnects, turns where nothing was recognised, and your thumbs-up / thumbs-down. It never contains the text
itself (covered by a test). It can be switched off, exported and cleared from the Analytics panel. Sessions against
fake providers are excluded from the figures.

### Sharing statistics with the developer (on by default)

**On by default.** Unless you switch off **Share anonymous statistics** (Analytics panel), the app uploads those same
numbers-only records to the developer's collector, so that errors and slow turns on other people's computers reach the
developer and latency can be compared across installs. Up to release 1.2.0 this was off by default: if you switched it
off yourself, it stays off after the update (the app keeps that choice); if you had switched the analytics log off,
sharing stays off too. An install that never touched either switch starts sharing after the update **from that moment
on**: numbers recorded before the update are not sent. What travels: the records above, the app version, the operating system's version
(macOS or Windows), the interface language and a random install ID created the first time sharing is on (not derived
from your hardware, account or network). What never travels: anything that was said, translations,
audio, device names, the gateway address, keys. The collector does not store IP addresses with the data and
publishes aggregates only (`https://jaysonkhan.com/services/livebridge/`). Like any website, the server keeps an
ordinary access log in which a request's address appears; it is not linked to the records. Switching the option off
stops uploads at once.
The exact wire format is in `docs/telemetry-api.md`.

Forks: the collector address is a default in the source (`TelemetryUploader.defaultEndpoint`) and can be changed
with the `telemetryEndpoint` preference or removed entirely.

### Feedback

**Send feedback** posts the text you type to the same collector, with your e-mail and a rating only if you fill
them in. It is tied to your install ID only when statistics sharing is on. When you are signed in with an account, the
e-mail field starts with your account's address; you can change or clear it before sending.

### Problem reports and the diagnostic log

From the moment the app starts it keeps a **diagnostic log** of what happened, so a problem can be traced: the app
and system version, the connection mode, your account's e-mail (only when signed in with an account), the gateway's
host name (never its full address or token), your audio devices and which ones you chose (names, sample rates,
whether one is Bluetooth or USB), the meeting apps you chose, settings, each Start, state changes and reconnects,
error codes, failed requests to the site or the gateway (status and code only), the timings of each turn, and app
errors. It **never** holds what was said, translations, audio levels, keys, tokens or the refresh token: captions are
not recorded at all, and every line passes a filter that replaces anything shaped like a key or token (and your own
gateway's token) with `[secret]` — covered by tests. The log stays on your computer.

**Report a problem** (the bug icon at the top right) sends a description you write, the e-mail in the form (in
account mode it starts with your account's address; you can clear it), the app and OS version and the connection
mode to the developer's site. **Include the diagnostic log** is on by default and adds the device list and the log;
**Show what will be sent** shows exactly that text first. The report goes to the developer only: the site keeps it
for the developer's eyes and notifies the developer in a private Telegram group with a short summary and the log as a
file, with every e-mail address in them hidden. It is tied
to your install ID only when statistics sharing is on.

### The hosted gateway (account and own-keys modes)

With an account or your own keys the app talks to the developer's hosted gateway instead of one you run. It is the
same gateway code, with the same rules:

- **Audio and text pass through and are not stored.** Your audio, the transcripts and the translations go from the
  app through the gateway to the providers and back, in memory only, as described above. The gateway writes no
  content to disk and its logs hold no content.
- **Account usage is counted, never content.** For an account session the gateway asks the developer's site once, at
  the start, who the account is and whether it has a balance. While the session runs it reports, every 10 seconds by
  default and once at the end, how many milliseconds of audio were sent to speech-to-text in each direction and how many
  characters were sent to speech synthesis, with the account and session ids. The site turns these counts into the
  entries in your account history. No audio, transcript or translation is part of a report. The gateway does not keep
  the account's access token after that first check.
- **What an account holds on the developer's site:** the e-mail address and name from your Google account and its
  Google id; the balance and its history (trial, purchases, usage counts, refunds, adjustments); and, for each
  connected app, the computer's name the app sends at sign-in (up to 80 characters, shown on the connect page) and a
  random install id the app made once and keeps in its preferences. Access and refresh tokens are kept only as one-way
  hashes. Nothing that was said is part of it.
- **Own keys travel over TLS and live in memory for one session.** Your ElevenLabs and Gemini keys go to the gateway
  over HTTPS when a session starts and are used only to call those providers for that session. They are held in the
  gateway's memory until the session ends (or, if it never connects, until its one-minute start token expires),
  never logged and never written to disk. When the voice picker lists your ElevenLabs voices, the key travels in the
  same way; the gateway keeps that list in memory for 10 minutes under a one-way hash of the key, not the key itself.
  With your own keys, the providers' terms are those of your own provider accounts.

## Logs

Gateway logs hold event names, session ids, counts, durations and provider error codes. Transcript text, audio,
tokens and provider payloads cannot be logged: log fields are restricted to primitives and no call site passes
content (tested in `tests/integration`). The app does not log captions; its diagnostic log is described above.

## Third-party processing — not controlled by this project

LiveBridge storing nothing does not mean the providers store nothing.

- **ElevenLabs:** `enable_logging=false` (zero retention) is an Enterprise feature per their API reference; on other
  plans requests are logged under their terms. Check the account's data settings.
- **Google Gemini:** requests are sent with `store: false` so prompts are not kept in AI Studio logs on projects
  where storing is the default. Paid-tier content is not used for training per Google's terms; abuse-monitoring
  retention still applies. Zero retention is not claimed.

Translation runs on one provider at a time. The fallback model is the same provider under the same terms; using it
is shown in the UI and logged. Audio is never fanned out to several providers.

## Consent and conduct

- The app shows a disclosure sentence (English and Russian) before every session and will not start until you
  confirm the other participants were told and agreed. A capture indicator is visible for the whole session.
- Voices: both directions default to "JaysonKhan - Natural Uzbek Voice" (`ehTFHBkERkWR22A3sR8M`), the project
  author's own voice, which the author published in the ElevenLabs Voice Library. You may set any voice you are
  authorised to use instead (for example your own clone) in `.env`, or choose one of your account's voices in the
  app. The remote speaker's voice is never cloned.
- With the default voice the other participant hears a voice that is **not yours**. The disclosure sentence
  therefore says "a synthesized voice"; do not present it as your natural voice.
- The tool only interprets: the translation prompt forbids answering questions or following instructions heard in
  speech, and speech is passed to the model as quoted data. Model output that is empty, runaway or structured is
  rejected rather than spoken.
- No covert use, no impersonation, no automatic interview answers, no screen-share concealment, no meeting bots, no
  script injection into meeting pages. Follow each platform's terms; Upwork pre-contract conversations stay inside
  Upwork's own meeting tools. No platform has approved this tool.
- Recording laws and confidentiality agreements vary; for confidential interviews confirm the other side accepts
  third-party AI processing.

## Third-party software

BlackHole 2ch is installed separately from its official source and is not bundled or redistributed (GPL-3.0; the
name is a trademark of Existential Audio). Distributing this app commercially would need a review of BlackHole's
licence, signing/notarisation, the provider terms for voice cloning, and dependency licences.
