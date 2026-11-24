// Test harness: a real gateway on an ephemeral port plus a protocol-speaking client.
// Everything here uses FAKE providers or local MOCK provider servers. Nothing in tests/integration touches a real API.
import WebSocket from "ws";
import {
  decodeFrame,
  encodeFrame,
  type AudioFrame,
  type ClientMessage,
  type Direction,
  type ServerMessage,
} from "../../packages/protocol/src/index.ts";
import { loadConfig } from "../../services/gateway/src/config.ts";
import { createLogger } from "../../services/gateway/src/log.ts";
import {
  createFakeProviders,
  type FakeOptions,
} from "../../services/gateway/src/providers/fake.ts";
import { createRealProviders } from "../../services/gateway/src/providers/real.ts";
import { createGateway } from "../../services/gateway/src/server.ts";

export const ACCESS_TOKEN = "test-access-token-0123456789abcdef0123";

export async function startGateway(
  options: { fake?: FakeOptions; env?: Record<string, string> } = {},
) {
  const logLines: string[] = [];
  const config = loadConfig({
    PROVIDER_MODE: "fake",
    GATEWAY_ACCESS_TOKEN: ACCESS_TOKEN,
    PORT: "0",
    ...options.env,
  });
  const log = createLogger((line) => logLines.push(line));
  // PROVIDER_MODE=real here always means the real adapters pointed at local mock provider servers.
  const factory =
    config.PROVIDER_MODE === "real"
      ? createRealProviders(config, log)
      : createFakeProviders({ delayMs: 2, ...options.fake });
  const gateway = createGateway({
    config,
    factory,
    log,
    retryDelayMs: () => 20,
  });
  const port = await gateway.listen();
  return { gateway, port, base: `http://127.0.0.1:${port}`, logLines, config };
}

export async function issueSession(base: string, token = ACCESS_TOKEN) {
  const response = await fetch(`${base}/v1/sessions`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
  });
  return {
    status: response.status,
    body: (await response.json()) as {
      session_id?: string;
      token?: string;
      error?: string;
    },
  };
}

export class TestClient {
  readonly messages: ServerMessage[] = [];
  readonly frames: AudioFrame[] = [];
  closed = false;
  private readonly ws: WebSocket;
  private waiters: (() => void)[] = [];

  private constructor(ws: WebSocket) {
    this.ws = ws;
    ws.on("message", (data, isBinary) => {
      if (isBinary) this.frames.push(decodeFrame(data as Buffer));
      else this.messages.push(JSON.parse(data.toString()));
      this.wake();
    });
    ws.on("close", () => {
      this.closed = true;
      this.wake();
    });
  }

  static async connect(base: string): Promise<TestClient> {
    const { body } = await issueSession(base);
    return TestClient.open(base, body.token!);
  }

  static open(base: string, token: string): Promise<TestClient> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`${base.replace("http", "ws")}/v1/realtime`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const client = new TestClient(ws);
      ws.once("open", () => resolve(client));
      ws.once("unexpected-response", (_req, res) =>
        reject(new Error(`upgrade rejected: ${res.statusCode}`)),
      );
      ws.once("error", reject);
    });
  }

  send(message: ClientMessage) {
    this.ws.send(JSON.stringify(message));
  }

  sendRaw(data: string | Uint8Array) {
    this.ws.send(data);
  }

  sendFrame(
    frame: Omit<AudioFrame, "kind" | "flags" | "timestampUs" | "turnId"> &
      Partial<AudioFrame>,
  ) {
    this.ws.send(
      encodeFrame({
        kind: "capture",
        flags: 0,
        timestampUs: 0n,
        turnId: 0,
        ...frame,
      }),
    );
  }

  /** Sends PCM as 20 ms capture frames; returns the next sequence number. */
  sendAudio(
    direction: Direction,
    generation: number,
    pcm: Buffer,
    sequence = 0,
  ): number {
    for (let at = 0; at < pcm.length; at += 640) {
      this.sendFrame({
        direction,
        generation,
        sequence: sequence++,
        payload: pcm.subarray(at, at + 640),
      });
    }
    return sequence;
  }

  /** Resolves with the first truthy value `probe` returns, re-evaluated on every incoming message. */
  waitFor<T>(
    probe: (client: this) => T | undefined | null | false,
    what: string,
    timeoutMs = 3000,
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      const check = () => {
        const value = probe(this);
        if (!value) return false;
        clearTimeout(timer);
        this.waiters = this.waiters.filter((w) => w !== check);
        resolve(value);
        return true;
      };
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((w) => w !== check);
        const seen = this.messages.map((m) => m.type).join(", ");
        reject(
          new Error(
            `timed out waiting for ${what}; received: [${seen}] and ${this.frames.length} frames`,
          ),
        );
      }, timeoutMs);
      if (!check()) this.waiters.push(check);
    });
  }

  message<T extends ServerMessage["type"]>(
    type: T,
    match: (m: Extract<ServerMessage, { type: T }>) => boolean = () => true,
  ) {
    return this.waitFor(
      (c) =>
        c.messages.find(
          (m): m is Extract<ServerMessage, { type: T }> =>
            m.type === type && match(m as never),
        ),
      type,
    );
  }

  /** Round-trips a ping so everything sent before it has been processed by the gateway. */
  async sync() {
    const t = Math.random();
    this.send({ v: 1, type: "ping", t });
    await this.waitFor(
      (c) => c.messages.some((m) => m.type === "pong" && m.t === t),
      "pong",
    );
  }

  async configure(
    overrides: { out?: object; in?: object; translation_model?: string } = {},
  ) {
    this.send({
      v: 1,
      type: "session.configure",
      capture_format: {
        encoding: "pcm_s16le",
        sample_rate: 16000,
        channels: 1,
      },
      directions: {
        out: {
          enabled: true,
          source_lang: "uz",
          target_lang: "en",
          speak: true,
          commit: "manual",
          ...overrides.out,
        },
        in: {
          enabled: true,
          source_lang: "en",
          target_lang: "uz",
          speak: true,
          commit: "vad",
          ...overrides.in,
        },
      },
      translation_model: overrides.translation_model,
    } as ClientMessage);
    return this.message("session.ready");
  }

  close() {
    this.ws.close();
    return this.waitFor((c) => c.closed, "socket close");
  }

  private wake() {
    for (const waiter of [...this.waiters]) waiter();
  }
}

/** 16 kHz s16le square wave, loud enough for the fake STT to count as speech. */
export function speech(ms: number): Buffer {
  const samples = ms * 16;
  const pcm = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++)
    pcm.writeInt16LE(i % 40 < 20 ? 8000 : -8000, i * 2);
  return pcm;
}

export const silence = (ms: number) => Buffer.alloc(ms * 32);
export const sleep = (ms: number) =>
  new Promise((resolve) => setTimeout(resolve, ms));
