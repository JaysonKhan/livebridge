// Deterministic in-process providers for tests and offline development. They produce placeholder text and test
// tones — never a real transcript or translation — and the gateway reports `mock: true` whenever they are in use.
import type {
  ProviderFactory,
  SttOptions,
  StreamingSTT,
  StreamingTTS,
  StreamingTranslator,
  TranslateRequest,
  TtsOptions,
  Voice,
} from "./types.ts";
import { ProviderError } from "./types.ts";

export interface FakeOptions {
  synthSampleRate?: number;
  /** Simulated provider latency per step. */
  delayMs?: number;
  /** Transcripts returned by successive commits; when exhausted a numbered placeholder is used. */
  transcripts?: string[];
  /** Override the translator output; throw to simulate a provider failure. */
  translate?: (req: TranslateRequest) => string;
  /** RMS (16-bit scale) above which audio counts as speech. Lower it to let quiet room noise through. */
  speechRms?: number;
  /** Make `open()` of the given provider fail, to exercise unavailable-provider paths. */
  failOpen?: { stt?: boolean; tts?: boolean };
}

const SPEECH_RMS = 500;
const VAD_SILENCE_MS = 300;
const PARTIAL_EVERY_MS = 500;
const BYTES_PER_MS = 32; // 16 kHz s16le mono

const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason);
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      "abort",
      () => (clearTimeout(timer), reject(signal.reason)),
      { once: true },
    );
  });

function rms(pcm: Uint8Array): number {
  const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength);
  let sum = 0;
  const n = pcm.byteLength >> 1;
  for (let i = 0; i < n; i++) {
    const s = view.getInt16(i * 2, true);
    sum += s * s;
  }
  return n ? Math.sqrt(sum / n) : 0;
}

class FakeSTT implements StreamingSTT {
  private readonly options: SttOptions;
  private readonly fake: FakeOptions;
  private readonly counter: { n: number };
  private speechMs = 0;
  private silenceMs = 0;
  private partialAt = PARTIAL_EVERY_MS;
  private closed = false;
  private segment = 0;
  /** Moved on by fence(): a commit answered after it belongs to an older generation and is never delivered. */
  private epoch = 0;

  constructor(options: SttOptions, fake: FakeOptions, counter: { n: number }) {
    this.options = options;
    this.fake = fake;
    this.counter = counter;
  }

  async open() {
    await sleep(this.fake.delayMs ?? 0);
    if (this.fake.failOpen?.stt)
      throw new ProviderError(
        "auth_error",
        "fake STT refused the session",
        true,
      );
  }

  sendAudio(pcm: Uint8Array) {
    if (this.closed) return 0;
    const ms = pcm.byteLength / BYTES_PER_MS;
    if (rms(pcm) >= (this.fake.speechRms ?? SPEECH_RMS)) {
      this.speechMs += ms;
      this.silenceMs = 0;
      if (this.speechMs >= this.partialAt) {
        this.partialAt += PARTIAL_EVERY_MS;
        // A partial that has not been delivered by the time the segment commits is dropped, as a real
        // recogniser would not report a hypothesis for speech it has already finalised.
        const segment = this.segment;
        const text = `fake partial (${Math.round(this.speechMs)} ms)`;
        this.later(
          () => segment === this.segment && this.options.events.onPartial(text),
        );
      }
    } else if (this.speechMs > 0) {
      this.silenceMs += ms;
      if (this.options.commit !== "manual" && this.silenceMs >= VAD_SILENCE_MS)
        this.commit();
    }
    return 0;
  }

  commit() {
    const spoke = this.speechMs > 0;
    const ms = Math.round(this.speechMs);
    this.discardPending();
    const text = spoke
      ? (this.fake.transcripts?.shift() ??
        `fake transcript ${++this.counter.n} (${ms} ms)`)
      : "";
    const epoch = this.epoch;
    this.later(() => epoch === this.epoch && this.options.events.onCommitted(text));
  }

  fence() {
    this.discardPending();
    this.epoch++;
  }

