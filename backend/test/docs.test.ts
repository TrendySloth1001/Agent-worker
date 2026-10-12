import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import express from "express";
import type { AddressInfo } from "node:net";
import { makeOutline, normalizeOutline, OutlineError } from "../src/docs/outline.js";
import { SectionFilter, writeSection, keepValidTags, type RunChatFn } from "../src/docs/section.js";
import { runPipeline, runRewrite, addSection, DEFAULT_LIMITS, type DocDeps } from "../src/docs/pipeline.js";
import { answerQuestion, editSelection, locateSpan, planNextSection } from "../src/docs/followup.js";
import { finishJob, registerJob, Semaphore } from "../src/docs/registry.js";
import { anchorQuote, memoryStore, MAX_REVISIONS, prismaStore, type DocStore } from "../src/docs/store.js";
import { toDocx, toMarkdown } from "../src/docs/export.js";
import type { DocSource, DocState } from "../src/docs/types.js";
import { ChatFailure } from "../src/llm/router.js";
import { UpstreamError, type Message } from "../src/providers.js";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";
import { config } from "../src/config.js";
import { docLimit } from "../src/auth/limits.js";
import { errorMiddleware, AppError } from "../src/util/errors.js";

// ---- fakes ------------------------------------------------------------------------

const OUTLINE = {
  title: "HTTPS and TLS 1.3",
  subtitle: "How the web stays private",
  audience: "developers",
  style: "guide",
  glossary: [{ term: "TLS", definition: "Transport Layer Security." }],
  sections: [1, 2, 3, 4, 5].map((i) => ({ id: `x${i}`, heading: `Part ${i}`, goal: `Goal ${i}.`, keyPoints: ["a", "b"], queries: [`query ${i}`], visual: "none", words: 300 })),
};

const src = (id: string, text = "TLS 1.3 removed RSA key exchange and requires forward secrecy for every connection."): DocSource => ({
  id,
  kind: "web",
  title: `Source ${id}`,
  url: `https://example.com/${id}`,
  snippet: text.slice(0, 50),
  site: "example.com",
  text,
  full: text,
});

/** A runChat that streams [chunks] in pieces. */
function streamOf(chunks: string[], finishReason = "stop"): RunChatFn {
  return async (candidates, _messages, _signal, hooks) => {
    hooks.onModel(candidates[0], 1);
    for (const c of chunks) hooks.onDelta(c);
    return { model: candidates[0], promptTokens: null, completionTokens: null, finishReason };
  };
}

const sectionBody = (id: string) => `Body of ${id}: TLS 1.3 removed RSA key exchange [W1]. Invented [W99].\n<!--summary: ${id} done. Second sentence.-->`;

function fakeDeps(store: DocStore, over: Partial<DocDeps> = {}): DocDeps {
  return {
    store,
    ask: async (_m, _msgs, opts) => {
      if (opts.purpose === "doc-outline") return JSON.stringify(OUTLINE);
      return JSON.stringify({ takeaways: ["One.", "Two.", "Three."], abstract: "An abstract." });
    },
    runChat: async (candidates, messages, _signal, hooks) => {
      const sid = /Write §(\d+)/.exec(messages[messages.length - 1].content)?.[1];
      hooks.onModel(candidates[0], 1);
      hooks.onDelta(sectionBody(`s${sid}`));
      return { model: candidates[0], promptTokens: null, completionTokens: null, finishReason: "stop" };
    },
    candidates: async () => ["fake:a", "fake:b", "fake:c"],
    outlineModels: async () => ["fake:o1", "fake:o2", "fake:o3"],
    finishModels: async () => ["fake:f"],
    webSearch: async (q) => [{ title: `R ${q}`, url: `https://example.com/${encodeURIComponent(q)}`, content: "TLS 1.3 removed RSA key exchange and requires forward secrecy.", full: "TLS 1.3 removed RSA key exchange and requires forward secrecy." }],
    webFetch: async () => null,
    images: async () => [],
    retrieve: async () => [],
    attachments: async () => ({ items: [], failed: [] }),
    linkMessage: async () => {},
    limits: { ...DEFAULT_LIMITS, staggerMs: 0 },
    slots: new Semaphore(3),
    ...over,
  };
}

