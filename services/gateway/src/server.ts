// HTTP + WebSocket surface:
//   GET  /healthz       no credentials
//   POST /v1/sessions   -> short-lived single-use session token, in one of three modes (body `mode`):
//                         token (no body): Authorization: Bearer <GATEWAY_ACCESS_TOKEN>
//                         account: Authorization: Bearer <account access token>, authorized by the owner's site
//                         keys: the caller's own provider keys in the body
//   GET  /v1/voices     Authorization: Bearer <GATEWAY_ACCESS_TOKEN> -> the voices a session may choose from
//   WSS  /v1/realtime   Authorization: Bearer <session token>
// TLS is terminated by the reverse proxy; this process listens on localhost.
import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import type { AddressInfo } from "node:net";
import { WebSocketServer } from "ws";
import {
  FRAME_HEADER_BYTES,
  MAX_PAYLOAD_BYTES,
  parseSessionRequest,
} from "../../../packages/protocol/src/index.ts";
import { Admission, type Ticket } from "./admission.ts";
import type { Config } from "./config.ts";
import type { Logger } from "./log.ts";
import { createRealProviders } from "./providers/real.ts";
import {
  ProviderError,
  type ProviderFactory,
  type Voice,
} from "./providers/types.ts";
import { Session, type SessionAuth } from "./session.ts";
import { SiteError, type SiteClient } from "./site.ts";

const SESSION_TOKEN_TTL_MS = 60_000;
const SESSION_REQUESTS_PER_MINUTE = 20;
const VOICES_CACHE_MS = 600_000;
const MAX_SESSION_REQUEST_BYTES = 4096;

export interface Gateway {
  listen(): Promise<number>;
  close(): Promise<void>;
  readonly server: Server;
}

export interface GatewayOptions {
  config: Config;
  factory: ProviderFactory;
  log: Logger;
  retryDelayMs?: (attempt: number) => number;
  /** How long a voice list is served without asking the provider again. Default 10 minutes. */
  voicesCacheMs?: number;
  /** The owner's site, which authorizes account sessions. Absent = account sessions are unavailable. */
  site?: SiteClient;
  /** Builds an own-keys session's providers. Default: the real adapters with those keys; the fakes in fake mode. */
  providersFor?: (keys: { elevenlabs: string; gemini: string }) => ProviderFactory;
  /** How long an issued session token waits for its socket. Default 60 seconds. */
  sessionTokenTtlMs?: number;
}

function bearer(req: IncomingMessage): string {
  const header = req.headers.authorization ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

/**
 * Who is asking, for the request limit. Behind the reverse proxy every request arrives from loopback and the proxy
 * names the caller in X-Forwarded-For; its last entry is the one the proxy itself wrote (the sample vhost overwrites
 * the header, a proxy that appends adds its entry at the end). The header is believed only from loopback.
 */
function callerAddress(req: IncomingMessage): string {
  const peer = req.socket.remoteAddress ?? "";
  const forwarded = req.headers["x-forwarded-for"];
  const fromProxy = peer === "127.0.0.1" || peer === "::1" || peer === "::ffff:127.0.0.1";
  const last = typeof forwarded === "string" ? forwarded.split(",").at(-1)!.trim() : "";
  return fromProxy && last ? last : peer;
}

function safeEqual(a: string, b: string) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

/** The body as text, or null once it passes `limit` bytes: the rest is discarded, never buffered. */
function readBody(req: IncomingMessage, limit: number): Promise<string | null> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    let size = 0;
    const onData = (chunk: Buffer) => {
      size += chunk.byteLength;
      if (size <= limit) return void chunks.push(chunk);
      req.off("data", onData);
      req.resume();
      resolve(null);
    };
    req.on("data", onData);
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", () => resolve(null));
  });
}

