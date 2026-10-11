import { AppError } from "../../util/errors.js";
import { fetchJson } from "../fetcher.js";
import { snippetHtmlToMarkdown } from "../extract.js";
import type { Connector } from "../types.js";

const ALGOLIA = "https://hn.algolia.com/api/v1";

type Item = { id: number; type?: string; title?: string | null; url?: string | null; text?: string | null; author?: string | null; points?: number | null; children?: Item[] };

function parse(input: string): { kind: "item"; id: number } | { kind: "search"; query: string } {
  const s = input.trim();
  if (/^\d+$/.test(s)) return { kind: "item", id: Number(s) };
  if (/^https?:\/\//i.test(s)) {
    const u = new URL(s);
    const id = u.searchParams.get("id");
    if (u.hostname === "news.ycombinator.com" && id && /^\d+$/.test(id)) return { kind: "item", id: Number(id) };
    throw new AppError(400, "bad_request", "Expected a news.ycombinator.com/item?id=... URL, an item id, or a search query");
  }
  if (s.length < 2) throw new AppError(400, "bad_request", "Search query too short");
  return { kind: "search", query: s };
}

function flatten(children: Item[] | undefined, depth: number, out: string[], budget: { n: number }) {
  for (const c of children ?? []) {
    if (budget.n <= 0) return;
    if (!c.text) continue;
    budget.n--;
    const body = snippetHtmlToMarkdown(c.text).replace(/\n/g, "\n" + "> ".repeat(depth + 1));
    out.push(`${"> ".repeat(depth)}**${c.author ?? "anon"}**: ${body}`);
    if (depth < 2) flatten(c.children, depth + 1, out, budget);
  }
}

function render(it: Item): string {
  const parts = [`# ${it.title ?? `HN item ${it.id}`}`];
  if (it.url) parts.push(`Link: ${it.url}`);
  if (it.points != null) parts.push(`Points: ${it.points}`);
  if (it.text) parts.push(snippetHtmlToMarkdown(it.text));
  const comments: string[] = [];
  flatten(it.children, 0, comments, { n: 60 });
  if (comments.length) parts.push("## Discussion", ...comments);
  return parts.join("\n\n");
}

async function emitItem(id: number, ctx: Parameters<Connector["run"]>[1]) {
  try {
    const { data } = await fetchJson<Item>(`${ALGOLIA}/items/${id}`);
    if (!data?.id) return ctx.skip("item not found");
    await ctx.emit({ url: `https://news.ycombinator.com/item?id=${data.id}`, title: data.title ?? `HN item ${data.id}`, markdown: render(data), meta: { points: data.points } });
  } catch (e) {
    ctx.skip((e as Error).message);
  }
}

export const hackernews: Connector = {
  async resolve(input) {
    const p = parse(input);
    return p.kind === "item"
      ? { uri: `https://news.ycombinator.com/item?id=${p.id}`, options: { kind: "item", id: p.id } }
      : { uri: `search:${p.query}`, title: `HN: ${p.query}`, options: { kind: "search", query: p.query } };
  },

  async run(source, ctx) {
    const o = source.options as { kind: string; id?: number; query?: string };
    if (o.kind === "item") {
      ctx.setTotal(1);
      await emitItem(o.id!, ctx);
      return;
    }
    const { data } = await fetchJson<{ hits: Array<{ objectID: string; num_comments?: number }> }>(
      `${ALGOLIA}/search?${new URLSearchParams({ query: o.query!, tags: "story", hitsPerPage: String(Math.min(ctx.limit * 2, 100)) })}`,
    );
    const ids = data.hits.filter((h) => (h.num_comments ?? 0) > 0).slice(0, ctx.limit).map((h) => Number(h.objectID));
    if (!ids.length) throw new AppError(502, "upstream_failed", `No Hacker News stories found for "${o.query}"`);
    ctx.setTotal(ids.length);
    ctx.setTitle(`HN: ${o.query}`);
    for (const id of ids) await emitItem(id, ctx);
  },
};
