// Recognises our own synthesized speech when a microphone hears it again — the far end on loudspeakers, or the owner
// without headphones — so a translation is never translated a second time. One instance per session, shared by both
// directions: an echo can come back on either one.
import type { Direction } from "../../../packages/protocol/src/index.ts";

/** An echo is committed at most this long after the client finished playing the turn. */
const TAIL_MS = 3_000;
/** How long a spoken turn is remembered when the client never reports the end of its playback. */
const MAX_AGE_MS = 30_000;
/** Shorter transcripts must repeat a whole spoken turn word for word (a short reply is usually real speech); longer
 * ones may be a fragment or a slightly different hearing of it. */
const FRAGMENT_WORDS = 4;
const FRAGMENT_OVERLAP = 0.75;

interface Spoken {
  direction: Direction;
  turnId: number;
  words: string[];
  startedAt: number;
  endedAt?: number;
}

const words = (text: string) =>
  text
    .normalize("NFKC")
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);

/** Share of `heard` words that also occur in `spoken`, counting repeats. */
function overlap(heard: string[], spoken: string[]): number {
  const left = new Map<string, number>();
  for (const word of spoken) left.set(word, (left.get(word) ?? 0) + 1);
  let found = 0;
  for (const word of heard) {
    const n = left.get(word) ?? 0;
    if (n > 0) {
      found++;
      left.set(word, n - 1);
    }
  }
  return found / heard.length;
}

export class EchoGuard {
  private spoken: Spoken[] = [];
  private readonly now: () => number;

  constructor(now: () => number = () => performance.now()) {
    this.now = now;
  }

  /** A translation was handed to speech synthesis. */
  spoke(direction: Direction, turnId: number, text: string) {
    this.spoken.push({
      direction,
      turnId,
      words: words(text),
      startedAt: this.now(),
    });
  }

  /** The client finished playing that turn. */
  playbackEnded(direction: Direction, turnId: number) {
    const turn = this.spoken.find(
      (s) => s.direction === direction && s.turnId === turnId,
    );
    if (turn) turn.endedAt = this.now();
  }

  /** True when a committed transcript repeats something this session has just spoken. */
  isEcho(text: string): boolean {
    const now = this.now();
    this.spoken = this.spoken.filter((s) =>
      s.endedAt === undefined
        ? now - s.startedAt <= MAX_AGE_MS
        : now - s.endedAt <= TAIL_MS,
    );
    const heard = words(text);
    if (!heard.length) return false;
    return this.spoken.some((s) =>
      heard.length >= FRAGMENT_WORDS
        ? overlap(heard, s.words) >= FRAGMENT_OVERLAP
        : s.words.length === heard.length && overlap(heard, s.words) === 1,
    );
  }
}
