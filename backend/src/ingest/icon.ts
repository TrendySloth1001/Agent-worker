import { db } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { fetchText } from "./fetcher.js";

/** Types whose icon comes from a web page; the rest (note, file, doc) use local type icons in the app. */
const REMOTE_TYPES = new Set(["web", "github", "stackoverflow", "reddit", "hackernews"]);
const FIXED_HOST: Record<string, string> = {
  stackoverflow: "https://stackoverflow.com/",
  reddit: "https://www.reddit.com/",
  hackernews: "https://news.ycombinator.com/",
};
const MAX_ICON_URL = 2000;

export const hasRemoteIcon = (type: string) => REMOTE_TYPES.has(type);

export function githubAvatarUrl(owner: string): string {
  return `https://github.com/${encodeURIComponent(owner)}.png?size=96`;
}

function attrs(tag: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of tag.matchAll(/([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g)) out[m[1].toLowerCase()] = (m[2] ?? m[3] ?? m[4] ?? "").trim();
  return out;
}

function absolute(href: string | undefined, base: string): string | null {
  if (!href || /^(data|javascript|blob):/i.test(href)) return null;
  try {
    const u = new URL(href.replace(/&amp;/g, "&"), base);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (u.protocol === "http:") u.protocol = "https:"; // cleartext traffic is blocked on the phone
    const s = u.toString();
    return s.length <= MAX_ICON_URL ? s : null;
  } catch {
    return null;
  }
}

function sizeOf(sizes: string | undefined): number {
  const m = sizes?.match(/(\d+)x(\d+)/);
  return m ? Number(m[1]) : 0;
}

/**
 * The best icon a page declares: apple-touch-icon, then `<link rel=icon>` (bitmaps only, since the app cannot draw SVG;
 * larger first), then og:image, then /favicon.ico. Relative URLs are resolved against [base].
 */
export function pickIconUrl(html: string, base: string): string {
  const head = html.slice(0, 200_000);
  const apple: Array<{ url: string; size: number }> = [];
  const icons: Array<{ url: string; size: number }> = [];
  let og: string | null = null;
  for (const m of head.matchAll(/<(link|meta)\b[^>]*>/gi)) {
    const a = attrs(m[0]);
    if (m[1].toLowerCase() === "link") {
      const rel = (a.rel ?? "").toLowerCase().split(/\s+/);
      const url = absolute(a.href, base);
      if (!url) continue;
      const size = sizeOf(a.sizes);
      if (rel.includes("apple-touch-icon") || rel.includes("apple-touch-icon-precomposed")) apple.push({ url, size });
      else if (rel.includes("icon") && !/\.svg(\?|$)/i.test(url) && !/svg/i.test(a.type ?? "")) icons.push({ url, size });
    } else if (!og && /^(og:image|og:image:secure_url)$/i.test(a.property ?? a.name ?? "")) {
      og = absolute(a.content, base);
    }
  }
  const best = (l: Array<{ url: string; size: number }>) => [...l].sort((x, y) => y.size - x.size)[0]?.url;
  return best(apple) ?? best(icons) ?? og ?? new URL("/favicon.ico", base).toString();
}

/** Resolves the icon URL for a source, or null when none can be determined. Fetches through the SSRF-guarded fetcher. */
export async function resolveIconUrl(type: string, uri: string): Promise<string | null> {
  if (!REMOTE_TYPES.has(type)) return null;
  if (type === "github") {
    const owner = uri.split("/")[0];
    return owner ? githubAvatarUrl(owner) : null;
  }
  const page = FIXED_HOST[type] ?? uri;
  try {
    const u = new URL(page);
    try {
      const r = await fetchText(u.toString(), { delayMs: 0, maxBytes: 400_000 });
      return pickIconUrl(r.body, r.url);
    } catch {
      return new URL("/favicon.ico", u.origin).toString();
    }
  } catch {
    return null;
  }
}

/** Looks up and stores a source's icon unless it already has one. Never throws. */
export async function storeIcon(id: string, type: string, uri: string): Promise<void> {
  try {
    const url = await resolveIconUrl(type, uri);
    if (url) await db().source.updateMany({ where: { id, iconUrl: null }, data: { iconUrl: url } });
  } catch (e) {
    log.warn("icon resolve failed", { sourceId: id, reason: (e as Error).message.slice(0, 120) });
  }
}

let backfilling = false;
/** Fills in icons for existing sources that have none, one at a time in the background. */
export function backfillIcons(): void {
  if (backfilling) return;
  backfilling = true;
  void (async () => {
    try {
      const rows = await db().source.findMany({
        where: { iconUrl: null, type: { in: [...REMOTE_TYPES] } },
        select: { id: true, type: true, uri: true },
        take: 500,
      });
      for (const r of rows) await storeIcon(r.id, r.type, r.uri);
      if (rows.length) log.info("source icons backfilled", { count: rows.length });
    } catch (e) {
      log.warn("icon backfill failed", { reason: (e as Error).message.slice(0, 120) });
    } finally {
      backfilling = false;
    }
  })();
}
