// Latency benchmark over the real pipeline code (STT -> translation -> TTS) with synthetic fixtures.
//
//   npm run bench -- [--rounds 10] [--models gemini-3.8-flash,gemini-3.5-flash-lite] [--directions uz-en,en-uz]
//
// Fixture audio is synthesized once from tests/fixtures/sentences.json with the incoming voice
// and cached under tests/fixtures/audio/. Each turn is fed in real time, committed at end of speech, and timed with
// the server's monotonic clock. Client playback (jitter buffer + device) is NOT included — measure that with
// `lbaudio session`. Sends only synthetic sentences; never run it on real call audio.
//
// Remote mode sends the same fixtures through a running gateway (HTTP + WebSocket), as the app would, so a hosted
// gateway can be measured in each connection mode:
//
//   npm run bench -- --gateway https://bridge.example.com --mode token|account|keys [--rounds N] [--models …]
//                    [--directions uz-en,…] [--site https://jaysonkhan.com]
//
// Credentials come from the shell, never from arguments or files, and are never printed or written to bench-out/:
// token mode reads LIVEBRIDGE_BENCH_TOKEN; keys mode LIVEBRIDGE_BENCH_ELEVENLABS_KEY and LIVEBRIDGE_BENCH_GEMINI_KEY
// (e.g. `read -rs LIVEBRIDGE_BENCH_TOKEN && export LIVEBRIDGE_BENCH_TOKEN`); account mode signs a bench device in on
// the site (`--site`) — you confirm a code in the browser — and signs it out again at the end. Each direction (and
// model) gets its own session; its creation is timed separately from the turns.
import { randomBytes } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";
import {
  decodeFrame,
  encodeFrame,
  type ClientMessage,
  type Lang,
  type ServerMessage,
} from "../../../packages/protocol/src/index.ts";
import { loadConfig, type Config } from "../src/config.ts";
import { silentLogger } from "../src/log.ts";
import { DirectionPipeline } from "../src/pipeline.ts";
import { createRealProviders } from "../src/providers/real.ts";
import type { ProviderFactory } from "../src/providers/types.ts";

interface Sentence {
  words: number;
  text: string;
}
export interface BenchTurn {
  model: string;
  direction: string;
  words: number;
  ok: boolean;
  error?: string;
  /** End of speech (commit) -> first synthesized audio leaving the gateway. */
  firstAudioMs?: number;
  sttCommitMs?: number;
  translateFirstMs?: number;
  translateTotalMs?: number;
  ttsFirstAudioMs?: number;
  audioSeconds: number;
  /** Length of the synthesized translation, to spot audio that was cut short. */
  synthesizedMs?: number;
  ttsCharacters: number;
  source: string;
  transcript?: string;
  translation?: string;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const FRAME_BYTES = 640; // 20 ms at 16 kHz s16le

export function percentile(values: number[], p: number): number | undefined {
  if (!values.length) return undefined;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[
    Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)
  ];
}

/** Linear-interpolation resample of s16le mono. Good enough to turn synthesized speech into 16 kHz test input. */
export function resampleTo16k(pcm: Buffer, fromRate: number): Buffer {
  if (fromRate === 16_000) return pcm;
  const input = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.byteLength >> 1);
  const output = new Int16Array(Math.floor((input.length * 16_000) / fromRate));
  for (let i = 0; i < output.length; i++) {
    const at = (i * fromRate) / 16_000;
    const left = Math.floor(at);
    const right = Math.min(left + 1, input.length - 1);
    output[i] = Math.round(
      input[left]! + (input[right]! - input[left]!) * (at - left),
    );
  }
  return Buffer.from(output.buffer);
}

async function fixtureAudio(
  factory: ProviderFactory,
  lang: Lang,
  index: number,
  text: string,
  cacheDir: string | null,
) {
  const file = cacheDir ? `${cacheDir}/${lang}-${index}.pcm` : null;
  if (file && existsSync(file)) return readFileSync(file);
  // A single dropped connection must not cost the whole run (seen live: one failed handshake in ~35).
  let chunks: Buffer[] = [];
  let sampleRate = 0;
  for (let attempt = 1; ; attempt++) {
    const tts = factory.tts({ voice: "incoming", language: lang });
    chunks = [];
    sampleRate = tts.sampleRate;
    try {
      await tts.open();
      await tts.synthesize(
        text,
        (pcm) => chunks.push(Buffer.from(pcm)),
        new AbortController().signal,
      );
      // Speech runs at roughly 50-70 ms per character; far less means the audio was cut short.
      const seconds = Buffer.concat(chunks).length / 2 / sampleRate;
      if (seconds < text.length * 0.03) throw new Error(`fixture audio too short (${seconds.toFixed(2)} s)`);
      break;
    } catch (error) {
      if (attempt >= 3) throw error;
      await sleep(1000 * attempt);
    } finally {
      tts.close();
    }
  }
  const audio = resampleTo16k(Buffer.concat(chunks), sampleRate);
  if (file) writeFileSync(file, audio);
  return audio;
}