async function newDoc(store: DocStore, userId = randomUUID(), length: "short" | "standard" = "short"): Promise<DocState> {
  return store.create({ userId, conversationId: null, prompt: "Write a guide to how HTTPS and TLS 1.3 work", options: { length, web: true, kb: false } });
}

async function run(state: DocState, mode: "full" | "write" | "resume", deps: DocDeps) {
  const job = registerJob(state, "pipeline");
  const events: Array<[string, any]> = [];
  job.emitter.on("event", (e: string, d: unknown) => events.push([e, d]));
  await runPipeline(job, mode, deps);
  finishJob(job);
  return events;
}

// ---- outline ----------------------------------------------------------------------

const ctx = { web: [], kb: [], files: [] };

test("outline: invalid JSON is retried once on the next model", async () => {
  const seen: string[] = [];
  const r = await makeOutline({
    prompt: "p",
    length: "short",
    ctx,
    preamble: "",
    models: ["m1", "m2", "m3"],
    signal: new AbortController().signal,
    ask: async (m) => {
      seen.push(m);
      return m === "m1" ? "Sure! Here is the outline: {not json" : "```json\n" + JSON.stringify(OUTLINE) + "\n```";
    },
  });
  assert.deepEqual(seen, ["m1", "m2"]);
  assert.equal(r.calls, 2);
  assert.equal(r.model, "m2");
  // short = 4 body sections (extra dropped), ids renumbered, takeaways + references appended.
  assert.deepEqual(r.outline.sections.map((s) => s.id), ["s1", "s2", "s3", "s4", "takeaways", "references"]);
  assert.equal(r.outline.style, "guide");
});

test("outline: two invalid answers fail retryably; upstream errors move on", async () => {
  const seen: string[] = [];
  await assert.rejects(
    makeOutline({ prompt: "p", length: "short", ctx, preamble: "", models: ["m1", "m2", "m3"], signal: new AbortController().signal, ask: async (m) => (seen.push(m), "nope") }),
    OutlineError,
  );
  assert.deepEqual(seen, ["m1", "m2"]);
  const r = await makeOutline({
    prompt: "p",
    length: "standard",
    ctx,
    preamble: "",
    models: ["m1", "m2", "m3"],
    signal: new AbortController().signal,
    ask: async (m) => {
      if (m !== "m3") throw new UpstreamError(429, "rate limited");
      return JSON.stringify(OUTLINE);
    },
  });
  assert.equal(r.model, "m3");
  assert.throws(() => normalizeOutline({ sections: [{ heading: "Only one" }] }, "short", "t"), OutlineError);
});

// ---- section stream ---------------------------------------------------------------

test("section filter: drops a leading heading and hides the summary line across chunk splits", () => {
  const f = new SectionFilter();
  const chunks = ["## Intro", "duction\nTLS is a protocol.", " It encrypts. <", "!--sum", "mary: Covers TLS. Two-->", "\n"];
  const out = chunks.map((c) => f.push(c)).join("") + f.flush();
  assert.equal(out.trim(), "TLS is a protocol. It encrypts.");
  assert.equal(f.summary(), "Covers TLS. Two");
  assert.ok(!out.includes("<!--"));
});

test("section: streams deltas without the summary, strips invalid tags", async () => {
  const deltas: string[] = [];
  const r = await writeSection({
    messages: [{ role: "user", content: "x" }],
    candidates: ["m"],
    sources: [src("W1"), src("W2")],
    signal: new AbortController().signal,
    events: { start: () => {}, delta: (t) => deltas.push(t), reset: () => {}, notice: () => {} },
    runChat: streamOf(["TLS 1.3 removed RSA key exchange [W", "1]. Made up [W9]. Also 【W2】.\n", "<!--summary: A. B.-->"]),
    images: async () => [],
    canContinue: () => false,
  });
  const streamed = deltas.join("");
  assert.ok(!streamed.includes("[W9]") && !streamed.includes("summary"));
  assert.ok(streamed.includes("[W1]") && streamed.includes("[W2]"));
  assert.equal(r.summary, "A. B.");
  assert.deepEqual(r.usedIds, ["W1", "W2"]);
  assert.ok(!r.markdown.includes("[W9]"));
  assert.ok(r.evidence.some((e) => e.tag === "W1"));
  assert.equal(keepValidTags("a [K1] b [W3]", new Set(["W3"])), "a  b [W3]");
});

