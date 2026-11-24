import type {
  CommitStrategy,
  Lang,
} from "../../../../packages/protocol/src/index.ts";

export class ProviderError extends Error {
  /** Short machine identifier from the provider (HTTP status, `message_type`, ...). Never contains content. */
  readonly code: string;
  /** Retrying the same request cannot succeed (bad credentials, unknown voice/model, quota). */
  readonly permanent: boolean;
  constructor(code: string, message: string, permanent = false) {
    super(message);
    this.code = code;
    this.permanent = permanent;
  }
}

export interface SttEvents {
  /** Mutable hypothesis for the speech since the last commit. Captions only — never translated or spoken. */
  onPartial(text: string): void;
  /** Stable transcript of one committed segment. */
  onCommitted(text: string): void;
  /** The provider session ended without `close()` being called. */
  onDisconnected(error: ProviderError): void;
}

export interface SttOptions {
  language: Lang;
  commit: CommitStrategy;
  events: SttEvents;
}

export interface StreamingSTT {
  /** Resolves once the provider session is actually accepting audio. */
  open(): Promise<void>;
  /** PCM s16le mono 16 kHz. Returns the number of bytes dropped because the bounded queue overflowed. */
  sendAudio(pcm: Uint8Array): number;
  /** Finalise whatever speech is pending (manual strategy; harmless otherwise). */
  commit(): void;
  /** Throw away audio that has not been sent yet. */
  discardPending(): void;
  close(): void;
}

export interface TranslateRequest {
  source: Lang;
  target: Lang;
  text: string;
  /** Recent committed turns of this direction, oldest first. Terminology / pronoun context only. */
  context: { source: string; target: string }[];
  glossary: { source: string; target: string }[];
  model: string;
}

export interface TranslateResult {
  text: string;
  /** The model that actually answered (differs from the request when the fallback was used). */
  model: string;
}

export interface StreamingTranslator {
  /** Optional: get a connection ready before a translation is needed (called when speech starts). */
  warm?(model: string): void;
  translate(
    req: TranslateRequest,
    onDelta: (text: string) => void,
    signal: AbortSignal,
  ): Promise<TranslateResult>;
}

export interface TtsOptions {
  voice: "owner" | "incoming";
  language: Lang;
}

export interface StreamingTTS {
  readonly sampleRate: number;
  open(): Promise<void>;
  /**
   * Speaks one turn. `onAudio` receives PCM s16le mono at `sampleRate`, always whole samples. Resolves when the
   * provider has delivered all audio for the turn. Callers serialise turns: never call while another is in flight.
   * Aborting drops the turn; implementations that cannot cancel a turn recycle their connection.
   */
  synthesize(
    text: string,
    onAudio: (pcm: Uint8Array) => void,
    signal: AbortSignal,
  ): Promise<void>;
  close(): void;
}

export interface ProviderFactory {
  /** True for the deterministic fakes. Surfaced to the client so the UI can never pass a mock off as real. */
  readonly mock: boolean;
  readonly names: { stt: string; translation: string; tts: string };
  readonly synthSampleRate: number;
  stt(options: SttOptions): StreamingSTT;
  translator(): StreamingTranslator;
  tts(options: TtsOptions): StreamingTTS;
}