async function runTurn(
  pipeline: DirectionPipeline,
  inbox: { messages: ServerMessage[]; firstAudioAt?: number },
  audio: Buffer,
  generation: number,
  startSequence: number,
) {
  inbox.messages.length = 0;
  inbox.firstAudioAt = undefined;
  pipeline.captureStart(generation);
  let sequence = startSequence;
  const started = performance.now();
  for (let at = 0; at < audio.length; at += FRAME_BYTES, sequence++) {
    pipeline.onCaptureFrame({
      kind: "capture",
      direction: "out",
      flags: 0,
      generation,
      sequence,
      timestampUs: 0n,
      turnId: 0,
      payload: audio.subarray(at, at + FRAME_BYTES),
    });
    // Real-time pacing against the wall clock, so timer drift does not accumulate.
    const due = started + (sequence - startSequence + 1) * 20;
    const wait = due - performance.now();
    if (wait > 0) await sleep(wait);
  }
  const committedAt = performance.now();
  pipeline.commit();
  pipeline.capturePause();
  const deadline = committedAt + 20_000;
  while (performance.now() < deadline) {
    const done = inbox.messages.find(
      (m) =>
        m.type === "metrics" || (m.type === "error" && m.turn_id !== undefined),
    );
    if (done) return { committedAt, sequence, done };
    await sleep(5);
  }
  return { committedAt, sequence, done: undefined };
}

/** One turn's record from what the gateway sent for it. Both modes build it here, so their reports compare. */
function benchTurn(turn: {
  model: string;
  direction: string;
  sentence: Sentence;
  audio: Buffer;
  /** This turn's messages only. */
  messages: ServerMessage[];
  /** The message that ended the turn; absent when it timed out. */
  done?: ServerMessage;
  committedAt: number;
  firstAudioAt?: number;
}): BenchTurn {
  const find = <T extends ServerMessage["type"]>(type: T) =>
    turn.messages.find((m): m is Extract<ServerMessage, { type: T }> => m.type === type);
  const metrics = turn.done?.type === "metrics" ? turn.done : undefined;
  const translation = find("translation.final")?.text;
  return {
    model: turn.model,
    direction: turn.direction,
    words: turn.sentence.words,
    ok: !!metrics && turn.firstAudioAt !== undefined,
    error: metrics
      ? undefined
      : turn.done?.type === "error"
        ? turn.done.code
        : turn.done?.type === "turn.skipped"
          ? `skipped_${turn.done.reason}`
          : "timeout",
    firstAudioMs:
      metrics && turn.firstAudioAt !== undefined ? Math.round(turn.firstAudioAt - turn.committedAt) : undefined,
    sttCommitMs: metrics?.stt_commit_ms,
    translateFirstMs: metrics?.translate_first_ms,
    translateTotalMs: metrics?.translate_total_ms,
    ttsFirstAudioMs: metrics?.tts_first_audio_ms,
    synthesizedMs: metrics?.audio_ms,
    audioSeconds: turn.audio.length / 32_000,
    ttsCharacters: translation?.length ?? 0,
    source: turn.sentence.text,
    transcript: find("caption.final")?.text,
    translation,
  };
}

