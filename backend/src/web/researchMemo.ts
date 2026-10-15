// Memo of whole research runs (the final, ranked results). A repeated or
// near-same question, or a follow-up in the same chat on an unchanged topic,
// is answered from here instead of asking the engines and pages again.
// Public web data only; keyed in memory by normalized query terms.
import { queryIdentity, queryTerms, termOverlap } from "./cacheStore.js";
import type { Freshness, WebResult } from "./types.js";

/** How long a finished research run is reused: short for time-sensitive topics, long for stable facts. */
export const MEMO_TTL_MS: Record<Freshness, number> = { breaking: 3 * 60_000, recent: 30 * 60_000, evergreen: 6 * 60 * 60_000 };
/** Queries this similar (term overlap) are the same question. */
export const NEAR_SAME = 0.85;
/** In one chat, a follow-up this similar to the previous search is still the same topic. */
export const SAME_TOPIC = 0.6;
const MAX_ENTRIES = 300;

type Entry = { id: string; fresh: Freshness; lang: string; terms: Set<string>; conv?: string; results: WebResult[]; maxResults: number; fetched: boolean; exp: number };

export type MemoQuery = { queries: string[]; fresh: Freshness; lang?: string; conversationId?: string; maxResults: number; fetched: boolean };

export class ResearchMemo {
  private entries = new Map<string, Entry>();
  constructor(private now: () => number = Date.now) {}

  private static id(q: Pick<MemoQuery, "queries" | "fresh" | "lang">): string {
    return `${q.fresh}|${q.lang ?? "en"}|${q.queries.map(queryIdentity).join("||")}`;
  }

  get(q: MemoQuery): { results: WebResult[]; via: "exact" | "near" | "conversation" } | null {
    const t = this.now();
    const terms = new Set(q.queries.flatMap((s) => [...queryTerms(s)]));
    const usable = (e: Entry) => e.exp > t && e.fresh === q.fresh && e.lang === (q.lang ?? "en") && (e.results.length >= q.maxResults || e.maxResults >= q.maxResults) && (e.fetched || !q.fetched);
    const exact = this.entries.get(ResearchMemo.id(q));
    if (exact && usable(exact)) return { results: exact.results.slice(0, q.maxResults), via: "exact" };
    let best: { e: Entry; score: number; via: "near" | "conversation" } | null = null;
    for (const e of this.entries.values()) {
      if (!usable(e)) continue;
      const score = termOverlap(terms, e.terms);
      const sameChat = !!q.conversationId && e.conv === q.conversationId;
      const via = sameChat && score >= SAME_TOPIC ? "conversation" : score >= NEAR_SAME ? "near" : null;
      if (via && (!best || score > best.score)) best = { e, score, via };
    }
    return best ? { results: best.e.results.slice(0, q.maxResults), via: best.via } : null;
  }

  set(q: MemoQuery, results: WebResult[]): void {
    if (!results.length) return; // an empty answer is retried next time
    const id = ResearchMemo.id(q);
    this.entries.delete(id);
    this.entries.set(id, {
      id,
      fresh: q.fresh,
      lang: q.lang ?? "en",
      terms: new Set(q.queries.flatMap((s) => [...queryTerms(s)])),
      conv: q.conversationId,
      results,
      maxResults: q.maxResults,
      fetched: q.fetched,
      exp: this.now() + MEMO_TTL_MS[q.fresh],
    });
    while (this.entries.size > MAX_ENTRIES) this.entries.delete(this.entries.keys().next().value as string);
  }

  clear(): void {
    this.entries.clear();
  }
}