export function createGateway({
  config,
  factory,
  log,
  retryDelayMs,
  voicesCacheMs = VOICES_CACHE_MS,
  site,
  providersFor = (keys) =>
    config.PROVIDER_MODE === "real"
      ? createRealProviders(
          { ...config, ELEVENLABS_API_KEY: keys.elevenlabs, GEMINI_API_KEY: keys.gemini },
          log,
        )
      : factory,
  sessionTokenTtlMs = SESSION_TOKEN_TTL_MS,
}: GatewayOptions): Gateway {
  /**
   * Issued but not yet connected: token -> what the session needs. A token is consumed by the first upgrade; a keys
   * session's providers (and with them its keys) leave this map at that moment, or when the token expires unused.
   */
  const pending = new Map<
    string,
    {
      id: string;
      expires: number;
      timer: NodeJS.Timeout;
      auth: SessionAuth;
      ticket: Ticket;
      factory: ProviderFactory;
    }
  >();
  /** Connected sessions by the admission ticket each holds. */
  const sessions = new Map<Ticket, Session>();
  const admission = new Admission({
    total: config.MAX_SESSIONS,
    account: config.MAX_ACCOUNT_SESSIONS,
    keys: config.MAX_KEYS_SESSIONS,
    paidReserved: config.PAID_RESERVED_SESSIONS,
  });
  const recentRequests = new Map<string, number[]>();

  const json = (res: ServerResponse, status: number, body: object) => {
    res.writeHead(status, {
      "content-type": "application/json",
      "cache-control": "no-store",
    });
    res.end(JSON.stringify(body));
  };

  /** Takes an issued token out of the map, with its expiry timer. Its slot is the caller's to release or hand on. */
  const forget = (token: string) => {
    const entry = pending.get(token);
    if (!entry) return undefined;
    pending.delete(token);
    clearTimeout(entry.timer);
    return entry;
  };

  /** An unused token's time is up: its slot goes back, and a keys session's keys go with the entry. */
  const expire = (token: string) => {
    const entry = forget(token);
    if (!entry) return;
    admission.release(entry.ticket);
    log.info("session.token_expired", { session: entry.id });
  };

  // Each token's own timer expires it on a quiet gateway; this catches one whose timer has not fired yet.
  const prune = () => {
    const now = Date.now();
    for (const [token, entry] of pending) if (entry.expires <= now) expire(token);
  };

  /** The static token, when one is configured. An empty one never matches, not even an empty bearer. */
  const staticTokenOk = (req: IncomingMessage) =>
    config.GATEWAY_ACCESS_TOKEN !== "" && safeEqual(bearer(req), config.GATEWAY_ACCESS_TOKEN);

  /** The account's newer session has taken this ticket's slot: void the older token, or end the older session. */
  const replace = (old: Ticket) => {
    for (const [token, entry] of pending)
      if (entry.ticket === old) return void forget(token);
    sessions.get(old)?.end("session_replaced", "a newer session of this account started");
  };

  const rateLimited = (ip: string) => {
    const cutoff = Date.now() - 60_000;
    const hits = (recentRequests.get(ip) ?? []).filter((t) => t > cutoff);
    hits.push(Date.now());
    recentRequests.set(ip, hits);
    return hits.length > SESSION_REQUESTS_PER_MINUTE;
  };

  let voices: { list: Voice[]; at: number } | undefined;
  /** The cached list while it is fresh; otherwise the provider's, falling back to the stale one when it fails. */
  const listVoices = async () => {
    if (voices && Date.now() - voices.at < voicesCacheMs) return voices.list;
    try {
      const list = await factory.voices();
      voices = { list, at: Date.now() };
      log.info("voices.listed", { count: list.length });
      return list;
    } catch (error) {
      log.warn("voices.failed", {
        code: error instanceof ProviderError ? error.code : "unknown",
      });
      if (voices) return voices.list;
      throw error;
    }
  };

  /** Who the caller is, or the refusal to send. Account mode asks the site, once. */
  const authorize = async (
    req: IncomingMessage,
    mode: SessionAuth["mode"],
  ): Promise<SessionAuth | { status: number; error: string }> => {
    if (mode === "token")
      return staticTokenOk(req) ? { mode } : { status: 401, error: "unauthorized" };
    // Keys sessions carry their own credentials; any Authorization header is ignored.
    if (mode === "keys") return { mode };
    if (!site) return { status: 503, error: "accounts_unavailable" };
    const accessToken = bearer(req);
    if (!accessToken) return { status: 401, error: "invalid_token" };
    try {
      const account = await site.authorize(accessToken);
      if (account.balanceUnits <= 0) return { status: 402, error: "balance_empty" };
      return { mode, ...account };
    } catch (error) {
      if (error instanceof SiteError && error.code === "invalid_token")
        return { status: 401, error: "invalid_token" };
      log.warn("site.authorize_failed", {
        code: error instanceof SiteError ? error.code : "unknown",
      });
      return { status: 503, error: "billing_unavailable" };
    }
  };

  const issueSession = async (req: IncomingMessage, res: ServerResponse) => {
    const body = await readBody(req, MAX_SESSION_REQUEST_BYTES);
    if (body === null) {
      // What was not read is not wanted: drop the connection after the answer instead of reading on.
      res.setHeader("connection", "close");
      return json(res, 400, { error: "bad_request" });
    }
    const request = parseSessionRequest(body);
    if ("error" in request) return json(res, 400, { error: "bad_request" });
    const auth = await authorize(req, request.mode);
    if ("error" in auth) return json(res, auth.status, { error: auth.error });
    // Keys are not checked up front: a refused key shows up as a provider error once the session opens.
    const sessionFactory =
      request.mode === "keys"
        ? providersFor({
            elevenlabs: request.elevenlabs_api_key,
            gemini: request.gemini_api_key,
          })
        : factory;
    prune();
    const admitted = admission.admit(auth);
    if (!admitted.ok) return json(res, 429, { error: "session_limit" });
    const id = randomUUID();
    if (admitted.replaces) {
      replace(admitted.replaces);
      log.info("session.replaced", { session: id });
    }
    const token = randomBytes(32).toString("base64url");
    pending.set(token, {
      id,
      expires: Date.now() + sessionTokenTtlMs,
      timer: setTimeout(() => expire(token), sessionTokenTtlMs).unref(),
      auth,
      ticket: admitted.ticket,
      factory: sessionFactory,
    });
    log.info("session.issued", { session: id, mode: auth.mode });
    const issued = {
      session_id: id,
      token,
      expires_in: sessionTokenTtlMs / 1000,
      ws_path: "/v1/realtime",
    };
    return json(
      res,
      201,
      auth.mode === "account"
        ? { ...issued, account: { balance_units: auth.balanceUnits } }
        : issued,
    );
  };

  const server = createServer((req, res) => {
    const path = (req.url ?? "").split("?")[0];
    if (req.method === "GET" && path === "/healthz")
      return json(res, 200, { ok: true });
    if (req.method === "POST" && path === "/v1/sessions") {
      if (rateLimited(callerAddress(req))) {
        req.resume();
        return json(res, 429, { error: "rate_limited" });
      }
      return void issueSession(req, res).catch(() => {
        // A fault of ours, not the caller's. The error itself is not logged: it may carry what the caller sent.
        log.error("session.issue_failed");
        if (!res.headersSent) json(res, 500, { error: "internal" });
      });
    }
    if (req.method === "GET" && path === "/v1/voices") {
      if (rateLimited(callerAddress(req))) return json(res, 429, { error: "rate_limited" });
      if (!staticTokenOk(req)) return json(res, 401, { error: "unauthorized" });
      return void listVoices().then(
        (list) => json(res, 200, { voices: list }),
        () => json(res, 502, { error: "voices_unavailable" }),
      );
    }
    json(res, 404, { error: "not_found" });
  });

  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: FRAME_HEADER_BYTES + MAX_PAYLOAD_BYTES,
  });

  server.on("upgrade", (req, socket, head) => {
    const reject = (status: number, reason: string) => {
      socket.write(`HTTP/1.1 ${status} ${reason}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
    };
    if ((req.url ?? "").split("?")[0] !== "/v1/realtime")
      return reject(404, "Not Found");
    prune();
    const entry = forget(bearer(req));
    if (!entry) return reject(401, "Unauthorized");
    let connected = false;
    // A handshake the socket server refuses never reaches the callback; the slot must not stay taken.
    socket.once("close", () => {
      if (!connected) admission.release(entry.ticket);
    });
    wss.handleUpgrade(req, socket, head, (ws) => {
      connected = true;
      const session = new Session({
        id: entry.id,
        socket: ws,
        config,
        factory: entry.factory,
        log,
        retryDelayMs,
        auth: entry.auth,
        site,
        onClosed: () => {
          sessions.delete(entry.ticket);
          admission.release(entry.ticket);
        },
      });
      sessions.set(entry.ticket, session);
      log.info("session.connected", { session: entry.id, mode: entry.auth.mode });
    });
  });

  return {
    server,
    listen: () =>
      new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(config.PORT, config.HOST, () =>
          resolve((server.address() as AddressInfo).port),
        );
      }),
    close: async () => {
      for (const token of pending.keys()) forget(token);
      for (const session of sessions.values()) session.close();
      for (const client of wss.clients) client.terminate();
      await new Promise<void>((resolve) => wss.close(() => resolve()));
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
