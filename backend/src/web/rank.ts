// Merging and ranking of search candidates: RRF across providers, authority,
// recency, lexical relevance (term coverage + BM25), an optional semantic
// blend, and MMR selection for diversity. Pure functions.

import { rankPassages, terms } from "./passages.js";
import type { Candidate, Freshness } from "./types.js";
import { authority, baseDomain, dedupeByUrl } from "./url.js";

const RRF_K = 60;
/** Sources whose own ranking is a real web search; the others are topical APIs that return something for any query. */
const WEB_SOURCES = new Set(["ollama", "searxng", "brave", "duckduckgo"]);
/** RRF weight per source: full web engines first, then news, then topical APIs. */
const SOURCE_WEIGHT: Record<string, number> = { ollama: 1, brave: 1, duckduckgo: 1, searxng: 0.9, bingnews: 0.8 };
/** Topical-API hits must cover this share of the query's content terms. */
const MIN_TOPICAL_REL = 0.5;
const GENERIC = new Set(["work", "works", "working", "use", "using", "way", "make", "get", "tutorial", "guide", "example", "examples", "news", "today"]);

export type Merged = Candidate & { sources: Set<string>; rrf: number; score: number };

function freshnessBoost(published: string | undefined, fresh: Freshness, now: number): number {
  if (fresh === "evergreen") return 0;
  const t = published ? Date.parse(published) : NaN;
  if (!Number.isFinite(t)) return 0.3; // unknown date: neutral
  const ageDays = Math.max(0, (now - t) / 86_400_000);
  const halfLife = fresh === "breaking" ? 3 : 45;
  return Math.pow(0.5, ageDays / halfLife);
}

/** Fraction of the query's content terms found in the candidate's title, snippet and the start of its body. */
export function relevance(c: Candidate, focus: string): number {
  const q = [...new Set(terms(focus.replace(/\b20\d\d\b/g, " ")).filter((t) => !GENERIC.has(t)))];
  if (!q.length) return 1;
  const have = new Set(terms(`${c.title} ${c.snippet} ${(c.text ?? "").slice(0, 1500)}`));
  return q.filter((t) => have.has(t)).length / q.length;
}

/** What a candidate is measured against: one string, or the planned queries plus the raw question. */
export type MergeFocus = string | { queries: string[]; question?: string };

/** Relevance against the best-matching phrasing: any planned query, or the raw question. */
export function bestRelevance(c: Candidate, focus: MergeFocus): number {
  if (typeof focus === "string") return focus ? relevance(c, focus) : 1;
  const phrasings = [...focus.queries, ...(focus.question ? [focus.question] : [])].filter(Boolean);
  if (!phrasings.length) return 1;
  return Math.max(...phrasings.map((f) => relevance(c, f)));
}

const focusText = (focus: MergeFocus) => (typeof focus === "string" ? focus : focus.queries.join(" ") || focus.question || "");
const docText = (c: Candidate) => `${c.title} ${c.snippet} ${(c.text ?? "").slice(0, 1500)}`;

function toMerged(c: Candidate): Merged {
  const w = SOURCE_WEIGHT[c.source] ?? 0.6;
  return { ...c, sources: new Set([c.source]), rrf: w / (RRF_K + c.rank + 1), score: 0 };
}

/**
 * Merge ranked lists from all providers: dedupe by canonical URL, score by
 * RRF + authority + recency + lexical relevance, and drop topical-API hits
 * (Wikipedia, arXiv, ...) that share too little with the query.
 *
 * Relevance is measured against the best of the planned queries and the raw
 * question, never their concatenation: concatenating a long or non-English
 * question with an English keyword query diluted every hit below the cut-off,
 * which was the cause of "merged: 0" with providers returning results.
 */
