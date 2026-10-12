// URL normalisation, dedupe and domain authority for search results.

const TRACKING = /^(utm_\w+|fbclid|gclid|dclid|msclkid|mc_cid|mc_eid|igshid|ref|ref_src|ref_url|spm|cmpid|_ga|_gl|yclid|s_cid)$/i;

/** Canonical form used as the identity of a page: https, no www/mobile/amp, no tracking params or fragment. */
export function normalizeUrl(raw: string): string | null {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  const host = u.hostname.toLowerCase().replace(/^(www\d?|m|mobile|amp)\./, "");
  let path = u.pathname.replace(/\/{2,}/g, "/");
  // arXiv: abs/pdf and versions are the same paper.
  if (host === "arxiv.org") {
    const m = path.match(/^\/(?:abs|pdf)\/(.+?)(?:v\d+)?(?:\.pdf)?$/);
    if (m) path = `/abs/${m[1]}`;
  }
  path = path.replace(/\/(amp|index\.html?)$/i, "").replace(/\/+$/, "");
  const params = [...u.searchParams.entries()].filter(([k]) => !TRACKING.test(k)).sort(([a], [b]) => a.localeCompare(b));
  const qs = params.length ? "?" + params.map(([k, v]) => `${k}=${v}`).join("&") : "";
  const port = u.port && !((u.protocol === "https:" && u.port === "443") || (u.protocol === "http:" && u.port === "80")) ? `:${u.port}` : "";
  return `https://${host}${port}${path}${qs}`;
}

export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** Registrable-ish domain (last two labels, three for co.uk style) for diversity limits. */
export function baseDomain(url: string): string {
  const h = hostOf(url);
  const p = h.split(".");
  if (p.length <= 2) return h;
  const sld = p[p.length - 2];
  return p[p.length - 1].length === 2 && ["co", "com", "org", "gov", "ac", "net"].includes(sld) ? p.slice(-3).join(".") : p.slice(-2).join(".");
}

export type WithUrl = { url: string };

/** Drops later duplicates (by normalised URL), keeping the first; `merge` may fold the loser into the keeper. */
export function dedupeByUrl<T extends WithUrl>(items: T[], merge?: (keep: T, drop: T) => void): T[] {
  const seen = new Map<string, T>();
  const out: T[] = [];
  for (const it of items) {
    const k = normalizeUrl(it.url) ?? it.url;
    const prev = seen.get(k);
    if (prev) {
      merge?.(prev, it);
      continue;
    }
    seen.set(k, it);
    out.push(it);
  }
  return out;
}

const HIGH =
  /(^|\.)(wikipedia\.org|github\.com|arxiv\.org|nature\.com|science\.org|ieee\.org|acm\.org|nih\.gov|who\.int|mozilla\.org|python\.org|nodejs\.org|rust-lang\.org|kernel\.org|w3\.org|ietf\.org|postgresql\.org|stackoverflow\.com|stackexchange\.com|dart\.dev|flutter\.dev|android\.com|microsoft\.com|cloud\.google\.com|aws\.amazon\.com|reuters\.com|apnews\.com|bbc\.com|bbc\.co\.uk|nytimes\.com|theguardian\.com|bloomberg\.com|ft\.com|wsj\.com)$/i;
const MID =
  /(^|\.)(medium\.com|dev\.to|substack\.com|ycombinator\.com|reddit\.com|techcrunch\.com|theverge\.com|arstechnica\.com|wired\.com|hackernoon\.com|freecodecamp\.org|baeldung\.com|geeksforgeeks\.org)$/i;
const LOW =
  /(^|\.)(pinterest\.[a-z.]+|quora\.com|facebook\.com|instagram\.com|tiktok\.com|twitter\.com|x\.com|linkedin\.com|slideshare\.net|scribd\.com|answers\.com|ehow\.com|w3schools\.com)$/i;

/** Source authority in [0,1]: official/reference sites high, social and content farms low. */
export function authority(url: string): number {
  const h = hostOf(url);
  if (!h) return 0.3;
  if (LOW.test(h)) return 0.1;
  if (HIGH.test(h) || /^docs\./.test(h) || /\.(gov|edu)(\.[a-z]{2})?$/.test(h) || /\.ac\.[a-z]{2}$/.test(h)) return 0.9;
  if (MID.test(h)) return 0.55;
  return 0.4;
}
