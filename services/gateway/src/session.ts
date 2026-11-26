// One client connection = one call. Validates every message and state transition, then routes to the two
// independent direction pipelines.
import type { RawData, WebSocket } from "ws";
import {
  decodeFrame,
  FrameError,
  parseClientMessage,
  type ClientMessage,
  type Direction,
  type DirectionReady,
  type ServerMessage,
} from "../../../packages/protocol/src/index.ts";
import { BillingReporter, UsageMeter } from "./billing.ts";
import type { Config } from "./config.ts";
import { EchoGuard } from "./echo.ts";
import type { Logger } from "./log.ts";
import { DirectionPipeline } from "./pipeline.ts";
import type { ProviderFactory } from "./providers/types.ts";
import type { SiteClient } from "./site.ts";

/** Who the session was issued to. An account session carries what the site answered when it was authorized. */
export type SessionAuth =
  | { mode: "token" }
  | { mode: "keys" }
  | { mode: "account"; accountId: string; hasPurchase: boolean; balanceUnits: number };

export interface SessionDeps {
  id: string;
  socket: WebSocket;
  config: Config;
  /** For a keys session, the providers built from that session's own keys. */
  factory: ProviderFactory;
  log: Logger;
  retryDelayMs?: (attempt: number) => number;
  /** No recognised speech for this long ends the session; 0 = never. */
  idleTimeoutMs: number;
  auth: SessionAuth;
  site?: SiteClient;
  /** Account sessions only: whether the client may choose this voice. */
  voiceAllowed?: (voiceId: string) => Promise<boolean>;
  /** Called exactly once, when the session closes; gives its admission slot back. */
  onClosed(): void;
}

const MAX_BAD_FRAMES = 50;
const MAX_CONTROL_BYTES = 16_384;
type ErrorCode = Extract<ServerMessage, { type: "error" }>["code"];

export class Session {
  private readonly deps: SessionDeps;
  private phase: "new" | "configuring" | "ready" | "closed" = "new";
  private readonly pipelines = new Map<Direction, DirectionPipeline>();
  private readonly echo = new EchoGuard();
  private badFrames = 0;
  private readonly expiry: NodeJS.Timeout;
  private idle?: NodeJS.Timeout;
  private lastSpeech = Date.now();
  /** Account sessions only. */
  private readonly meter?: UsageMeter;
  private readonly reporter?: BillingReporter;
  private final: Promise<void> = Promise.resolve();

  constructor(deps: SessionDeps) {
    this.deps = deps;
    if (deps.auth.mode === "account") {
      this.meter = new UsageMeter();
      this.reporter = new BillingReporter({
        // An account session is only ever authorized by a site, so there is one.
        site: deps.site!,
        accountId: deps.auth.accountId,
        sessionId: deps.id,
        meter: this.meter,
        everyMs: deps.config.USAGE_REPORT_SECONDS * 1000,
        log: deps.log,
        onBalance: (units) =>
          this.send({ v: 1, type: "account.balance", balance_units: units }),
        onFatal: (code) => {
          deps.log.warn("billing.fatal", { session: deps.id, code });
          this.end(
            code,
            code === "balance_exhausted"
              ? "the account balance is used up"
              : "usage could not be reported; billing is unavailable",
          );
        },
      });
    }
    this.expiry = setTimeout(
      () => this.end("session_expired", "session time limit reached"),
      deps.config.MAX_SESSION_MINUTES * 60_000,
    );
    if (deps.idleTimeoutMs > 0) this.armIdle(deps.idleTimeoutMs);
    deps.socket.on("message", (data, isBinary) =>
      this.onMessage(data, isBinary),
    );
    deps.socket.on("close", () => this.close());
    deps.socket.on("error", () => this.close());
  }

  /** Settles once the final usage report is done; at once for a session that is not billed. */
  get finished(): Promise<void> {
    return this.final;
  }

  close() {
    if (this.phase === "closed") return;
    this.phase = "closed";
    clearTimeout(this.expiry);
    clearTimeout(this.idle);
    for (const pipeline of this.pipelines.values()) pipeline.close();
    this.pipelines.clear();
    // The final report goes out in the background; only a gateway shutdown waits for it.
    if (this.reporter) this.final = this.reporter.stop();
    this.deps.socket.close();
    this.deps.log.info("session.closed", { session: this.deps.id });
    this.deps.onClosed();
  }

  /** One timer per session; speech only records a time, and the timer re-arms for what is left when it fires. */
  private armIdle(ms: number) {
    this.idle = setTimeout(() => {
      const left = this.lastSpeech + this.deps.idleTimeoutMs - Date.now();
      if (left > 0) return this.armIdle(left);
      const minutes = Math.round((this.deps.idleTimeoutMs / 60_000) * 100) / 100;
      this.end("idle_timeout", `no speech for ${minutes} minutes`);
    }, ms);
  }

  /** Tells the client why with a fatal error, then closes. */
  end(code: ErrorCode, message: string) {
    this.send({ v: 1, type: "error", code, message, fatal: true });
    this.close();
  }

  private onMessage(data: RawData, isBinary: boolean) {
    if (this.phase === "closed") return;
    const bytes = Array.isArray(data)
      ? Buffer.concat(data)
      : Buffer.from(data as ArrayBuffer);
    if (isBinary) return this.onFrame(bytes);
    if (bytes.byteLength > MAX_CONTROL_BYTES)
      return this.error("bad_message", "control message too large");
    const message = parseClientMessage(bytes.toString("utf8"));
    if ("error" in message) return this.error("bad_message", message.error);
    this.onControl(message);
  }

