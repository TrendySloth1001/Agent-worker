import { AppError } from "../../util/errors.js";
import { assertPublicUrl, fetchText } from "../fetcher.js";
import { extractHtml, looksLikeHtml } from "../extract.js";
import type { Connector } from "../types.js";

const SKIP_EXT = /\.(png|jpe?g|gif|svg|webp|ico|pdf|zip|gz|tgz|mp4|mp3|woff2?|ttf|css|js|json|xml|rss|atom|exe|dmg)(\?|$)/i;

function norm(u: string): string {
  const x = new URL(u);
  x.hash = "";
  if (x.pathname.length > 1 && x.pathname.endsWith("/")) x.pathname = x.pathname.slice(0, -1);
  return x.toString();
}

async function robots(origin: string): Promise<{ disallow: string[]; sitemaps: string[] }> {
  try {
    const r = await fetchText(`${origin}/robots.txt`, { delayMs: 0, maxBytes: 200_000 });
    const disallow: string[] = [];
    const sitemaps: string[] = [];
    let applies = false;
    for (const raw of r.body.split("\n")) {
      const line = raw.replace(/#.*/, "").trim();
      const m = line.match(/^([\w-]+)\s*:\s*(.*)$/);
      if (!m) continue;
      const k = m[1].toLowerCase();
      if (k === "user-agent") applies = m[2] === "*" || /agentworker/i.test(m[2]);
      else if (k === "disallow" && applies && m[2]) disallow.push(m[2]);
      else if (k === "sitemap") sitemaps.push(m[2]);
    }
    return { disallow, sitemaps };
  } catch {
    return { disallow: [], sitemaps: [] };
  }
}

async function sitemapUrls(sitemaps: string[], max: number): Promise<string[]> {
  const out: string[] = [];
  const queue = [...sitemaps];
  let fetched = 0;
  while (queue.length && out.length < max && fetched < 5) {
    const u = queue.shift()!;
    fetched++;
    try {
      const r = await fetchText(u, { delayMs: 0, maxBytes: 3_000_000 });
      const locs = [...r.body.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1].replace(/&amp;/g, "&"));
      if (/<sitemapindex/i.test(r.body)) queue.push(...locs.slice(0, 3));
      else out.push(...locs);
    } catch {
      /* ignore broken sitemap */
    }
  }
  return out;
}

function llmsLinks(md: string, base: string): string[] {
  const out: string[] = [];
  for (const m of md.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
    try {
      out.push(new URL(m[1], base).toString());
    } catch {
      /* ignore */
    }
  }
  return out;
}

export const web: Connector = {
  async resolve(input) {
    const raw = input.trim();
    const u = await assertPublicUrl(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`);
    u.hash = "";
    return { uri: u.toString() };
  },

  async run(source, ctx) {
    const start = new URL(source.uri);
    const origin = start.origin;
    const isRoot = start.pathname === "/" || start.pathname === "";
    const crawl = isRoot || start.pathname.endsWith("/");
    const prefix = crawl ? start.pathname : null;
    const rb = await robots(origin);
    const allowed = (u: URL) => !rb.disallow.some((d) => u.pathname.startsWith(d.replace(/\*.*$/, "")));
    const inScope = (u: URL) => u.origin === origin && (prefix === null || u.pathname.startsWith(prefix)) && !SKIP_EXT.test(u.pathname) && allowed(u);

    // llms.txt / llms-full.txt direct input
    if (/\/llms(-full)?\.txt$/i.test(start.pathname)) {
      const r = await fetchText(source.uri);
      ctx.setTitle(`${start.hostname} llms`);
      if (/llms-full\.txt$/i.test(start.pathname)) {
        ctx.setTotal(1);
        await ctx.emit({ url: r.url, title: `${start.hostname} documentation`, markdown: r.body });
        return;
      }
      const links = [...new Set(llmsLinks(r.body, r.url))].filter((l) => !SKIP_EXT.test(l)).slice(0, ctx.limit);
      ctx.setTotal(links.length);
      for (const l of links) await pageInto(l, ctx);
      return;
    }

    ctx.setTotal(crawl ? ctx.limit : 1);
    const queue: Array<{ url: string; depth: number }> = [{ url: norm(source.uri), depth: 0 }];
    const queued = new Set([queue[0].url]);
    let count = 0;

    // Sitemap seeds for site roots (and prefixes), preferred over blind crawling.
    if (crawl) {
      const maps = rb.sitemaps.length ? rb.sitemaps : [`${origin}/sitemap.xml`];
      const urls = await sitemapUrls(maps, ctx.limit * 4);
      for (const u of urls) {
        try {
          const x = new URL(u);
          if (!inScope(x)) continue;
          const n = norm(u);
          if (!queued.has(n)) (queued.add(n), queue.push({ url: n, depth: 1 }));
        } catch {
          /* ignore */
        }
      }
    }

    while (queue.length && count < ctx.limit) {
      const { url, depth } = queue.shift()!;
      try {
        const r = await fetchText(url);
        const final = new URL(r.url);
        if (final.origin !== origin && depth > 0) continue; // redirected off-site
        count++;
        if (looksLikeHtml(r.contentType, r.body)) {
          const ex = extractHtml(r.body, r.url);
          const refresh = r.body.match(/<meta[^>]+http-equiv=["']?refresh["']?[^>]*content=["'][^"']*url=([^"']+)["']/i);
          if (refresh && ex.markdown.length < 300 && depth < 2) {
            // meta-refresh stub: follow the target instead of indexing the stub
            try {
              const target = new URL(refresh[1].trim(), r.url);
              if (target.origin === origin && !queued.has(norm(target.toString()))) {
                queued.add(norm(target.toString()));
                queue.unshift({ url: norm(target.toString()), depth: depth + 1 });
              }
            } catch {
              /* ignore */
            }
            count--;
            continue;
          }
          if (count === 1) ctx.setTitle(ex.title ?? start.hostname);
          await ctx.emit({ url: norm(r.url), title: ex.title, markdown: ex.markdown });
          if (crawl && depth < 2) {
            for (const l of ex.links) {
              try {
                const x = new URL(l);
                if (!inScope(x)) continue;
                const n = norm(l);
                if (!queued.has(n)) (queued.add(n), queue.push({ url: n, depth: depth + 1 }));
              } catch {
                /* ignore */
              }
            }
          }
        } else {
          await ctx.emit({ url: norm(r.url), title: final.pathname.split("/").pop() || start.hostname, markdown: r.body });
        }
      } catch (e) {
        if (depth === 0) {
          throw new AppError(502, "upstream_failed", `Could not fetch ${start.hostname}: ${(e as Error).message}`);
        }
        ctx.skip((e as Error).message);
      }
    }
  },
};

async function pageInto(url: string, ctx: Parameters<Connector["run"]>[1]) {
  try {
    const r = await fetchText(url);
    if (looksLikeHtml(r.contentType, r.body)) {
      const ex = extractHtml(r.body, r.url);
      await ctx.emit({ url: r.url, title: ex.title, markdown: ex.markdown });
    } else await ctx.emit({ url: r.url, title: null, markdown: r.body });
  } catch (e) {
    ctx.skip((e as Error).message);
  }
}
