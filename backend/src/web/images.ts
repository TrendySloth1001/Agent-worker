import { fetchText, USER_AGENT } from "../ingest/fetcher.js";
import { log } from "../util/logger.js";
import { redactForExternal } from "../nlp/pii.js";

export type ImageResult = {
  url: string;
  /** Page the image explains or comes from. */
  sourceUrl: string;
  title: string;
  site: string;
  width?: number;
  height?: number;
};

const MAX_IMAGES = 8;
const UA = { "User-Agent": `${USER_AGENT} (engineering chat app)` };

const STOPWORDS = new Set(
  ("a an and are as at be briefly can could describe detail difference does do explain explanation for from give " +
    "how i in into is it its me my of on or please show simple simply tell that the this to vs versus was what " +
    "when where which while who why with work works would you your").split(" "),
);

/** The topic words of a question: "explain the TCP handshake briefly" -> "TCP handshake". */
export function topicOf(question: string): string {
  return question
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/[^\p{L}\p{N}\s\-+#.]/gu, " ")
    .split(/\s+/)
    .filter((w) => w && !STOPWORDS.has(w.toLowerCase()))
    .slice(0, 6)
    .join(" ");
}
const PAGE_TIMEOUT_MS = 5_000;
const COMMONS_TIMEOUT_MS = 5_000;

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
};

function timeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error("timeout")), ms))]);
}

const META_RE = /<meta\s+[^>]*>/gi;
const attr = (tag: string, name: string) =>
  tag.match(new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, "i"))?.[1];

/** The page's share image (og:image / twitter:image), resolved to an absolute https URL. */
async function pageImage(pageUrl: string, title: string): Promise<ImageResult | null> {
  const page = await timeout(fetchText(pageUrl, { delayMs: 0, maxBytes: 3_000_000 }), PAGE_TIMEOUT_MS);
  const head = page.body.slice(0, 200_000);
  for (const tag of head.match(META_RE) ?? []) {
    const key = (attr(tag, "property") ?? attr(tag, "name") ?? "").toLowerCase();
    if (!["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"].includes(key)) continue;
    const raw = attr(tag, "content");
    if (!raw) continue;
    try {
      const url = new URL(raw.replace(/&amp;/g, "&"), page.url);
      if (url.protocol !== "https:") continue;
      // Skip logos and site-wide share cards: they explain nothing.
      if (/favicon|logo|sprite|avatar|social|open-?graph|og[-_]?image|share|default|banner|\.ico($|\?)|\.svg($|\?)/i.test(url.pathname)) continue;
      return { url: url.toString(), sourceUrl: pageUrl, title, site: hostOf(pageUrl) };
    } catch {
      /* bad URL, try the next tag */
    }
  }
  return null;
}

/** Figures from the Wikipedia article that best matches the topic. */
async function wikipediaImages(topic: string, limit: number): Promise<ImageResult[]> {
  const search = await fetch(
    `https://en.wikipedia.org/w/rest.php/v1/search/page?${new URLSearchParams({ q: topic, limit: "1" })}`,
    { headers: UA, signal: AbortSignal.timeout(COMMONS_TIMEOUT_MS) },
  );
  if (!search.ok) throw new Error(`wikipedia search ${search.status}`);
  const page = ((await search.json()) as any)?.pages?.[0];
  if (!page?.key) return [];
  const media = await fetch(`https://en.wikipedia.org/api/rest_v1/page/media-list/${encodeURIComponent(page.key)}`, {
    headers: UA,
    signal: AbortSignal.timeout(COMMONS_TIMEOUT_MS),
  });
  if (!media.ok) throw new Error(`wikipedia media ${media.status}`);
  const articleUrl = `https://en.wikipedia.org/wiki/${page.key}`;
  return (((await media.json()) as any)?.items ?? [])
    .filter((it: any) => it.type === "image" && it.showInGallery !== false && it.srcset?.[0]?.src)
    .filter((it: any) => !/icon|logo|flag|symbol|commons-logo|question_book|edit-clear|ambox/i.test(it.title ?? ""))
    .slice(0, limit)
    .map((it: any) => ({
      url: `https:${String(it.srcset[it.srcset.length - 1].src).replace(/^https?:/, "")}`,
      sourceUrl: articleUrl,
      title: String(it.caption?.text || it.title || "").replace(/^File:/, "").replace(/\.[a-z0-9]+$/i, "").slice(0, 160),
      site: "en.wikipedia.org",
    }));
}

