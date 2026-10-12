// Memory extraction used to be one background LLM call on every turn. Now the
// rule-based intent classifier (src/nlp/memoryIntent.ts) decides per turn:
//   - most turns (questions, tasks, chit-chat, recall questions): no call,
//   - facts the rules can read (name, location, work, tools, likes...): slot
//     ops with no call at all,
//   - explicit remember/forget/correct/instruction the rules could not turn
//     into clean ops: one call at once,
//   - other first-person statements: batched, one call per [size] turns of a
//     conversation, or when the conversation goes idle.
import type { MemoryAnalysis } from "../nlp/memoryIntent.js";

export const BATCH_SIZE = 3;
export const IDLE_MS = 90_000;

export type ExtractionPlan = "now" | "batch" | "skip";

/** Whether the LLM extractor runs for this turn: at once, batched, or not at all. */
export function extractionPlan(a: Pick<MemoryAnalysis, "llm">): ExtractionPlan {
  return a.llm === "none" ? "skip" : a.llm;
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
