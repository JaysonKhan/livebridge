// Signed calls from the gateway to the owner's site over its local unix socket. The site authorizes account
// tokens and charges usage; the gateway only forwards raw counters. Nothing here logs, and no error message
// carries the token, the secret or anything the site answered.
import { createHmac } from "node:crypto";
import { request } from "node:http";

export type SiteErrorCode =
  | "invalid_token"
  | "unknown_account"
  | "bad_request"
  | "unavailable";

export class SiteError extends Error {
  readonly code: SiteErrorCode;
  constructor(code: SiteErrorCode) {
    super(`site call failed (${code})`);
    this.name = "SiteError";
    this.code = code;
  }
}

/** Raw counters for one report; the site turns them into billing units. */
export type UsageReport = {
  account_id: string;
  session_id: string;
  seq: number;
  stt_ms_out: number;
  stt_ms_in: number;
  tts_chars: number;
};

export type SiteClient = {
  authorize(
    accessToken: string,
  ): Promise<{ accountId: string; balanceUnits: number; hasPurchase: boolean }>;
  usage(
    report: UsageReport,
  ): Promise<{ chargedUnits: number; balanceUnits: number }>;
};

const AUTHORIZE_PATH = "/internal/livebridge/v1/authorize/";
const USAGE_PATH = "/internal/livebridge/v1/usage/";
const DEFAULT_TIMEOUT_MS = 3000;

type Reply = { status: number; body: unknown };

const isInt = (value: unknown): value is number => Number.isSafeInteger(value);

export function createSiteClient(options: {
  socketPath: string;
  host: string;
  secret: string;
  timeoutMs?: number;
  now?: () => number;
}): SiteClient {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const now = options.now ?? Date.now;

  function post(path: string, payload: unknown): Promise<Reply> {
    const raw = JSON.stringify(payload);
    const timestamp = String(Math.floor(now() / 1000));
    const signature = createHmac("sha256", options.secret)
      .update(`${timestamp}.${raw}`)
      .digest("hex");
    return new Promise((resolve, reject) => {
      const unavailable = () => reject(new SiteError("unavailable"));
      const req = request({
        socketPath: options.socketPath,
        method: "POST",
        path,
        headers: {
          // The site sits behind its own proxy; these stand in for what the proxy would add.
          Host: options.host,
          "X-Forwarded-Proto": "https",
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(raw),
          "X-LiveBridge-Timestamp": timestamp,
          "X-LiveBridge-Signature": signature,
        },
      });
      // One deadline for the whole exchange: connect, send and the answer.
      const timer = setTimeout(() => {
        req.destroy();
        unavailable();
      }, timeoutMs);
      req.on("error", () => {
        clearTimeout(timer);
        unavailable();
      });
      req.on("response", (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("error", () => {
          clearTimeout(timer);
          unavailable();
        });
        res.on("end", () => {
          clearTimeout(timer);
          let body: unknown;
          try {
            body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          } catch {
            body = undefined;
          }
          resolve({ status: res.statusCode ?? 0, body });
        });
      });
      req.end(raw);
    });
  }

  /** The failure statuses shared by both calls; anything not listed is `unavailable`. */
  function failure(reply: Reply): SiteError {
    const error = (reply.body as { error?: unknown } | null | undefined)?.error;
    if (reply.status === 401) return new SiteError("invalid_token");
    if (reply.status === 400) return new SiteError("bad_request");
    if (reply.status === 404 && error === "unknown_account")
      return new SiteError("unknown_account");
    return new SiteError("unavailable");
  }

  return {
    async authorize(accessToken) {
      const reply = await post(AUTHORIZE_PATH, { access_token: accessToken });
      const body = reply.body as Record<string, unknown> | null | undefined;
      if (reply.status !== 200) throw failure(reply);
      if (
        typeof body?.account_id !== "string" ||
        !body.account_id ||
        !isInt(body.balance_units) ||
        typeof body.has_purchase !== "boolean"
      )
        throw new SiteError("unavailable");
      return {
        accountId: body.account_id,
        balanceUnits: body.balance_units,
        hasPurchase: body.has_purchase,
      };
    },
    async usage(report) {
      const reply = await post(USAGE_PATH, report);
      const body = reply.body as Record<string, unknown> | null | undefined;
      if (reply.status !== 200) throw failure(reply);
      if (!isInt(body?.charged_units) || !isInt(body.balance_units))
        throw new SiteError("unavailable");
      return {
        chargedUnits: body.charged_units,
        balanceUnits: body.balance_units,
      };
    },
  };
}