  private onFrame(bytes: Buffer) {
    if (this.phase !== "ready")
      return this.error("bad_state", "audio before session.ready");
    try {
      const frame = decodeFrame(bytes);
      if (frame.kind !== "capture") throw new FrameError("bad_kind");
      const pipeline = this.pipelines.get(frame.direction);
      if (!pipeline)
        return this.error(
          "bad_state",
          `direction ${frame.direction} is not enabled`,
        );
      pipeline.onCaptureFrame(frame);
    } catch (error) {
      if (!(error instanceof FrameError)) throw error;
      if (++this.badFrames > MAX_BAD_FRAMES)
        return this.end("bad_frame", "too many invalid audio frames");
      this.error("bad_frame", error.message);
    }
  }

  private onControl(message: ClientMessage) {
    if (message.type === "ping")
      return this.send({ v: 1, type: "pong", t: message.t });
    if (message.type === "session.configure") {
      if (this.phase !== "new")
        return this.error("bad_state", "session is already configured");
      return void this.configure(message);
    }
    if (this.phase !== "ready")
      return this.error("bad_state", `${message.type} before session.ready`);

    const pipeline = this.pipelines.get(message.direction);
    if (!pipeline)
      return this.error(
        "bad_state",
        `direction ${message.direction} is not enabled`,
      );
    let problem: string | null = null;
    switch (message.type) {
      case "capture.start":
        problem = pipeline.captureStart(message.generation);
        break;
      case "capture.pause":
        pipeline.capturePause();
        break;
      case "capture.stop":
        pipeline.captureStop();
        break;
      case "turn.commit":
        pipeline.commit();
        break;
      case "turn.cancel":
        problem = pipeline.cancelTo(message.generation);
        break;
      case "playback.start":
      case "playback.end":
        // Client-side observation, distinct from provider completion: logged, and the end of playback bounds how
        // long that turn can still come back as an echo.
        if (message.type === "playback.end")
          this.echo.playbackEnded(message.direction, message.turn_id);
        this.deps.log.info(message.type, {
          session: this.deps.id,
          direction: message.direction,
          turn: message.turn_id,
        });
        break;
    }
    if (problem) this.error("bad_state", problem);
  }

  private async configure(
    message: Extract<ClientMessage, { type: "session.configure" }>,
  ) {
    const { config, factory, log, id } = this.deps;
    const model = message.translation_model ?? config.TRANSLATION_MODEL;
    if (!config.allowedTranslationModels.includes(model)) {
      return this.error(
        "bad_message",
        "translation_model is not on the allowed list",
      );
    }
    // Phase "configuring" while the voices are checked, so a second configure cannot slip in.
    this.phase = "configuring";
    const named = [message.voices?.out, message.voices?.in].filter((v) => v !== undefined);
    if (this.deps.voiceAllowed && named.length) {
      const allowed = await Promise.all(named.map(this.deps.voiceAllowed));
      if (this.phase !== "configuring") return;
      if (!allowed.every(Boolean)) {
        this.phase = "new";
        return this.error("bad_message", "voice is not on the allowed list");
      }
    }
    for (const direction of ["out", "in"] as const) {
      const directionConfig = message.directions[direction];
      if (!directionConfig.enabled) continue;
      this.pipelines.set(
        direction,
        new DirectionPipeline({
          direction,
          config: directionConfig,
          factory,
          translationModel: model,
          voiceId: message.voices?.[direction],
          glossary: message.glossary ?? [],
          echo: this.echo,
          log,
          emit: (m) => this.send(m),
          sendAudio: (frame) => {
            if (this.phase !== "closed")
              this.deps.socket.send(frame, { binary: true });
            return this.deps.socket.bufferedAmount;
          },
          onReadyChanged: () => this.phase === "ready" && this.announce(),
          retryDelayMs: this.deps.retryDelayMs,
          meter: this.meter,
          onSpeech: this.onSpeech,
        }),
      );
    }
    await Promise.all([...this.pipelines.values()].map((p) => p.open()));
    if (this.phase !== "configuring") return;
    this.phase = "ready";
    log.info("session.ready", {
      session: id,
      out: this.pipelines.get("out")?.ready,
      in: this.pipelines.get("in")?.ready,
    });
    this.announce();
    // Once, after the first announcement; later announcements are provider state changes, not news about money.
    if (this.deps.auth.mode === "account")
      this.send({
        v: 1,
        type: "account.balance",
        balance_units: this.deps.auth.balanceUnits,
      });
    this.reporter?.start();
  }

  private readonly onSpeech = () => {
    this.lastSpeech = Date.now();
  };

  /** Sent after configuration and again whenever a direction's provider state changes — never optimistically. */
  private announce() {
    const { factory, config, id } = this.deps;
    const describe = (direction: Direction): DirectionReady => {
      const pipeline = this.pipelines.get(direction);
      return {
        enabled: !!pipeline,
        ready: pipeline?.ready ?? false,
        speak: pipeline?.speaks ?? false,
        synth_sample_rate: factory.synthSampleRate,
      };
    };
    this.send({
      v: 1,
      type: "session.ready",
      session_id: id,
      providers: { ...factory.names, mock: factory.mock },
      directions: { out: describe("out"), in: describe("in") },
      max_session_seconds: config.MAX_SESSION_MINUTES * 60,
    });
  }

  private send(message: ServerMessage) {
    if (this.phase !== "closed") this.deps.socket.send(JSON.stringify(message));
  }

  private error(code: ErrorCode, message: string) {
    this.send({ v: 1, type: "error", code, message, fatal: false });
  }
}
