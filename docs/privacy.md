# Privacy, consent and data handling

## What the tool does with speech

| Data | Where it goes | Kept? |
|---|---|---|
| Your microphone audio | Leaves the Mac only while push-to-talk is held (or an automatic turn mode is on) during a session you started. Mac → your gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Meeting app audio (the other participant) | Only the processes you selected, only during a session. Mac → gateway → ElevenLabs speech-to-text. | Not stored by LiveBridge. |
| Transcripts and translations | Gateway → Gemini (translation) → ElevenLabs (speech synthesis) → back to the Mac. Shown as captions. | In RAM only; gone when the session or app closes. The last 4 turns per direction are sent with each translation request as context. |
| Gateway access token | macOS login Keychain. | Until you change it. |
| Device choices, language, mode, gateway URL | macOS UserDefaults. | Until changed. No content. |

Nothing is captured before **Start session** and the consent confirmation, and nothing after stop, panic or app
exit. There is no recording, archive, analytics or transcript export. `STORE_CONTENT` must be `false`; any other
value stops the gateway at startup.

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
- Outgoing speech uses **your own** authorised cloned voice. Incoming Uzbek uses a separate stock voice; the remote
  speaker's voice is never cloned, and the gateway refuses to start if both voice ids are the same.
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
