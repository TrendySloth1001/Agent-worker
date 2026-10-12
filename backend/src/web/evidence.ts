// Sentence-level evidence: pairs each cited answer sentence with the best
// supporting passage from the cited source. Pure CPU, no model calls.

export type EvidenceItem = { tag: string; claim: string; quote: string; score: number };
export type EvidenceSource = { id: string; text: string };

const STOP = new Set(
  "a an the and or but if then else of to in on at by for with from as is are was were be been being it its this that these those he she they we you i not no do does did has have had will would can could should may might about into over under than so such there their them his her our your also which who whom what when where how can more most some any all each other just only very".split(
    " ",
  ),
);

const MIN_SCORE = 0.45;
const MAX_CLAIM = 300;
const MAX_QUOTE = 280;

export function splitSentences(input: string): string[] {
  const text = input.replace(/\s+/g, " ").trim();
  if (!text) return [];
  const out: string[] = [];
  let start = 0;
  // Boundary: .!? (optionally followed by closing quotes/brackets/tags) + space + uppercase/digit/quote.
  const re = /[.!?]+["')\]]*(?:\s*\[[KWDGC]\d+\])*\s+(?=["'(\[]?[A-Z0-9])/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const before = text.slice(start, m.index + 1);
    // Avoid splitting on abbreviations / initials / decimals like "e.g." or "Dr."
    if (/(?:\b[A-Z]|\b(?:e\.g|i\.e|vs|etc|Dr|Mr|Mrs|Ms|Inc|Ltd|No|St))\.$/.test(before) && m[0].startsWith(".") && m[0].length < 3) continue;
    out.push(text.slice(start, m.index + m[0].trimEnd().length).trim());
    start = m.index + m[0].length;
  }
  const rest = text.slice(start).trim();
  if (rest) out.push(rest);
  return out;
}