test("section: a length cut-off gets one continuation call", async () => {
  const calls: Message[][] = [];
  let n = 0;
  const runChat: RunChatFn = async (c, messages, _s, hooks) => {
    calls.push(messages);
    hooks.onModel(c[0], 1);
    if (n++ === 0) {
      hooks.onDelta("First half of the section about TLS");
      return { model: c[0], promptTokens: null, completionTokens: null, finishReason: "length" };
    }
    hooks.onDelta(" and the second half.\n<!--summary: Done.-->");
    return { model: c[0], promptTokens: null, completionTokens: null, finishReason: "stop" };
  };
  let budget = 1;
  const r = await writeSection({
    messages: [{ role: "user", content: "x" }],
    candidates: ["m"],
    sources: [],
    signal: new AbortController().signal,
    events: { start: () => {}, delta: () => {}, reset: () => {}, notice: () => {} },
    runChat,
    images: async () => [],
    canContinue: () => (budget > 0 ? (budget--, true) : false),
  });
  assert.equal(calls.length, 2);
  assert.match(calls[1][calls[1].length - 1].content, /First half of the section about TLS/);
  assert.equal(r.markdown, "First half of the section about TLS and the second half.");
  assert.equal(r.summary, "Done.");
  assert.equal(r.calls, 2);
});

// ---- pipeline ----------------------------------------------------------------------

test("pipeline: full run writes every section, takeaways and references", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  const events = await run(doc, "full", fakeDeps(store));
  const names = events.map((e) => e[0]);
  assert.equal(names[0], "doc_status");
  assert.ok(names.includes("doc_outline") && names.includes("doc_sources"));
  assert.equal(names.filter((n) => n === "doc_section_done").length, 4 + 2);
  assert.equal(names[names.length - 1], "doc_done");
  const saved = (await store.get(doc.userId, doc.id))!;
  assert.equal(saved.status, "done");
  assert.equal(saved.title, "HTTPS and TLS 1.3");
  const body = saved.sections.filter((s) => /^s\d$/.test(s.sectionId));
  assert.ok(body.every((s) => s.status === "done" && !s.markdown.includes("summary") && !s.markdown.includes("[W99]")));
  assert.equal(body[0].summary, "s1 done. Second sentence.");
  assert.match(saved.sections.find((s) => s.sectionId === "references")!.markdown, /^1\. \[W\d+\] \[R /);
  assert.match(saved.sections.find((s) => s.sectionId === "takeaways")!.markdown, /^- One\./);
  assert.equal(saved.summary, "An abstract.");
  assert.ok(saved.words > 0);
  // Section research: sources deduped by URL with stable ids.
  assert.deepEqual(saved.sources.map((s) => s.id), saved.sources.map((_, i) => `W${i + 1}`));
});

