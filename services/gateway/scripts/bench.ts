// Latency benchmark over the real pipeline code (STT -> translation -> TTS) with synthetic fixtures.
//
//   npm run bench -- [--rounds 10] [--models gemini-3.8-flash,gemini-3.5-flash-lite] [--directions uz-en,en-uz]
//
// Fixture audio is synthesized once from tests/fixtures/sentences.json with the STOCK voice (never the owner clone)
// and cached under tests/fixtures/audio/. Each turn is fed in real time, committed at end of speech, and timed with
// the server's monotonic clock. Client playback (jitter buffer + device) is NOT included — measure that with
// `lbaudio session`. Sends only synthetic sentences; never run it on real call audio.
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import type {
  Lang,
  ServerMessage,
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
        // Timing is direction-agnostic; the benchmark always drives the pipeline as "out" with the stock voice.
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
          const find = <T extends ServerMessage["type"]>(type: T) =>
            inbox.messages.find(
              (m): m is Extract<ServerMessage, { type: T }> => m.type === type,
            );
          const metrics =
            result.done?.type === "metrics" ? result.done : undefined;
          const translation = find("translation.final")?.text;
          turns.push({
            model,
            direction: `${source}-${target}`,
            words: sentence.words,
            ok: !!metrics && inbox.firstAudioAt !== undefined,
            error: metrics
              ? undefined
              : result.done?.type === "error"
                ? result.done.code
                : "timeout",
            firstAudioMs:
              metrics && inbox.firstAudioAt !== undefined
                ? Math.round(inbox.firstAudioAt - result.committedAt)
                : undefined,
            sttCommitMs: metrics?.stt_commit_ms,
            translateFirstMs: metrics?.translate_first_ms,
            translateTotalMs: metrics?.translate_total_ms,
            ttsFirstAudioMs: metrics?.tts_first_audio_ms,
            synthesizedMs: metrics?.audio_ms,
            audioSeconds: audio[index]!.length / 32_000,
            ttsCharacters: translation?.length ?? 0,
            source: sentence.text,
            transcript: find("caption.final")?.text,
            translation,
          });
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
): string {
  const fmt = (value: number | undefined) =>
    value === undefined ? "—" : String(Math.round(value));
  const lines = [
    "# LiveBridge latency benchmark",
    "",
    ...Object.entries(meta).map(([key, value]) => `- **${key}:** ${value}`),
    "",
    'Times are milliseconds on the gateway clock. "First audio" = end of speech (commit) → first synthesized audio',
    "leaving the gateway; client playback is not included. Stage columns are medians.",
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

const isMain = process.argv[1] === fileURLToPath(import.meta.url);
if (isMain) {
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
