/**
 * Factual-accuracy eval through the real chat pipeline (not part of the unit tests).
 *
 *   PORT=3999 pnpm exec tsx src/index.ts &                      # local backend, local .env (never production)
 *   FACTUAL_BASE_URL=http://localhost:3999 pnpm exec tsx scripts/factual-eval.ts --out /tmp/before.json
 *
 * Options: --pause <ms> between questions (default 7000, keeps free-tier rate limits happy),
 *          --only <id,id> to run a subset, --web auto|off (default auto = the app default).
 * Authenticates with the local API_TOKEN dev bypass; never prints it. Scores each reply as
 * correct / abstained_ok / abstained_unhelpful / confident_wrong (see factual-score.ts).
 */
import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { score, summarize, type EvalItem, type Row } from "./factual-score.js";

const arg = (name: string, def?: string) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : def;
};
const BASE = process.env.FACTUAL_BASE_URL ?? `http://localhost:${process.env.PORT ?? 3000}`;
const TOKEN = process.env.API_TOKEN ?? "";
if (/cloudnsofts|sparky\./i.test(BASE)) throw new Error("Refusing to run the eval against a non-local backend");
const pause = Number(arg("pause", "7000"));
const only = arg("only")?.split(",");
const web = (arg("web", "auto") as "auto" | "off");
const out = arg("out");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const items = (JSON.parse(readFileSync(new URL("../test/fixtures/factual-eval.json", import.meta.url), "utf8")).items as EvalItem[]).filter((i) => !only || only.includes(i.id));

async function ask(q: string): Promise<{ text: string; model: string | null; web: boolean; error?: string }> {
  const r = await fetch(BASE + "/chat", {
    method: "POST",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({ messages: [{ role: "user", content: q }], webMode: web, knowledge: false, smartSuggestions: false }),
  });
  let text = "";
  let model: string | null = null;
  let searched = false;
  let error: string | undefined;
  if (!r.body) return { text, model, web: false, error: `http ${r.status}` };
  const reader = r.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i: number;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const block = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const ev = /^event: (.*)$/m.exec(block)?.[1];
      const raw = /^data: (.*)$/m.exec(block)?.[1];
      const data = raw ? JSON.parse(raw) : null;
      if (ev === "delta") text += data?.text ?? "";
      else if (ev === "reset") text = "";
      else if (ev === "model") model = data?.model ?? model;
      else if (ev === "tools") searched = !!data?.web;
      else if (ev === "error") error = data?.message ?? "error";
      if (ev === "done" || ev === "error") {
        model = data?.model ?? model;
        await reader.cancel().catch(() => {});
        return { text, model, web: searched, error };
      }
    }
  }
  return { text, model, web: searched, error };
}

const rows: Row[] = [];
for (const [n, item] of items.entries()) {
  let res = await ask(item.q).catch((e) => ({ text: "", model: null, web: false, error: (e as Error).message }));
  // A busy upstream is not a wrong answer: retry once after a longer pause.
  if (res.error || !res.text.trim()) {
    await sleep(Math.max(pause * 3, 20_000));
    res = await ask(item.q).catch((e) => ({ text: "", model: null, web: false, error: (e as Error).message }));
  }
  const outcome = res.text.trim() ? score(item, res.text) : ("abstained_unhelpful" as const);
  rows.push({ id: item.id, cat: item.cat, outcome, model: res.model, web: res.web, reply: res.text });
  console.log(`${String(n + 1).padStart(2)}/${items.length} ${item.id} ${outcome.padEnd(19)} web=${res.web ? "y" : "n"} ${res.model ?? "-"}${res.error ? ` ERR ${res.error.slice(0, 60)}` : ""}`);
  if (n < items.length - 1) await sleep(pause);
}
const summary = summarize(rows);
console.log(JSON.stringify(summary, null, 1));
if (out) writeFileSync(out, JSON.stringify({ at: new Date().toISOString(), web, summary, rows }, null, 1));
