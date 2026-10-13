/**
 * Aux model calls (titles, suggestions, memory, compaction, preflight,
 * autocomplete, query rewriting) run at a lower priority than the answer:
 *  - they are skipped when the model's budget is tight (they must leave room
 *    for at least a couple more main calls) or the provider has no spare slot;
 *  - identical requests within a few minutes share one result (in-flight
 *    dedupe plus a small TTL cache), so retries and re-renders cost nothing.
 */
import { createHash } from "node:crypto";
import type { Message } from "../providers.js";
import { BudgetBlockedError, check, noteAuxCacheHit, noteAuxDeferred } from "./budget.js";
import { slotsFor } from "./slots.js";

/** Telemetry purposes that are aux work. Anything else (chat, docs, round table, reviews, merges) is main. */
export const AUX_PURPOSES = new Set([
  "title",
  "memory",
  "summary",
  "suggestions",
  "starters",
  "autocomplete",
  "preflight",
  "kb-rewrite",
  "kb-rerank",
  "toggle-suggest",
  "followups",
]);

export const isAux = (purpose: string | undefined): boolean => !!purpose && AUX_PURPOSES.has(purpose);

/** Extra requests an aux call must leave free in the minute/day windows. */
export const AUX_HEADROOM_REQUESTS = 3;
/** Extra tokens an aux call must leave free, on top of its own estimate. */
export const AUX_HEADROOM_TOKENS = 2_000;

/** Throws BudgetBlockedError("aux_deferred") when aux work on [id] would eat into the answer's headroom. */
export function auxGate(id: string, tokens: number, purpose: string): void {
  const v = check(id, tokens + AUX_HEADROOM_TOKENS, { requests: AUX_HEADROOM_REQUESTS });
  const slots = slotsFor(id);
  if (v.ok && (!slots || slots.auxSpare > 0)) return;
  noteAuxDeferred(purpose);
  throw new BudgetBlockedError(id, "aux_deferred", v.ok ? 1_000 : v.waitMs);
}

// ---- dedupe + cache ---------------------------------------------------------------

const TTL_MS = 10 * 60_000;
const MAX_ENTRIES = 300;
const cache = new Map<string, { at: number; text: string }>();
const inflight = new Map<string, Promise<string>>();

const keyOf = (purpose: string, messages: Message[], extra = "") =>
  createHash("sha1")
    .update(purpose)
    .update("\0")
    .update(extra)
    .update("\0")
    .update(JSON.stringify(messages.map((m) => [m.role, m.content, m.images?.length ?? 0])))
    .digest("base64url");

/**
 * Runs [fn] once per identical aux request: a cached result (≤ 10 min old) or
 * an identical call already in flight is shared. Failures are not cached.
 */
export async function auxOnce(purpose: string, messages: Message[], fn: () => Promise<string>, extra = ""): Promise<string> {
  const key = keyOf(purpose, messages, extra);
  const now = Date.now();
  const hit = cache.get(key);
  if (hit && now - hit.at < TTL_MS) {
    noteAuxCacheHit(purpose);
    return hit.text;
  }
  const running = inflight.get(key);
  if (running) {
    noteAuxCacheHit(purpose);
    return running;
  }
  const p = fn()
    .then((text) => {
      cache.set(key, { at: Date.now(), text });
      if (cache.size > MAX_ENTRIES) cache.delete(cache.keys().next().value!);
      return text;
    })
    .finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

/** Test hook. */
export function resetAux(): void {
  cache.clear();
  inflight.clear();
}