export async function runBench(options: {
  config: Config;
  factory: ProviderFactory;
  sentences: Record<string, Sentence[]>;
  models: string[];
  directions: [Lang, Lang][];
  rounds: number;
  cacheDir: string | null;
  onProgress?: (line: string) => void;
  /** Called after every turn, so results can be saved as they are produced. */
  onTurn?: (turn: BenchTurn) => void;
  /** A direction/model group that could not run at all (it is skipped, the rest of the run continues). */
  onProblem?: (message: string) => void;
}): Promise<BenchTurn[]> {
  const turns: BenchTurn[] = [];
  for (const [source, target] of options.directions) {
    try {
      await runDirection(options, source, target, turns);
    } catch (error) {
      options.onProblem?.(
        `${source}->${target} stopped: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
  return turns;
}

async function runDirection(
  options: Parameters<typeof runBench>[0],
  source: Lang,
  target: Lang,
  turns: BenchTurn[],
) {
  {
    const sentences = options.sentences[source] ?? [];
    const audio: Buffer[] = [];
    for (const [index, sentence] of sentences.entries()) {
      audio.push(
        await fixtureAudio(
          options.factory,
          source,
          index,
          sentence.text,
          options.cacheDir,
        ),
      );
    }
    for (const model of options.models) {
      const inbox: { messages: ServerMessage[]; firstAudioAt?: number } = {
        messages: [],
      };
      const pipeline = new DirectionPipeline({
        // Timing is direction-agnostic; the benchmark always drives the pipeline as "out" with the incoming voice.
        direction: "out",
        config: {
          enabled: true,
          source_lang: source,
          target_lang: target,
          speak: true,
          commit: "manual",
        },
        factory: {
          ...options.factory,
          tts: (o) => options.factory.tts({ ...o, voice: "incoming" }),
        },
        translationModel: model,
        glossary: [],
        log: silentLogger,
        emit: (m) => inbox.messages.push(m),
        sendAudio: () => {
          inbox.firstAudioAt ??= performance.now();
          return 0;
        },
        onReadyChanged: () => {},
      });
      await pipeline.open();
      // A failed first connection is retried by the pipeline itself; give that a chance before giving up.
      for (let waited = 0; !pipeline.ready && waited < 20_000; waited += 250) await sleep(250);
      if (!pipeline.ready) {
        pipeline.close();
        throw new Error(
          `providers not ready for ${source}->${target}: ${JSON.stringify(inbox.messages.at(-1))}`,
        );
      }
      let sequence = 0;
      for (let round = 0; round < options.rounds; round++) {
        for (const [index, sentence] of sentences.entries()) {
          const result = await runTurn(
            pipeline,
            inbox,
            audio[index]!,
            1,
            sequence,
          );
          sequence = result.sequence;
          turns.push(
            benchTurn({
              model,
              direction: `${source}-${target}`,
              sentence,
              audio: audio[index]!,
              messages: inbox.messages,
              done: result.done,
              committedAt: result.committedAt,
              firstAudioAt: inbox.firstAudioAt,
            }),
          );
          options.onTurn?.(turns.at(-1)!);
          options.onProgress?.(
            `${source}->${target} ${model} round ${round + 1}/${options.rounds} sentence ${index + 1}/${sentences.length}`,
          );
          await sleep(150);
        }
      }
      pipeline.close();
    }
  }
}

export function report(
  turns: BenchTurn[],
  meta: Record<string, string | number>,
  /** Where "first audio" was measured: inside the gateway (in-process run) or on this machine (remote run). */
  clock: "gateway" | "client" = "gateway",
): string {
  const fmt = (value: number | undefined) =>
    value === undefined ? "—" : String(Math.round(value));
  const lines = [
    "# LiveBridge latency benchmark",
    "",
    ...Object.entries(meta).map(([key, value]) => `- **${key}:** ${value}`),
    "",
    ...(clock === "gateway"
      ? [
          'Times are milliseconds on the gateway clock. "First audio" = end of speech (commit) → first synthesized audio',
          "leaving the gateway; client playback is not included. Stage columns are medians.",
        ]
      : [
          'Times are milliseconds. "First audio" = `turn.commit` sent → first synthesized frame received, on this',
          "machine's clock, so it includes the network both ways; client playback is not included. Stage columns are",
          "medians of the gateway's own per-turn `metrics`.",
        ]),
    "",
    "| Model | Direction | Words | Turns | Failed | First audio p50 | p95 | p99 | STT commit | Translate first | Translate total | TTS first audio |",
    "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
  ];
  const groups = new Map<string, BenchTurn[]>();
  for (const turn of turns) {
    const key = `${turn.model}|${turn.direction}|${turn.words}`;
    groups.set(key, [...(groups.get(key) ?? []), turn]);
  }
  for (const [key, group] of groups) {
    const ok = group.filter((t) => t.ok);
    const column = (pick: (t: BenchTurn) => number | undefined, p: number) =>
      fmt(
        percentile(
          ok.map(pick).filter((v): v is number => v !== undefined),
          p,
        ),
      );
    const [model, direction, words] = key.split("|");
    lines.push(
      `| ${model} | ${direction} | ${words} | ${group.length} | ${group.length - ok.length} | ${column((t) => t.firstAudioMs, 50)} | ${column((t) => t.firstAudioMs, 95)} | ${column((t) => t.firstAudioMs, 99)} | ${column((t) => t.sttCommitMs, 50)} | ${column((t) => t.translateFirstMs, 50)} | ${column((t) => t.translateTotalMs, 50)} | ${column((t) => t.ttsFirstAudioMs, 50)} |`,
    );
  }
  const audioHours = turns.reduce((n, t) => n + t.audioSeconds, 0) / 3600;
  const characters = turns.reduce((n, t) => n + t.ttsCharacters, 0);
  lines.push(
    "",
    "## Billable quantities in this run",
    "",
    `- Speech-to-text audio streamed: ${(audioHours * 60).toFixed(1)} minutes (billed per second sent, silence included; idle keep-alive silence is extra)`,
    `- Speech synthesis characters: ${characters}`,
    "- Translation tokens: not captured by this script — read them from the provider console for the run window",
    "",
    "Multiply by your own account prices; this report deliberately contains no price figures.",
    "",
  );
  return lines.join("\n");
}

// ---- Remote mode: the same fixtures through a running gateway, over HTTP + WebSocket, in each connection mode ----

export type RemoteMode = "token" | "account" | "keys";

/** How `POST /v1/sessions` is authorized. Held in memory only: never printed, logged or written to bench-out/. */
export type RemoteCredentials =
  | { mode: "token"; token: string }
  | { mode: "keys"; elevenlabsKey: string; geminiKey: string }
  | { mode: "account"; account: AccountTokens };

export interface SessionCreation {
  direction: string;
  model: string;
  /** `POST /v1/sessions` sent → its answer read, on this machine's clock. Account mode includes the site's check. */
  ms: number;
}

export interface RemoteResult {
  turns: BenchTurn[];
  sessions: SessionCreation[];
  /** As the gateway announced them in `session.ready`. */
  providers?: { stt: string; translation: string; tts: string; mock: boolean };
  /** Why the run stopped early: a refused session, a fatal error from the gateway, or a closed connection. */
  fatal?: string;
  /** Directions that could not run; the rest of the run went on. */
  problems: string[];
}

export interface RemoteOptions {
  /** The gateway's origin, e.g. https://bridge.example.com. */
  gateway: string;
  credentials: RemoteCredentials;
  sentences: Record<string, Sentence[]>;
  /** One sentence's fixture audio, 16 kHz s16le mono. */
  audioFor: (lang: Lang, index: number, text: string) => Promise<Buffer>;
  /** Translation models to request, one session each; empty = the gateway's default. */
  models: string[];
  directions: [Lang, Lang][];
  rounds: number;
  onProgress?: (line: string) => void;
  /** Called after every turn, so results can be saved as they are produced. */
  onTurn?: (turn: BenchTurn) => void;
  /** How long a turn may take from its commit. Default 20 s; overridable for tests. */
  turnTimeoutMs?: number;
}

/** Ends the whole run: every later session would be refused or ended the same way. */
class RunStopped extends Error {}

const SITE_API = "/api/livebridge/v1/";
const SITE_TIMEOUT_MS = 10_000;
const SESSION_TIMEOUT_MS = 15_000;
/** The site's access token lives 15 minutes; it is refreshed when less than this is left. */
const REFRESH_MARGIN_MS = 60_000;
/** The bench speaks on the "in" lane, so the gateway answers in its incoming voice, as the in-process run does. */
const LANE = "in";

type TokenPair = { access_token: string; refresh_token: string; expires_in: number };

const isPair = (value: any): value is TokenPair =>
  typeof value?.access_token === "string" &&
  typeof value.refresh_token === "string" &&
  Number.isFinite(value.expires_in);

const messageOf = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** The `{"error": code}` of an answer when it is a plain code — never anything else the server sent. */
const errorCode = (status: number, body: any): string =>
  typeof body?.error === "string" && /^[a-z_]{1,40}$/.test(body.error) ? body.error : `http_${status}`;

/** A JSON call to the site's app API. */
async function siteCall(site: string, path: string, body?: object, bearer?: string) {
  const response = await fetch(new URL(SITE_API + path, site), {
    method: "POST",
    headers: { "content-type": "application/json", ...(bearer ? { authorization: `Bearer ${bearer}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(SITE_TIMEOUT_MS),
  });
  const text = await response.text();
  let json: any;
  try {
    json = text ? JSON.parse(text) : undefined;
  } catch {
    json = undefined;
  }
  return { status: response.status, json, code: errorCode(response.status, json) };
}

/** The bench device's tokens, in memory only. One refresh at a time; every caller waits for the same one. */
export class AccountTokens {
  private readonly site: string;
  private pair: TokenPair;
  private expiresAt: number;
  private refreshing: Promise<void> | null = null;

  constructor(site: string, pair: TokenPair) {
    this.site = site;
    this.pair = pair;
    this.expiresAt = Date.now() + pair.expires_in * 1000;
  }

  /** A valid access token: refreshed first when it is close to expiry. */
  async accessToken(): Promise<string> {
    if (this.expiresAt - Date.now() < REFRESH_MARGIN_MS) await this.refresh();
    return this.pair.access_token;
  }

  refresh(): Promise<void> {
    return (this.refreshing ??= this.renew().finally(() => (this.refreshing = null)));
  }

  /** Signs the bench device out, so it does not stay among the account's connected devices. */
  async logout() {
    const reply = await siteCall(this.site, "logout/", undefined, await this.accessToken());
    if (reply.status !== 204) throw new Error(`the site did not sign the bench device out (${reply.code})`);
  }

  private async renew() {
    const reply = await siteCall(this.site, "token/refresh/", { refresh_token: this.pair.refresh_token });
    if (reply.status !== 200 || !isPair(reply.json))
      throw new Error(`the site refused to refresh the bench sign-in (${reply.code}); run the benchmark again`);
    this.pair = reply.json;
    this.expiresAt = Date.now() + reply.json.expires_in * 1000;
  }
}

const SIGN_IN_STOPS: Record<string, string> = {
  expired_token: "the sign-in code expired before it was confirmed; run the benchmark again",
  access_denied: "the sign-in was declined in the browser",
  invalid_grant: "the site no longer accepts this sign-in; run the benchmark again",
};

/**
 * The site's device sign-in, as the app does it: the owner confirms the code in his browser while the bench polls for
 * the tokens. Each run is a new device; `logout()` at the end removes it again.
 */
export async function deviceSignIn(options: {
  site: string;
  /** Shows the owner where to confirm. */
  say: (line: string) => void;
  /** Overridable for tests. */
  sleep?: (ms: number) => Promise<void>;
}): Promise<AccountTokens> {
  const wait = options.sleep ?? sleep;
  const start = await siteCall(options.site, "device/start/", {
    device_id: `bench-${randomBytes(8).toString("hex")}`,
    device_name: "LiveBridge bench",
  });
  const grant = start.json;
  if (
    start.status !== 201 ||
    typeof grant?.device_code !== "string" ||
    typeof grant.verification_uri_complete !== "string"
  )
    throw new Error(`the site did not start the device sign-in (${start.code})`);
  let interval = Number(grant.interval) > 0 ? Number(grant.interval) : 5;
  const expiresIn = Number(grant.expires_in) > 0 ? Number(grant.expires_in) : 600;
  options.say(
    `Open ${grant.verification_uri_complete} and confirm the code ${grant.user_code} ` +
      `(valid ${Math.round(expiresIn / 60)} minutes).`,
  );
  const deadline = Date.now() + expiresIn * 1000;
  while (Date.now() < deadline) {
    await wait(interval * 1000);
    let reply;
    try {
      reply = await siteCall(options.site, "device/token/", { device_code: grant.device_code });
    } catch {
      continue; // a dropped request: the code is still valid, so poll again
    }
    if (reply.status === 200 && isPair(reply.json)) return new AccountTokens(options.site, reply.json);
    if (reply.code === "authorization_pending") continue;
    // A 429 from the site's request limit means what slow_down means: poll less often; the code is still valid.
    if (reply.code === "slow_down" || reply.status === 429) {
      interval += 5;
      continue;
    }
    throw new Error(SIGN_IN_STOPS[reply.code] ?? `the device sign-in failed (${reply.code})`);
  }
  throw new Error(SIGN_IN_STOPS.expired_token!);
}

async function sessionRequest(
  credentials: RemoteCredentials,
): Promise<{ headers: Record<string, string>; body: string }> {
  const json = { "content-type": "application/json" };
  switch (credentials.mode) {
    case "token":
      return {
        headers: { ...json, authorization: `Bearer ${credentials.token}` },
        body: JSON.stringify({ mode: "token" }),
      };
    case "account":
      return {
        headers: { ...json, authorization: `Bearer ${await credentials.account.accessToken()}` },
        body: JSON.stringify({ mode: "account" }),
      };
    case "keys":
      return {
        headers: json,
        body: JSON.stringify({
          mode: "keys",
          elevenlabs_api_key: credentials.elevenlabsKey,
          gemini_api_key: credentials.geminiKey,
        }),
      };
  }
}

/** `POST /v1/sessions`, timed from the request to its answer. A refusal stops the run. */
async function createSession(gateway: string, credentials: RemoteCredentials) {
  let refreshed = false;
  for (let attempt = 1; ; attempt++) {
    let request;
    try {
      // Before the clock starts: refreshing the account's token is the bench's work, not the gateway's.
      request = await sessionRequest(credentials);
    } catch (error) {
      throw new RunStopped(messageOf(error));
    }
    const started = performance.now();
    let status: number;
    let body: any;
    try {
      const response = await fetch(new URL("/v1/sessions", gateway), {
        method: "POST",
        ...request,
        signal: AbortSignal.timeout(SESSION_TIMEOUT_MS),
      });
      status = response.status;
      body = await response.json().catch(() => undefined);
    } catch (error) {
      throw new RunStopped(`the gateway could not be reached (${messageOf(error)})`);
    }
    const ms = performance.now() - started;
    if (status === 201 && typeof body?.token === "string" && typeof body.ws_path === "string")
      return { ms, token: body.token as string, wsPath: body.ws_path as string };
    const code = errorCode(status, body);
    if (code === "invalid_token" && credentials.mode === "account" && !refreshed) {
      refreshed = true;
      try {
        await credentials.account.refresh();
      } catch (error) {
        throw new RunStopped(messageOf(error));
      }
      continue;
    }
    // The previous session's slot comes back once the gateway has seen its socket close; allow it a moment.
    if (code === "session_limit" && attempt <= 3) {
      await sleep(1000);
      continue;
    }
    throw new RunStopped(`the gateway refused the session: ${status} ${code}`);
  }
}

/** A message's turn id, for the messages that belong to a turn. */
const turnOf = (m: ServerMessage) => ("turn_id" in m ? m.turn_id : undefined);

/** One WebSocket to the gateway: collects control messages and notes when synthesized audio arrives. */
class RemoteClient {
  readonly messages: ServerMessage[] = [];
  /** Messages and frames of turns up to this id are left over from earlier turns. */
  afterTurn = 0;
  firstAudioAt?: number;
  private fatal?: string;
  private closedWith?: number;
  private readonly ws: WebSocket;

  private constructor(ws: WebSocket) {
    this.ws = ws;
    ws.on("message", (data, isBinary) => {
      if (isBinary) {
        const frame = decodeFrame(data as Buffer);
        if (frame.turnId > this.afterTurn && frame.payload.byteLength > 0) this.firstAudioAt ??= performance.now();
        return;
      }
      const message = JSON.parse(data.toString()) as ServerMessage;
      if (message.type === "error" && message.fatal) this.fatal ??= `${message.code} (${message.message})`;
      this.messages.push(message);
    });
    ws.on("close", (code) => (this.closedWith = code));
    // A failure after the handshake is followed by "close"; without a listener it would crash the process.
    ws.on("error", () => {});
  }

  static open(gateway: string, path: string, token: string): Promise<RemoteClient> {
    const url = new URL(path, gateway);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url, { headers: { authorization: `Bearer ${token}` } });
      const client = new RemoteClient(ws);
      ws.once("open", () => resolve(client));
      ws.once("error", (error) => reject(new Error(`the WebSocket did not open (${error.message})`)));
    });
  }

  send(message: ClientMessage) {
    this.ws.send(JSON.stringify(message));
  }

  sendAudio(sequence: number, payload: Buffer) {
    const frame = { kind: "capture", direction: LANE, flags: 0, generation: 1, timestampUs: 0n, turnId: 0 } as const;
    this.ws.send(encodeFrame({ ...frame, sequence, payload }));
  }

  /** Throws RunStopped once the gateway has ended the session. */
  check() {
    if (this.fatal) throw new RunStopped(`the gateway ended the session: ${this.fatal}`);
    if (this.closedWith !== undefined)
      throw new RunStopped(`the gateway closed the connection (code ${this.closedWith})`);
  }

  /** Resolves with what `probe` finds, or undefined after `timeoutMs`; throws once the session has ended. */
  async until<T>(probe: () => T | undefined | null | false, timeoutMs: number): Promise<T | undefined> {
    const deadline = performance.now() + timeoutMs;
    for (;;) {
      const found = probe();
      if (found) return found;
      this.check();
      if (performance.now() >= deadline) return undefined;
      await sleep(5);
    }
  }

  async close() {
    if (this.closedWith === undefined) this.ws.close();
    for (let waited = 0; this.closedWith === undefined && waited < 3000; waited += 20) await sleep(20);
    if (this.closedWith === undefined) this.ws.terminate();
  }
}

