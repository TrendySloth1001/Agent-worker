/**
 * Fuzzy ranking of repositories (and branch names) against loose user text:
 * "my keepit repo", "reprot card", "eysium report", "report-card-generator".
 *
 * Names are normalised into tokens (camelCase, kebab, snake, dots, digits)
 * and scored by the best of: exact name / full_name, prefix, token coverage
 * (with typo-tolerant token matches), substring, character-trigram Jaccard and
 * Damerau-Levenshtein similarity of the joined name. Small boosts for an owner
 * match, description/topic hits, recency and stars break ties. Scores are
 * roughly 0..1.2; under [CONFIDENT] the caller should ask instead of guessing.
 */

export type RankableRepo = {
  fullName: string;
  owner: string;
  name: string;
  description?: string | null;
  topics?: string[];
  pushedAt?: string | null;
  stars?: number;
  fork?: boolean;
  archived?: boolean;
};

export type Ranked<T> = { repo: T; score: number; matched: string[] };

/** A top score at or above this is a confident match. */
export const CONFIDENT = 0.62;
/** Results under this are noise. */
export const MIN_SCORE = 0.35;

/** Words people wrap around a repo name ("my keepit repo on github"). */
const FILLER = new Set(
  "my mine our the a an this that repo repos repository repositories project projects codebase code app github gh called named on in of for please show open find look at".split(
    " ",
  ),
);

