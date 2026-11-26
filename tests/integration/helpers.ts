// Test harness: a real gateway on an ephemeral port plus a protocol-speaking client.
// Everything here uses FAKE providers or local MOCK provider servers. Nothing in tests/integration touches a real API.
import { createHmac, timingSafeEqual } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, type Server, type ServerResponse } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
import type {
  ProviderFactory,
  Voice,
} from "../../services/gateway/src/providers/types.ts";
import { createGateway } from "../../services/gateway/src/server.ts";

export const ACCESS_TOKEN = "test-access-token-0123456789abcdef0123";

export async function startGateway(
  options: {
    fake?: FakeOptions;
    env?: Record<string, string>;
    /** Replaces the factory the mode would build, e.g. to count or fail calls. */
    factory?: ProviderFactory;
    voicesCacheMs?: number;
  } = {},
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
    options.factory ??
    (config.PROVIDER_MODE === "real"
      ? createRealProviders(config, log)
      : createFakeProviders({ delayMs: 2, ...options.fake }));
  const gateway = createGateway({
    config,
    factory,
    log,
    retryDelayMs: () => 20,
    voicesCacheMs: options.voicesCacheMs,
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

export async function listVoices(base: string, token = ACCESS_TOKEN) {
  const response = await fetch(`${base}/v1/voices`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  return {
    status: response.status,
    body: (await response.json()) as { voices?: Voice[]; error?: string },
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
    overrides: {
      out?: object;
      in?: object;
      translation_model?: string;
      voices?: { out?: string; in?: string };
    } = {},
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
      voices: overrides.voices,
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

// ---- a fake of the owner's site: the same checks the real internal API makes, over a unix socket ----

/** What a fake-site handler answers: an object is sent as JSON, a string as raw text. */
export type FakeSiteReply = { status: number; body: unknown };
/** Returned by a handler to keep the request open without answering. */
export const NEVER_ANSWER = Symbol("never-answer");
export type FakeSiteRecord = {
  path: string;
  /** The parsed JSON body, or undefined when it was not JSON. */
  body: any;
  rawBody: string;
  headers: Record<string, string | string[] | undefined>;
};

export async function startFakeSite(options: {
  secret: string;
  handle: (path: string, body: any) => FakeSiteReply | typeof NEVER_ANSWER;
  /** The Host the site expects. */
  host?: string;
  /** Seconds of clock difference the site accepts. */
  skewSeconds?: number;
}) {
  const host = options.host ?? "jaysonkhan.com";
  const skew = options.skewSeconds ?? 60;
  // Short on purpose: unix socket paths are limited to ~104 bytes on macOS.
  const dir = mkdtempSync(join(tmpdir(), "lbs-"));
  const socketPath = join(dir, "s");
  /** Every request that passed verification. */
  const requests: FakeSiteRecord[] = [];
  /** One line per request that failed verification (answered 404, like the real site). */
  const failures: string[] = [];
  const hanging = new Set<ServerResponse>();

  function verify(
    req: import("node:http").IncomingMessage,
    raw: string,
  ): string | null {
    if (req.method !== "POST") return "method";
    if (
      req.url !== "/internal/livebridge/v1/authorize/" &&
      req.url !== "/internal/livebridge/v1/usage/"
    )
      return "path";
    if (req.headers.host !== host) return "host";
    if (req.headers["x-forwarded-proto"] !== "https") return "x-forwarded-proto";
    if (req.headers["content-type"] !== "application/json") return "content-type";
    if (req.headers["x-real-ip"] !== undefined) return "x-real-ip present";
    if (req.headers["x-forwarded-for"] !== undefined) return "x-forwarded-for present";
    const timestamp = String(req.headers["x-livebridge-timestamp"] ?? "");
    if (!/^\d+$/.test(timestamp)) return "timestamp format";
    if (Math.abs(Date.now() / 1000 - Number(timestamp)) > skew) return "timestamp stale";
    const expected = createHmac("sha256", options.secret)
      .update(`${timestamp}.${raw}`)
      .digest("hex");
    const given = String(req.headers["x-livebridge-signature"] ?? "");
    if (
      given.length !== expected.length ||
      !timingSafeEqual(Buffer.from(given), Buffer.from(expected))
    )
      return "signature";
    return null;
  }

  const server: Server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      const rawBody = Buffer.concat(chunks).toString("utf8");
      const problem = verify(req, rawBody);
      if (problem) {
        failures.push(`${req.method} ${req.url}: ${problem}`);
        res.writeHead(404, { "content-type": "text/html" });
        res.end("<html><body>Not Found</body></html>");
        return;
      }
      let body: any;
      try {
        body = JSON.parse(rawBody);
      } catch {
        body = undefined;
      }
      requests.push({ path: req.url!, body, rawBody, headers: req.headers });
      const reply = options.handle(req.url!, body);
      if (reply === NEVER_ANSWER) {
        hanging.add(res);
        res.on("close", () => hanging.delete(res));
        return;
      }
      const isText = typeof reply.body === "string";
      res.writeHead(reply.status, {
        "content-type": isText ? "text/html" : "application/json",
      });
      res.end(isText ? (reply.body as string) : JSON.stringify(reply.body));
    });
  });
  await new Promise<void>((resolve) => server.listen(socketPath, resolve));

  return {
    socketPath,
    host,
    requests,
    failures,
    async close() {
      for (const res of hanging) res.destroy();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      rmSync(dir, { recursive: true, force: true });
    },
  };
}
