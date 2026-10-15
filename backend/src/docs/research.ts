// Research: one doc-wide source list (deduped by URL, stable ids W#/K#/D#),
// per-section web searches, and the pick of sources each section sees.
import pLimit from "p-limit";
import type { WebResult } from "../web/search.js";
import type { DocSource, OutlineSection } from "./types.js";

export const SNIPPET_CHARS = 1_500;
/** Stored text per source for evidence matching (kept bounded, it lives in a jsonb column). */
export const FULL_CHARS = 6_000;
const OWN_PER_SECTION = 4;
const SHARED_PER_SECTION = 2;
const KB_PER_SECTION = 3;
const FILES_PER_SECTION = 2;

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
};
const snippet = (s: string) => s.replace(/\s+/g, " ").trim().slice(0, 200);
export const urlKey = (url: string) => url.replace(/^https?:\/\/(www\.)?/i, "").replace(/#.*$/, "").replace(/\/+$/, "").toLowerCase();

type Kind = DocSource["kind"];
const PREFIX: Record<Kind, string> = { web: "W", kb: "K", file: "D" };

export class SourceBook {
  readonly items: DocSource[];
  private byKey = new Map<string, string>();
  /** Ids of the base (doc-wide) web search, in rank order. */
  shared: string[] = [];

  constructor(existing: DocSource[] = []) {
    this.items = [...existing];
    for (const s of existing) this.byKey.set(`${s.kind}|${urlKey(s.url) || s.id}`, s.id);
  }

  private next(kind: Kind): string {
    const p = PREFIX[kind];
    let n = 0;
    for (const s of this.items) if (s.id.startsWith(p)) n = Math.max(n, Number(s.id.slice(1)) || 0);
    return `${p}${n + 1}`;
  }

  /** Adds a source unless its URL is already listed; returns its id and whether it is new. */
  add(kind: Kind, r: { title: string; url: string; content: string; full?: string; site?: string; sourceType?: string; key?: string }): { id: string; added: DocSource | null } {
    const key = `${kind}|${r.key ?? (urlKey(r.url) || r.title)}`;
    const have = this.byKey.get(key);
    if (have) return { id: have, added: null };
    const id = this.next(kind);
    const src: DocSource = {
      id,
      kind,
      title: (r.title || r.url).replace(/\s+/g, " ").trim(),
      url: r.url,
      snippet: snippet(r.content),
      site: r.site ?? (kind === "file" ? "document" : hostOf(r.url)),
      ...(r.sourceType ? { sourceType: r.sourceType } : {}),
      text: r.content.slice(0, SNIPPET_CHARS),
      full: (r.full ?? r.content).slice(0, FULL_CHARS),
    };
    this.items.push(src);
    this.byKey.set(key, id);
    return { id, added: src };
  }

  get(id: string): DocSource | undefined {
    return this.items.find((s) => s.id === id);
  }
}

const WORD = /[\p{L}\p{N}]{3,}/gu;
const terms = (s: string) => new Set((s.toLowerCase().match(WORD) ?? []).filter((w) => !STOP.has(w)));
const STOP = new Set("the and for with that this from into are was were how what why when which their there about your you its can will not".split(" "));

/** Token-overlap relevance of a source to a section (cheap, no model). */
export function relevance(section: OutlineSection, src: { title: string; text: string }): number {
  const want = terms(`${section.heading} ${section.goal} ${section.keyPoints.join(" ")}`);
  if (!want.size) return 0;
  const have = terms(`${src.title} ${src.text.slice(0, 1500)}`);
  let hit = 0;
  for (const w of want) if (have.has(w)) hit++;
  return hit / want.size;
}

export type SearchFn = (query: string, signal?: AbortSignal) => Promise<WebResult[]>;

/**
 * Runs the sections' queries (first query of every section before any second
 * one, so a tight budget still covers all sections), ≤3 at a time, staggered.
 * Returns each section's own result ids in rank order.
 */
export async function researchSections(args: {
  sections: OutlineSection[];
  book: SourceBook;
  search: SearchFn;
  signal: AbortSignal;
  budget: number;
  staggerMs: number;
  timeoutMs: number;
  onSources: (added: DocSource[]) => void;
}): Promise<{ own: Map<string, string[]>; searches: number; failed: number }> {
  const jobs: Array<{ section: string; query: string }> = [];
  const maxQ = Math.max(0, ...args.sections.map((s) => s.queries.length));
  for (let q = 0; q < maxQ; q++) for (const s of args.sections) if (s.queries[q]) jobs.push({ section: s.id, query: s.queries[q] });
  const run = jobs.slice(0, Math.max(0, args.budget));
  const own = new Map<string, string[]>(args.sections.map((s) => [s.id, []]));
  const results = new Map<number, WebResult[]>();
  const limit = pLimit(3);
  let failed = 0;
  let nextStart = 0;
  await Promise.all(
    run.map((job, i) =>
      limit(async () => {
        if (args.signal.aborted) return;
        // Stagger starts so a burst does not trip the search rate limit.
        const at = Math.max(Date.now(), nextStart);
        nextStart = at + args.staggerMs;
        if (at > Date.now()) await new Promise((r) => setTimeout(r, at - Date.now()));
        if (args.signal.aborted) return;
        try {
          results.set(i, await args.search(job.query, AbortSignal.any([args.signal, AbortSignal.timeout(args.timeoutMs)])));
        } catch {
          failed++;
        }
      }),
    ),
  );
  // Add in job order so ids are stable regardless of which search finished first.
  run.forEach((job, i) => {
    const added: DocSource[] = [];
    for (const r of results.get(i) ?? []) {
      const { id, added: a } = args.book.add("web", r);
      if (a) added.push(a);
      const list = own.get(job.section)!;
      if (!list.includes(id)) list.push(id);
    }
    if (added.length) args.onSources(added);
  });
  return { own, searches: run.length, failed };
}

/** Sources a writer sees per section, and the characters of each (the best-matching sentences). */
export const WRITER_SOURCES = 6;
export const WRITER_EXCERPT_CHARS = 600;

/** The sentences of [text] that best match the section, in their original order, within [max] characters. */
export function excerptFor(section: OutlineSection, text: string, max = WRITER_EXCERPT_CHARS): string {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= max) return flat;
  const want = terms(`${section.heading} ${section.goal} ${section.keyPoints.join(" ")}`);
  const sentences = flat.match(/[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$/g) ?? [flat];
  const scored = sentences.map((s, i) => {
    let hit = 0;
    for (const w of terms(s)) if (want.has(w)) hit++;
    // The opening sentence usually names the subject; keep a small preference for it.
    return { s: s.trim(), i, score: hit + (i === 0 ? 0.5 : 0) };
  });
  const keep = new Set<number>();
  let used = 0;
  for (const x of [...scored].sort((a, b) => b.score - a.score || a.i - b.i)) {
    if (used + x.s.length + 1 > max) continue;
    keep.add(x.i);
    used += x.s.length + 1;
  }
  const out = scored.filter((x) => keep.has(x.i)).map((x) => x.s).join(" ");
  return out || flat.slice(0, max);
}

/** The sources one section sees: its top own results + top shared, plus the most relevant KB and file sources. */
export function pickSectionSources(section: OutlineSection, own: string[], book: SourceBook): string[] {
  const out: string[] = [];
  const push = (id: string) => {
    if (!out.includes(id)) out.push(id);
  };
  own.slice(0, OWN_PER_SECTION).forEach(push);
  const byRel = (ids: string[]) =>
    ids
      .map((id) => ({ id, r: relevance(section, book.get(id) ?? { title: "", text: "" }) }))
      .sort((a, b) => b.r - a.r)
      .map((x) => x.id);
  // No results of its own: the most relevant shared ones stand in.
  const shared = own.length ? book.shared : byRel(book.shared);
  shared.filter((id) => !out.includes(id)).slice(0, own.length ? SHARED_PER_SECTION : OWN_PER_SECTION).forEach(push);
  byRel(book.items.filter((s) => s.kind === "kb").map((s) => s.id)).slice(0, KB_PER_SECTION).forEach(push);
  byRel(book.items.filter((s) => s.kind === "file").map((s) => s.id)).slice(0, FILES_PER_SECTION).forEach(push);
  return out;
}
