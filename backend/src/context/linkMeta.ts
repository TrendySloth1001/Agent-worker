/**
 * Rich-card metadata for one link the app will open ("Open in YouTube Music"):
 * a title, a subtitle (artist, channel or site) and a cover image.
 * - YouTube / YouTube Music: the video id gives the thumbnail
 *   (i.ytimg.com/vi/<id>/hqdefault.jpg) and YouTube's oEmbed the title and
 *   channel, so no page is scraped.
 * - Anything else: the page's og:title / og:image / og:site_name.
 * Cached in memory and in the shared web cache (web_cache); never throws and
 * gives up after a short timeout (the card falls back to the app's logo).
 */
import { fetchText } from "../ingest/fetcher.js";
import { decodeEntities } from "../web/html.js";
import { TtlLru } from "../web/lru.js";
import { readPersistedValue, writePersisted } from "../web/cacheStore.js";

export type LinkMeta = { title?: string; subtitle?: string; image?: string; site?: string };

/** Fetches a URL's text (a page or JSON); injectable for tests. */
export type MetaFetch = (url: string, signal?: AbortSignal) => Promise<{ body: string; url: string }>;

const TIMEOUT_MS = 2_500;
const TTL_MS = 7 * 24 * 3_600_000;
const MAX_FIELD = 140;
const mem = new TtlLru<LinkMeta>(500);

const YT_HOST = /(^|\.)(youtube\.com|youtu\.be)$/i;
const YT_ID = /(?:[?&]v=|youtu\.be\/|\/shorts\/|\/embed\/)([\w-]{6,})/;

/** The YouTube video id of [url] (youtube.com, music.youtube.com, youtu.be), if any. */
export function youtubeId(url: string): string | null {
  try {
    if (!YT_HOST.test(new URL(url).hostname)) return null;
  } catch {
    return null;
  }
  return YT_ID.exec(url)?.[1] ?? null;
}

/** The video's thumbnail; always exists for a real id. */
export const youtubeThumb = (id: string) => `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;

const META_RE = /<meta\s+[^>]*>/gi;
const attr = (tag: string, name: string) => tag.match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1];
const clean = (s: string | undefined) => {
  const v = s ? decodeEntities(s).replace(/\s+/g, " ").trim() : "";
  return v ? v.slice(0, MAX_FIELD) : undefined;
};

/** og:title / og:image / og:site_name of an HTML page (absolute https image only). */
export function parseOgMeta(html: string, pageUrl: string): LinkMeta {
  const out: Record<string, string> = {};
  for (const tag of html.slice(0, 300_000).match(META_RE) ?? []) {
    const key = (attr(tag, "property") ?? attr(tag, "name") ?? "").toLowerCase();
    const content = attr(tag, "content");
    if (!content || out[key]) continue;
    if (["og:title", "twitter:title", "og:image", "og:image:secure_url", "twitter:image", "og:site_name"].includes(key)) out[key] = content;
  }
  let image: string | undefined;
  const raw = out["og:image:secure_url"] ?? out["og:image"] ?? out["twitter:image"];
  if (raw) {
    try {
      const u = new URL(decodeEntities(raw), pageUrl);
      if (u.protocol === "https:") image = u.toString();
    } catch {
      /* no image */
    }
  }
  const title = clean(out["og:title"] ?? out["twitter:title"]) ?? clean(/<title[^>]*>([^<]{1,300})<\/title>/i.exec(html)?.[1]);
  const site = clean(out["og:site_name"]);
  return { ...(title ? { title } : {}), ...(image ? { image } : {}), ...(site ? { site } : {}) };
}

const defaultFetch: MetaFetch = async (url) => {
  const r = await fetchText(url, { delayMs: 0, maxBytes: 1_500_000, anyType: true });
  return { body: r.body, url: r.url };
};

async function fetchMeta(url: string, get: MetaFetch, signal?: AbortSignal): Promise<LinkMeta> {
  const id = youtubeId(url);
  if (id) {
    const meta: LinkMeta = { image: youtubeThumb(id) };
    try {
      const watch = `https://www.youtube.com/watch?v=${id}`;
      const r = await get(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(watch)}`, signal);
      const j = JSON.parse(r.body) as { title?: string; author_name?: string };
      const title = clean(j.title);
      const subtitle = clean(j.author_name?.replace(/\s+-\s+Topic$/i, ""));
      if (title) meta.title = title;
      if (subtitle) meta.subtitle = subtitle;
    } catch {
      /* the thumbnail alone still makes the card */
    }
    return meta;
  }
  const page = await get(url, signal);
  return parseOgMeta(page.body, page.url || url);
}

/**
 * The card metadata of [url], or {} when nothing could be read in time.
 * [fetch] is injectable for tests (it also skips the shared cache).
 */
export async function linkMeta(url: string, o: { fetch?: MetaFetch; signal?: AbortSignal; timeoutMs?: number } = {}): Promise<LinkMeta> {
  const key = `linkmeta|${url}`.slice(0, 400);
  const shared = !o.fetch;
  const hit = shared ? mem.get(key) : undefined;
  if (hit) return hit;
  const work = (async () => {
    if (shared) {
      const stored = await readPersistedValue(key, (v): v is LinkMeta => !!v && typeof v === "object" && !Array.isArray(v));
      if (stored) return stored;
    }
    const meta = await fetchMeta(url, o.fetch ?? defaultFetch, o.signal);
    if (shared && (meta.title || meta.image)) writePersisted(key, meta, TTL_MS);
    return meta;
  })();
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<LinkMeta>((r) => {
    timer = setTimeout(() => r({}), o.timeoutMs ?? TIMEOUT_MS);
  });
  try {
    const meta = await Promise.race([work.catch(() => ({}) as LinkMeta), timeout]);
    if (shared && (meta.title || meta.image)) mem.set(key, meta, TTL_MS);
    return meta;
  } catch {
    return {};
  } finally {
    clearTimeout(timer);
  }
}