/** Lowercase tokens: camelCase, kebab, snake, dots, slashes and letter/digit boundaries split. */
export function tokens(s: string): string[] {
  return (s ?? "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
    .replace(/([a-zA-Z])(\d)/g, "$1 $2")
    .replace(/(\d)([a-zA-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

/** Query tokens without filler words (kept when nothing else is left). */
export function queryTokens(q: string): string[] {
  const all = tokens(q);
  const kept = all.filter((t) => !FILLER.has(t));
  return kept.length ? kept : all;
}

function trigrams(s: string): Set<string> {
  const p = `  ${s} `;
  const out = new Set<string>();
  for (let i = 0; i + 3 <= p.length; i++) out.add(p.slice(i, i + 3));
  return out;
}

/** Jaccard similarity of character trigrams (0..1). */
export function trigramSim(a: string, b: string): number {
  if (!a || !b) return 0;
  const x = trigrams(a);
  const y = trigrams(b);
  let inter = 0;
  for (const t of x) if (y.has(t)) inter++;
  return inter / (x.size + y.size - inter);
}

/** Optimal string alignment distance (Damerau-Levenshtein with adjacent transpositions). */
export function damerau(a: string, b: string): number {
  const n = a.length;
  const m = b.length;
  if (!n) return m;
  if (!m) return n;
  const d: number[][] = Array.from({ length: n + 1 }, (_, i) => {
    const row = new Array<number>(m + 1).fill(0);
    row[0] = i;
    return row;
  });
  for (let j = 0; j <= m; j++) d[0][j] = j;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  }
  return d[n][m];
}

/** 1 - distance / longer length (0..1). */
export function editSim(a: string, b: string): number {
  const len = Math.max(a.length, b.length);
  return len ? 1 - damerau(a, b) / len : 1;
}

/** Typos allowed for a token of [len] characters. */
const allowedTypos = (len: number) => (len <= 3 ? 0 : len <= 5 ? 1 : len <= 9 ? 2 : 3);

/** How well query token [q] matches name token [t] (0..1). */
export function tokenMatch(q: string, t: string): number {
  if (q === t) return 1;
  if (q.length >= 2 && t.startsWith(q)) return 0.8 + 0.15 * (q.length / t.length);
  if (t.length >= 3 && q.startsWith(t)) return 0.7 * (t.length / q.length);
  const d = damerau(q, t);
  if (d <= allowedTypos(Math.min(q.length, t.length))) return 0.85 * (1 - d / Math.max(q.length, t.length)) + 0.1;
  return 0;
}

type NameScore = { score: number; matched: string[] };

/** Match of query tokens [q] against a name (0..1), with the query tokens that hit. */
export function nameScore(q: string[], name: string): NameScore {
  const nt = tokens(name);
  const qc = q.join("");
  const nc = nt.join("");
  if (!qc || !nc) return { score: 0, matched: [] };
  if (qc === nc) return { score: 1.1, matched: [...q] };

  // Token coverage: every query token's best match among the name tokens.
  const matched: string[] = [];
  const used = new Set<number>();
  let sum = 0;
  let all = true;
  for (const qt of q) {
    let best = 0;
    let at = -1;
    nt.forEach((t, i) => {
      const v = tokenMatch(qt, t) - (used.has(i) ? 0.05 : 0);
      if (v > best) [best, at] = [v, i];
    });
    if (best > 0) {
      matched.push(qt);
      used.add(at);
    } else all = false;
    sum += best;
  }
  const covered = used.size / nt.length;
  let coverage = (sum / q.length) * (0.85 + 0.15 * covered);
  if (!all) coverage *= 0.6;

  const prefix = nc.startsWith(qc) ? 0.75 + 0.15 * (qc.length / nc.length) : 0;
  const substring = qc.length >= 3 && nc.includes(qc) ? 0.6 + 0.15 * (qc.length / nc.length) : 0;
  const tri = trigramSim(qc, nc);
  const edit = editSim(qc, nc);
  const fuzzy = Math.max(0.9 * tri, edit >= 0.6 ? 0.88 * edit : 0);
  const score = Math.max(coverage, prefix, substring, fuzzy) + 0.04 * tri;
  return { score: Math.min(0.99, score), matched: matched.length ? matched : prefix || substring || fuzzy > 0.5 ? [...q] : [] };
}

/** Query tokens found (exactly or as a prefix) in [text]'s tokens. */
function textHits(q: string[], text: string): string[] {
  const tt = new Set(tokens(text));
  if (!tt.size) return [];
  return q.filter((x) => tt.has(x) || (x.length >= 4 && [...tt].some((t) => t.startsWith(x) || tokenMatch(x, t) >= 0.75)));
}

export type ScoreOptions = { now?: number };

/** Score of [repo] for the raw query text [query]. */
export function scoreRepo(query: string, repo: RankableRepo, opts: ScoreOptions = {}): { score: number; matched: string[] } {
  const raw = query.trim().toLowerCase();
  const now = opts.now ?? Date.now();
  if (!raw) return { score: 0, matched: [] };
  const full = repo.fullName.toLowerCase();
  if (raw === full || raw === `github.com/${full}`) return { score: 1.2, matched: tokens(repo.fullName) };

  // "owner/name" typed out: score both parts.
  let q = queryTokens(raw);
  let ownerHit = false;
  const slash = raw.match(/^([\w.-]+)\/([\w.-]+)$/);
  if (slash) {
    ownerHit = editSim(slash[1], repo.owner.toLowerCase()) >= 0.8;
    q = queryTokens(slash[2]);
  }
  let best = nameScore(q, repo.name);
  // A query token naming the owner ("eysium report"): try it as the owner.
  if (!slash && q.length > 1) {
    const ownerTokens = tokens(repo.owner);
    const oc = ownerTokens.join("");
    for (let i = 0; i < q.length; i++) {
      const t = q[i];
      if (t === oc || (t.length >= 4 && editSim(t, oc) >= 0.8) || ownerTokens.includes(t)) {
        const rest = q.filter((_, j) => j !== i);
        const s = nameScore(rest, repo.name);
        if (s.score + 0.15 > best.score + (ownerHit ? 0.15 : 0)) {
          best = { score: s.score, matched: [...s.matched, t] };
          ownerHit = true;
        }
        break;
      }
    }
  }
  let score = best.score + (ownerHit ? 0.15 : 0);

  // Description and topics: a weak signal alone, a tie-breaker otherwise.
  const extra = `${repo.description ?? ""} ${(repo.topics ?? []).join(" ")}`;
  const hits = textHits(q, extra);
  if (hits.length) {
    const frac = hits.length / q.length;
    score = Math.max(score, 0.55 * frac) + 0.06 * frac;
  }

  // Recency and popularity: small tie-breakers.
  const pushed = repo.pushedAt ? Date.parse(repo.pushedAt) : NaN;
  if (Number.isFinite(pushed)) score += 0.04 * Math.exp(-Math.max(0, now - pushed) / (180 * 86_400_000));
  if (repo.stars) score += 0.02 * Math.min(1, Math.log10(repo.stars + 1) / 4);
  if (repo.archived) score -= 0.03;
  if (repo.fork) score -= 0.02;
  return { score: Math.round(score * 1000) / 1000, matched: [...new Set([...best.matched, ...hits])] };
}

export type RankResult<T> = {
  items: Ranked<T>[];
  /** The top result is a confident, unambiguous match. */
  confident: boolean;
};

/** Ranks [repos] for [query], best first, dropping noise. */
export function rankRepos<T extends RankableRepo>(query: string, repos: T[], opts: ScoreOptions & { limit?: number; min?: number } = {}): RankResult<T> {
  const min = opts.min ?? MIN_SCORE;
  const items = repos
    .map((repo) => ({ repo, ...scoreRepo(query, repo, opts) }))
    .filter((r) => r.score >= min)
    .sort((a, b) => b.score - a.score || a.repo.fullName.localeCompare(b.repo.fullName))
    .slice(0, opts.limit ?? 20);
  const [top, second] = items;
  const confident = !!top && top.score >= CONFIDENT && (!second || top.score >= 1.2 || top.score - second.score >= 0.05);
  return { items, confident };
}

/** Ranks plain names (branches) for [query]; best first. */
export function rankNames<T>(query: string, list: T[], name: (t: T) => string, min = 0.4): { item: T; score: number }[] {
  const q = queryTokens(query);
  const raw = query.trim().toLowerCase();
  return list
    .map((item) => {
      const n = name(item).toLowerCase();
      const s = n === raw ? 1.1 : n.includes(raw) ? Math.max(0.8, nameScore(q, n).score) : nameScore(q, n).score;
      return { item, score: s };
    })
    .filter((x) => x.score >= min)
    .sort((a, b) => b.score - a.score);
}

// ---- public search: query building and typo repair --------------------------

const LANGS: Record<string, string> = {
  rust: "rust", go: "go", golang: "go", python: "python", typescript: "typescript", javascript: "javascript",
  java: "java", kotlin: "kotlin", swift: "swift", dart: "dart", flutter: "dart", ruby: "ruby", php: "php",
  elixir: "elixir", haskell: "haskell", scala: "scala", zig: "zig", cpp: "c++", csharp: "c#", lua: "lua",
  julia: "julia", clojure: "clojure", ocaml: "ocaml", erlang: "erlang", perl: "perl", r: "r", nim: "nim",
};

const TOPICS = new Set(
  "machine-learning deep-learning llm ai cli database vector-database react vue svelte nextjs kubernetes docker devops security game-engine compiler blockchain web3 nlp computer-vision rag agents chatbot".split(
    " ",
  ),
);

/** Common words in repository names and descriptions, for repairing typos in search text. */
const VOCAB = (
  "vector database databases search engine framework library server client parser compiler interpreter runtime " +
  "container kubernetes docker orchestration monitoring logging testing authentication encryption blockchain game " +
  "image video audio processing scraper crawler bot chat notification payment analytics dashboard visualization " +
  "chart markdown static site generator template component animation mobile android desktop emulator sql nosql " +
  "orm migration schema validation serialization json yaml config state management reactive async concurrency " +
  "parallel distributed consensus similarity index nearest neighbor retrieval agent workflow pipeline scheduler " +
  "proxy balancer gateway firewall security scanner linter formatter bundler package manager build deploy serverless " +
  "toolkit wrapper plugin extension theme font icon calendar note editor wiki blog forum ecommerce cms report card " +
  "inventory invoice finance trading crypto wallet weather map geospatial location recommendation classification " +
  "detection segmentation translation speech recognition synthesis diffusion transformer tokenizer inference training " +
  "dataset benchmark quantization compression rendering shader physics simulation robotics embedded firmware kernel " +
  "driver filesystem network protocol websocket graphql microservice monorepo starter boilerplate awesome tutorial " +
  "algorithm structure realtime collaborative offline backup storage upload download email password session token " +
  "permission terminal embedding embeddings language model models neural learning machine deep graph cache queue " +
  "stream router http api tracker converter downloader portfolio resume worker service platform engine assistant"
).split(/\s+/);

/** Repairs likely typos against [VOCAB] ("vectr databse" -> "vector database"); null when nothing changed. */
export function repairTypos(text: string): string | null {
  let changed = false;
  const out = text.split(/\s+/).map((w) => {
    const low = w.toLowerCase();
    if (low.length < 4 || /[:/]/.test(low) || VOCAB.includes(low)) return w;
    let best: string | null = null;
    let bestD = Infinity;
    for (const v of VOCAB) {
      if (Math.abs(v.length - low.length) > 2) continue;
      const d = damerau(low, v);
      if (d < bestD) [best, bestD] = [v, d];
    }
    // Conservative: same first letter, one typo (two for long words).
    if (best && bestD > 0 && best[0] === low[0] && bestD <= (low.length >= 8 ? 2 : 1)) {
      changed = true;
      return best;
    }
    return w;
  });
  return changed ? out.join(" ") : null;
}

export type PublicQuery = {
  /** Plain search words. */
  terms: string[];
  language: string | null;
  owner: string | null;
  topic: string | null;
  /** The user's own GitHub qualifiers, kept verbatim. */
  qualifiers: string[];
};

/** Splits user text into words and GitHub qualifiers (language:, user:, topic:). */
export function parsePublicQuery(text: string): PublicQuery {
  const out: PublicQuery = { terms: [], language: null, owner: null, topic: null, qualifiers: [] };
  const words = text.trim().split(/\s+/).filter(Boolean);
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    const low = w.toLowerCase();
    if (/^[a-z-]+:\S+$/i.test(w)) {
      out.qualifiers.push(w);
      continue;
    }
    if ((low === "by" || low === "from") && words[i + 1] && /^[\w-]{1,39}$/.test(words[i + 1])) {
      out.owner = words[++i];
      continue;
    }
    const ownerSlash = w.match(/^([\w-]{1,39})\/$/);
    if (ownerSlash) {
      out.owner = ownerSlash[1];
      continue;
    }
    if (LANGS[low] && !out.language) {
      out.language = LANGS[low];
      continue;
    }
    out.terms.push(w);
  }
  const joined = out.terms.map((t) => t.toLowerCase()).join("-");
  if (TOPICS.has(joined)) out.topic = joined;
  return out;
}

/**
 * Search strings to try, in order: qualified (in:name,description,readme +
 * language/user), plain words, then the typo-repaired variant.
 */
export function publicAttempts(text: string): string[] {
  const p = parsePublicQuery(text);
  const owner = p.owner ? [`user:${p.owner}`] : [];
  const lang = p.language ? [`language:${p.language}`] : [];
  const words = p.terms.join(" ");
  const attempts: string[] = [];
  const add = (parts: string[]) => {
    const s = parts.filter(Boolean).join(" ").trim();
    if (s && !attempts.includes(s)) attempts.push(s);
  };
  if (p.qualifiers.length) add([words, ...p.qualifiers, ...owner, ...lang]);
  add([words, words ? "in:name,description,readme" : "", ...owner, ...lang]);
  add([words, ...owner]);
  const fixed = repairTypos(words);
  if (fixed) {
    add([fixed, "in:name,description,readme", ...owner, ...lang]);
    add([fixed, ...owner]);
  }
  if (p.topic) add([`topic:${p.topic}`, ...owner, ...lang]);
  return attempts;
}