/** One turn through the gateway, paced in real time like the in-process run. */
async function remoteTurn(client: RemoteClient, audio: Buffer, startSequence: number, timeoutMs: number) {
  client.messages.length = 0;
  client.firstAudioAt = undefined;
  const after = client.afterTurn;
  // Partial captions carry the id the next turn will get, not a settled one.
  const settled = (m: ServerMessage) => m.type !== "caption.partial" && (turnOf(m) ?? 0) > after;
  client.send({ v: 1, type: "capture.start", direction: LANE, generation: 1 });
  let sequence = startSequence;
  const started = performance.now();
  for (let at = 0; at < audio.length; at += FRAME_BYTES, sequence++) {
    client.check();
    client.sendAudio(sequence, audio.subarray(at, at + FRAME_BYTES));
    const due = started + (sequence - startSequence + 1) * 20;
    const wait = due - performance.now();
    if (wait > 0) await sleep(wait);
  }
  const committedAt = performance.now();
  client.send({ v: 1, type: "turn.commit", direction: LANE });
  client.send({ v: 1, type: "capture.pause", direction: LANE });
  const done = await client.until(
    () =>
      client.messages.find(
        (m) => settled(m) && (m.type === "metrics" || m.type === "turn.skipped" || m.type === "error"),
      ),
    timeoutMs,
  );
  const messages = client.messages.filter(settled);
  // What still arrives for this turn must not be taken for the next turn's (one that timed out ends its session).
  client.afterTurn = Math.max(after, ...messages.map((m) => turnOf(m) ?? 0));
  return { committedAt, sequence, done, messages, firstAudioAt: client.firstAudioAt };
}

