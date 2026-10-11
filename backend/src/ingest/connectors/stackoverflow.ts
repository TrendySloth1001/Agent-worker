import { config } from "../../config.js";
import { AppError } from "../../util/errors.js";
import { fetchJson } from "../fetcher.js";
import { snippetHtmlToMarkdown } from "../extract.js";
import type { Connector } from "../types.js";

const API = "https://api.stackexchange.com/2.3";

const decode = (s: string) =>
  s.replace(/&#39;|&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");

type Q = { question_id: number; title: string; body?: string; link: string; score: number; tags: string[]; answer_count: number; accepted_answer_id?: number };
type A = { answer_id: number; question_id: number; body?: string; score: number; is_accepted: boolean };

let nextOkAt = 0;
async function se<T>(path: string, params: Record<string, string | number>): Promise<T[]> {
  const wait = nextOkAt - Date.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  const qs = new URLSearchParams({ site: "stackoverflow", ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)])) });
  if (config.stackExchangeKey) qs.set("key", config.stackExchangeKey);
  try {
    const { data } = await fetchJson<{ items?: T[]; backoff?: number; error_message?: string }>(`${API}${path}?${qs}`);
    if (data.backoff) nextOkAt = Date.now() + data.backoff * 1000;
    return data.items ?? [];
  } catch (e) {
    const st = (e as { status?: number }).status;
    if (st === 400 || st === 502 || st === 429) throw new AppError(502, "upstream_failed", "Stack Exchange API throttled this server. Try again later");
    throw e;
  }
}

function parse(input: string): { kind: "question"; id: number } | { kind: "tag"; tag: string } {
  const s = input.trim();
  if (/^\d+$/.test(s)) return { kind: "question", id: Number(s) };
  if (/^https?:\/\//i.test(s)) {
    const u = new URL(s);
    const q = u.pathname.match(/\/(?:questions|q|a)\/(\d+)/);
    if (q) return { kind: "question", id: Number(q[1]) };
    const t = u.pathname.match(/\/questions\/tagged\/([^/]+)/);
    if (t) return { kind: "tag", tag: decodeURIComponent(t[1]).toLowerCase() };
    throw new AppError(400, "bad_request", "Expected a Stack Overflow question URL, question id, or tag name");
  }
  if (/^[a-z0-9][a-z0-9#+.\-]{0,34}$/i.test(s)) return { kind: "tag", tag: s.toLowerCase() };
  throw new AppError(400, "bad_request", "Expected a Stack Overflow question URL, question id, or tag name");
}

function render(q: Q, answers: A[]): string {
  const parts = [`# ${decode(q.title)}`, `Tags: ${q.tags.join(", ")} | Score: ${q.score}`, snippetHtmlToMarkdown(q.body ?? "")];
  const sorted = [...answers].sort((a, b) => Number(b.is_accepted) - Number(a.is_accepted) || b.score - a.score).slice(0, 5);
  sorted.forEach((a, i) => {
    parts.push(`## Answer ${i + 1}${a.is_accepted ? " (accepted)" : ""} - score ${a.score}`, snippetHtmlToMarkdown(a.body ?? ""));
  });
  return parts.join("\n\n");
}

export const stackoverflow: Connector = {
  async resolve(input) {
    const p = parse(input);
    return p.kind === "question"
      ? { uri: `https://stackoverflow.com/questions/${p.id}`, options: { kind: "question", id: p.id } }
      : { uri: `tag:${p.tag}`, title: `Stack Overflow [${p.tag}]`, options: { kind: "tag", tag: p.tag } };
  },

  async run(source, ctx) {
    const o = source.options as { kind: string; id?: number; tag?: string };
    let questions: Q[];
    if (o.kind === "question") {
      questions = await se<Q>(`/questions/${o.id}`, { filter: "withbody" });
      if (!questions.length) throw new AppError(502, "upstream_failed", "Question not found");
    } else {
      ctx.setTitle(`Stack Overflow [${o.tag}]`);
      questions = await se<Q>("/search/advanced", { tagged: o.tag!, sort: "votes", order: "desc", answers: 1, pagesize: Math.min(ctx.limit, 100), filter: "withbody" });
      if (!questions.length) throw new AppError(502, "upstream_failed", `No answered questions found for tag "${o.tag}"`);
    }
    ctx.setTotal(questions.length);
    if (o.kind === "question") ctx.setTitle(decode(questions[0].title));

    const answers = new Map<number, A[]>();
    const ids = questions.map((q) => q.question_id);
    for (let i = 0; i < ids.length; i += 30) {
      const part = ids.slice(i, i + 30);
      const items = await se<A>(`/questions/${part.join(";")}/answers`, { sort: "votes", order: "desc", pagesize: 100, filter: "withbody" });
      for (const a of items) answers.set(a.question_id, [...(answers.get(a.question_id) ?? []), a]);
    }
    for (const q of questions) {
      await ctx.emit({
        url: `https://stackoverflow.com/questions/${q.question_id}`,
        title: decode(q.title),
        markdown: render(q, answers.get(q.question_id) ?? []),
        meta: { score: q.score, tags: q.tags },
      });
    }
  },
};
