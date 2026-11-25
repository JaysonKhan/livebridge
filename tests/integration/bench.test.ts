// Runs the benchmark harness against local MOCK provider servers. This checks that the harness itself works and
// reports sensible numbers; the latencies it measures here are those of the mocks, not of any real provider.
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig } from "../../services/gateway/src/config.ts";
import { silentLogger } from "../../services/gateway/src/log.ts";
import { createRealProviders } from "../../services/gateway/src/providers/real.ts";
import {
  percentile,
  report,
  resampleTo16k,
  runBench,
} from "../../services/gateway/scripts/bench.ts";
import { ACCESS_TOKEN } from "./helpers.ts";
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