export function mergeCandidates(lists: Candidate[][], fresh: Freshness, focus: MergeFocus = "", now = Date.now()): Merged[] {
  const flat: Merged[] = [];
  const dropped: Array<{ c: Candidate; rel: number }> = [];
  const hasFocus = typeof focus === "string" ? !!focus : focus.queries.length > 0 || !!focus.question;
  for (const list of lists) {
    for (const c of list) {
      if (!WEB_SOURCES.has(c.source) && hasFocus) {
        const rel = bestRelevance(c, focus);
        if (rel < MIN_TOPICAL_REL) {
          dropped.push({ c, rel });
          continue;
        }
      }
      flat.push(toMerged(c));
    }
  }
  // Only topical hits that share some terms: keep the closest few rather than answer with nothing.
  if (!flat.length && dropped.length) {
    for (const { c } of dropped.filter((d) => d.rel >= 0.34).sort((a, b) => b.rel - a.rel).slice(0, 3)) flat.push(toMerged(c));
  }
  const merged = dedupeByUrl(flat, (keep, drop) => {
    keep.rrf += drop.rrf;
    for (const s of drop.sources) keep.sources.add(s);
    if ((drop.text?.length ?? 0) > (keep.text?.length ?? 0)) keep.text = drop.text;
    if (drop.snippet.length > keep.snippet.length) keep.snippet = drop.snippet;
    if (!keep.title || keep.title === keep.url) keep.title = drop.title;
    keep.published ??= drop.published;
  });
  if (!merged.length) return [];
  const max = Math.max(...merged.map((m) => m.rrf), 1e-9);
  const recencyW = fresh === "evergreen" ? 0 : fresh === "breaking" ? 0.3 : 0.18;
  const bm25 = rankPassages(merged.map(docText), terms(focusText(focus).replace(/\b20\d\d\b/g, " "))).map((p) => p.score);
  const bmMax = Math.max(...bm25, 1e-9);
  for (const [i, m] of merged.entries()) {
    const multi = Math.min(1, (m.sources.size - 1) * 0.5);
    const cover = hasFocus ? bestRelevance(m, focus) : 0.5;
    const lexical = 0.5 * cover + 0.5 * (bm25[i] / bmMax);
    m.score = (0.45 * m.rrf) / max + 0.22 * authority(m.url) + 0.08 * multi + 0.17 * lexical + recencyW * freshnessBoost(m.published, fresh, now);
  }
  return merged.sort((a, b) => b.score - a.score);
}

/**
 * Blends a semantic similarity (embedding cosine, min-max normalised over the
 * set) into the score; items without one keep theirs. Re-sorts in place.
 */
export function blendSemantic<T extends { url: string; score: number }>(items: T[], sims: Map<string, number>, weight = 0.25): T[] {
  if (!sims.size) return items;
  const vals = [...sims.values()];
  const lo = Math.min(...vals);
  const hi = Math.max(...vals);
  for (const it of items) {
    const s = sims.get(it.url);
    if (s === undefined) continue;
    const norm = hi > lo ? (s - lo) / (hi - lo) : 0.5;
    it.score = (1 - weight) * it.score + weight * norm;
  }
  return items.sort((a, b) => b.score - a.score);
}

const jaccard = (a: Set<string>, b: Set<string>) => {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter++;
  return inter / (a.size + b.size - inter);
};

/**
 * Maximal marginal relevance: the best-scoring item first, then each next one
 * by score minus its similarity to what is already picked (near-duplicates and
 * syndicated copies lose), with diminishing returns and a cap per site.
 */
export function mmr<T extends { url: string; score: number; title?: string; snippet?: string }>(items: T[], n: number, opts: { lambda?: number; perDomain?: number } = {}): T[] {
  const lambda = opts.lambda ?? 0.75;
  const perDomain = opts.perDomain ?? 2;
  const left = items.map((it) => ({ it, toks: new Set(terms(`${it.title ?? ""} ${it.snippet ?? ""}`)) }));
  const picked: typeof left = [];
  const count = new Map<string, number>();
  const max = Math.max(...items.map((i) => i.score), 1e-9);
  while (picked.length < n && left.length) {
    let bi = -1;
    let bs = -Infinity;
    for (let i = 0; i < left.length; i++) {
      const d = baseDomain(left[i].it.url);
      const c = count.get(d) ?? 0;
      if (c >= perDomain) continue;
      const sim = picked.length ? Math.max(...picked.map((p) => jaccard(p.toks, left[i].toks))) : 0;
      const s = lambda * (left[i].it.score / max) * Math.pow(0.85, c) - (1 - lambda) * sim;
      if (s > bs) (bs = s), (bi = i);
    }
    if (bi < 0) break;
    const [pick] = left.splice(bi, 1);
    picked.push(pick);
    const d = baseDomain(pick.it.url);
    count.set(d, (count.get(d) ?? 0) + 1);
  }
  return picked.map((p) => p.it);
}

/** Greedy pick with diminishing returns per domain, at most [perDomain] from one site. */
export function diversify<T extends { url: string; score: number }>(items: T[], n: number, perDomain = 2): T[] {
  const left = [...items];
  const out: T[] = [];
  const count = new Map<string, number>();
  while (out.length < n && left.length) {
    let bi = -1;
    let bs = -1;
    for (let i = 0; i < left.length; i++) {
      const d = baseDomain(left[i].url);
      const c = count.get(d) ?? 0;
      if (c >= perDomain) continue;
      const s = left[i].score * Math.pow(0.8, c);
      if (s > bs) (bs = s), (bi = i);
    }
    if (bi < 0) break;
    const [pick] = left.splice(bi, 1);
    out.push(pick);
    const d = baseDomain(pick.url);
    count.set(d, (count.get(d) ?? 0) + 1);
  }
  return out;
}