test("pipeline: a failing section leaves the doc partial; resume rewrites only that section", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  const failing = fakeDeps(store, {
    runChat: async (c, messages, _s, hooks) => {
      const k = /Write §(\d+)/.exec(messages[messages.length - 1].content)?.[1];
      if (k === "2") throw new ChatFailure("all_models_failed", "All models failed.", true);
      hooks.onModel(c[0], 1);
      hooks.onDelta(sectionBody(`s${k}`));
      return { model: c[0], promptTokens: null, completionTokens: null, finishReason: "stop" };
    },
  });
  const events = await run(doc, "full", failing);
  const failed = events.find((e) => e[0] === "doc_section_failed")!;
  assert.equal(failed[1].sectionId, "s2");
  assert.equal(events[events.length - 1][1].status, "partial");
  const partial = (await store.get(doc.userId, doc.id))!;
  assert.equal(partial.status, "partial");
  assert.equal(partial.sections.find((s) => s.sectionId === "s2")!.status, "failed");

  const written: string[] = [];
  const resumed = fakeDeps(store, {
    runChat: async (c, messages, _s, hooks) => {
      const k = /Write §(\d+)/.exec(messages[messages.length - 1].content)![1];
      written.push(`s${k}`);
      hooks.onModel(c[0], 1);
      hooks.onDelta(sectionBody(`s${k}`));
      return { model: c[0], promptTokens: null, completionTokens: null, finishReason: "stop" };
    },
  });
  await run(partial, "resume", resumed);
  assert.deepEqual(written, ["s2"]);
  assert.equal((await store.get(doc.userId, doc.id))!.status, "done");
});

test("pipeline: cancel stops the run and marks the doc partial", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  const job = registerJob(doc, "pipeline");
  const deps = fakeDeps(store, {
    runChat: async (c, _m, signal, hooks) => {
      hooks.onModel(c[0], 1);
      hooks.onDelta("Some text");
      job.cancelled = true;
      job.ctl.abort();
      if (signal.aborted) throw new DOMException("aborted", "AbortError");
      return { model: c[0], promptTokens: null, completionTokens: null, finishReason: "stop" };
    },
  });
  await runPipeline(job, "full", deps);
  finishJob(job);
  const saved = (await store.get(doc.userId, doc.id))!;
  assert.equal(saved.status, "partial");
});

test("pipeline: outline failure is a retryable doc_error and status failed", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  const events = await run(doc, "full", fakeDeps(store, { ask: async () => "no json here" }));
  const err = events.find((e) => e[0] === "doc_error")!;
  assert.equal(err[1].retryable, true);
  assert.equal((await store.get(doc.userId, doc.id))!.status, "failed");
});

test("rewrite: saves a revision, bumps the version, keeps the last 10", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  await run(doc, "full", fakeDeps(store));
  for (let i = 0; i < 12; i++) {
    const st = (await store.get(doc.userId, doc.id))!;
    const job = registerJob(st, "rewrite");
    await runRewrite(job, "s1", "shorten", {}, fakeDeps(store, { runChat: streamOf([`Short ${i} [W1].\n<!--summary: s.-->`]) }));
    finishJob(job);
  }
  const st = (await store.get(doc.userId, doc.id))!;
  assert.equal(st.version, 13);
  assert.equal(st.sections.find((s) => s.sectionId === "s1")!.markdown, "Short 11 [W1].");
  const revs = await store.revisions(doc.userId, doc.id, "s1");
  assert.equal(revs.length, MAX_REVISIONS);
  assert.equal(revs[0].markdown, "Short 11 [W1].");
  assert.equal(revs[0].reason, "shorten");
});

// ---- follow-ups: ask, selection edits, continue ---------------------------------------

test("followup: locateSpan finds a plain quote across marks and tags", () => {
  const md = "TLS 1.3 **removed RSA key** exchange [W1] and kept `ECDHE`.";
  const span = locateSpan(md, "removed RSA key exchange and kept ECDHE")!;
  assert.equal(md.slice(span.start, span.end), "**removed RSA key** exchange [W1] and kept `ECDHE`");
  assert.equal(locateSpan(md, "nothing like it"), null);
});

