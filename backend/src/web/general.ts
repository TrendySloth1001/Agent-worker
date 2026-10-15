// General web search that needs no paid key: DuckDuckGo's HTML and lite
// endpoints (and Bing News RSS for news), plus Brave's API when a (free tier)
// key is configured. They keep sparky able to search the open web while the
// Ollama web search quota is used up. The parsers are pure and exported for
// tests; requests go through the provider runner (breaker, cache, timeouts).

import { htmlToText } from "./html.js";
import type { Candidate, Freshness } from "./types.js";

const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n) : s);

/** Browser-ish UA for the RSS endpoints (Bing serves RSS to anyone). */
export const BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0";
/** DuckDuckGo's HTML endpoint challenges browser UAs from server IPs but serves text browsers. */
export const TEXT_BROWSER_UA = "Lynx/2.9.0 libwww-FM/2.14 SSL-MM/1.4.1";

const tag = (xml: string, t: string): string => {
  const m = xml.match(new RegExp(`<${t}(?:\\s[^>]*)?>([\\s\\S]*?)</${t}>`, "i"));
  if (!m) return "";
  return m[1].replace(/^<!\[CDATA\[([\s\S]*?)\]\]>$/, "$1");
};

const isoDate = (s: string): string | undefined => {
  const t = Date.parse(s);
  return Number.isFinite(t) ? new Date(t).toISOString().slice(0, 10) : undefined;
};

/** Real target of a redirecting result link (Bing News apiclick, DuckDuckGo /l/?uddg=). */
export function unwrapRedirect(raw: string): string {
  let href = htmlToText(raw).trim();
  if (href.startsWith("//")) href = `https:${href}`;
  try {
    const u = new URL(href);
    const host = u.hostname.replace(/^www\./, "");
    if (host === "bing.com" && /apiclick/i.test(u.pathname)) return u.searchParams.get("url") ?? href;
    if (host.endsWith("duckduckgo.com") && u.pathname === "/l/") return u.searchParams.get("uddg") ?? href;
    return u.toString();
  } catch {
    return href;
  }
}

