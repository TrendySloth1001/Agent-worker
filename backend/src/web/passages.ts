// Query-focused passage extraction: split a page into paragraph-sized
// passages, rank them with BM25 and keep the best ones (in reading order)
// instead of dumping the head of the page. Pure CPU, no model calls.

const STOP = new Set(
  "a an the and or but if then of to in on at by for with from as is are was were be been it its this that these those not no do does did has have had will would can could should may might about into than so such there their them his her our your also which who what when where how why i you we they he she me my us vs versus latest new best".split(
    " ",
  ),
);

/** Light suffix stripping so "computer", "computing" and "computation" meet; short words and numbers are kept as they are. */
export function stem(t: string): string {
  if (/\d/.test(t) || t.length < 5 || !/^[a-z]/.test(t)) return t;
  const r = t.replace(/(ations?|ions?|ings?|ers?|edly|ed|es|s|ly)$/, "");
  if (r.length < 4) return t;
  return r.replace(/e$/, "");
}

export function terms(s: string): string[] {
  return (s.toLowerCase().match(/[\p{L}\p{N}][\p{L}\p{N}.+#_-]*[\p{L}\p{N}+#]|[\p{L}\p{N}]/gu) ?? [])
    .map(stem)
    .filter((t) => t && !STOP.has(t) && (t.length > 1 || /\d/.test(t)));
}

const MIN_PASSAGE = 60;

/** Paragraph-ish passages: blank-line blocks, headings glued to what follows, long blocks cut on sentence ends. */
export function splitPassages(text: string, maxLen = 700): string[] {
  const blocks = text
    .replace(/\r/g, "")
    .split(/\n{2,}/)
    .map((b) => b.replace(/[ \t]+/g, " ").trim())
    .filter(Boolean);
  const out: string[] = [];
  let heading = "";
  for (let b of blocks) {
    if (/^#{1,6}\s/.test(b) && !b.includes("\n")) {
      heading = b.replace(/^#+\s*/, "");
      continue;
    }
    if (isNoise(b)) continue;
    b = stripMarkup(b);
    if (b.length < 3) continue;
    const pieces: string[] = [];
    if (b.length <= maxLen) pieces.push(b);
    else {
      let cur = "";
      for (const s of b.split(/(?<=[.!?])\s+(?=[A-Z0-9"'(\[])|\n(?=[-*\d])/)) {
        if (cur && cur.length + s.length + 1 > maxLen) {
          pieces.push(cur);
          cur = "";
        }
        cur = cur ? `${cur} ${s}` : s;
        while (cur.length > maxLen * 1.5) {
          pieces.push(cur.slice(0, maxLen));
          cur = cur.slice(maxLen);
        }
      }
      if (cur) pieces.push(cur);
    }
    for (const p of pieces) {
      if (p.length < MIN_PASSAGE && !/\d/.test(p)) continue;
      out.push(heading && !p.startsWith("```") ? `${heading}: ${p}` : p);
    }
  }
  return out;
}

/** Navigation crumbs, link lists, cookie banners and similar boilerplate. */
function isNoise(b: string): boolean {
  if (/^(\[[^\]]*\]\([^)]*\)\s*[|·•\-*]?\s*){3,}$/.test(b)) return true; // row of links
  const linkChars = [...b.matchAll(/\]\([^)]*\)/g)].reduce((n, m) => n + m[0].length, 0);
  if (b.length > 0 && linkChars / b.length > 0.5) return true;
  if (/\b(cookies?|privacy policy|subscribe to our newsletter|all rights reserved|sign up for)\b/i.test(b) && b.length < 220) return true;
  if (b.length < 90 && BOILERPLATE.test(b.replace(/[[\]*_#>]/g, "").trim())) return true;
  // A menu: several short lines without sentence punctuation.
  if (!b.startsWith("```")) {
    const lines = b.split("\n").map((l) => l.trim()).filter(Boolean);
    if (lines.length >= 4 && lines.reduce((n, l) => n + l.length, 0) / lines.length < 28 && !lines.some((l) => /[.!?:;]\s*$/.test(l) || /\d/.test(l))) return true;
  }
  return false;
}

const BOILERPLATE = /^(skip to (main )?content|share( this( article| post)?)?|advertisement|sponsored|read more|continue reading|sign in|log ?in|sign up|subscribe|follow us|related (posts|articles|stories)|table of contents|contents|menu|search|loading\.*|back to top|print|email|tweet|copy link|image( credit| source)?:.*|photo:.*|getty images|you may also like|recommended( for you)?|most popular|trending)\b/i;

/** Markdown to plain prose: images dropped, links reduced to their text, emphasis markers removed. */
export function stripMarkup(b: string): string {
  if (b.startsWith("```")) return b;
  return b
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]*)\]\((?:[^()]|\([^)]*\))*\)/g, "$1")
    .replace(/(\*\*|__)(.+?)\1/g, "$2")
    .replace(/[ \t]+/g, " ")
    .trim();
}

export type ScoredPassage = { text: string; score: number; index: number };

/** BM25 over the passages for a set of query terms (already tokenised). */
export function rankPassages(passages: string[], queryTerms: string[], opts: { k1?: number; b?: number } = {}): ScoredPassage[] {
  const k1 = opts.k1 ?? 1.2;
  const b = opts.b ?? 0.75;
  const q = [...new Set(queryTerms)];
  if (!passages.length || !q.length) return passages.map((text, index) => ({ text, score: 0, index }));
  const docs = passages.map((p) => terms(p));
  const n = docs.length;
  const avg = docs.reduce((s, d) => s + d.length, 0) / n || 1;
  const df = new Map<string, number>();
  for (const d of docs) for (const w of new Set(d)) df.set(w, (df.get(w) ?? 0) + 1);
  return docs.map((d, index) => {
    const tf = new Map<string, number>();
    for (const w of d) tf.set(w, (tf.get(w) ?? 0) + 1);
    let score = 0;
    for (const w of q) {
      const f = tf.get(w);
      if (!f) continue;
      const idf = Math.log(1 + (n - (df.get(w) ?? 0) + 0.5) / ((df.get(w) ?? 0) + 0.5));
      score += idf * ((f * (k1 + 1)) / (f + k1 * (1 - b + (b * d.length) / avg)));
    }
    // Numbers in a passage are often the fact being asked for.
    if (score > 0 && /\d/.test(passages[index])) score *= 1.05;
    return { text: passages[index], score, index };
  });
}

export type SelectOpts = { maxChars?: number; maxPassages?: number; passageLen?: number };

/**
 * The passages of [text] most relevant to [query], joined in reading order.
 * Falls back to the head of the page when nothing matches the query.
 */
export function selectPassages(text: string, query: string, opts: SelectOpts = {}): string {
  const maxChars = opts.maxChars ?? 1500;
  const maxPassages = opts.maxPassages ?? 4;
  const passages = splitPassages(text, opts.passageLen ?? 600);
  if (!passages.length) return text.replace(/\s+/g, " ").trim().slice(0, maxChars);
  const ranked = rankPassages(passages, terms(query));
  const useful = ranked.filter((p) => p.score > 0).sort((a, b) => b.score - a.score || a.index - b.index);
  // Nothing matched: the opening passages are the best guess.
  const pool = useful.length ? useful : ranked.slice(0, maxPassages);
  const picked: ScoredPassage[] = [];
  let used = 0;
  for (const p of pool) {
    if (picked.length >= maxPassages) break;
    const room = maxChars - used;
    if (room < 80) break;
    const t = p.text.length > room ? p.text.slice(0, room) : p.text;
    picked.push({ ...p, text: t });
    used += t.length + 1;
  }
  return picked
    .sort((a, b) => a.index - b.index)
    .map((p) => p.text)
    .join("\n");
}
