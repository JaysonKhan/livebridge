// Usage counting and the reports that charge an account. The meter only adds integers; the reporter talks to the
// site in the background. Timers are mocked and the fake site answers at once, so one settle finishes each interval.
import assert from "node:assert/strict";
import { test, type TestContext } from "node:test";
import type { AudioFrame } from "../../../packages/protocol/src/index.ts";
import { BillingReporter, UsageMeter, type ReporterOptions } from "../src/billing.ts";
import { createLogger, silentLogger } from "../src/log.ts";
import { DirectionPipeline } from "../src/pipeline.ts";
import { createFakeProviders } from "../src/providers/fake.ts";
import type { StreamingSTT } from "../src/providers/types.ts";
import { SiteError, type SiteClient, type UsageReport } from "../src/site.ts";

const EVERY_MS = 10_000;
const ACCOUNT = "6f1c0000-0000-4000-8000-000000000001";
const SESSION = "0b7e3c2a-5d41-4f7a-9c1e-2a6b8d9e0f13";

/**
 * A site that keeps each report's body exactly as the real client would send it, and answers from a script: a
 * balance, "fail" (the site client's own error) or "crash" (any other error).
 */
function fakeSite(script: (number | "fail" | "crash")[] = []) {
  const bodies: string[] = [];
  const site: SiteClient = {
    authorize: () => Promise.reject(new Error("not used")),
    usage: async (report) => {
      bodies.push(JSON.stringify(report));
      const reply = script.shift() ?? 1000;
      if (reply === "fail") throw new SiteError("unavailable");
      if (reply === "crash") throw new Error("socket hang up");
      return { chargedUnits: 1, balanceUnits: reply };
    },
  };
  /** The reports without the fields every one of them shares. */
  const sent = () =>
    bodies.map((body) => {
      const { account_id, session_id, ...rest } = JSON.parse(body) as UsageReport;
      assert.deepEqual([account_id, session_id], [ACCOUNT, SESSION]);
      return rest;
    });
  return { site, bodies, sent };
}

function reporterWith(site: SiteClient, options: Partial<ReporterOptions> = {}) {
  const meter = new UsageMeter();
  const balances: number[] = [];
  const fatals: string[] = [];
  const lines: string[] = [];
  const reporter = new BillingReporter({
    site,
    accountId: ACCOUNT,
    sessionId: SESSION,
    meter,
    everyMs: EVERY_MS,
    log: createLogger((line) => lines.push(line)),
    onBalance: (units) => balances.push(units),
    onFatal: (code) => fatals.push(code),
    ...options,
  });
  /** The log lines as written, without their timestamp. */
  const logs = () =>
    lines.map((line) => {
      const { t, ...rest } = JSON.parse(line);
      return rest;
    });
  return { reporter, meter, balances, fatals, lines, logs };
}

/** Lets every promise the fake site settled run to completion; setImmediate is not mocked. */
const settle = () => new Promise((resolve) => setImmediate(resolve));

/** Mocks the timers for this test; the returned function moves the clock on and settles what that started. */
function clock(t: TestContext) {
  t.mock.timers.enable({ apis: ["setInterval", "setTimeout"] });
  return async (ms = EVERY_MS) => {
    t.mock.timers.tick(ms);
    await settle();
  };
}

test("meter: 32 000 bytes of 16 kHz audio is 1000 ms; a take clears it, and a part of a millisecond waits for the next", () => {
  const meter = new UsageMeter();
  meter.addStt("out", 32_000);
  assert.deepEqual(meter.take(), { sttMsOut: 1000, sttMsIn: 0, ttsChars: 0 });
  assert.deepEqual(meter.take(), { sttMsOut: 0, sttMsIn: 0, ttsChars: 0 });
  meter.addStt("in", 50);
  assert.deepEqual(meter.take(), { sttMsOut: 0, sttMsIn: 1, ttsChars: 0 });
  meter.addStt("in", 14);
  assert.deepEqual(meter.take(), { sttMsOut: 0, sttMsIn: 1, ttsChars: 0 });
});

