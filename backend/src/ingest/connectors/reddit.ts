import { AppError } from "../../util/errors.js";
import { fetchJson } from "../fetcher.js";
import type { Connector } from "../types.js";

type Listing<T> = { data: { children: Array<{ kind: string; data: T }> } };
type Post = { id: string; title: string; selftext?: string; permalink: string; score: number; subreddit: string; url?: string; num_comments?: number };
type Comment = { body?: string; author?: string; score?: number; replies?: Listing<Comment> | ""; depth?: number };

const base = "https://www.reddit.com";
const HEADERS = { "User-Agent": "AgentWorkerBot/1.0 (knowledge base ingestion)" };

async function getJson<T>(path: string): Promise<T> {
  try {
    return (await fetchJson<T>(`${base}${path}`, { delayMs: 2000, headers: HEADERS })).data;
  } catch (e) {
    const st = (e as { status?: number }).status;
    if (st === 403 || st === 429) throw new AppError(502, "upstream_failed", "Reddit blocked or rate limited the request (no OAuth). Try a Hacker News or Stack Overflow source instead");
    if (st === 404) throw new AppError(502, "upstream_failed", "Reddit thread or subreddit not found");
    throw e;
  }
}

function parse(input: string): { kind: "thread"; path: string } | { kind: "sub"; sub: string } {
  const s = input.trim();
  const sub = s.match(/^\/?r\/(\w+)\/?$/i);
  if (sub) return { kind: "sub", sub: sub[1] };
  if (/^https?:\/\//i.test(s)) {
    const u = new URL(s);
    const t = u.pathname.match(/^\/r\/(\w+)\/comments\/(\w+)(?:\/([^/]*))?/i);
    if (t) return { kind: "thread", path: `/r/${t[1]}/comments/${t[2]}/${t[3] ?? "_"}` };
    const r = u.pathname.match(/^\/r\/(\w+)\/?/i);
    if (r) return { kind: "sub", sub: r[1] };
  }
  throw new AppError(400, "bad_request", "Expected a Reddit thread URL or r/subreddit");
}

function renderComments(list: Listing<Comment> | "" | undefined, depth: number, out: string[], budget: { n: number }) {
  if (!list) return;
  const items = list.data.children.filter((c) => c.kind === "t1" && c.data.body).sort((a, b) => (b.data.score ?? 0) - (a.data.score ?? 0));
  for (const c of items) {
    if (budget.n <= 0) return;
    budget.n--;
    const pre = "> ".repeat(depth);
    out.push(`${pre}**${c.data.author ?? "?"}** (${c.data.score ?? 0}): ${(c.data.body ?? "").trim().replace(/\n/g, `\n${pre}`)}`);
    if (depth < 2) renderComments(c.data.replies, depth + 1, out, budget);
  }
}

async function emitThread(path: string, ctx: Parameters<Connector["run"]>[1]) {
  try {
    const [postL, comL] = await getJson<[Listing<Post>, Listing<Comment>]>(`${path.replace(/\/$/, "")}.json?limit=100&raw_json=1`);
    const p = postL.data.children[0]?.data;
    if (!p) return ctx.skip("thread not found");
    const comments: string[] = [];
    renderComments(comL, 0, comments, { n: 40 });
    const md = [`# ${p.title}`, `r/${p.subreddit} | score ${p.score}`, p.selftext ?? "", comments.length ? "## Comments" : "", ...comments].filter(Boolean).join("\n\n");
    await ctx.emit({ url: `https://www.reddit.com${p.permalink}`, title: p.title, markdown: md, meta: { score: p.score } });
  } catch (e) {
    if (e instanceof AppError) throw e;
    ctx.skip((e as Error).message);
  }
}

export const reddit: Connector = {
  async resolve(input) {
    const p = parse(input);
    return p.kind === "thread"
      ? { uri: `${base}${p.path}`, options: { kind: "thread", path: p.path } }
      : { uri: `r/${p.sub.toLowerCase()}`, title: `r/${p.sub}`, options: { kind: "sub", sub: p.sub } };
  },

  async run(source, ctx) {
    const o = source.options as { kind: string; path?: string; sub?: string };
    if (o.kind === "thread") {
      ctx.setTotal(1);
      await emitThread(o.path!, ctx);
      return;
    }
    const l = await getJson<Listing<Post>>(`/r/${o.sub}/top.json?t=year&limit=${Math.min(ctx.limit, 100)}&raw_json=1`);
    const posts = l.data.children.filter((c) => c.kind === "t3").map((c) => c.data).slice(0, ctx.limit);
    ctx.setTotal(posts.length);
    ctx.setTitle(`r/${o.sub}`);
    for (const p of posts) await emitThread(p.permalink, ctx);
  },
};
