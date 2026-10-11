// Live DOC jobs: one entry per running document (pipeline or a section
// rewrite). Jobs run in-process, detached from any HTTP request; clients
// attach and detach through GET /docs/:id/events.
import { EventEmitter } from "node:events";
import type { DocState } from "./types.js";

export type DocEventName =
  | "doc_snapshot"
  | "doc_status"
  | "doc_outline"
  | "doc_sources"
  | "doc_section_start"
  | "doc_section_delta"
  | "doc_section_reset"
  | "doc_section_done"
  | "doc_section_failed"
  | "doc_notice"
  | "doc_done"
  | "doc_error";

export type JobKind = "pipeline" | "rewrite";

export type LiveJob = {
  id: string;
  userId: string;
  kind: JobKind;
  ctl: AbortController;
  emitter: EventEmitter;
  /** Kept current while the job runs (partial section text included), for snapshots. */
  state: DocState;
  startedAt: number;
  /** Set by cancel, so the pipeline can tell a user stop from a time-out. */
  cancelled: boolean;
};

const live = new Map<string, LiveJob>();

export function liveJob(id: string): LiveJob | undefined {
  return live.get(id);
}

export function liveIds(): Set<string> {
  return new Set(live.keys());
}

/** The user's running pipeline (one running document per user), if any. */
export function runningPipelineFor(userId: string): LiveJob | undefined {
  for (const j of live.values()) if (j.userId === userId && j.kind === "pipeline") return j;
  return undefined;
}

export function registerJob(state: DocState, kind: JobKind): LiveJob {
  const job: LiveJob = { id: state.id, userId: state.userId, kind, ctl: new AbortController(), emitter: new EventEmitter(), state, startedAt: Date.now(), cancelled: false };
  job.emitter.setMaxListeners(50);
  live.set(state.id, job);
  return job;
}

export function emit(job: LiveJob, event: DocEventName, data: unknown): void {
  job.emitter.emit("event", event, data);
}

export function finishJob(job: LiveJob): void {
  if (live.get(job.id) === job) live.delete(job.id);
  job.emitter.emit("end");
  job.emitter.removeAllListeners();
}

export function cancelJob(id: string): boolean {
  const job = live.get(id);
  if (!job) return false;
  job.cancelled = true;
  job.ctl.abort();
  return true;
}

/** Counting semaphore; acquire rejects when the signal aborts while waiting. */
export class Semaphore {
  private waiting: Array<() => void> = [];
  constructor(private free: number) {}
  async acquire(signal?: AbortSignal): Promise<() => void> {
    if (signal?.aborted) throw new DOMException("aborted", "AbortError");
    if (this.free > 0) {
      this.free--;
      return this.releaser();
    }
    await new Promise<void>((resolve, reject) => {
      const grant = () => {
        signal?.removeEventListener("abort", abort);
        resolve();
      };
      const abort = () => {
        this.waiting = this.waiting.filter((w) => w !== grant);
        reject(new DOMException("aborted", "AbortError"));
      };
      signal?.addEventListener("abort", abort, { once: true });
      this.waiting.push(grant);
    });
    return this.releaser();
  }
  private releaser() {
    let done = false;
    return () => {
      if (done) return;
      done = true;
      const next = this.waiting.shift();
      if (next) next();
      else this.free++;
    };
  }
}

/** Section model calls across all documents (leaves provider room for chat). */
export const sectionSlots = new Semaphore(3);