test("meter: synthesis is counted in characters (code points), not UTF-16 units", () => {
  const meter = new UsageMeter();
  meter.addTts("o'zbek 👋");
  assert.deepEqual(meter.take(), { sttMsOut: 0, sttMsIn: 0, ttsChars: 8 });
});

test("pipeline: only audio that speech-to-text accepted is counted, never dropped or refused frames", async () => {
  const overflows = [0, 320, 640];
  const stt: StreamingSTT = {
    open: async () => {},
    sendAudio: () => overflows.shift() ?? 0,
    commit() {},
    discardPending() {},
    close() {},
  };
  const meter = new UsageMeter();
  const pipeline = new DirectionPipeline({
    direction: "out",
    config: { enabled: true, source_lang: "uz", target_lang: "en", speak: false, commit: "manual" },
    factory: { ...createFakeProviders(), stt: () => stt },
    translationModel: "fake-model",
    glossary: [],
    log: silentLogger,
    emit: () => {},
    sendAudio: () => 0,
    onReadyChanged: () => {},
    meter,
  });
  const frame = (sequence: number, generation = 1): AudioFrame => ({
    kind: "capture",
    direction: "out",
    flags: 0,
    generation,
    sequence,
    timestampUs: 0n,
    turnId: 0,
    payload: new Uint8Array(640),
  });
  pipeline.captureStart(1);
  pipeline.onCaptureFrame(frame(0)); // no speech-to-text session yet: all of it is dropped
  await pipeline.open();
  pipeline.onCaptureFrame(frame(1)); // 640 bytes accepted
  pipeline.onCaptureFrame(frame(2)); // 320 of 640 dropped
  pipeline.onCaptureFrame(frame(3)); // all dropped
  pipeline.onCaptureFrame(frame(3)); // a duplicate never reaches speech-to-text
  pipeline.onCaptureFrame(frame(4, 0)); // nor does a stale generation
  pipeline.close();
  assert.deepEqual(overflows, []);
  assert.deepEqual(meter.take(), { sttMsOut: 30, sttMsIn: 0, ttsChars: 0 });
});

test("reporter: each interval reports what was used since the last report, numbered from 0, and passes the balance on", async (t) => {
  const advance = clock(t);
  const { site, sent } = fakeSite([480]);
  const { reporter, meter, balances, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 32_000);
  meter.addStt("in", 16_000);
  meter.addTts("Hello");
  await advance(EVERY_MS - 1);
  assert.deepEqual(sent(), []);
  await advance(1);
  assert.deepEqual(sent(), [{ seq: 0, stt_ms_out: 1000, stt_ms_in: 500, tts_chars: 5 }]);
  assert.deepEqual(balances, [480]);
  assert.deepEqual(fatals, []);
});

test("reporter: an interval with nothing used sends nothing", async (t) => {
  const advance = clock(t);
  const { site, bodies } = fakeSite();
  const { reporter, meter, balances } = reporterWith(site);
  reporter.start();
  await advance();
  meter.addStt("out", 31); // less than a millisecond
  await advance();
  assert.deepEqual(bodies, []);
  assert.deepEqual(balances, []);
});

