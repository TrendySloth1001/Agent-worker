/**
 * Per-provider concurrency caps with two priorities.
 *
 * Main work (the answer the user waits for, docs, round table) queues for a
 * slot and is served first. Aux work (titles, suggestions, memory,
 * compaction, preflight, autocomplete) never takes the last free slot of a
 * provider that has more than one, waits only briefly, and gives up instead
 * of queueing behind main work, so the answer always has headroom.
 */
import type { ProviderId } from "../models.js";

export type Priority = "main" | "aux";

type Waiter = { priority: Priority; grant: () => void };

export class Slots {
  private waiting: Waiter[] = [];
  private free: number;
  constructor(public readonly size: number) {
    this.free = size;
  }
  get available(): boolean {
    return this.free > 0;
  }
  get inUse(): number {
    return this.size - this.free;
  }
  get queued(): number {
    return this.waiting.length;
  }
  /** Free slots aux work may take: one is always kept for main work when there is more than one. */
  get auxSpare(): number {
    if (this.waiting.some((w) => w.priority === "main")) return 0;
    return Math.max(0, this.free - (this.size > 1 ? 1 : 0));
  }

  /**
   * Main: waits in line (main waiters before aux ones) until a slot frees or
   * [signal] aborts. Aux: takes a spare slot at once, else waits at most
   * [maxWaitMs] for one and then rejects with "slot_busy".
   */
  async acquire(signal: AbortSignal, opts: { priority?: Priority; onWait?: () => void; maxWaitMs?: number } = {}): Promise<() => void> {
    const priority = opts.priority ?? "main";
    if (priority === "main" ? this.free > 0 && !this.waiting.some((w) => w.priority === "main") : this.auxSpare > 0) {
      this.free--;
      return this.releaser();
    }
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    opts.onWait?.();
    await new Promise<void>((resolve, reject) => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const waiter: Waiter = {
        priority,
        grant: () => {
          clearTimeout(timer);
          signal.removeEventListener("abort", abort);
          resolve();
        },
      };
      const drop = () => {
        this.waiting = this.waiting.filter((w) => w !== waiter);
      };
      const abort = () => {
        clearTimeout(timer);
        drop();
        reject(new DOMException("aborted", "AbortError"));
      };
      signal.addEventListener("abort", abort, { once: true });
      if (opts.maxWaitMs !== undefined) {
        timer = setTimeout(() => {
          signal.removeEventListener("abort", abort);
          drop();
          reject(new Error("slot_busy"));
        }, opts.maxWaitMs);
      }
      // Main waiters go ahead of every aux waiter.
      if (priority === "main") {
        const firstAux = this.waiting.findIndex((w) => w.priority === "aux");
        if (firstAux < 0) this.waiting.push(waiter);
        else this.waiting.splice(firstAux, 0, waiter);
      } else this.waiting.push(waiter);
    });
    return this.releaser();
  }

  private releaser(): () => void {
    let done = false;
    return () => {
      if (done) return;
      done = true;
      this.release();
    };
  }

  private release(): void {
    this.free++;
    // Hand the slot to the next waiter that may take it.
    const next = this.waiting[0];
    if (!next) return;
    if (next.priority === "aux" && this.auxSpare <= 0) return;
    this.waiting.shift();
    this.free--;
    next.grant();
  }
}

/** Requests in flight per provider (Ollama Cloud's free plan allows one at a time). */
export const SLOT_SIZES: Record<ProviderId, number> = { ollama: 1, openrouter: 2, groq: 3, nvidia: 2 };

export const slots: Record<ProviderId, Slots> = {
  ollama: new Slots(SLOT_SIZES.ollama),
  openrouter: new Slots(SLOT_SIZES.openrouter),
  groq: new Slots(SLOT_SIZES.groq),
  nvidia: new Slots(SLOT_SIZES.nvidia),
};

export const slotsFor = (id: string): Slots | undefined => slots[id.slice(0, id.indexOf(":")) as ProviderId];

/** Live slot use per provider (owner telemetry). */
export const slotSnapshot = () => Object.fromEntries(Object.entries(slots).map(([p, s]) => [p, { size: s.size, inUse: s.inUse, queued: s.queued }]));
