// Runs the benchmark harness against local MOCK provider servers. This checks that the harness itself works and
// reports sensible numbers; the latencies it measures here are those of the mocks, not of any real provider.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { loadConfig } from "../../services/gateway/src/config.ts";
import { silentLogger } from "../../services/gateway/src/log.ts";
import { createFakeProviders } from "../../services/gateway/src/providers/fake.ts";
import { createRealProviders } from "../../services/gateway/src/providers/real.ts";
import type { ProviderFactory } from "../../services/gateway/src/providers/types.ts";
import { SiteError, type SiteClient, type UsageReport } from "../../services/gateway/src/site.ts";
import {
  deviceSignIn,
  percentile,
  remoteMeta,
  report,
  resampleTo16k,
  runBench,
  runRemoteBench,
} from "../../services/gateway/scripts/bench.ts";
import { ACCESS_TOKEN, speech, startGateway } from "./helpers.ts";
import {
  MOCK_API_KEY,
  MOCK_GEMINI_KEY,
  startMockElevenLabs,
  startMockGemini,
} from "./mock-providers.ts";

test("benchmark harness (mock servers): times every turn, groups by model/direction/length, reports quantities", async () => {
  const eleven = await startMockElevenLabs({
    transcripts: Array(8).fill("salom dunyo"),
    ttsChunks: [24000, 24000],
  });
  const gemini = await startMockGemini({
    "model-a": { pieces: ["hello ", "world"] },
    "model-b": { status: 500 },
  });
  try {
    const config = loadConfig({
      PROVIDER_MODE: "real",
      GATEWAY_ACCESS_TOKEN: ACCESS_TOKEN,
      ELEVENLABS_API_KEY: MOCK_API_KEY,
      ELEVENLABS_OWNER_VOICE_ID: "voice-owner",
      ELEVENLABS_INCOMING_VOICE_ID: "voice-stock",
      ELEVENLABS_BASE_URL: eleven.base,
      GEMINI_API_KEY: MOCK_GEMINI_KEY,
      GEMINI_BASE_URL: gemini.base,
      TRANSLATION_FALLBACK_MODEL: "",
    });
    const turns = await runBench({
      config,
      factory: createRealProviders(config, silentLogger),
      sentences: {
        uz: [
          { words: 1, text: "Rahmat." },
          { words: 5, text: "Ha, albatta, men roziman." },
        ],
      },
      models: ["model-a", "model-b"],
      directions: [["uz", "en"]],
      rounds: 2,
      cacheDir: null,
    });

    assert.equal(turns.length, 8);
    const good = turns.filter((t) => t.model === "model-a");
    assert.ok(
      good.every(
        (t) =>
          t.ok &&
          t.translation === "hello world" &&
          t.transcript === "salom dunyo",
      ),
    );
    assert.ok(
      good.every(
        (t) =>
          t.firstAudioMs! >= 0 &&
          t.firstAudioMs! < 2000 &&
          t.sttCommitMs !== undefined,
      ),
    );
    // A model that fails is recorded as failed turns, not silently skipped or retried elsewhere.
    const bad = turns.filter((t) => t.model === "model-b");
    assert.ok(
      bad.length === 4 &&
        bad.every((t) => !t.ok && t.error === "translation_failed"),
    );
    // Fixtures are spoken by the incoming voice only.
    const voices = new Set(
      eleven.tts.messages
        .filter((m) => m.voices)
        .map((m) => (m.voices as string[])[0]),
    );
    assert.deepEqual([...voices], ["voice-stock"]);

    const text = report(turns, { Date: "test" });
    assert.match(text, /\| model-a \| uz-en \| 1 \| 2 \| 0 \|/);
    assert.match(text, /\| model-b \| uz-en \| 5 \| 2 \| 2 \| — \|/);
    assert.match(text, /Speech synthesis characters: 44/);
    assert.ok(!/\$\s?\d/.test(text), "the report must not invent prices");
  } finally {
    await eleven.close();
    await gemini.close();
  }
});

test("percentile and resampling helpers", () => {
  const values = Array.from({ length: 100 }, (_, i) => i + 1);
  assert.deepEqual(
    [percentile(values, 50), percentile(values, 95), percentile(values, 99)],
    [50, 95, 99],
  );
  assert.equal(percentile([], 50), undefined);
  assert.equal(percentile([7], 99), 7);
  const pcm = Buffer.alloc(4800 * 2);
  for (let i = 0; i < 4800; i++)
    pcm.writeInt16LE(
      Math.round(10000 * Math.sin((2 * Math.PI * 440 * i) / 24000)),
      i * 2,
    );
  const down = resampleTo16k(pcm, 24000);
  assert.equal(down.length, 3200 * 2);
  assert.equal(resampleTo16k(down, 16000), down);
  const peak = Math.max(
    ...new Int16Array(down.buffer, down.byteOffset, 3200).map(Math.abs),
  );
  assert.ok(peak > 9000 && peak <= 10000);
});