test("reporter: a failed report is resent unchanged at the next interval; usage since then waits for the next number", async (t) => {
  const advance = clock(t);
  const { site, bodies, sent } = fakeSite(["fail", 470, 460]);
  const { reporter, meter, balances, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  await advance();
  meter.addStt("in", 6_400);
  meter.addTts("ok");
  await advance();
  assert.equal(bodies.length, 2);
  assert.equal(bodies[1], bodies[0]);
  await advance();
  assert.deepEqual(sent(), [
    { seq: 0, stt_ms_out: 100, stt_ms_in: 0, tts_chars: 0 },
    { seq: 0, stt_ms_out: 100, stt_ms_in: 0, tts_chars: 0 },
    { seq: 1, stt_ms_out: 0, stt_ms_in: 200, tts_chars: 2 },
  ]);
  assert.deepEqual(balances, [470, 460]);
  assert.deepEqual(fatals, []);
});

test("reporter: each failed report is logged with its number, the failure count and the code, and nothing else", async (t) => {
  const advance = clock(t);
  const { site } = fakeSite(["fail", "crash", 450]);
  const { reporter, meter, lines, logs } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  for (let i = 0; i < 3; i++) await advance();
  assert.deepEqual(logs(), [
    { level: "warn", event: "billing.report_failed", session: SESSION, seq: 0, failures: 1, code: "unavailable" },
    { level: "warn", event: "billing.report_failed", session: SESSION, seq: 0, failures: 2, code: "unknown" },
  ]);
  const log = lines.join("\n");
  assert.ok(!log.includes(ACCOUNT) && !log.includes("hang up"));
});

test("reporter: three failed reports in a row are fatal billing_unavailable, said once, and reporting stops", async (t) => {
  const advance = clock(t);
  const { site, bodies } = fakeSite(["fail", "fail", "fail"]);
  const { reporter, meter, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  await advance();
  await advance();
  assert.deepEqual(fatals, []);
  await advance();
  assert.deepEqual(fatals, ["billing_unavailable"]);
  meter.addStt("out", 3_200);
  await advance();
  await advance();
  assert.equal(bodies.length, 3);
  assert.deepEqual(fatals, ["billing_unavailable"]);
});

test("reporter: a success in between starts the failure count again", async (t) => {
  const advance = clock(t);
  const { site, bodies } = fakeSite(["fail", "fail", 400, "fail", "fail"]);
  const { reporter, meter, balances, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  for (let i = 0; i < 3; i++) await advance();
  meter.addStt("out", 3_200);
  for (let i = 0; i < 2; i++) await advance();
  assert.equal(bodies.length, 5);
  assert.deepEqual(balances, [400]);
  assert.deepEqual(fatals, []);
});

test("reporter: a balance of 0 is passed on and then fatal balance_exhausted; reporting stops", async (t) => {
  const advance = clock(t);
  const { site, bodies } = fakeSite([0]);
  const { reporter, meter, balances, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("in", 3_200);
  await advance();
  assert.deepEqual(balances, [0]);
  assert.deepEqual(fatals, ["balance_exhausted"]);
  meter.addStt("in", 3_200);
  await advance();
  assert.equal(bodies.length, 1);
});

test("reporter: usage above what one report may carry goes out at once in consecutive numbers", async (t) => {
  const advance = clock(t);
  const { site, sent } = fakeSite([900, 800, 700]);
  const { reporter, meter, balances } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 32 * 250_000);
  meter.addStt("in", 32 * 130_000);
  meter.addTts("x".repeat(45_000));
  await advance();
  assert.deepEqual(sent(), [
    { seq: 0, stt_ms_out: 120_000, stt_ms_in: 120_000, tts_chars: 20_000 },
    { seq: 1, stt_ms_out: 120_000, stt_ms_in: 10_000, tts_chars: 20_000 },
    { seq: 2, stt_ms_out: 10_000, stt_ms_in: 0, tts_chars: 5_000 },
  ]);
  assert.deepEqual(balances, [900, 800, 700]);
});

test("reporter: stop() sends what is left, the unanswered report first and unchanged, then nothing more", async (t) => {
  const advance = clock(t);
  const { site, bodies, sent } = fakeSite(["fail"]);
  const { reporter, meter, balances, fatals } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  await advance();
  meter.addTts("bye");
  const stopped = reporter.stop();
  assert.equal(reporter.stop(), stopped);
  await stopped;
  assert.equal(bodies[1], bodies[0]);
  assert.deepEqual(sent(), [
    { seq: 0, stt_ms_out: 100, stt_ms_in: 0, tts_chars: 0 },
    { seq: 0, stt_ms_out: 100, stt_ms_in: 0, tts_chars: 0 },
    { seq: 1, stt_ms_out: 0, stt_ms_in: 0, tts_chars: 3 },
  ]);
  // Once stopping, answers are not passed on, and the interval is gone.
  assert.deepEqual(balances, []);
  meter.addStt("out", 32_000);
  await advance();
  assert.equal(bodies.length, 3);
  assert.deepEqual(fatals, []);
});

test("reporter: stop() pauses between final attempts and, after the third failure, logs the report it dropped", async (t) => {
  const advance = clock(t);
  const { site, bodies } = fakeSite(["fail", "fail", "fail", "fail"]);
  const { reporter, meter, fatals, logs } = reporterWith(site);
  meter.addStt("out", 3_200);
  const stopped = reporter.stop();
  await settle();
  assert.equal(bodies.length, 1);
  // A site that is restarting refuses at once; the next attempt waits half a second.
  await advance(499);
  assert.equal(bodies.length, 1);
  await advance(1);
  assert.equal(bodies.length, 2);
  await advance(500);
  assert.equal(bodies.length, 3);
  await stopped;
  assert.equal(new Set(bodies).size, 1);
  assert.deepEqual(fatals, []);
  assert.deepEqual(
    logs().map((l) => [l.event, l.failures]),
    [
      ["billing.report_failed", 1],
      ["billing.report_failed", 2],
      ["billing.report_failed", 3],
      ["billing.final_dropped", undefined],
    ],
  );
  assert.deepEqual(logs().at(-1), { level: "warn", event: "billing.final_dropped", session: SESSION, seq: 0 });
});

test("reporter: a callback that throws is logged; neither the interval nor stop() rejects", async (t) => {
  const advance = clock(t);
  const unhandled: unknown[] = [];
  const onUnhandled = (reason: unknown) => void unhandled.push(reason);
  process.on("unhandledRejection", onUnhandled);
  t.after(() => process.off("unhandledRejection", onUnhandled));
  const { site } = fakeSite([400]);
  const { reporter, meter, lines, logs } = reporterWith(site, {
    onBalance: () => {
      throw new Error("socket gone");
    },
  });
  reporter.start();
  meter.addStt("out", 3_200);
  await advance();
  await reporter.stop();
  await settle();
  assert.deepEqual(unhandled, []);
  assert.deepEqual(logs(), [{ level: "error", event: "billing.callback_failed", session: SESSION }]);
  assert.ok(!lines.join("\n").includes("socket gone"));
});

test("reporter: while a report is unanswered an interval sends nothing; stop() waits for the answer, then sends the rest", async (t) => {
  const advance = clock(t);
  const bodies: string[] = [];
  const answers: ((balance: number) => void)[] = [];
  const site: SiteClient = {
    authorize: () => Promise.reject(new Error("not used")),
    usage: (report) => {
      bodies.push(JSON.stringify(report));
      return new Promise((resolve) => answers.push((balance) => resolve({ chargedUnits: 1, balanceUnits: balance })));
    },
  };
  const { reporter, meter, balances } = reporterWith(site);
  reporter.start();
  meter.addStt("out", 3_200);
  await advance();
  meter.addStt("out", 6_400);
  await advance();
  assert.equal(bodies.length, 1);
  const stopped = reporter.stop();
  await settle();
  assert.equal(bodies.length, 1);
  answers[0]!(400);
  await settle();
  assert.equal(bodies.length, 2);
  answers[1]!(300);
  await stopped;
  assert.deepEqual(
    bodies.map((b) => JSON.parse(b) as UsageReport).map(({ seq, stt_ms_out }) => [seq, stt_ms_out]),
    [
      [0, 100],
      [1, 200],
    ],
  );
  assert.deepEqual(balances, []);
});