async function runRemoteGroup(
  options: RemoteOptions,
  result: RemoteResult,
  source: Lang,
  target: Lang,
  sentences: Sentence[],
  audio: Buffer[],
  model: string | undefined,
) {
  const label = model ?? "gateway default";
  const direction = `${source}-${target}`;
  /** A new session, configured and ready; its creation is timed. */
  const connect = async () => {
    const session = await createSession(options.gateway, options.credentials);
    result.sessions.push({ direction, model: label, ms: Math.round(session.ms) });
    const client = await RemoteClient.open(options.gateway, session.wsPath, session.token);
    try {
      await configure(client);
      return client;
    } catch (error) {
      await client.close();
      throw error;
    }
  };
  const configure = async (client: RemoteClient) => {
    client.send({
      v: 1,
      type: "session.configure",
      capture_format: { encoding: "pcm_s16le", sample_rate: 16_000, channels: 1 },
      directions: {
        in: { enabled: true, source_lang: source, target_lang: target, speak: true, commit: "manual" },
        out: { enabled: false, source_lang: target, target_lang: source, speak: false, commit: "manual" },
      },
      ...(model ? { translation_model: model } : {}),
    });
    const account = options.credentials.mode === "account";
    const ready = await client.until(() => {
      const refused = client.messages.find(
        (m) => m.type === "error" && (m.code === "bad_message" || m.code === "bad_state"),
      );
      if (refused?.type === "error")
        throw new Error(`the gateway refused session.configure: ${refused.code} (${refused.message})`);
      const announced = client.messages.findLast(
        (m): m is Extract<ServerMessage, { type: "session.ready" }> => m.type === "session.ready",
      );
      // In account mode the first balance follows the first announcement; the app shows it before speech starts.
      const balance = !account || client.messages.some((m) => m.type === "account.balance");
      return announced?.directions[LANE].ready && balance ? announced : undefined;
    }, 20_000);
    if (!ready)
      throw new Error(`providers not ready for ${source}->${target}: ${JSON.stringify(client.messages.at(-1))}`);
    result.providers ??= ready.providers;
  };
  let client = await connect();
  try {
    let sequence = 0;
    let timedOut = false;
    for (let round = 0; round < options.rounds; round++) {
      for (const [index, sentence] of sentences.entries()) {
        // A turn that timed out can still be answered later, and nothing in that answer tells it from the next turn's:
        // the run goes on in a new session, so none of it can be counted for a turn it does not belong to.
        if (timedOut) {
          await client.close();
          client = await connect();
        }
        const turn = await remoteTurn(client, audio[index]!, sequence, options.turnTimeoutMs ?? 20_000);
        timedOut = !turn.done;
        sequence = turn.sequence;
        result.turns.push(benchTurn({ model: label, direction, sentence, audio: audio[index]!, ...turn }));
        options.onTurn?.(result.turns.at(-1)!);
        options.onProgress?.(
          `${source}->${target} ${label} round ${round + 1}/${options.rounds} sentence ${index + 1}/${sentences.length}`,
        );
        await sleep(150);
      }
    }
  } finally {
    await client.close();
  }
}