// ---- Remote mode: a real gateway on a local port with FAKE providers, and a fake site. Nothing reaches a real service.

const uzSentences = {
  uz: [
    { words: 1, text: "Rahmat." },
    { words: 5, text: "Ha, albatta, men roziman." },
  ],
};
/** Square-wave "speech" the fake recogniser hears; its length stands in for the sentence's audio. */
const fakeAudio = async (_lang: string, index: number) => speech(300 + index * 200);

test("remote benchmark, token and own keys: turns through a running gateway, session creation timed, no credential in the output", async () => {
  const OWN_ELEVENLABS = "own-elevenlabs-key-0123456789abcdef";
  const OWN_GEMINI = "own-gemini-key-0123456789abcdef";
  const WRONG_TOKEN = "wrong-token-0123456789abcdef0123456789";
  const asked: { elevenlabs: string; gemini: string }[] = [];
  const { gateway, base } = await startGateway({
    env: { MAX_KEYS_SESSIONS: "1" },
    // A translation unlike the transcript, so no turn is taken for an echo of the one before.
    fake: { translate: () => "hello world" },
    providersFor: (keys) => (asked.push(keys), createFakeProviders({ delayMs: 2, translate: () => "hello world" })),
  });
  const output: string[] = [];
  const run = (credentials: Parameters<typeof runRemoteBench>[0]["credentials"], rounds: number) =>
    runRemoteBench({
      gateway: base,
      credentials,
      sentences: uzSentences,
      audioFor: fakeAudio,
      models: [],
      directions: [["uz", "en"]],
      rounds,
      onProgress: (line) => output.push(line),
      onTurn: (turn) => output.push(JSON.stringify(turn)),
    });
  try {
    const token = await run({ mode: "token", token: ACCESS_TOKEN }, 2);
    assert.equal(token.fatal, undefined);
    assert.deepEqual(token.problems, []);
    assert.equal(token.turns.length, 4);
    assert.ok(
      token.turns.every(
        (t) =>
          t.ok &&
          t.model === "gateway default" &&
          t.direction === "uz-en" &&
          t.translation === "hello world" &&
          t.firstAudioMs! >= 0 &&
          t.firstAudioMs! < 2000 &&
          t.sttCommitMs !== undefined &&
          t.ttsFirstAudioMs !== undefined,
      ),
      JSON.stringify(token.turns),
    );
    assert.equal(token.sessions.length, 1);
    assert.ok(token.sessions[0]!.ms >= 0 && token.sessions[0]!.ms < 2000);
    assert.equal(token.providers?.mock, true);
    const text = report(token.turns, remoteMeta(token, { mode: "token", gateway: base, rounds: 2 }), "client");
    output.push(text);
    assert.match(text, /- \*\*Mode:\*\* token\n/);
    assert.match(text, /- \*\*Gateway:\*\* 127\.0\.0\.1:\d+\n/);
    assert.match(text, /- \*\*Session creation \(token\):\*\* median \d+ ms, max \d+ ms over 1 session/);
    assert.match(text, /MOCK providers/);
    assert.match(text, /`turn\.commit` sent → first synthesized frame received/);
    assert.match(text, /\| gateway default \| uz-en \| 1 \| 2 \| 0 \|/);
    assert.match(text, /\| gateway default \| uz-en \| 5 \| 2 \| 0 \|/);

    // Own keys: the session's providers are built from exactly the keys the bench was given.
    const keys = await run({ mode: "keys", elevenlabsKey: OWN_ELEVENLABS, geminiKey: OWN_GEMINI }, 1);
    assert.equal(keys.fatal, undefined);
    assert.ok(keys.turns.length === 2 && keys.turns.every((t) => t.ok));
    assert.deepEqual(asked, [{ elevenlabs: OWN_ELEVENLABS, gemini: OWN_GEMINI }]);
    output.push(report(keys.turns, remoteMeta(keys, { mode: "keys", gateway: base, rounds: 1 }), "client"));

    // A refused session stops the run with the reason, never with the credential.
    const wrong = await run({ mode: "token", token: WRONG_TOKEN }, 1);
    assert.equal(wrong.fatal, "the gateway refused the session: 401 unauthorized");
    assert.equal(wrong.turns.length, 0);
    output.push(report(wrong.turns, remoteMeta(wrong, { mode: "token", gateway: base, rounds: 1 }), "client"));

    const all = output.join("\n");
    for (const secret of [ACCESS_TOKEN, OWN_ELEVENLABS, OWN_GEMINI, WRONG_TOKEN])
      assert.ok(!all.includes(secret), "a credential reached the output");
  } finally {
    await gateway.close();
  }
});