/** Diagrams and photos from Wikimedia Commons that match the question. */
async function commonsImages(query: string, limit: number): Promise<ImageResult[]> {
  const params = new URLSearchParams({
    action: "query",
    format: "json",
    generator: "search",
    gsrnamespace: "6",
    gsrsearch: `${query} filetype:bitmap|drawing`,
    gsrlimit: String(limit),
    prop: "imageinfo",
    iiprop: "url|size|mime",
    iiurlwidth: "800",
    origin: "*",
  });
  const res = await fetch(`https://commons.wikimedia.org/w/api.php?${params}`, {
    headers: UA,
    signal: AbortSignal.timeout(COMMONS_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`commons ${res.status}`);
  const data = (await res.json()) as any;
  const pages = Object.values(data?.query?.pages ?? {}) as any[];
  return pages
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .map((p) => ({ p, info: p.imageinfo?.[0] }))
    .filter(({ info }) => info?.thumburl && /^image\/(png|jpeg|gif|webp|svg\+xml)$/.test(info.mime ?? ""))
    .map(({ p, info }) => ({
      url: info.thumburl as string,
      sourceUrl: (info.descriptionurl as string) ?? info.url,
      title: String(p.title ?? "").replace(/^File:/, "").replace(/\.[a-z0-9]+$/i, ""),
      site: "commons.wikimedia.org",
      width: info.thumbwidth,
      height: info.thumbheight,
    }));
}

/**
 * Images that help explain the answer: figures from the matching Wikipedia
 * article, then Commons media, then real share images of the web results.
 * Never throws; returns what it found in time.
 */
export async function findImages(question: string, pages: Array<{ url: string; title: string }>): Promise<ImageResult[]> {
  const topic = redactForExternal(topicOf(question) || question.slice(0, 80));
  const quiet = (label: string) => (e: unknown) => {
    log.warn(`${label} image search failed`, { message: (e as Error).message.slice(0, 80) });
    return [] as ImageResult[];
  };
  const [fromWiki, fromCommons, fromPages] = await Promise.all([
    wikipediaImages(topic, 4).catch(quiet("wikipedia")),
    commonsImages(topic, 6).catch(quiet("commons")),
    Promise.allSettled(pages.slice(0, 5).map((p) => pageImage(p.url, p.title))),
  ]);
  const seen = new Set<string>();
  const out: ImageResult[] = [];
  for (const img of [
    ...fromWiki,
    ...fromCommons,
    ...fromPages.flatMap((r) => (r.status === "fulfilled" && r.value ? [r.value] : [])),
  ]) {
    // The same file often comes back from Wikipedia and Commons at different sizes.
    const file = decodeURIComponent(img.url.split("/").slice(-2, -1)[0] ?? img.url).toLowerCase();
    if (seen.has(img.url) || seen.has(file)) continue;
    seen.add(img.url);
    seen.add(file);
    out.push(img);
    if (out.length >= MAX_IMAGES) break;
  }
  return out;
}

const queryCache = new Map<string, { at: number; images: ImageResult[] }>();
const QUERY_TTL_MS = 60 * 60_000;

/**
 * Images for a description the model wrote inline, e.g. "TCP three-way
 * handshake diagram": Wikipedia figures first, then Commons. Cached for an hour.
 */
export async function imagesForQuery(query: string, limit: number): Promise<ImageResult[]> {
  const key = `${query.toLowerCase()}|${limit}`;
  const hit = queryCache.get(key);
  if (hit && Date.now() - hit.at < QUERY_TTL_MS) return hit.images;
  const topic = redactForExternal(topicOf(query) || query.slice(0, 80));
  const [wiki, commons] = await Promise.all([
    wikipediaImages(topic, limit + 2).catch(() => [] as ImageResult[]),
    commonsImages(topic, limit + 2).catch(() => [] as ImageResult[]),
  ]);
  const seen = new Set<string>();
  const images: ImageResult[] = [];
  for (const img of [...wiki, ...commons]) {
    const file = decodeURIComponent(img.url.split("/").slice(-2, -1)[0] ?? img.url).toLowerCase();
    if (seen.has(file)) continue;
    seen.add(file);
    images.push(img);
    if (images.length >= limit) break;
  }
  queryCache.set(key, { at: Date.now(), images });
  if (queryCache.size > 500) queryCache.delete(queryCache.keys().next().value as string);
  return images;
}