test("followup: ASK AI answers on the highlight's thread and never touches the section", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  await run(doc, "full", fakeDeps(store));
  const st = (await store.get(doc.userId, doc.id))!;
  const sec = st.sections.find((s) => s.sectionId === "s1")!;
  const before = sec.markdown;
  const seen: Message[][] = [];
  const deps = fakeDeps(store, { ask: async (_m, msgs) => (seen.push(msgs), "It means the key is never reused [W1] [W99].") });
  const entry = await answerQuestion(deps, st, sec, { quote: "RSA key exchange", question: "What does this mean?", thread: [] });
  assert.equal(entry.a, "It means the key is never reused [W1] .");
  assert.match(seen[0][seen[0].length - 1].content, /Question: What does this mean\?/);
  const h = (await store.addHighlight(st.userId, st.id, { sectionId: "s1", quote: "RSA key exchange", prefix: "", suffix: "", color: "ask", note: null }))!;
  const saved = (await store.appendThread(st.userId, st.id, h.id, entry))!;
  assert.equal(saved.thread.length, 1);
  assert.equal((await store.highlights(st.userId, st.id))[0].thread[0].q, "What does this mean?");
  assert.equal(await store.appendThread(randomUUID(), st.id, h.id, entry), null);
  assert.equal(sec.markdown, before);
});

test("followup: selection edit previews a replacement; explain inserts a note; failures are retryable", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  await run(doc, "full", fakeDeps(store));
  const st = (await store.get(doc.userId, doc.id))!;
  const sec = st.sections.find((s) => s.sectionId === "s1")!;
  const simple = await editSelection(fakeDeps(store, { ask: async () => "TLS 1.3 dropped RSA key swaps" }), st, sec, "simplify", "TLS 1.3 removed RSA key exchange", undefined);
  assert.equal(simple.original, "TLS 1.3 removed RSA key exchange");
  assert.ok(simple.markdown.includes("TLS 1.3 dropped RSA key swaps [W1]. Invented"));
  const note = await editSelection(fakeDeps(store, { ask: async () => "Forward secrecy means old traffic stays safe." }), st, sec, "explain", "RSA key exchange", undefined);
  assert.equal(note.original, "");
  assert.match(note.markdown, /\n\n> \[!NOTE\]\n> Forward secrecy/);
  await assert.rejects(editSelection(fakeDeps(store, { ask: async () => "x" }), st, sec, "simplify", "text that is not there", undefined), (e: any) => e.status === 422);
  await assert.rejects(
    editSelection(fakeDeps(store, { ask: async () => { throw new UpstreamError(429, "quota"); } }), st, sec, "simplify", "RSA key exchange", undefined),
    (e: any) => e.status === 502 && e.retryable === true,
  );
});

test("followup: continue plans a new section that can be added before takeaways", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  await run(doc, "full", fakeDeps(store));
  const st = (await store.get(doc.userId, doc.id))!;
  const plan = await planNextSection(fakeDeps(store, { ask: async () => '{"heading":"3. Session resumption","goal":"How 0-RTT works.","keyPoints":["PSK","0-RTT"]}' }), st, "resumption");
  assert.equal(plan.heading, "Session resumption");
  const last = st.outline!.sections.filter((s) => !s.kind).at(-1)!.id;
  const added = await addSection(store, st, last, plan.heading, plan.goal, plan.keyPoints);
  const ids = st.outline!.sections.map((s) => s.kind ?? s.id);
  assert.equal(ids.indexOf(added.sectionId), ids.indexOf("takeaways") - 1);
  assert.deepEqual(st.outline!.sections.find((s) => s.id === added.sectionId)!.keyPoints, ["PSK", "0-RTT"]);
});

// ---- highlights / export ------------------------------------------------------------

test("highlights: text-quote anchoring with prefix/suffix and orphans", () => {
  const text = "The cat sat. The cat ran.\nThe   dog sat.";
  assert.deepEqual(anchorQuote(text, { quote: "The cat" }), { start: 0, end: 7 });
  const second = anchorQuote(text, { quote: "The cat", prefix: "sat. ", suffix: " ran" })!;
  assert.equal(text.slice(second.start, second.end), "The cat");
  assert.equal(second.start, 13);
  const ws = anchorQuote(text, { quote: "The dog sat" })!;
  assert.equal(text.slice(ws.start, ws.end), "The   dog sat");
  assert.equal(anchorQuote(text, { quote: "a bird" }), null);
});

