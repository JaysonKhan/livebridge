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
import type { Config } from "./config.ts";
import { EchoGuard } from "./echo.ts";
import type { Logger } from "./log.ts";
import { DirectionPipeline } from "./pipeline.ts";
import type { ProviderFactory } from "./providers/types.ts";

export interface SessionDeps {
  id: string;
  socket: WebSocket;
  config: Config;
  factory: ProviderFactory;
  log: Logger;
  retryDelayMs?: (attempt: number) => number;
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

  constructor(deps: SessionDeps) {
    this.deps = deps;
    this.expiry = setTimeout(
      () => this.fail("session_expired", "session time limit reached"),
      deps.config.MAX_SESSION_MINUTES * 60_000,
    );
    deps.socket.on("message", (data, isBinary) =>
      this.onMessage(data, isBinary),
    );
    deps.socket.on("close", () => this.close());
    deps.socket.on("error", () => this.close());
  }

  close() {
    if (this.phase === "closed") return;
    this.phase = "closed";
    clearTimeout(this.expiry);
    for (const pipeline of this.pipelines.values()) pipeline.close();
    this.pipelines.clear();
    this.deps.socket.close();
    this.deps.log.info("session.closed", { session: this.deps.id });
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
        return this.fail("bad_frame", "too many invalid audio frames");
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
    this.phase = "configuring";
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
  }

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

  private fail(code: ErrorCode, message: string) {
    this.send({ v: 1, type: "error", code, message, fatal: true });
    this.close();
  }
}
