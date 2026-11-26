# Privacy, consent and data handling

## What the tool does with speech

| Data | Where it goes | Kept? |
|---|---|---|
| Your microphone audio | Leaves the Mac only while push-to-talk is held (or an automatic turn mode is on) during a session you started. Mac → your gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Meeting app audio (the other participant) | Only the processes you selected, only during a session. Mac → gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Transcripts and translations | Gateway → Gemini (translation) → ElevenLabs (speech synthesis) → back to the Mac. Shown as captions. | In RAM only; gone when the session or app closes. The last 4 turns per direction are sent with each translation request as context. |
| Gateway access token | macOS login Keychain. | Until you change it. |
| Device choices, language, mode, gateway URL, interface language, the chosen voices | macOS UserDefaults. | Until changed. No content. |
| Voice list and samples | The list of your ElevenLabs account's voices: gateway → ElevenLabs → the app, when a voice picker is opened or a chosen voice needs its name. A sample you play is downloaded by the app straight from the provider's public sample storage. | The gateway keeps the list in memory for 10 minutes. Nothing is stored on disk. |
| **Conversation export** (text of both speakers) | Only when you press **Export conversation** and choose where to save. A Markdown file on your disk. | Until you delete the file. |
| **Analytics log** (numbers only) | `~/Library/Application Support/LiveBridge/analytics.jsonl` on this Mac. Stays there unless you opt in to sharing (next row). | Until you press **Clear log** (capped at 20 MB plus one previous file). |
| **Shared statistics** (opt-in, off by default) | The same numbers-only records, with a random install ID, sent to the developer's collector at `jaysonkhan.com`. | Raw records 180 days on the collector; only aggregates are published. |
| **Feedback** | Only when you write and submit it: your message, optionally your e-mail and a 1–5 rating. | Until the developer deletes it. |

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

### Sharing statistics with the developer (opt-in)

Off by default. If you switch on **Share anonymous statistics** the app uploads those same numbers-only records to
the developer's collector so latency and error rates can be compared across installs. What travels: the records
above, the app version, the macOS version, the interface language and a random install ID created at that moment
(not derived from your hardware, account or network). What never travels: anything that was said, translations,
audio, device names, the gateway address, keys. The collector does not store IP addresses with the data and
publishes aggregates only (`https://jaysonkhan.com/services/livebridge/`). Like any website, the server keeps an
ordinary access log in which a request's address appears; it is not linked to the records. Switching the option off
stops uploads.
The exact wire format is in `docs/telemetry-api.md`.

Forks: the collector address is a default in the source (`TelemetryUploader.defaultEndpoint`) and can be changed
with the `telemetryEndpoint` preference or removed entirely.

### Feedback

**Send feedback** posts the text you type to the same collector, with your e-mail and a rating only if you fill
them in. It is tied to your install ID only when statistics sharing is on.

## Logs

Gateway logs hold event names, session ids, counts, durations and provider error codes. Transcript text, audio,
tokens and provider payloads cannot be logged: log fields are restricted to primitives and no call site passes
content (tested in `tests/integration`). The app does not log captions.

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