test("export: markdown and a valid docx zip", async () => {
  const store = memoryStore();
  const doc = await newDoc(store);
  await run(doc, "full", fakeDeps(store));
  const st = (await store.get(doc.userId, doc.id))!;
  st.sections[0].markdown += "\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```mermaid\nflowchart LR\n  A[\"x\"] --> B[\"y\"]\n```";
  const md = toMarkdown(st);
  assert.match(md, /^# HTTPS and TLS 1\.3/);
  assert.match(md, /## Key takeaways[\s\S]*## References/);
  const buf = await toDocx(st);
  assert.equal(buf.subarray(0, 2).toString(), "PK");
  assert.ok(buf.includes(Buffer.from("word/document.xml")));
});

// ---- database: isolation, limits, revisions -----------------------------------------

const dbReady = await new Promise<boolean>((resolve) => {
  if (!config.databaseUrl) return resolve(false);
  const timer = setTimeout(() => resolve(false), 8000);
  onDbUp(() => {
    clearTimeout(timer);
    resolve(true);
  });
  initDb();
});
after(() => closeDb());
const needsDb = { skip: dbReady ? false : "database not reachable" };

async function tempUser(limits: Record<string, number> = {}) {
  const u = await db().user.create({ data: { email: `doc-test-${randomUUID()}@example.test`, limits } });
  return u.id;
}

test("db: another user's document is not found (store and HTTP 404)", needsDb, async (t) => {
  const a = await tempUser();
  const b = await tempUser();
  t.after(() => db().user.deleteMany({ where: { id: { in: [a, b] } } }));
  const doc = await prismaStore.create({ userId: a, conversationId: null, prompt: "p", options: { length: "short", web: false, kb: false } });
  assert.ok(await prismaStore.get(a, doc.id));
  assert.equal(await prismaStore.get(b, doc.id), null);
  assert.equal((await prismaStore.list(b)).length, 0);
  assert.equal(await prismaStore.remove(b, doc.id), false);
  assert.equal(await prismaStore.addHighlight(b, doc.id, { sectionId: "s1", quote: "q", prefix: "", suffix: "", color: "yellow", note: null }), null);

  const { docsRouter } = await import("../src/routes/docs.js");
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = { id: String(req.headers["x-user"]), role: "user", sid: null, bypass: false };
    next();
  });
  app.use("/docs", docsRouter);
  app.use(errorMiddleware);
  const server = app.listen(0);
  t.after(() => server.close());
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/docs/${doc.id}`;
  for (const path of ["", "/events", "/export?format=md", "/highlights"]) {
    const res = await fetch(base + path, { headers: { "x-user": b } });
    assert.equal(res.status, 404, path);
  }
  assert.equal((await fetch(base, { method: "DELETE", headers: { "x-user": b } })).status, 404);
  assert.equal((await fetch(base, { headers: { "x-user": a } })).status, 200);
  const del = await fetch(`http://127.0.0.1:${(server.address() as AddressInfo).port}/docs/${doc.id}`, { method: "DELETE", headers: { "x-user": a } });
  assert.equal(del.status, 204);
});

test("db: docLimit counts per day and rejects over the limit; revisions keep the last 10", needsDb, async (t) => {
  const u = await tempUser({ docs: 2 });
  t.after(() => db().user.deleteMany({ where: { id: u } }));
  const call = () =>
    new Promise<unknown>((resolve) => {
      void docLimit({ user: { id: u, role: "user", sid: null, bypass: false } } as never, {} as never, (err?: unknown) => resolve(err));
    });
  assert.equal(await call(), undefined);
  assert.equal(await call(), undefined);
  const err = await call();
  assert.ok(err instanceof AppError && err.status === 429 && err.code === "daily_limit");

  const doc = await prismaStore.create({ userId: u, conversationId: null, prompt: "p", options: { length: "short", web: false, kb: false } });
  for (let i = 1; i <= 12; i++) await prismaStore.addRevision(u, doc.id, "s1", i, `v${i}`, "edit");
  const revs = await prismaStore.revisions(u, doc.id, "s1");
  assert.equal(revs.length, 10);
  assert.equal(revs[0].markdown, "v12");
  assert.equal(await db().docRevision.count({ where: { docId: doc.id } }), 10);
});
