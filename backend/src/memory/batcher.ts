// Memory extraction is the one background LLM call that used to run on every
// turn. Most turns hold no durable fact about the user, so now:
//   - explicit "remember/forget" asks run at once,
//   - chit-chat, very short and non-personal messages are skipped (no call),
//   - turns that look like a statement about the user are batched: one call per
//     [size] turns of a conversation, or when the conversation goes idle.
import type { IntentResult } from "../nlp/intent.js";

export const MIN_EXTRACT_CHARS = 12;
export const BATCH_SIZE = 3;
export const IDLE_MS = 90_000;

/** First-person statements that tend to carry a lasting fact (who they are, what they use, prefer or work on). */
const PERSONAL =
  /\b(i am|i['’]m|i['’]ve|i['’]d|i work|i use|i live|i prefer|i like|i love|i hate|i have|i study|i build|i code|i write|i speak|i run|i own|i need to always|my (?:name|job|role|team|company|project|stack|setup|goal|favou?rite|wife|husband|partner|kids?|son|daughter|dog|cat|boss|school|university|college|city|country|timezone|birthday|budget|business|startup|app|site|website|phone|laptop|editor|workflow)|we use|we['’]re|we are|our (?:team|stack|company|product|app|startup|codebase|repo|project)|call me|from now on|always (?:use|answer|reply|respond)|never (?:use|answer|reply|respond))\b/i;

export type ExtractionPlan = "now" | "batch" | "skip";

/** What to do with a turn's message for memory: extract at once, batch it, or skip the call entirely. */
export function extractionPlan(text: string, explicit: boolean, intent?: IntentResult): ExtractionPlan {
  if (explicit) return "now";
  const t = text.trim();
  if (t.length < MIN_EXTRACT_CHARS) return "skip";
  // Confident small talk ("thanks!") holds no facts.
  if (intent && intent.top === "chitchat" && !intent.uncertain && intent.confidence >= 0.6) return "skip";
  return PERSONAL.test(t) ? "batch" : "skip";
}

/** Collects items per key and runs [run] when [size] have arrived or the key has been quiet for [idleMs]. */
export class TurnBatcher<T> {
  private items = new Map<string, T[]>();
  private timers = new Map<string, NodeJS.Timeout>();

  constructor(
    private run: (key: string, items: T[]) => Promise<void>,
    private opts: { size: number; idleMs: number } = { size: BATCH_SIZE, idleMs: IDLE_MS },
  ) {}

  /** Adds an item; returns true when this addition triggered a flush. */
  add(key: string, item: T): boolean {
    const list = this.items.get(key) ?? [];
    list.push(item);
    this.items.set(key, list);
    this.clearTimer(key);
    if (list.length >= this.opts.size) {
      void this.flush(key);
      return true;
    }
    const timer = setTimeout(() => void this.flush(key), this.opts.idleMs);
    timer.unref?.();
    this.timers.set(key, timer);
    return false;
  }

  pending(key: string): number {
    return this.items.get(key)?.length ?? 0;
  }

  async flush(key: string): Promise<void> {
    this.clearTimer(key);
    const list = this.items.get(key);
    this.items.delete(key);
    if (!list?.length) return;
    try {
      await this.run(key, list);
    } catch {
      // best effort: the run callback logs its own failures
    }
  }

  private clearTimer(key: string): void {
    const t = this.timers.get(key);
    if (t) clearTimeout(t);
    this.timers.delete(key);
  }
}
