// HTTP + WebSocket surface:
//   GET  /healthz       no credentials
//   POST /v1/sessions   Authorization: Bearer <GATEWAY_ACCESS_TOKEN> -> short-lived single-use session token
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
} from "../../../packages/protocol/src/index.ts";
import type { Config } from "./config.ts";
import type { Logger } from "./log.ts";
import type { ProviderFactory } from "./providers/types.ts";
import { Session } from "./session.ts";

const SESSION_TOKEN_TTL_MS = 60_000;
const SESSION_REQUESTS_PER_MINUTE = 20;

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
}

function bearer(req: IncomingMessage): string {
  const header = req.headers.authorization ?? "";
  return header.startsWith("Bearer ") ? header.slice(7) : "";
}

function safeEqual(a: string, b: string) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

export function createGateway({
  config,
  factory,
  log,
  retryDelayMs,
}: GatewayOptions): Gateway {
  /** Issued but not yet connected: token -> session id + expiry. A token is consumed by the first upgrade. */
  const pending = new Map<string, { id: string; expires: number }>();
  const sessions = new Set<Session>();
  const recentRequests = new Map<string, number[]>();

  const json = (res: ServerResponse, status: number, body: object) => {
    res.writeHead(status, {
      "content-type": "application/json",
      "cache-control": "no-store",
    });
    res.end(JSON.stringify(body));
  };

  const prune = () => {
    const now = Date.now();
    for (const [token, entry] of pending)
      if (entry.expires <= now) pending.delete(token);
  };

  const rateLimited = (ip: string) => {
    const cutoff = Date.now() - 60_000;
    const hits = (recentRequests.get(ip) ?? []).filter((t) => t > cutoff);
    hits.push(Date.now());
    recentRequests.set(ip, hits);
    return hits.length > SESSION_REQUESTS_PER_MINUTE;
  };

  const server = createServer((req, res) => {
    const path = (req.url ?? "").split("?")[0];
    if (req.method === "GET" && path === "/healthz")
      return json(res, 200, { ok: true });
    if (req.method === "POST" && path === "/v1/sessions") {
      req.resume();
      const ip = req.socket.remoteAddress ?? "";
      if (rateLimited(ip)) return json(res, 429, { error: "rate_limited" });
      if (!safeEqual(bearer(req), config.GATEWAY_ACCESS_TOKEN))
        return json(res, 401, { error: "unauthorized" });
      prune();
      if (sessions.size + pending.size >= config.MAX_SESSIONS)
        return json(res, 429, { error: "session_limit" });
      const id = randomUUID();
      const token = randomBytes(32).toString("base64url");
      pending.set(token, { id, expires: Date.now() + SESSION_TOKEN_TTL_MS });
      log.info("session.issued", { session: id });
      return json(res, 201, {
        session_id: id,
        token,
        expires_in: SESSION_TOKEN_TTL_MS / 1000,
        ws_path: "/v1/realtime",
      });
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
    const token = bearer(req);
    const entry = pending.get(token);
    if (!entry) return reject(401, "Unauthorized");
    pending.delete(token);
    wss.handleUpgrade(req, socket, head, (ws) => {
      const session = new Session({
        id: entry.id,
        socket: ws,
        config,
        factory,
        log,
        retryDelayMs,
      });
      sessions.add(session);
      ws.on("close", () => sessions.delete(session));
      log.info("session.connected", { session: entry.id });
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
      for (const session of sessions) session.close();
      for (const client of wss.clients) client.terminate();
      await new Promise<void>((resolve) => wss.close(() => resolve()));
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
