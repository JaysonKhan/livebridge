// What an account session uses, and the reports that charge it. The audio and turn paths only add integers to the
// meter; the reporter asks the site in the background, so a slow or failed report never delays audio. The site turns
// the raw counters into units and answers with the balance that is left.
import type { Direction } from "../../../packages/protocol/src/index.ts";
import type { SiteClient, UsageReport } from "./site.ts";

/** 16 kHz s16le mono capture audio. */
const BYTES_PER_MS = 32;
/** The most the site accepts in one report; more is split across consecutive reports. */
const MAX_STT_MS = 120_000;
const MAX_TTS_CHARS = 20_000;
/** Consecutive failed reports before the session is stopped; also what the final report is allowed at the end. */
const MAX_FAILURES = 3;

export type Usage = { sttMsOut: number; sttMsIn: number; ttsChars: number };

export class UsageMeter {
  private readonly sttBytes: Record<Direction, number> = { out: 0, in: 0 };
  private ttsChars = 0;

  /** Bytes speech-to-text accepted on one lane. */
  addStt(direction: Direction, bytes: number) {
    this.sttBytes[direction] += bytes;
  }

  /** Text sent to synthesis, in characters (code points). */
  addTts(text: string) {
    this.ttsChars += [...text].length;
  }

  /** Hands over the usage since the last take; bytes short of a whole millisecond stay for the next one. */
  take(): Usage {
    const sttMsOut = Math.floor(this.sttBytes.out / BYTES_PER_MS);
    const sttMsIn = Math.floor(this.sttBytes.in / BYTES_PER_MS);
    this.sttBytes.out -= sttMsOut * BYTES_PER_MS;
    this.sttBytes.in -= sttMsIn * BYTES_PER_MS;
    const ttsChars = this.ttsChars;
    this.ttsChars = 0;
    return { sttMsOut, sttMsIn, ttsChars };
  }
}

export interface ReporterOptions {
  site: SiteClient;
  accountId: string;
  sessionId: string;
  meter: UsageMeter;
  everyMs: number;
  /** The balance the site answered after a report it accepted. */
  onBalance(units: number): void;
  /** The session must end. Called at most once, and never once stop() has begun. */
  onFatal(code: "balance_exhausted" | "billing_unavailable"): void;
}

export class BillingReporter {
  private readonly options: ReporterOptions;
  private timer: NodeJS.Timeout | null = null;
  private seq = 0;
  /** Taken from the meter but not yet in a report. */
  private readonly carry: Usage = { sttMsOut: 0, sttMsIn: 0, ttsChars: 0 };
  /**
   * Sent and not yet accepted. Resent exactly as it is: the site charges a sequence number once and ignores new usage
   * under a number it has seen, so a retry never carries anything else.
   */
  private pending: UsageReport | null = null;
  private failures = 0;
  private inFlight: Promise<void> | null = null;
  private fatal = false;
  private stopping: Promise<void> | null = null;

  constructor(options: ReporterOptions) {
    this.options = options;
  }

  start() {
    if (this.timer || this.fatal || this.stopping) return;
    this.timer = setInterval(() => this.tick(), this.options.everyMs);
  }

  /** Sends what is left (up to three failed attempts in all, then gives up quietly). The same promise every call. */
  stop(): Promise<void> {
    return (this.stopping ??= this.finish());
  }

  private tick() {
    // One site call at a time: an interval that finds one still unanswered leaves it be.
    if (this.inFlight || this.fatal || this.stopping) return;
    this.inFlight = this.report().finally(() => (this.inFlight = null));
  }

  private async report() {
    let report = this.pending ?? this.cut();
    while (report) {
      let balance: number;
      try {
        ({ balanceUnits: balance } = await this.options.site.usage(report));
      } catch {
        // Every failure counts, whatever the site said; the same report goes again at the next interval.
        if (++this.failures >= MAX_FAILURES) this.die("billing_unavailable");
        return;
      }
      this.accepted();
      if (this.stopping) return;
      this.options.onBalance(balance);
      if (balance <= 0) return this.die("balance_exhausted");
      // More was used than one report may carry: the rest goes now, not at the next interval.
      report = this.carried() ? this.cut() : null;
    }
  }

  private async finish() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    await this.inFlight;
    for (let failures = 0; failures < MAX_FAILURES; ) {
      const report = this.pending ?? this.cut();
      if (!report) return;
      try {
        await this.options.site.usage(report);
        this.accepted();
      } catch {
        failures++;
      }
    }
  }

  /** Moves the meter into the carry and cuts the next report from it, no larger than the site accepts. */
  private cut(): UsageReport | null {
    const taken = this.options.meter.take();
    const carry = this.carry;
    carry.sttMsOut += taken.sttMsOut;
    carry.sttMsIn += taken.sttMsIn;
    carry.ttsChars += taken.ttsChars;
    if (!this.carried()) return null;
    const report: UsageReport = {
      account_id: this.options.accountId,
      session_id: this.options.sessionId,
      seq: this.seq,
      stt_ms_out: Math.min(carry.sttMsOut, MAX_STT_MS),
      stt_ms_in: Math.min(carry.sttMsIn, MAX_STT_MS),
      tts_chars: Math.min(carry.ttsChars, MAX_TTS_CHARS),
    };
    carry.sttMsOut -= report.stt_ms_out;
    carry.sttMsIn -= report.stt_ms_in;
    carry.ttsChars -= report.tts_chars;
    return (this.pending = report);
  }

  private carried() {
    return this.carry.sttMsOut > 0 || this.carry.sttMsIn > 0 || this.carry.ttsChars > 0;
  }

  private accepted() {
    this.pending = null;
    this.seq++;
    this.failures = 0;
  }

  private die(code: "balance_exhausted" | "billing_unavailable") {
    this.fatal = true;
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    if (!this.stopping) this.options.onFatal(code);
  }
}