/**
 * The benchmark through a running gateway. Turns are timed as in-process, plus the client's own time from commit to
 * the first synthesized frame; each direction (and model) opens one session, and a new one after a turn that timed out;
 * each session's creation is timed on its own.
 */
export async function runRemoteBench(options: RemoteOptions): Promise<RemoteResult> {
  const result: RemoteResult = { turns: [], sessions: [], problems: [] };
  const models = options.models.length ? options.models : [undefined];
  for (const [source, target] of options.directions) {
    try {
      const sentences = options.sentences[source] ?? [];
      const audio: Buffer[] = [];
      for (const [index, sentence] of sentences.entries())
        audio.push(await options.audioFor(source, index, sentence.text));
      for (const model of models) await runRemoteGroup(options, result, source, target, sentences, audio, model);
    } catch (error) {
      if (error instanceof RunStopped) {
        result.fatal = error.message;
        break;
      }
      result.problems.push(`${source}->${target} stopped: ${messageOf(error)}`);
    }
  }
  return result;
}

/** The report header of a remote run: the mode, the gateway's host (never a credential) and session creation. */
export function remoteMeta(
  result: RemoteResult,
  run: { mode: RemoteMode; gateway: string; rounds: number },
): Record<string, string | number> {
  const times = result.sessions.map((s) => s.ms);
  const providers = result.providers;
  return {
    Date: new Date().toISOString(),
    Mode: run.mode,
    Gateway: new URL(run.gateway).host,
    ...(providers
      ? {
          "Gateway providers":
            `${providers.stt} / ${providers.translation} / ${providers.tts}` +
            (providers.mock ? " (MOCK providers: not a real measurement)" : ""),
        }
      : {}),
    [`Session creation (${run.mode})`]: times.length
      ? `median ${percentile(times, 50)} ms, max ${Math.max(...times)} ms over ${times.length} session(s)` +
        " (POST /v1/sessions to its answer, this machine's clock)"
      : "no session was created",
    "Rounds per sentence": run.rounds,
    "Session state":
      "warm (one session per direction and model, and a new one after a turn that timed out; each configured before " +
      "timing, its creation timed separately above)",
    "Run from": process.env.HOSTNAME ?? "this machine — note the region when comparing runs",
    ...(result.fatal ? { "Stopped early": result.fatal } : {}),
    ...(result.problems.length ? { Incomplete: result.problems.join("; ") } : {}),
  };
}