function sourceSentences(text: string): string[] {
  const out: string[] = [];
  for (const para of stripFences(text).split(/\n+/)) {
    const line = para.replace(/^\s*#+\s+.*$/, "").replace(/^\s*[-*+]\s+/, "");
    for (const s of splitSentences(line)) {
      // Skip headings, nav crumbs, syntax lines and other fragments.
      if (s.length >= 30 && s.split(" ").length >= 5 && !/^[A-Z ]+[{|(]/.test(s)) out.push(s);
    }
  }
  return out;
}

function tokens(s: string): string[] {
  return (s.toLowerCase().match(/[\p{L}\p{N}][\p{L}\p{N}.,'-]*[\p{L}\p{N}]|[\p{L}\p{N}]/gu) ?? [])
    .map((t) => t.replace(/[.,'-]+$/g, "").replace(/,/g, ""))
    .map(stem)
    .filter((t) => t && !STOP.has(t) && (t.length > 1 || /\d/.test(t)));
}

function stem(t: string): string {
  if (/\d/.test(t) || t.length < 5) return t;
  return t.replace(/(ing|edly|ed|es|s|ly)$/, "");
}

/** Strip citation tags and markdown noise, leaving the plain claim text. */
function cleanClaim(s: string): string {
  return s
    .replace(/\{\{icon:[^}]*\}\}\s*/g, "")
    .replace(/\s*\[[KWDGC]\d+\]/g, "")
    .replace(/^\s*\|/, "")
    .replace(/\s*\|\s*/g, " \u2013 ")
    .replace(/\u2013\s*$/, "")
    .replace(/[\u{1F300}-\u{1FAFF}\u2705\u2714\u2B50]\uFE0F?\s*/gu, "")
    .replace(/\*+|__|`/g, "")
    .replace(/^\s*(?:[-*+]|\d+[.)])\s+/, "")
    .replace(/^#+\s+/, "")
    .replace(/\s+([.,;:!?])/g, "$1")
    .trim();
}

function clip(s: string, max: number): string {
  if (s.length <= max) return s;
  const cut = s.slice(0, max - 1);
  const sp = cut.lastIndexOf(" ");
  return (sp > max * 0.6 ? cut.slice(0, sp) : cut).trimEnd() + "…";
}

export type Index = { sents: string[]; toks: Set<string>[]; idf: Map<string, number> };

export function buildIndex(text: string): Index {
  const sents = sourceSentences(text);
  const toks = sents.map((s) => new Set(tokens(s)));
  const df = new Map<string, number>();
  for (const t of toks) for (const w of t) df.set(w, (df.get(w) ?? 0) + 1);
  const n = Math.max(sents.length, 1);
  const idf = new Map<string, number>();
  for (const [w, d] of df) idf.set(w, Math.log(1 + (n - d + 0.5) / (d + 0.5)));
  return { sents, toks, idf };
}

function weight(w: string, idx: Index): number {
  // Unseen-in-source terms get a mid weight; numbers count extra.
  const base = idx.idf.get(w) ?? 1;
  return /\d/.test(w) ? base * 1.8 + 0.5 : base;
}

/** Weighted fraction of claim terms covered by a window of source sentences. */
export function scoreWindow(claimToks: string[], windowToks: Set<string>, idx: Index): number {
  let total = 0;
  let hit = 0;
  for (const w of claimToks) {
    const wt = weight(w, idx);
    total += wt;
    if (windowToks.has(w)) hit += wt;
  }
  return total > 0 ? hit / total : 0;
}

export function bestPassage(claim: string, idx: Index): { quote: string; score: number } | null {
  const ct = [...new Set(tokens(claim))];
  if (ct.length < 2 || idx.sents.length === 0) return null;
  let best = { score: 0, i: 0, len: 1 };
  for (let i = 0; i < idx.sents.length; i++) {
    for (const len of [1, 2]) {
      if (i + len > idx.sents.length) continue;
      const win = new Set<string>();
      for (let k = i; k < i + len; k++) for (const w of idx.toks[k]) win.add(w);
      // Mild penalty for two-sentence windows so tight matches win ties.
      const sc = scoreWindow(ct, win, idx) * (len === 2 ? 0.97 : 1);
      if (sc > best.score) best = { score: sc, i, len };
    }
  }
  if (best.score <= 0) return null;
  let quote = idx.sents.slice(best.i, best.i + best.len).join(" ");
  // A two-sentence window only earns its place if it adds coverage.
  if (best.len === 2) {
    const solo = scoreWindow(ct, idx.toks[best.i], idx);
    const solo2 = scoreWindow(ct, idx.toks[best.i + 1], idx);
    if (Math.max(solo, solo2) >= best.score - 0.08) {
      const k = solo >= solo2 ? best.i : best.i + 1;
      quote = idx.sents[k];
    }
  }
  return { quote: clip(quote, MAX_QUOTE), score: Math.round(Math.min(best.score, 1) * 100) / 100 };
}

export function stripFences(text: string): string {
  return text.replace(/```[\s\S]*?(?:```|$)/g, "\n").replace(/~~~[\s\S]*?(?:~~~|$)/g, "\n");
}

export function computeEvidence(answer: string, sources: EvidenceSource[], minScore = MIN_SCORE): EvidenceItem[] {
  const byId = new Map(sources.map((s) => [s.id, s]));
  const indexes = new Map<string, Index>();
  const out: EvidenceItem[] = [];
  const seen = new Set<string>();
  const sentences = stripFences(answer)
    .split(/\n+/)
    .flatMap((line) => splitSentences(line));
  for (const sentence of sentences) {
    const tags = [...new Set([...sentence.matchAll(/\[([KWDGC]\d+)\]/g)].map((m) => m[1]))];
    if (tags.length === 0) continue;
    const claim = cleanClaim(sentence);
    if (claim.length < 8) continue;
    for (const tag of tags) {
      const src = byId.get(tag);
      if (!src) continue;
      let idx = indexes.get(tag);
      if (!idx) indexes.set(tag, (idx = buildIndex(src.text)));
      const hit = bestPassage(claim, idx);
      if (!hit || hit.score < minScore) continue;
      const key = `${tag}\u0000${claim}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ tag, claim: clip(claim, MAX_CLAIM), quote: hit.quote, score: hit.score });
    }
  }
  return out;
}
