// Pure text helpers for search: normalise, code-aware tokenise, stem, synonym
// expansion and typo-tolerant query building. No I/O.
import { damerau, editSim, trigramSim } from "../github/repoSearch.js";

export { damerau, editSim, trigramSim };

/** NFKC, lowercase, diacritics stripped, whitespace collapsed. */
export function normalize(s: string): string {
  return (s ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Code-aware tokens: splits camelCase, snake_case, kebab-case, dotted paths and
 * letter/digit boundaries after normalising. "getUserByID" -> get user by id.
 */
export function tokenize(s: string): string[] {
  const split = (s ?? "")
    .normalize("NFKC")
    .replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2")
    .replace(/(\p{Lu}+)(\p{Lu}\p{Ll})/gu, "$1 $2")
    .replace(/(\p{L})(\d)/gu, "$1 $2")
    .replace(/(\d)(\p{L})/gu, "$1 $2");
  return normalize(split)
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);
}

// ---- Porter stemmer (English) ----------------------------------------------------------

const isCons = (w: string, i: number): boolean => {
  const c = w[i];
  if ("aeiou".includes(c)) return false;
  if (c === "y") return i === 0 || !isCons(w, i - 1);
  return true;
};
/** Number of VC sequences in the stem. */
function measure(w: string): number {
  let n = 0;
  let i = 0;
  const len = w.length;
  while (i < len && isCons(w, i)) i++;
  while (i < len) {
    while (i < len && !isCons(w, i)) i++;
    if (i >= len) break;
    n++;
    while (i < len && isCons(w, i)) i++;
  }
  return n;
}
const hasVowel = (w: string) => [...w].some((_, i) => !isCons(w, i));
const endsDouble = (w: string) => w.length >= 2 && w[w.length - 1] === w[w.length - 2] && isCons(w, w.length - 1);
function endsCvc(w: string): boolean {
  const n = w.length;
  if (n < 3) return false;
  return isCons(w, n - 1) && !isCons(w, n - 2) && isCons(w, n - 3) && !"wxy".includes(w[n - 1]);
}

function replaceSuffix(w: string, rules: Array<[string, string]>, minM: number): string {
  for (const [suf, rep] of rules) {
    if (w.endsWith(suf)) {
      const stem = w.slice(0, -suf.length);
      return measure(stem) > minM ? stem + rep : w;
    }
  }
  return w;
}

/** Porter (1980) stemmer for lowercase English words. Short or non-alphabetic words pass through. */
export function stem(word: string): string {
  let w = word;
  if (w.length <= 2 || !/^[a-z]+$/.test(w)) return w;
  // 1a
  if (w.endsWith("sses")) w = w.slice(0, -2);
  else if (w.endsWith("ies")) w = w.slice(0, -2);
  else if (w.endsWith("ss")) {
    /* keep */
  } else if (w.endsWith("s")) w = w.slice(0, -1);
  // 1b
  let step1b = false;
  if (w.endsWith("eed")) {
    if (measure(w.slice(0, -3)) > 0) w = w.slice(0, -1);
  } else if (w.endsWith("ed") && hasVowel(w.slice(0, -2))) {
    w = w.slice(0, -2);
    step1b = true;
  } else if (w.endsWith("ing") && hasVowel(w.slice(0, -3))) {
    w = w.slice(0, -3);
    step1b = true;
  }
  if (step1b) {
    if (/(at|bl|iz)$/.test(w)) w += "e";
    else if (endsDouble(w) && !"lsz".includes(w[w.length - 1])) w = w.slice(0, -1);
    else if (measure(w) === 1 && endsCvc(w)) w += "e";
  }
  // 1c
  if (w.endsWith("y") && hasVowel(w.slice(0, -1))) w = w.slice(0, -1) + "i";
  // 2
  w = replaceSuffix(
    w,
    [
      ["ational", "ate"], ["tional", "tion"], ["enci", "ence"], ["anci", "ance"], ["izer", "ize"], ["abli", "able"],
      ["alli", "al"], ["entli", "ent"], ["eli", "e"], ["ousli", "ous"], ["ization", "ize"], ["ation", "ate"],
      ["ator", "ate"], ["alism", "al"], ["iveness", "ive"], ["fulness", "ful"], ["ousness", "ous"], ["aliti", "al"],
      ["iviti", "ive"], ["biliti", "ble"],
    ],
    0,
  );
  // 3
  w = replaceSuffix(w, [["icate", "ic"], ["ative", ""], ["alize", "al"], ["iciti", "ic"], ["ical", "ic"], ["ful", ""], ["ness", ""]], 0);
  // 4
  for (const suf of ["al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment", "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize"]) {
    if (w.endsWith(suf)) {
      const stemmed = w.slice(0, -suf.length);
      if (measure(stemmed) > 1 && (suf !== "ion" || /[st]$/.test(stemmed))) w = stemmed;
      break;
    }
  }
  // 5a / 5b
  if (w.endsWith("e")) {
    const s = w.slice(0, -1);
    const m = measure(s);
    if (m > 1 || (m === 1 && !endsCvc(s))) w = s;
  }
  if (measure(w) > 1 && endsDouble(w) && w.endsWith("l")) w = w.slice(0, -1);
  return w;
}

/** Tokens, stemmed; digits-only and non-ASCII tokens pass through unchanged. */
export function stemTokens(s: string): string[] {
  return tokenize(s).map(stem);
}

// ---- synonyms / abbreviations -----------------------------------------------------------

const SYNONYM_GROUPS: string[][] = [
  ["k8s", "kubernetes"],
  ["js", "javascript"],
  ["ts", "typescript"],
  ["db", "database"],
  ["auth", "authentication", "authorization"],
  ["config", "configuration"],
  ["env", "environment"],
  ["repo", "repository"],
  ["pg", "postgres", "postgresql"],
  ["py", "python"],
  ["app", "application"],
  ["dev", "development"],
  ["prod", "production"],
  ["docs", "documentation"],
  ["impl", "implementation"],
  ["infra", "infrastructure"],
  ["async", "asynchronous"],
  ["regex", "regexp"],
  ["ml", "machine learning"],
  ["msg", "message"],
  ["param", "parameter"],
  ["dep", "dependency"],
  ["deps", "dependencies"],
];

const SYNONYMS = new Map<string, string[]>();
for (const g of SYNONYM_GROUPS) for (const t of g) SYNONYMS.set(t, g.filter((x) => x !== t));

/** Alternative spellings for a single term (empty when none). */
export function synonymsOf(term: string): string[] {
  return SYNONYMS.get(normalize(term)) ?? [];
}

/** Query terms (normalised, unique) plus their synonyms, capped. */
export function expandQuery(q: string, max = 24): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (t: string) => {
    if (t && !seen.has(t)) {
      seen.add(t);
      out.push(t);
    }
  };
  for (const t of normalize(q)
    .split(/[^\p{L}\p{N}+#.]+/u)
    .map((x) => x.replace(/^\.+|\.+$/g, ""))) {
    add(t);
    for (const s of synonymsOf(t)) add(s);
  }
  return out.slice(0, max);
}

// ---- Postgres query builders ------------------------------------------------------------

/**
 * Text for websearch_to_tsquery('english', ...): OR-joined words plus synonyms.
 * Stemming itself is done by the 'english' config, so words are passed as typed.
 */
export function tsQueryText(q: string, maxTerms = 14): string {
  const all = expandQuery(q, maxTerms * 2).filter((t) => t.length >= 2);
  const single = all.filter((t) => !/\s/.test(t));
  const multi = all.filter((t) => /\s/.test(t)).map((t) => `"${t}"`);
  return [...single, ...multi].slice(0, maxTerms).join(" or ");
}

/** Minimum word length for which a trigram typo fallback is meaningful. */
export const MIN_FUZZY_LEN = 4;

/** Words worth running a trigram comparison on (long enough, not pure digits). */
export function fuzzyTerms(q: string, max = 4): string[] {
  return [...new Set(tokenize(q).filter((t) => t.length >= MIN_FUZZY_LEN && !/^\d+$/.test(t)))].slice(0, max);
}

/** The typo fallback runs when full-text search returned fewer rows than this. */
export const FEW_HITS = 3;
export const needsFuzzy = (hits: number) => hits < FEW_HITS;

/** Escapes LIKE/ILIKE wildcards. */
export const escapeLike = (s: string) => s.replace(/[\\%_]/g, "\\$&");

/**
 * Client-side fuzzy match: does [haystack] contain every query token, allowing
 * typos (Damerau), stems and synonyms? Returns a 0..1 score, 0 for no match.
 */
export function fuzzyScore(query: string, haystack: string): number {
  const words = (query ?? "").normalize("NFKC").split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const hs = tokenize(haystack);
  if (!words.length || !hs.length) return 0;
  const hStem = hs.map(stem);
  // Best match of one token among the haystack tokens (0 = none).
  const tokenScore = (a: string): number => {
    const as = stem(a);
    let best = 0;
    for (let i = 0; i < hs.length; i++) {
      if (hs[i] === a) return 1;
      if (hStem[i] === as) best = Math.max(best, 0.9);
      else if (a.length >= 4 && hs[i].length >= 4) {
        const d = damerau(a, hs[i]);
        if (d <= (a.length <= 5 ? 1 : 2)) best = Math.max(best, 0.8 - 0.1 * d);
      }
    }
    return best;
  };
  // A query word matches through itself or a synonym; all of its code-aware tokens must be present.
  const wordScore = (w: string): number => {
    let best = 0;
    for (const alt of [w, ...synonymsOf(w)]) {
      const ts = tokenize(alt);
      const scores = ts.map(tokenScore);
      if (ts.length && scores.every((x) => x > 0)) best = Math.max(best, scores.reduce((x, y) => x + y, 0) / ts.length);
    }
    return best;
  };
  let total = 0;
  for (const w of words) {
    const sc = wordScore(w);
    if (sc === 0) return 0;
    total += sc;
  }
  return total / words.length;
}

/** A short excerpt of [text] around the first query-term match (null when no term occurs). */
export function snippetAround(text: string, q: string, width = 120): { snippet: string; start: number; length: number } | null {
  const flat = text.replace(/\s+/g, " ");
  const lower = flat.toLowerCase();
  let at = -1;
  let len = 0;
  for (const t of expandQuery(q).filter((x) => x.length >= 2)) {
    const i = lower.indexOf(t);
    if (i >= 0 && (at < 0 || i < at)) {
      at = i;
      len = t.length;
    }
  }
  if (at < 0) {
    // Typo / stem fallback: first word that fuzzily matches any query token.
    const qTokens = tokenize(q);
    for (const m of flat.matchAll(/[\p{L}\p{N}_]+/gu)) {
      if (m[0].length >= 3 && qTokens.some((t) => fuzzyScore(t, m[0]) > 0)) {
        at = m.index!;
        len = m[0].length;
        break;
      }
    }
    if (at < 0) return null;
  }
  const from = Math.max(0, at - Math.floor((width - len) / 2));
  const to = Math.min(flat.length, from + width);
  const prefix = from > 0 ? "…" : "";
  const suffix = to < flat.length ? "…" : "";
  return { snippet: prefix + flat.slice(from, to) + suffix, start: prefix.length + (at - from), length: len };
}
