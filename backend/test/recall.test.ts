import assert from "node:assert/strict";
import { test } from "node:test";
import { detectPastReference } from "../src/recall/detect.js";
import { buildChunks, diffChunks, MAX_TURNS } from "../src/recall/chunks.js";
import { searchSql, upsertSql } from "../src/recall/sql.js";
import { formatPastBlock, groupRows, AUTO_MIN_SIM, EXPLICIT_MIN_SIM } from "../src/recall/search.js";
import type { RecallRow } from "../src/recall/sql.js";

const UID = "11111111-1111-4111-8111-111111111111";
const CUR = "22222222-2222-4222-8222-222222222222";

test("past-reference detector: English cues", () => {
  const yes = [
    "Did we talk about Redis caching before?",
    "have we ever discussed my startup idea",
    "Last time we looked at the login bug, what was the fix?",
    "remember when you suggested Riverpod?",
    "As we discussed, the API should be versioned",
    "Earlier you said the index needs rebuilding. Why?",
    "You told me before that pgvector was fine",
    "What was in my previous chat about Docker?",
    "I asked you about this yesterday, can you find it",
    "Pick up where we left off",
    "do you remember our conversation about the resume?",
    "search through my old chats for the invoice template",
  ];
  for (const t of yes) assert.equal(detectPastReference(t).explicit, true, t);
  const no = [
    "How do I cache things in Redis?",
    "Remember that I like dark mode",
    "What was the last time zone change in India?",
    "Explain the difference between TCP and UDP",
    "hi",
    "We talked",
  ];
  for (const t of no) assert.equal(detectPastReference(t).explicit, false, t);
});

test("past-reference detector: Hinglish and Devanagari cues", () => {
  const yes = [
    "pehle humne Redis ke baare mein baat ki thi, wo kya tha?",
    "kya humne pehle is project par baat ki hai",
    "pichli baar maine tumse resume ke baare mein pucha tha",
    "tumne kaha tha ki index banana padega",
    "aapne bataya tha pehle wala solution",
    "hamari purani chat mein Docker setup tha",
    "yaad hai jab humne login flow banaya tha?",
    "पहले हमने इस बारे में बात की थी",
  ];
  for (const t of yes) assert.equal(detectPastReference(t).explicit, true, t);
  assert.equal(detectPastReference("mujhe Redis samjhao").explicit, false);
  assert.equal(detectPastReference("kal ka mausam kaisa rahega").explicit, false);
});

test("past-reference detector extracts the topic", () => {
  assert.equal(detectPastReference("Did we ever talk about Redis caching?").topic.toLowerCase().includes("redis caching"), true);
  assert.equal(detectPastReference("my previous chat about Docker networking").topic.toLowerCase(), "docker networking");
  assert.equal(detectPastReference("Last time we talked").explicit, true);
});

test("chunks: header plus one chunk per exchange, stable hashes, errors and placeholders skipped", () => {
  const msgs = [
    { role: "user", content: "How do I set up Redis?" },
    { role: "assistant", content: "Install it and run redis-server." },
    { role: "user", content: "(no message text, only attachments)" },
    { role: "assistant", content: "oops", isError: true },
    { role: "user", content: "And persistence?" },
    { role: "assistant", content: "Use AOF." },
  ];
  const a = buildChunks({ title: "Redis setup", summary: null, messages: msgs });
  assert.deepEqual(a.map((c) => [c.ord, c.kind]), [[0, "header"], [1, "turn"], [2, "turn"]]);
  assert.match(a[1].content, /^User: How do I set up Redis\?\nAssistant: Install it/);
  // Appending a message keeps earlier chunks identical.
  const b = buildChunks({ title: "Redis setup", messages: [...msgs, { role: "user", content: "Thanks" }, { role: "assistant", content: "Welcome" }] });
  assert.equal(b.length, 4);
  assert.deepEqual(b.slice(0, 3).map((c) => c.hash), a.map((c) => c.hash));
});