  discardPending() {
    this.segment++;
    this.speechMs = 0;
    this.silenceMs = 0;
    this.partialAt = PARTIAL_EVERY_MS;
  }

  close() {
    this.closed = true;
  }

  private later(fn: () => void) {
    setTimeout(() => this.closed || fn(), this.fake.delayMs ?? 0);
  }
}

class FakeTranslator implements StreamingTranslator {
  private readonly fake: FakeOptions;
  constructor(fake: FakeOptions) {
    this.fake = fake;
  }

  async translate(
    req: TranslateRequest,
    onDelta: (text: string) => void,
    signal: AbortSignal,
  ) {
    await sleep(this.fake.delayMs ?? 0, signal);
    const text = this.fake.translate
      ? this.fake.translate(req)
      : `(${req.source}→${req.target}) ${req.text}`;
    const cut = Math.ceil(text.length / 2);
    onDelta(text.slice(0, cut));
    await sleep(this.fake.delayMs ?? 0, signal);
    if (cut < text.length) onDelta(text.slice(cut));
    return { text, model: req.model };
  }
}

class FakeTTS implements StreamingTTS {
  readonly sampleRate: number;
  private readonly fake: FakeOptions;
  private readonly hz: number;

  constructor(options: TtsOptions, fake: FakeOptions, sampleRate: number) {
    this.sampleRate = sampleRate;
    this.fake = fake;
    this.hz = options.voice === "owner" ? 440 : 660;
  }

  async open() {
    await sleep(this.fake.delayMs ?? 0);
    if (this.fake.failOpen?.tts)
      throw new ProviderError(
        "voice_not_found",
        "fake TTS has no such voice",
        true,
      );
  }

  async synthesize(
    text: string,
    onAudio: (pcm: Uint8Array) => void,
    signal: AbortSignal,
  ) {
    const totalMs = Math.min(3000, Math.max(200, text.length * 40));
    const chunkSamples = this.sampleRate / 10;
    let sample = 0;
    for (let sent = 0; sent < totalMs; sent += 100) {
      await sleep(this.fake.delayMs ?? 0, signal);
      const chunk = Buffer.alloc(chunkSamples * 2);
      for (let i = 0; i < chunkSamples; i++, sample++) {
        chunk.writeInt16LE(
          Math.round(
            Math.sin((2 * Math.PI * this.hz * sample) / this.sampleRate) * 3276,
          ),
          i * 2,
        );
      }
      onAudio(chunk);
    }
  }

  close() {}
}

/** What the fake account lists. No sample addresses: nothing here can be played. */
export const FAKE_VOICES: Voice[] = [
  {
    id: "fakevoice0000000001",
    name: "Fake Aria",
    gender: "female",
    age: "young",
    accent: "american",
    language: "en",
    use_case: "conversational",
    category: "premade",
  },
  {
    id: "fakevoice0000000002",
    name: "Fake Bruno",
    gender: "male",
    age: "middle_aged",
    accent: "british",
    language: "en",
    use_case: "narration",
    category: "premade",
  },
  {
    id: "fakevoice0000000003",
    name: "Fake Dilnoza",
    gender: "female",
    age: "young",
    language: "uz",
    use_case: "conversational",
    category: "premade",
  },
  {
    id: "fakevoice0000000004",
    name: "Fake Timur",
    gender: "male",
    age: "old",
    language: "ru",
    use_case: "news",
    category: "premade",
  },
];

export function createFakeProviders(fake: FakeOptions = {}): ProviderFactory {
  const synthSampleRate = fake.synthSampleRate ?? 24_000;
  const counter = { n: 0 };
  return {
    mock: true,
    names: { stt: "fake-stt", translation: "fake-translator", tts: "fake-tts" },
    synthSampleRate,
    stt: (options) => new FakeSTT(options, fake, counter),
    translator: () => new FakeTranslator(fake),
    tts: (options) => new FakeTTS(options, fake, synthSampleRate),
    voices: async () => FAKE_VOICES,
  };
}
