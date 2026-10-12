// Merging and ranking of search candidates: RRF across providers, authority,
// recency, lexical relevance and domain diversity. Pure functions.

import { terms } from "./passages.js";
import type { Candidate, Freshness } from "./types.js";
import { authority, baseDomain, dedupeByUrl } from "./url.js";

const RRF_K = 60;
/** Sources whose own ranking is a real web search; the others are topical APIs that return something for any query. */
const WEB_SOURCES = new Set(["ollama", "searxng"]);
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

/**
 * Merge ranked lists from all providers: dedupe by normalised URL, score by
 * RRF + authority + recency + relevance, and drop topical-API hits (Wikipedia,
 * arXiv, ...) that share nothing with the query. [focus] is the query text.
 */
export function mergeCandidates(lists: Candidate[][], fresh: Freshness, focus = "", now = Date.now()): Merged[] {
  const flat: Merged[] = [];
  for (const list of lists) {
    for (const c of list) {
      if (!WEB_SOURCES.has(c.source) && focus) {
        const rel = relevance(c, focus);
        if (rel < 0.5) continue;
      }
      const w = c.source === "ollama" ? 1 : c.source === "searxng" ? 0.9 : 0.6;
      flat.push({ ...c, sources: new Set([c.source]), rrf: w / (RRF_K + c.rank + 1), score: 0 });
    }
  }
  const merged = dedupeByUrl(flat, (keep, drop) => {
    keep.rrf += drop.rrf;
    for (const s of drop.sources) keep.sources.add(s);
    if ((drop.text?.length ?? 0) > (keep.text?.length ?? 0)) keep.text = drop.text;
    if (drop.snippet.length > keep.snippet.length) keep.snippet = drop.snippet;
    keep.published ??= drop.published;
  });
  const max = Math.max(...merged.map((m) => m.rrf), 1e-9);
  const recencyW = fresh === "evergreen" ? 0 : fresh === "breaking" ? 0.3 : 0.18;
  for (const m of merged) {
    const multi = Math.min(1, (m.sources.size - 1) * 0.5);
    const rel = focus ? relevance(m, focus) : 0.5;
    m.score = (0.5 * m.rrf) / max + 0.25 * authority(m.url) + 0.08 * multi + 0.12 * rel + recencyW * freshnessBoost(m.published, fresh, now);
  }
  return merged.sort((a, b) => b.score - a.score);
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

