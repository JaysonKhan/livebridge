// Local MOCK provider servers that speak the documented ElevenLabs and Gemini wire protocols, so the real adapter
// code can be exercised without credentials. They prove the adapters match the documentation as read on 2026-11-24;
// they prove nothing about how the live services actually behave.
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { WebSocketServer, type WebSocket } from "ws";

export const MOCK_API_KEY = "mock-elevenlabs-key";
export const MOCK_GEMINI_KEY = "mock-gemini-key";

const listen = (server: Server) =>
  new Promise<string>((resolve) =>
    server.listen(0, "127.0.0.1", () =>
      resolve(`http://127.0.0.1:${(server.address() as AddressInfo).port}`),
    ),
  );
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export interface ElevenLabsBehaviour {
  transcripts?: string[];
  partials?: boolean;
  /** Sent instead of session_started, e.g. `quota_exceeded`. */
  sttStartError?: string;
  /** Audio chunk sizes in bytes for each synthesized turn. Odd sizes exercise sample re-alignment. */
  ttsChunks?: number[];
  ttsChunkDelayMs?: number;
  omitTurnMarker?: boolean;
  /** Sent in reply to a flush instead of audio. */
  ttsError?: string;
}

export async function startMockElevenLabs(behaviour: ElevenLabsBehaviour = {}) {
  const stt = {
    connections: 0,
    queries: [] as URLSearchParams[],
    chunks: [] as { bytes: number; commit: boolean; sample_rate: number }[],
    sockets: new Set<WebSocket>(),
  };
  const tts = {
    connections: 0,
    queries: [] as URLSearchParams[],
    messages: [] as Record<string, unknown>[],
    sockets: new Set<WebSocket>(),
  };
  const server = createServer((_req, res) => res.writeHead(404).end());
  const wss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url ?? "", "http://mock");
    if (req.headers["xi-api-key"] !== MOCK_API_KEY) {
      socket.write("HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n");
      return socket.destroy();
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      if (url.pathname === "/v1/speech-to-text/realtime")
        onStt(ws, url.searchParams);
      else if (url.pathname === "/v1/text-to-dialogue/stream-input")
        onTts(ws, url.searchParams);
      else ws.close();
    });
  });

  function onStt(ws: WebSocket, query: URLSearchParams) {
    stt.connections++;
    stt.queries.push(query);
    stt.sockets.add(ws);
    ws.on("close", () => stt.sockets.delete(ws));
    if (behaviour.sttStartError) {
      ws.send(
        JSON.stringify({
          message_type: behaviour.sttStartError,
          error: "mock refusal",
        }),
      );
      return ws.close();
    }
    ws.send(
      JSON.stringify({
        message_type: "session_started",
        session_id: "mock-session",
        config: { sample_rate: 16000 },
      }),
    );
    let partial = 0;
    let uncommitted = 0;
    ws.on("message", (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.message_type !== "input_audio_chunk") return;
      stt.chunks.push({
        bytes: Buffer.from(msg.audio_base_64, "base64").length,
        commit: msg.commit,
        sample_rate: msg.sample_rate,
      });
      uncommitted += stt.chunks.at(-1)!.bytes;
      if (msg.commit && uncommitted < 9600) {
        // The live service closes the session when a commit carries under 0.3 s of uncommitted audio.
        ws.send(JSON.stringify({ message_type: "commit_throttled", error: "Session closed: You need at least 0.3s of uncommitted audio before committing." }));
        return ws.close(1000);
      }
      if (msg.commit) {
        uncommitted = 0;
        const text = behaviour.transcripts?.shift() ?? "";
        ws.send(JSON.stringify({ message_type: "committed_transcript", text }));
        ws.send(
          JSON.stringify({
            message_type: "committed_transcript_with_timestamps",
            text,
            language_code: null,
            words: null,
          }),
        );
      } else if (behaviour.partials) {
        ws.send(
          JSON.stringify({
            message_type: "partial_transcript",
            text: `partial ${++partial}`,
            turn_probability: 0.08,
          }),
        );
      }
    });
  }

  function onTts(ws: WebSocket, query: URLSearchParams) {
    tts.connections++;
    tts.queries.push(query);
    tts.sockets.add(ws);
    ws.on("close", () => tts.sockets.delete(ws));
    let fill = 1;
    ws.on("message", async (data) => {
      const msg = JSON.parse(data.toString());
      tts.messages.push(msg);
      if (!msg.flush) return;
      if (behaviour.ttsError) {
        ws.send(
          JSON.stringify({
            message: "mock refusal",
            error: behaviour.ttsError,
            code: 1008,
            param: null,
          }),
        );
        return ws.close(1008);
      }
      // Each turn's audio is filled with its own byte value so a test can tell turns apart.
      const value = fill++;
      for (const size of behaviour.ttsChunks ?? [4801, 4799, 4800]) {
        if (behaviour.ttsChunkDelayMs) await wait(behaviour.ttsChunkDelayMs);
        if (ws.readyState !== ws.OPEN) return;
        ws.send(
          JSON.stringify({
            audio: Buffer.alloc(size, value).toString("base64"),
            alignment: null,
            normalized_alignment: null,
          }),
        );
      }
      if (!behaviour.omitTurnMarker)
        ws.send(JSON.stringify({ is_final_audio_for_turn: true }));
    });
  }

  const base = await listen(server);
  return {
    base,
    stt,
    tts,
    behaviour,
    dropStt: () => stt.sockets.forEach((ws) => ws.terminate()),
    sendSttError: (type: string) =>
      stt.sockets.forEach((ws) =>
        ws.send(JSON.stringify({ message_type: type, error: "mock failure" })),
      ),
    close: async () => {
      for (const ws of wss.clients) ws.terminate();
      await new Promise<void>((resolve) => wss.close(() => resolve()));
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}

export interface GeminiModelBehaviour {
  status?: number;
  pieces?: string[];
  finishReason?: string;
  /** Destroy the connection after this many text pieces. */
  dieAfter?: number;
  /** Never answer. */
  hang?: boolean;
  /** Wait this long before answering. */
  delayMs?: number;
  /** Wait this long before answering the first request only. */
  delayFirstMs?: number;
  /** Never answer the first N requests for this model, then behave normally. */
  hangFirst?: number;
}

export async function startMockGemini(
  models: Record<string, GeminiModelBehaviour>,
) {
  const requests: {
    model: string;
    url: string;
    apiKey: string | undefined;
    body: Record<string, any>;
  }[] = [];
  let warmups = 0;
  const server = createServer(async (req, res) => {
    // Connection warm-up (model metadata GET): no tokens, not a translation request.
    if (req.method !== "POST") {
      warmups++;
      return void res.writeHead(200).end("{}");
    }
    let raw = "";
    for await (const part of req) raw += part;
    const match = /\/models\/([^:]+):streamGenerateContent/.exec(req.url ?? "");
    const model = decodeURIComponent(match?.[1] ?? "");
    requests.push({
      model,
      url: req.url ?? "",
      apiKey: req.headers["x-goog-api-key"] as string | undefined,
      body: JSON.parse(raw || "{}"),
    });
    const behaviour = models[model];
    if (req.headers["x-goog-api-key"] !== MOCK_GEMINI_KEY)
      return void res
        .writeHead(403)
        .end('{"error":{"status":"PERMISSION_DENIED"}}');
    if (!behaviour)
      return void res.writeHead(404).end('{"error":{"status":"NOT_FOUND"}}');
    if (behaviour.hang) return;
    if (behaviour.hangFirst && requests.filter((r) => r.model === model).length <= behaviour.hangFirst) return;
    if (behaviour.delayMs) await wait(behaviour.delayMs);
    if (behaviour.delayFirstMs && requests.filter((r) => r.model === model).length === 1) await wait(behaviour.delayFirstMs);
    if (behaviour.status)
      return void res
        .writeHead(behaviour.status)
        .end('{"error":{"status":"MOCK"}}');

    res.writeHead(200, { "content-type": "text/event-stream" });
    const events = [
      // A thinking part must never be treated as translation text.
      {
        candidates: [
          {
            content: { parts: [{ text: "internal reasoning", thought: true }] },
          },
        ],
      },
      ...(behaviour.pieces ?? []).map((text) => ({
        candidates: [{ content: { parts: [{ text }] } }],
      })),
    ];
    let sent = 0;
    for (const event of events) {
      if (behaviour.dieAfter !== undefined && sent > behaviour.dieAfter)
        return void res.destroy();
      // Split every SSE event mid-line across two TCP writes to exercise the adapter's line buffering.
      const line = `data: ${JSON.stringify(event)}\r\n\r\n`;
      const cut = Math.floor(line.length / 2);
      res.write(line.slice(0, cut));
      await wait(2);
      res.write(line.slice(cut));
      sent++;
    }
    const last = {
      candidates: [
        {
          content: { parts: [] },
          finishReason: behaviour.finishReason ?? "STOP",
        },
      ],
      usageMetadata: { promptTokenCount: 10 },
    };
    res.end(`data: ${JSON.stringify(last)}\n\n`);
  });
  const base = await listen(server);
  return {
    base,
    requests,
    server,
    get warmups() {
      return warmups;
    },
    close: () =>
      new Promise<void>((resolve) => {
        server.closeAllConnections();
        server.close(() => resolve());
      }),
  };
}