test("remote benchmark: what a timed-out turn still sends later is never counted for the next turn", async () => {
  const inner = createFakeProviders({
    delayMs: 2,
    transcripts: ["birinchi", "ikkinchi", "uchinchi", "to'rtinchi"],
    translate: (req) => `said ${req.text}`,
  });
  let commits = 0;
  // The first turn's transcript comes back late: after that turn has timed out, while the next one is running.
  const factory: ProviderFactory = {
    ...inner,
    stt: (options) =>
      inner.stt({
        ...options,
        events: {
          ...options.events,
          onCommitted: (text) =>
            ++commits === 1
              ? void setTimeout(() => options.events.onCommitted(text), 600)
              : options.events.onCommitted(text),
        },
      }),
  };
  const { gateway, base } = await startGateway({ factory, env: { MAX_SESSIONS: "2" } });
  try {
    const result = await runRemoteBench({
      gateway: base,
      credentials: { mode: "token", token: ACCESS_TOKEN },
      sentences: uzSentences,
      audioFor: fakeAudio,
      models: [],
      directions: [["uz", "en"]],
      rounds: 2,
      turnTimeoutMs: 300,
    });
    assert.equal(result.fatal, undefined);
    assert.deepEqual(result.problems, []);
    assert.equal(result.turns.length, 4);
    assert.deepEqual(
      result.turns.map((t) => [t.ok, t.error, t.transcript, t.translation]),
      [
        [false, "timeout", undefined, undefined],
        [true, undefined, "ikkinchi", "said ikkinchi"],
        [true, undefined, "uchinchi", "said uchinchi"],
        [true, undefined, "to'rtinchi", "said to'rtinchi"],
      ],
    );
    // The turn that timed out ended its session; the rest ran in a new one.
    assert.equal(result.sessions.length, 2);
  } finally {
    await gateway.close();
  }
});

/**
 * The site's app API as far as the bench uses it (device sign-in, refresh, sign-out), on a local port. The first token
 * polls get `pollAnswers`, one each; the next one gets the tokens.
 */