const DEFAULT_SITE = "https://jaysonkhan.com";

const cliArg = (name: string) => {
  const at = process.argv.indexOf(`--${name}`);
  return at > 0 ? process.argv[at + 1] : undefined;
};

/** An http(s) origin. Plain http only to this machine, so no credential crosses a network unencrypted. */
function origin(value: string | undefined, flag: string): string {
  const url = value && URL.canParse(value) ? new URL(value) : undefined;
  const local = !!url && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (!url || !(url.protocol === "https:" || (url.protocol === "http:" && local)) || url.username || url.password)
    throw new Error(`${flag} must be an https:// address without credentials (plain http only for this machine)`);
  return url.origin;
}

async function remoteMain() {
  const fail = (message: string): never => {
    console.error(message);
    process.exit(2);
  };
  // Credentials come from the shell, never from a file: take them before .env is loaded.
  const shell = { ...process.env };
  const root = new URL("../../../", import.meta.url);
  const envFile = new URL(".env", root);
  // Used only to synthesize fixture audio that is not cached yet.
  if (existsSync(envFile)) process.loadEnvFile(envFile);
  const mode = cliArg("mode") ?? "token";
  if (mode !== "token" && mode !== "account" && mode !== "keys") return fail("--mode must be token, account or keys");
  let gateway = "";
  let site = "";
  try {
    gateway = origin(cliArg("gateway"), "--gateway");
    site = origin(cliArg("site") ?? DEFAULT_SITE, "--site");
  } catch (error) {
    fail(messageOf(error));
  }
  const rounds = Number(cliArg("rounds") ?? 10);
  if (!Number.isInteger(rounds) || rounds < 1) return fail("--rounds must be a whole number of at least 1");
  const models = (cliArg("models") ?? "").split(",").filter(Boolean);
  const directions = (cliArg("directions") ?? "uz-en,uz-ru,en-uz,ru-uz")
    .split(",")
    .map((d) => d.split("-") as [Lang, Lang]);
  const sentences = JSON.parse(readFileSync(new URL("tests/fixtures/sentences.json", root), "utf8"));

  let credentials: RemoteCredentials;
  let account: AccountTokens | undefined;
  if (mode === "token") {
    const token = shell.LIVEBRIDGE_BENCH_TOKEN;
    if (!token)
      return fail("token mode reads the gateway access token from LIVEBRIDGE_BENCH_TOKEN in the shell (not .env)");
    credentials = { mode, token };
  } else if (mode === "keys") {
    const elevenlabsKey = shell.LIVEBRIDGE_BENCH_ELEVENLABS_KEY;
    const geminiKey = shell.LIVEBRIDGE_BENCH_GEMINI_KEY;
    if (!elevenlabsKey || !geminiKey)
      return fail(
        "keys mode reads LIVEBRIDGE_BENCH_ELEVENLABS_KEY and LIVEBRIDGE_BENCH_GEMINI_KEY from the shell (not .env)",
      );
    credentials = { mode, elevenlabsKey, geminiKey };
  } else {
    try {
      account = await deviceSignIn({ site, say: (line) => console.log(line) });
    } catch (error) {
      return fail(`account sign-in failed: ${messageOf(error)}`);
    }
    console.log("Signed in. The bench device is signed out again at the end.");
    credentials = { mode, account };
  }

  const cacheDir = fileURLToPath(new URL("tests/fixtures/audio", root));
  mkdirSync(cacheDir, { recursive: true });
  const outDir = fileURLToPath(new URL("bench-out", root));
  mkdirSync(outDir, { recursive: true });
  let synthesizer: ProviderFactory | undefined;
  const audioFor = async (lang: Lang, index: number, text: string) => {
    const file = `${cacheDir}/${lang}-${index}.pcm`;
    if (existsSync(file)) return readFileSync(file);
    // Not cached yet: synthesized once with the local .env's ElevenLabs key, as the in-process run does.
    if (!process.env.ELEVENLABS_API_KEY)
      throw new Error(
        `fixture audio ${lang}-${index} is not cached and .env has no ELEVENLABS_API_KEY to synthesize it`,
      );
    synthesizer ??= createRealProviders(loadConfig({ ...process.env, PROVIDER_MODE: "fake" }), silentLogger);
    return fixtureAudio(synthesizer, lang, index, text, cacheDir);
  };

  const host = new URL(gateway).host;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 16);
  const name = `${mode}-${stamp}`;
  // As in-process: every turn is appended as it finishes, so an interrupted run still leaves its data.
  const turnsFile = `${outDir}/translations-${name}.jsonl`;
  writeFileSync(turnsFile, "");
  console.log(`Benchmarking ${host} in ${mode} mode.`);
  let result: RemoteResult;
  try {
    result = await runRemoteBench({
      gateway,
      credentials,
      sentences,
      audioFor,
      models,
      directions,
      rounds,
      onProgress: (line) => process.stdout.write(`\r${line.padEnd(90)}`),
      onTurn: (turn) => appendFileSync(turnsFile, JSON.stringify(turn) + "\n"),
    });
  } finally {
    await account
      ?.logout()
      .catch((error) =>
        console.error(`\ncould not sign the bench device out (${messageOf(error)}); remove it on the account page`),
      );
  }
  const text = report(result.turns, remoteMeta(result, { mode, gateway, rounds }), "client");
  writeFileSync(`${outDir}/benchmark-${name}.md`, text);
  console.log(`\n${text}\nwrote bench-out/benchmark-${name}.md and bench-out/translations-${name}.jsonl`);
  if (result.fatal) console.error(`stopped early: ${result.fatal}`);
  process.exit(result.fatal || result.problems.length ? 1 : 0);
}