/** Items of a Bing (web or news) RSS response. */
export function parseBingRss(xml: string, source: string): Candidate[] {
  const out: Candidate[] = [];
  for (const m of xml.matchAll(/<item>([\s\S]*?)<\/item>/gi)) {
    const it = m[1];
    const url = unwrapRedirect(tag(it, "link"));
    if (!/^https?:\/\//i.test(url) || /(^|\.)bing\.com\//i.test(url.replace(/^https?:\/\//, ""))) continue;
    const title = htmlToText(tag(it, "title"));
    const snippet = htmlToText(tag(it, "description"));
    if (!title) continue;
    out.push({ title: clip(title, 200), url, snippet: clip(snippet, 400), source, rank: out.length, published: source === "bingnews" ? isoDate(tag(it, "pubDate")) : undefined });
  }
  return out;
}

/** Organic results of DuckDuckGo's HTML page (ads skipped). */
export function parseDuckDuckGo(html: string): Candidate[] {
  const out: Candidate[] = [];
  // Every result is a div.result; ads carry result--ad.
  const blocks = html.split(/<div[^>]+class="[^"]*\bresult\b(?![-_])[^"]*"/i).slice(1);
  for (const b of blocks) {
    const head = b.slice(0, 200);
    if (/result--ad|badge--ad/i.test(head) || /result--ad/i.test(b.slice(0, 400))) continue;
    const a = b.match(/<a[^>]+class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i) ?? b.match(/<a[^>]+href="([^"]+)"[^>]*class="[^"]*result__a[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
    if (!a) continue;
    const url = unwrapRedirect(a[1]);
    if (!/^https?:\/\//i.test(url) || /duckduckgo\.com\/y\.js/i.test(url)) continue;
    const sn = b.match(/class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/(?:a|td|div)>/i);
    const title = htmlToText(a[2]);
    if (!title) continue;
    out.push({ title: clip(title, 200), url, snippet: clip(htmlToText(sn?.[1] ?? ""), 400), source: "duckduckgo", rank: out.length });
  }
  return out;
}

/** Organic results of DuckDuckGo's lite page (a table: link row, then snippet row). */
export function parseDuckDuckGoLite(html: string): Candidate[] {
  const out: Candidate[] = [];
  const re = /<a[^>]+href="([^"]+)"[^>]*class=['"]result-link['"][^>]*>([\s\S]*?)<\/a>|<td[^>]*class=['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>/gi;
  let cur: Candidate | null = null;
  for (const m of html.matchAll(re)) {
    if (m[1]) {
      if (cur) out.push(cur);
      cur = null;
      const url = unwrapRedirect(m[1]);
      const title = htmlToText(m[2]);
      if (!/^https?:\/\//i.test(url) || /duckduckgo\.com\/y\.js/i.test(url) || !title) continue;
      cur = { title: clip(title, 200), url, snippet: "", source: "duckduckgo", rank: out.length };
    } else if (cur && m[3]) {
      cur.snippet = clip(htmlToText(m[3]), 400);
    }
  }
  if (cur) out.push(cur);
  return out.map((c, rank) => ({ ...c, rank }));
}

/**
 * DuckDuckGo rejects (403) queries with some punctuation (parentheses, quotes,
 * colons in error messages): keep letters, digits and the symbols that matter
 * in code terms.
 */
export function engineQuery(q: string): string {
  return q
    .replace(/[^\p{L}\p{N}\p{M}\s.+#_\-/@]/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 200);
}

/** Brave web search API results. */
export function parseBrave(data: any): Candidate[] {
  const results: any[] = Array.isArray(data?.web?.results) ? data.web.results : [];
  return results
    .filter((r) => typeof r?.url === "string")
    .map((r, rank): Candidate => {
      const extra = Array.isArray(r.extra_snippets) ? r.extra_snippets.filter((s: unknown) => typeof s === "string").join("\n") : "";
      const snippet = htmlToText(String(r.description ?? ""));
      const text = extra ? `${snippet}\n${htmlToText(extra)}` : undefined;
      return { title: clip(htmlToText(String(r.title ?? r.url)), 200), url: r.url, snippet: clip(snippet, 400), text: text && text.length > 400 ? clip(text, 3000) : undefined, source: "brave", rank, published: typeof r.page_age === "string" ? r.page_age.slice(0, 10) : undefined };
    });
}

/** "4 June 2024 - text" / "3 days ago - text": Brave prefixes snippets with the page date. */
function splitDatePrefix(s: string, now: number): { published?: string; text: string } {
  const m = s.match(/^\s*(\d{1,2} [A-Z][a-z]+ \d{4}|[A-Z][a-z]+ \d{1,2}, \d{4}|\d+ (?:minute|hour|day|week)s? ago)\s+-\s+/);
  if (!m) return { text: s.trim() };
  const rel = m[1].match(/^(\d+) (minute|hour|day|week)s? ago$/);
  const unit = rel ? { minute: 60_000, hour: 3_600_000, day: 86_400_000, week: 7 * 86_400_000 }[rel[2] as "minute"] : 0;
  const t = rel ? now - Number(rel[1]) * unit : Date.parse(`${m[1]} UTC`);
  return { published: Number.isFinite(t) ? new Date(t).toISOString().slice(0, 10) : undefined, text: s.slice(m[0].length).trim() };
}

/**
 * Organic web results of Brave Search's HTML page (no key). Matches on the
 * stable parts of its markup: data-type="web" blocks, the first link, the
 * snippet title and the generic snippet content.
 */
export function parseBraveHtml(html: string, now = Date.now()): Candidate[] {
  const out: Candidate[] = [];
  for (const block of html.split(/data-type="web"/).slice(1)) {
    const b = block.slice(0, 6000);
    const a = b.match(/<a[^>]+href="(https?:\/\/[^"]+)"/);
    if (!a) continue;
    const url = htmlToText(a[1]);
    if (/(^|\.)brave\.com\//.test(url.replace(/^https?:\/\//, ""))) continue;
    const t = b.match(/search-snippet-title[^"]*"(?:\s+title="([^"]*)")?[^>]*>([\s\S]*?)<\/div>/);
    const title = htmlToText(t?.[1] || t?.[2] || "");
    if (!title) continue;
    const c = b.match(/class="content [^"]*"[^>]*>([\s\S]*?)<\/div>/);
    const { published, text } = splitDatePrefix(htmlToText((c?.[1] ?? "").replace(/<!--[\s\S]*?-->/g, "")), now);
    out.push({ title: clip(title, 200), url, snippet: clip(text, 400), source: "brave", rank: out.length, published });
  }
  return out;
}

/** Bing News RSS parameters. */
export function bingParams(query: string, lang?: string, region?: string): URLSearchParams {
  const qs = new URLSearchParams({ q: query, format: "rss" });
  if (lang === "hi") qs.set("setlang", "hi");
  if (region) qs.set("cc", region.toUpperCase());
  return qs;
}

/** DuckDuckGo form fields; df=w limits breaking news to the past week. */
/** DuckDuckGo region code ("in-en", "uk-en"); Great Britain is "uk" there. */
export const ddgRegion = (region: string): string => `${region === "gb" ? "uk" : region}-en`;

export function duckDuckGoForm(query: string, fresh: Freshness, lang?: string, region?: string): URLSearchParams {
  const f = new URLSearchParams({ q: engineQuery(query), b: "" });
  if (fresh === "breaking") f.set("df", "w");
  if (lang === "hi") f.set("kl", "in-en");
  else if (region) f.set("kl", ddgRegion(region));
  return f;
}