async function startDeviceSite(
  pollAnswers: [number, object][] = [
    [400, { error: "authorization_pending" }],
    [400, { error: "slow_down" }],
  ],
) {
  const DEVICE_CODE = "secret-device-code-0123456789";
  const calls: { path: string; body: any; authorization?: string }[] = [];
  const issued: { access_token: string; refresh_token: string }[] = [];
  let polls = 0;
  const pair = (expiresIn: number) => {
    const n = issued.length + 1;
    const tokens = { access_token: `lba_access_${n}_0123456789abcdef`, refresh_token: `refresh_${n}_0123456789abcdef` };
    issued.push(tokens);
    return { ...tokens, token_type: "Bearer", expires_in: expiresIn };
  };
  const server = createServer((req, res) => {
    let raw = "";
    req.on("data", (chunk) => (raw += chunk));
    req.on("end", () => {
      const path = (req.url ?? "").replace("/api/livebridge/v1/", "");
      const body = raw ? JSON.parse(raw) : undefined;
      calls.push({ path, body, authorization: req.headers.authorization });
      const send = (status: number, json?: object) => {
        res.writeHead(status, { "content-type": "application/json" });
        res.end(json ? JSON.stringify(json) : "");
      };
      if (path === "device/start/")
        return send(201, {
          device_code: DEVICE_CODE,
          user_code: "ABCD-1234",
          verification_uri: "https://site.test/en/connect/",
          verification_uri_complete: "https://site.test/en/connect/?code=ABCD-1234",
          expires_in: 600,
          interval: 5,
        });
      if (path === "device/token/") {
        if (body?.device_code !== DEVICE_CODE) return send(400, { error: "invalid_grant" });
        const early = pollAnswers[polls++];
        if (early) return send(...early);
        // 30 s is under the bench's refresh margin, so the first use refreshes it.
        return send(200, pair(30));
      }
      if (path === "token/refresh/")
        return body?.refresh_token === issued.at(-1)?.refresh_token
          ? send(200, pair(900))
          : send(401, { error: "invalid_grant" });
      if (path === "logout/")
        return req.headers.authorization === `Bearer ${issued.at(-1)?.access_token}`
          ? send(204)
          : send(401, { error: "invalid_token" });
      send(404, { error: "not_found" });
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return {
    base: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    DEVICE_CODE,
    calls,
    issued,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

test("device sign-in: a 429 from the site while polling waits longer and keeps polling, like slow_down", async () => {
  const site = await startDeviceSite([
    [429, { error: "rate_limited" }],
    [429, {}],
  ]);
  try {
    const slept: number[] = [];
    const account = await deviceSignIn({ site: site.base, say: () => {}, sleep: async (ms) => void slept.push(ms) });
    assert.deepEqual(slept, [5000, 10000, 15000]);
    assert.equal(await account.accessToken(), site.issued.at(-1)!.access_token);
  } finally {
    await site.close();
  }
});

test("remote benchmark, account: device sign-in, one shared refresh, a fatal error stops the run and keeps what was measured, sign-out", async () => {
  const site = await startDeviceSite();
  const authorized: string[] = [];
  const reports: UsageReport[] = [];
  const siteClient: SiteClient = {
    async authorize(accessToken) {
      authorized.push(accessToken);
      if (accessToken !== site.issued.at(-1)?.access_token) throw new SiteError("invalid_token");
      return { accountId: "account-1", balanceUnits: 5000, hasPurchase: false };
    },
    // The first report uses the balance up, so the gateway ends the session with balance_exhausted.
    async usage(report) {
      reports.push(report);
      return { chargedUnits: 5000, balanceUnits: 0 };
    },
  };
  const { gateway, base } = await startGateway({
    site: siteClient,
    env: { USAGE_REPORT_SECONDS: "2" },
    fake: { translate: () => "hello world" },
  });
  try {
    const said: string[] = [];
    const slept: number[] = [];
    const account = await deviceSignIn({
      site: site.base,
      say: (line) => said.push(line),
      sleep: async (ms) => void slept.push(ms),
    });
    const start = site.calls.find((c) => c.path === "device/start/")!;
    assert.match(start.body.device_id, /^bench-[0-9a-f]{16}$/);
    assert.equal(start.body.device_name, "LiveBridge bench");
    assert.match(said.join("\n"), /https:\/\/site\.test\/en\/connect\/\?code=ABCD-1234 .*ABCD-1234/);
    // Polled every `interval` seconds; slow_down adds five.
    assert.deepEqual(slept, [5000, 5000, 10000]);

    // Two callers at once share one refresh.
    const [first, second] = await Promise.all([account.accessToken(), account.accessToken()]);
    assert.equal(first, second);
    assert.equal(first, site.issued.at(-1)!.access_token);
    assert.equal(site.calls.filter((c) => c.path === "token/refresh/").length, 1);

    const output: string[] = [];
    const result = await runRemoteBench({
      gateway: base,
      credentials: { mode: "account", account },
      sentences: uzSentences,
      audioFor: fakeAudio,
      models: [],
      directions: [["uz", "en"]],
      // Ten turns: far longer than the two seconds before the first usage report.
      rounds: 5,
      onProgress: (line) => output.push(line),
      onTurn: (turn) => output.push(JSON.stringify(turn)),
    });
    assert.match(result.fatal ?? "", /^the gateway ended the session: balance_exhausted/);
    assert.ok(result.turns.length >= 1 && result.turns.length < 10, `${result.turns.length} turns`);
    assert.ok(result.turns.every((t) => t.ok));
    assert.equal(result.sessions.length, 1);
    assert.deepEqual(authorized, [first]);
    assert.ok(reports.length >= 1);
    const text = report(result.turns, remoteMeta(result, { mode: "account", gateway: base, rounds: 5 }), "client");
    output.push(text);
    assert.match(text, /- \*\*Session creation \(account\):\*\* median \d+ ms/);
    assert.match(text, /- \*\*Stopped early:\*\* the gateway ended the session: balance_exhausted/);

    await account.logout();
    assert.equal(site.calls.find((c) => c.path === "logout/")?.authorization, `Bearer ${first}`);

    const all = [...output, ...said].join("\n");
    for (const secret of [...site.issued.flatMap((t) => [t.access_token, t.refresh_token]), site.DEVICE_CODE])
      assert.ok(!all.includes(secret), "a credential reached the output");
  } finally {
    await gateway.close();
    await site.close();
  }
});