const isMain = process.argv[1] === fileURLToPath(import.meta.url);
const remoteRun = isMain && process.argv.includes("--gateway");
if (remoteRun) await remoteMain();
if (isMain && !remoteRun) {
  const root = new URL("../../../", import.meta.url);
  const envFile = new URL(".env", root);
  if (existsSync(envFile)) process.loadEnvFile(envFile);
  const arg = (name: string) => {
    const at = process.argv.indexOf(`--${name}`);
    return at > 0 ? process.argv[at + 1] : undefined;
  };
  const config = loadConfig({ ...process.env, PROVIDER_MODE: "real" });
  const models = (
    arg("models") ?? config.allowedTranslationModels.join(",")
  ).split(",");
  const directions = (arg("directions") ?? "uz-en,uz-ru,en-uz,ru-uz")
    .split(",")
    .map((d) => d.split("-") as [Lang, Lang]);
  const rounds = Number(arg("rounds") ?? 10);
  const cacheDir = fileURLToPath(new URL("tests/fixtures/audio", root));
  mkdirSync(cacheDir, { recursive: true });
  const outDir = fileURLToPath(new URL("bench-out", root));
  mkdirSync(outDir, { recursive: true });
  const sentences = JSON.parse(
    readFileSync(new URL("tests/fixtures/sentences.json", root), "utf8"),
  );

  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 16);
  // Every turn is appended as it finishes (source, recognised text, translation, timings), so an interrupted run
  // still leaves its data — and this file is what the bilingual human review reads.
  const turnsFile = `${outDir}/translations-${stamp}.jsonl`;
  writeFileSync(turnsFile, "");
  const problems: string[] = [];
  const turns = await runBench({
    config,
    factory: createRealProviders(config, silentLogger),
    sentences,
    models,
    directions,
    rounds,
    cacheDir,
    onProgress: (line) => process.stdout.write(`\r${line.padEnd(90)}`),
    onTurn: (turn) => appendFileSync(turnsFile, JSON.stringify(turn) + "\n"),
    onProblem: (message) => problems.push(message),
  });
  const text = report(turns, {
    Date: new Date().toISOString(),
    "STT model": config.STT_MODEL,
    "TTS model": `${config.TTS_MODEL} (${config.TTS_OUTPUT_FORMAT})`,
    "ElevenLabs host": config.ELEVENLABS_BASE_URL,
    "Rounds per sentence": rounds,
    "Session state":
      "warm (sockets opened before timing; first turn of each group includes no connection setup)",
    "Run from":
      process.env.HOSTNAME ??
      "this machine — note the region when comparing with the server",
    ...(problems.length ? { "Incomplete": problems.join("; ") } : {}),
  });
  writeFileSync(`${outDir}/benchmark-${stamp}.md`, text);
  console.log(
    `\n${text}\nwrote bench-out/benchmark-${stamp}.md and bench-out/translations-${stamp}.jsonl`,
  );
  process.exit(problems.length ? 1 : 0);
}