test("chunks: capped turns and diff only re-embeds what changed", () => {
  const many = Array.from({ length: (MAX_TURNS + 20) * 2 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `message ${i}` }));
  assert.equal(buildChunks({ title: "t", messages: many }).length, MAX_TURNS + 1);
  const first = buildChunks({ title: "t", messages: many.slice(0, 4) });
  const existing = new Map(first.map((c) => [c.ord, c.hash]));
  const grown = buildChunks({ title: "t", messages: many.slice(0, 6) });
  const d = diffChunks(existing, grown);
  assert.deepEqual(d.remove, []);
  assert.deepEqual(d.add.map((c) => c.ord), [3]);
  const edited = buildChunks({ title: "t", summary: "now with a summary", messages: many.slice(0, 4) });
  const d2 = diffChunks(existing, edited);
  assert.deepEqual(d2.remove, [0]);
  assert.deepEqual(d2.add.map((c) => c.ord), [0]);
  // A chat that shrank loses the surplus chunks.
  const d3 = diffChunks(new Map([[0, "x"], [1, "y"], [2, "z"]]), buildChunks({ title: "t", messages: [] }));
  assert.deepEqual(d3.remove.sort(), [0, 1, 2]);
});

test("search SQL is scoped to the user, excludes the current chat and archived chats", () => {
  const q = searchSql({ uid: UID, vec: [0.1, 0.2], excludeConversationId: CUR, limit: 10 });
  const sql = q.sql.replace(/\s+/g, " ");
  assert.match(sql, /cc\.user_id IS NOT DISTINCT FROM \?::uuid/);
  assert.match(sql, /c\.user_id IS NOT DISTINCT FROM \?::uuid/);
  assert.match(sql, /c\.archived_at IS NULL/);
  assert.match(sql, /cc\.conversation_id <> \?::uuid/);
  assert.ok(q.values.includes(UID));
  assert.ok(q.values.includes(CUR));
  assert.ok(q.values.includes("[0.1,0.2]"));
  assert.ok(q.values.includes(10));
  // The user filter comes first: a query can never be built without it.
  assert.ok(sql.indexOf("cc.user_id") < sql.indexOf("ORDER BY"));
});

test("search SQL: no exclusion clause without a current conversation, and null user scopes to unclaimed chats", () => {
  const q = searchSql({ uid: null, vec: [1], limit: 5 });
  assert.doesNotMatch(q.sql, /conversation_id <>/);
  assert.match(q.sql, /IS NOT DISTINCT FROM/);
  assert.deepEqual(q.values.slice(1, 3), [null, null]);
});

test("upsert SQL writes the owner on every chunk", () => {
  const q = upsertSql({ conversationId: CUR, uid: UID, ord: 1, kind: "turn", content: "x", hash: "h", vec: [0.5] });
  assert.match(q.sql, /user_id/);
  assert.match(q.sql, /ON CONFLICT \(conversation_id, ord\) DO UPDATE/);
  assert.ok(q.values.includes(UID));
});

const row = (id: string, sim: number, content: string, kind = "turn", title = "Chat " + id): RecallRow => ({
  conversation_id: id,
  ord: 1,
  kind,
  content,
  sim,
  title,
  updated_at: new Date("2026-10-12T10:00:00Z"),
});

test("grouping applies the similarity threshold and chat cap", () => {
  const rows = [row("a", 0.8, "User: x"), row("a", 0.7, "User: y"), row("a", 0.65, "User: z"), row("b", 0.6, "User: w"), row("c", 0.58, "User: v"), row("d", 0.4, "User: u")];
  const auto = groupRows(rows, { minSim: AUTO_MIN_SIM, maxChats: 2 });
  assert.deepEqual(auto.map((c) => c.id), ["a", "b"]);
  assert.equal(auto[0].excerpts.length, 2);
  assert.equal(groupRows([row("d", 0.4, "x")], { minSim: AUTO_MIN_SIM, maxChats: 2 }).length, 0);
  assert.equal(groupRows([row("d", 0.4, "x")], { minSim: EXPLICIT_MIN_SIM, maxChats: 4 }).length, 1);
});

test("past block: tags, date, chat: urls and budget", () => {
  const chats = groupRows([row("a", 0.8, "User: Redis?\nAssistant: Use AOF.", "turn", "Redis caching"), row("b", 0.7, "User: " + "long ".repeat(400))], { minSim: 0.5, maxChats: 3 });
  const out = formatPastBlock(chats, 3000)!;
  assert.match(out.block, /\[C1\] Chat "Redis caching" \(12 Oct 2026\)/);
  assert.match(out.block, /<past_conversations>/);
  assert.deepEqual(out.citations.map((c) => [c.id, c.url]), [["C1", "chat:a"], ["C2", "chat:b"]]);
  const tight = formatPastBlock(chats, 150)!;
  assert.equal(tight.citations.length, 1);
  assert.equal(formatPastBlock([], 1000), null);
});
