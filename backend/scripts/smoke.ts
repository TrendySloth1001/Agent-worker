/**
 * Black-box API smoke test against a running server (default http://localhost:3000).
 *
 *   pnpm exec tsx scripts/smoke.ts run <out.json>        # exercise the API, record responses
 *   pnpm exec tsx scripts/smoke.ts diff <a.json> <b.json> # compare two recordings (shapes + stable values)
 *
 * Uses the static API_TOKEN dev bypass (acts as the owner, or as the unclaimed
 * pre-accounts data while no owner exists). Everything it creates is removed
 * again: a throwaway conversation (+ fork + merge), two throwaway users (with a
 * note and a small file each), which are deleted through DELETE /auth/me.
 * Recordings can contain real conversation text: keep them out of the repo.
 */
import "dotenv/config";
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const BASE = process.env.SMOKE_BASE_URL ?? `http://localhost:${process.env.PORT ?? 3000}`;
const TOKEN = process.env.API_TOKEN ?? "";

type Rec = { status: number; body: unknown };
const recording: Record<string, Rec> = {};
const checks: Array<{ name: string; ok: boolean; detail?: string }> = [];

function check(name: string, ok: boolean, detail?: string) {
  checks.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail && !ok ? ` (${detail})` : ""}`);
}

async function call(method: string, path: string, opts: { token?: string; body?: unknown; form?: FormData } = {}): Promise<Rec> {
  const headers: Record<string, string> = {};
  const token = opts.token ?? TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;
  let body: BodyInit | undefined;
  if (opts.form) body = opts.form;
  else if (opts.body !== undefined) {
    headers["content-type"] = "application/json";
    body = JSON.stringify(opts.body);
  }
  const r = await fetch(BASE + path, { method, headers, body });
  const text = await r.text();
  let parsed: unknown = text;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    /* keep text */
  }
  return { status: r.status, body: parsed };
}

async function rec(key: string, method: string, path: string, opts: Parameters<typeof call>[2] = {}): Promise<Rec> {
  const r = await call(method, path, opts);
  recording[key] = r;
  return r;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Reads an SSE response until `done`/`error`; returns the event list. */
async function chatSse(body: unknown, token = TOKEN): Promise<Array<{ event: string; data: any }>> {
  const r = await fetch(BASE + "/chat", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const events: Array<{ event: string; data: any }> = [];
  if (!r.body) return events;
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
      const data = /^data: (.*)$/m.exec(block)?.[1];
      if (ev) events.push({ event: ev, data: data ? JSON.parse(data) : null });
      if (ev === "done" || ev === "error") {
        await reader.cancel().catch(() => {});
        return events;
      }
    }
  }
  return events;
}

async function run(out: string) {
  if (!TOKEN) throw new Error("API_TOKEN is not set");
  const health = await call("GET", "/health");
  check("health", health.status === 200);

  // ---- owner / dev bypass ------------------------------------------------
  await rec("authMe", "GET", "/auth/me");
  await rec("usage", "GET", "/usage");
  const list = await rec("conversations", "GET", "/conversations");
  await rec("conversationsArchived", "GET", "/conversations?archived=1");
  await rec("conversationsSearch", "GET", "/conversations?q=the&limit=5");
  const convs = ((list.body as any)?.conversations ?? []) as Array<{ id: string }>;
  check("list conversations", list.status === 200 && Array.isArray(convs));

  if (convs[0]) {
    const one = await rec("conversationOne", "GET", `/conversations/${convs[0].id}`);
    check("get one conversation", one.status === 200);
  }
  // Find an existing file through saved attachments.
  let fileId: string | null = null;
  for (const c of convs.slice(0, 30)) {
    const r = await call("GET", `/conversations/${c.id}`);
    for (const m of ((r.body as any)?.messages ?? []) as any[]) {
      for (const a of m.attachments ?? []) {
        const f = await call("GET", `/files/${a.id}`);
        if (f.status === 200) {
          fileId = a.id;
          break;
        }
      }
      if (fileId) break;
    }
    if (fileId) break;
  }
  if (fileId) {
    const f = await rec("fileExisting", "GET", `/files/${fileId}`);
    check("get existing file", f.status === 200);
    await rec("fileExistingText", "GET", `/files/${fileId}/text?limit=200`);
  } else {
    console.log("SKIP no existing file attachment found");
  }
  await rec("fileMissing", "GET", `/files/${randomUUID()}`);

  // ---- knowledge ---------------------------------------------------------
  const sources = await rec("knowledgeSources", "GET", "/knowledge/sources");
  check("knowledge list", sources.status === 200);
  const firstSource = ((sources.body as any)?.sources ?? [])[0];
  if (firstSource) await rec("knowledgeSourceOne", "GET", `/knowledge/sources/${firstSource.id}`);
  await rec("knowledgeStats", "GET", "/knowledge/stats");
  const search = await rec("knowledgeSearch", "POST", "/knowledge/search", { body: { query: "how does this work", k: 4 } });
  check("knowledge search", search.status === 200, JSON.stringify(search.body).slice(0, 200));

  // ---- throwaway conversation lifecycle -----------------------------------
  const id = randomUUID();
  const messages = [
    {
      role: "user",
      content: "Smoke test question: what is 2+2?",
      attachments: [],
      meta: { smoke: true },
    },
    {
      role: "assistant",
      content: "2+2 is 4.",
      model: "smoke:model",
      citations: [{ id: "S1", kind: "web", title: "Math", url: "https://example.com/math", snippet: "2+2=4", site: "example.com", extra: 1 }],
      usedIds: ["S1"],
      images: [{ url: "https://example.com/a.png", sourceUrl: "https://example.com", title: "A", site: "example.com" }],
      evidence: [{ tag: "S1", claim: "2+2 is 4", quote: "2+2=4", score: 0.9 }],
      isError: false,
      table: { seats: [{ model: "m1", answer: "4" }], reviews: [], unresolved: ["none"] },
    },
    { role: "user", content: "and 3+3?" },
    { role: "assistant", content: "Something went wrong", isError: true },
  ];
  const put = await rec("convPut", "PUT", `/conversations/${id}`, { body: { messages } });
  check("put new conversation", put.status === 200 && (put.body as any)?.id === id, JSON.stringify(put.body).slice(0, 200));
  const got = await rec("convGet", "GET", `/conversations/${id}`);
  const gm = (got.body as any)?.messages ?? [];
  check(
    "messages round-trip",
    gm.length === 4 &&
      gm[1].citations?.[0]?.extra === 1 &&
      gm[1].table?.unresolved?.[0] === "none" &&
      gm[0].meta?.smoke === true &&
      gm[3].isError === true &&
      gm[2].model === null &&
      Array.isArray(gm[2].usedIds),
    JSON.stringify(gm).slice(0, 300),
  );
  // second PUT (update path, 5 messages)
  const put2 = await rec("convPut2", "PUT", `/conversations/${id}`, {
    body: { messages: [...messages.slice(0, 3), { role: "assistant", content: "3+3 is 6." }, { role: "user", content: "thanks" }] },
  });
  check("put existing conversation", put2.status === 200 && (put2.body as any)?.messageCount === 5);
  const pin = await rec("convPin", "PATCH", `/conversations/${id}`, { body: { pinned: true } });
  check("pin", (pin.body as any)?.pinned === true);
  const rename = await rec("convRename", "PATCH", `/conversations/${id}`, { body: { title: "Smoke throwaway" } });
  check("rename", (rename.body as any)?.title === "Smoke throwaway" && (rename.body as any)?.titleSource === "user");
  const pinnedList = await call("GET", "/conversations");
  check("pinned first", (pinnedList.body as any)?.conversations?.[0]?.id === id);
  const fork = await rec("convFork", "POST", `/conversations/${id}/fork`, { body: { at: 2 } });
  const forkId = (fork.body as any)?.id as string | undefined;
  check(
    "fork",
    fork.status === 201 && (fork.body as any)?.messages?.length === 2 && (fork.body as any)?.parent?.id === id && (fork.body as any)?.messages?.[1]?.table?.seats?.length === 1,
    JSON.stringify(fork.body).slice(0, 200),
  );
  await rec("convForkBad", "POST", `/conversations/${id}/fork`, { body: { at: 99 } });
  const merge = await rec("convMerge", "POST", "/conversations/merge", { body: { ids: [id, forkId] } });
  const mergeId = (merge.body as any)?.id as string | undefined;
  check("merge", merge.status === 201 && (merge.body as any)?.messages?.[0]?.role === "context" && (merge.body as any)?.mergedFrom?.length === 2);
  const archive = await rec("convArchive", "PATCH", `/conversations/${id}`, { body: { archived: true } });
  check("archive unpins", (archive.body as any)?.archived === true && (archive.body as any)?.pinned === false);
  const archivedList = await call("GET", "/conversations?archived=1");
  check("archived listed", ((archivedList.body as any)?.conversations ?? []).some((c: any) => c.id === id));
  const forkAfter = await rec("convForkAfterArchive", "GET", `/conversations/${forkId}`);
  check("fork parent title", (forkAfter.body as any)?.parent?.title === "Smoke throwaway");
  for (const x of [mergeId, forkId, id]) if (x) await call("DELETE", `/conversations/${x}`);
  const gone = await rec("convGone", "GET", `/conversations/${id}`);
  check("deleted -> 404", gone.status === 404);
  await rec("convBadId", "GET", "/conversations/not-a-uuid");

  // ---- chat SSE ------------------------------------------------------------
  const events = await chatSse({ messages: [{ role: "user", content: "say hi in 3 words" }], knowledge: true, webSearch: false });
  const names = events.map((e) => e.event);
  const done = events.find((e) => e.event === "done");
  const reply = events.filter((e) => e.event === "delta").map((e) => e.data.text).join("");
  recording.chat = {
    status: 200,
    body: { events: [...new Set(names)], done: done?.data ?? null, start: events.find((e) => e.event === "start")?.data ?? null, replyChars: reply.length },
  };
  check("chat SSE done", !!done && reply.length > 0, names.join(","));

  // ---- two throwaway users: isolation -------------------------------------
  const stamp = Date.now().toString(36);
  const users = ["a", "b"].map((k) => ({ email: `smoke-${k}-${stamp}@example.test`, password: `smoke-pass-${stamp}`, name: `Smoke ${k.toUpperCase()}` }));
  const sessions: any[] = [];
  for (const [i, u] of users.entries()) {
    const r = await rec(`register${i}`, "POST", "/auth/register", { token: "", body: { ...u, device: "smoke" } });
    check(`register user ${i}`, r.status === 201 && (r.body as any)?.user?.role === "user", JSON.stringify(r.body).slice(0, 200));
    sessions.push(r.body);
  }
  const [A, B] = sessions;
  if (A?.accessToken && B?.accessToken) {
    const ta = A.accessToken as string;
    const tb = B.accessToken as string;
    await rec("userMe", "GET", "/auth/me", { token: ta });
    const patched = await rec("userPatch", "PATCH", "/auth/me", { token: ta, body: { name: "Smoke A2" } });
    check("patch me", (patched.body as any)?.user?.name === "Smoke A2");
    const login = await rec("userLogin", "POST", "/auth/login", { token: "", body: { email: users[0].email.toUpperCase(), password: users[0].password, device: "smoke2" } });
    check("login (citext email)", login.status === 200);
    const badLogin = await rec("userBadLogin", "POST", "/auth/login", { token: "", body: { email: users[0].email, password: "wrong-password" } });
    check("bad login 401", badLogin.status === 401);
    const dup = await rec("userDupRegister", "POST", "/auth/register", { token: "", body: users[0] });
    check("duplicate register 400", dup.status === 400);
    const refreshed = await rec("userRefresh", "POST", "/auth/refresh", { token: "", body: { refreshToken: A.refreshToken } });
    check("refresh", refreshed.status === 200 && (refreshed.body as any)?.sessionId === A.sessionId);
    const reuse = await call("POST", "/auth/refresh", { token: "", body: { refreshToken: A.refreshToken } });
    check("refresh reuse within grace -> 401", reuse.status === 401);
    const ta2 = (refreshed.body as any)?.accessToken ?? ta;
    const sess = await rec("userSessions", "GET", "/auth/sessions", { token: ta2 });
    check("sessions list", ((sess.body as any)?.sessions ?? []).length === 2);

    const cid = randomUUID();
    const aPut = await rec("userAPut", "PUT", `/conversations/${cid}`, { token: ta2, body: { messages: [{ role: "user", content: "private to A" }] } });
    check("A creates conversation", aPut.status === 200);
    check("A reads own", (await call("GET", `/conversations/${cid}`, { token: ta2 })).status === 200);
    check("B cannot read A's conversation (404)", (await call("GET", `/conversations/${cid}`, { token: tb })).status === 404);
    check("B cannot overwrite A's conversation (404)", (await call("PUT", `/conversations/${cid}`, { token: tb, body: { messages: [{ role: "user", content: "hijack" }] } })).status === 404);
    check("B cannot patch A's conversation (404)", (await call("PATCH", `/conversations/${cid}`, { token: tb, body: { title: "x" } })).status === 404);
    check("B cannot fork A's conversation (404)", (await call("POST", `/conversations/${cid}/fork`, { token: tb, body: { at: 1 } })).status === 404);
    await call("DELETE", `/conversations/${cid}`, { token: tb });
    const stillThere = await call("GET", `/conversations/${cid}`, { token: ta2 });
    check("B's delete did not touch A's conversation", stillThere.status === 200 && (stillThere.body as any)?.messages?.[0]?.content === "private to A");
    const bList = await call("GET", "/conversations", { token: tb });
    check("B's list is empty", ((bList.body as any)?.conversations ?? []).length === 0);
    const ownerList = await call("GET", "/conversations");
    check("owner/bypass list excludes A's chat", !((ownerList.body as any)?.conversations ?? []).some((c: any) => c.id === cid));

    // note + file isolation
    const note = await rec("userANote", "POST", "/knowledge/notes", { token: ta2, body: { content: `Smoke note ${stamp}: the purple elephant lives in Oslo.` } });
    const noteId = (note.body as any)?.source?.id;
    check("A saves note", note.status === 202 && !!noteId);
    check("B cannot read A's source (404)", (await call("GET", `/knowledge/sources/${noteId}`, { token: tb })).status === 404);
    const bSources = await call("GET", "/knowledge/sources", { token: tb });
    check("B's sources empty", ((bSources.body as any)?.sources ?? []).length === 0);
    for (let i = 0; i < 30; i++) {
      const s = await call("GET", `/knowledge/sources/${noteId}`, { token: ta2 });
      if (["ready", "failed"].includes((s.body as any)?.source?.status)) break;
      await sleep(1000);
    }
    const noteDone = await rec("userANoteDone", "GET", `/knowledge/sources/${noteId}`, { token: ta2 });
    check("note ingested", (noteDone.body as any)?.source?.status === "ready", JSON.stringify(noteDone.body).slice(0, 200));
    const aSearch = await rec("userASearch", "POST", "/knowledge/search", { token: ta2, body: { query: "where does the purple elephant live" } });
    check("A finds own note", ((aSearch.body as any)?.results ?? []).some((h: any) => /purple elephant/.test(h.content)));
    const bSearch = await call("POST", "/knowledge/search", { token: tb, body: { query: "where does the purple elephant live" } });
    check("B does not find A's note", !((bSearch.body as any)?.results ?? []).some((h: any) => /purple elephant/.test(h.content)));
    await rec("userAStats", "GET", "/knowledge/stats", { token: ta2 });

    const form = new FormData();
    form.append("file", new Blob([`hello smoke ${stamp}\nline two`], { type: "text/plain" }), "smoke.txt");
    form.append("conversationId", cid);
    const up = await rec("userAUpload", "POST", "/files", { token: ta2, form });
    const fid = (up.body as any)?.file?.id;
    check("A uploads file", up.status === 201 && !!fid, JSON.stringify(up.body).slice(0, 200));
    if (fid) {
      for (let i = 0; i < 20; i++) {
        const f = await call("GET", `/files/${fid}`, { token: ta2 });
        if ((f.body as any)?.file?.status !== "processing") break;
        await sleep(500);
      }
      await rec("userAFile", "GET", `/files/${fid}`, { token: ta2 });
      const txt = await rec("userAFileText", "GET", `/files/${fid}/text`, { token: ta2 });
      check("A reads file text", (txt.body as any)?.text?.includes("hello smoke"));
      check("B cannot read A's file (404)", (await call("GET", `/files/${fid}`, { token: tb })).status === 404);
      check("B cannot delete A's file (404)", (await call("DELETE", `/files/${fid}`, { token: tb })).status === 404);
      check("bypass cannot read A's file (404)", (await call("GET", `/files/${fid}`)).status === 404);
    }
    // Large document: chunked + embedded into file_chunks; a chat about it reads a vector excerpt
    // and counts against A's daily limits (conditional upsert).
    const filler = Array.from({ length: 400 }, (_, i) => `Paragraph ${i}: the warehouse inventory lists ${i * 7} crates of assorted parts.`).join("\n");
    const big = `${filler.slice(0, 9000)}\nThe secret code word is ZEPHYR-42.\n${filler.slice(9000)}`;
    const bigForm = new FormData();
    bigForm.append("file", new Blob([big], { type: "text/plain" }), "inventory.txt");
    const bigUp = await rec("userABigUpload", "POST", "/files", { token: ta2, form: bigForm });
    const bigId = (bigUp.body as any)?.file?.id as string | undefined;
    let bigFile: any = null;
    for (let i = 0; bigId && i < 60; i++) {
      bigFile = (await call("GET", `/files/${bigId}`, { token: ta2 })).body;
      if (bigFile?.file?.status !== "processing") break;
      await sleep(1000);
    }
    check("large document chunked", bigFile?.file?.status === "ready" && (bigFile?.file?.meta?.chars ?? 0) > 12_000, JSON.stringify(bigFile).slice(0, 200));
    const meBefore = await call("GET", "/auth/me", { token: ta2 });
    const docChat = await chatSse(
      { messages: [{ role: "user", content: "What is the secret code word in the attached document? Answer with the code word only.", attachments: [bigId] }], knowledge: false, webSearch: false },
      ta2,
    );
    const docReply = docChat.filter((e) => e.event === "delta").map((e) => e.data.text).join("");
    check("chat with large document", docChat.some((e) => e.event === "done"), docChat.map((e) => e.event).join(","));
    check("answer comes from the vector excerpt", /ZEPHYR/i.test(docReply), docReply.slice(0, 120));
    const meAfterChat = await call("GET", "/auth/me", { token: ta2 });
    check("chat counted for limited user", (meAfterChat.body as any)?.usage?.chats === ((meBefore.body as any)?.usage?.chats ?? 0) + 1);
    check("limits object for normal user", typeof (meAfterChat.body as any)?.limits?.chat === "number" && (meAfterChat.body as any)?.unlimited === false);

    // Shared attachment: deleting the original chat keeps a file its fork still uses.
    const att = { id: bigId, name: "inventory.txt", mime: "text/plain", size: big.length, kind: "document", status: "ready", meta: {} };
    const c1 = randomUUID();
    await call("PUT", `/conversations/${c1}`, { token: ta2, body: { messages: [{ role: "user", content: "see file", attachments: [att] }, { role: "assistant", content: "ok" }] } });
    const f1 = await call("POST", `/conversations/${c1}/fork`, { token: ta2, body: { at: 1 } });
    const f1Id = (f1.body as any)?.id;
    check("fork keeps attachment", (f1.body as any)?.messages?.[0]?.attachments?.[0]?.id === bigId);
    await call("DELETE", `/conversations/${c1}`, { token: ta2 });
    check("shared file survives deleting original", (await call("GET", `/files/${bigId}`, { token: ta2 })).status === 200);
    await call("DELETE", `/conversations/${f1Id}`, { token: ta2 });
    check("file deleted with its last chat", (await call("GET", `/files/${bigId}`, { token: ta2 })).status === 404);

    // Sessions: a password change signs out other devices; a session can be revoked; logout.
    const other = await call("POST", "/auth/login", { token: "", body: { email: users[0].email, password: users[0].password, device: "other" } });
    const otherAccess = (other.body as any)?.accessToken;
    check("other device signed in", (await call("GET", "/auth/me", { token: otherAccess })).status === 200);
    const newPassword = `${users[0].password}-2`;
    const pw = await call("POST", "/auth/password", { token: ta2, body: { current: users[0].password, next: newPassword } });
    check("password changed", pw.status === 204);
    users[0].password = newPassword;
    check("other device signed out", (await call("GET", "/auth/me", { token: otherAccess })).status === 401);
    check("this device still signed in", (await call("GET", "/auth/me", { token: ta2 })).status === 200);
    const third = await call("POST", "/auth/login", { token: "", body: { email: users[0].email, password: newPassword, device: "third" } });
    const thirdSid = (third.body as any)?.sessionId;
    const delSess = await call("DELETE", `/auth/sessions/${thirdSid}`, { token: ta2 });
    check("revoke a session", delSess.status === 204 && (await call("GET", "/auth/me", { token: (third.body as any)?.accessToken })).status === 401);
    check("revoke unknown session 404", (await call("DELETE", `/auth/sessions/${randomUUID()}`, { token: ta2 })).status === 404);
    const fourth = await call("POST", "/auth/login", { token: "", body: { email: users[0].email, password: newPassword, device: "fourth" } });
    const logout = await call("POST", "/auth/logout", { token: "", body: { refreshToken: (fourth.body as any)?.refreshToken } });
    check("logout", logout.status === 204 && (await call("POST", "/auth/refresh", { token: "", body: { refreshToken: (fourth.body as any)?.refreshToken } })).status === 401);

    await rec("userAMeAfter", "GET", "/auth/me", { token: ta2 });

    // cleanup: deleting the accounts cascades conversations, sources, files, sessions, usage
    const wrong = await call("DELETE", "/auth/me", { token: ta2, body: { password: "nope-nope" } });
    check("delete with wrong password 400", wrong.status === 400);
    const delA = await call("DELETE", "/auth/me", { token: ta2, body: { password: users[0].password } });
    const delB = await call("DELETE", "/auth/me", { token: tb, body: { password: users[1].password } });
    check("delete users", delA.status === 204 && delB.status === 204);
    check("deleted user token rejected", (await call("GET", "/auth/me", { token: ta2 })).status === 401);
    check("deleted user cannot log in", (await call("POST", "/auth/login", { token: "", body: { email: users[0].email, password: users[0].password } })).status === 401);
  }

  const failed = checks.filter((c) => !c.ok);
  writeFileSync(out, JSON.stringify({ at: new Date().toISOString(), checks, recording }, null, 2));
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed; recording written to ${out}`);
  if (failed.length) process.exitCode = 1;
}

// ---- diff ------------------------------------------------------------------

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
// Values that legitimately change between runs (counters, tokens, LLM text, signed URLs).
const VOLATILE_KEY = /^(requests|texts|requestsToday|tokensToday|tokens|accessToken|refreshToken|accessExpiresAt|refreshExpiresAt|sessionId|url|thumbUrl|uptimeS|latencyMs|requestId|replyChars|email|name|content|title|preview|text|chars|uri|used|remaining|todayRequests|todayTokens|monthRequests|monthTokens|todayFailures|todayTexts|lastLimitHitAt|resetsAt|chats|tables|uploads|bytes|storageBytes|model|finishReason|candidates|mergedFrom|score|chunkId|headingPath|sourceType|summarySource|messageCount|createdAt|updatedAt|lastUsedAt|expiresAt|lastIngestedAt|lastLoginAt|limit|tokens|chunks|sources|documents|docCount|chunkCount|progress)$/;

function shape(v: unknown): unknown {
  if (Array.isArray(v)) {
    const kinds = [...new Set(v.map((x) => JSON.stringify(shape(x))))].map((s) => JSON.parse(s));
    return kinds.length ? kinds : ["<empty>"];
  }
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, shape((v as any)[k])]));
  if (typeof v === "string") return UUID.test(v) ? "uuid" : ISO.test(v) ? "iso" : "string";
  return v === null ? "null" : typeof v;
}

// Reads of existing data: compared exactly, except presigned URLs.
const STABLE = new Set(["conversations", "conversationsArchived", "conversationsSearch", "conversationOne", "fileExisting", "fileExistingText", "fileMissing", "knowledgeSources", "knowledgeSourceOne", "knowledgeStats", "knowledgeSearch", "authMe", "convBadId", "convGone", "convForkBad"]);

function norm(v: unknown, strict: boolean, key = ""): unknown {
  if (Array.isArray(v)) return v.map((x) => norm(x, strict, key));
  if (v && typeof v === "object") return Object.fromEntries(Object.keys(v).sort().map((k) => [k, norm((v as any)[k], strict, k)]));
  if (strict) return key === "url" || key === "thumbUrl" ? "<signed>" : v;
  if (VOLATILE_KEY.test(key)) return "<volatile>";
  if (typeof v === "string" && (UUID.test(v) || ISO.test(v))) return "<id/ts>";
  return v;
}

function walk(a: unknown, b: unknown, path: string, out: string[]) {
  if (JSON.stringify(a) === JSON.stringify(b)) return;
  if (a && b && typeof a === "object" && typeof b === "object" && !Array.isArray(a) && !Array.isArray(b)) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) walk((a as any)[k], (b as any)[k], `${path}.${k}`, out);
    return;
  }
  if (Array.isArray(a) && Array.isArray(b) && a.length === b.length) {
    a.forEach((x, i) => walk(x, b[i], `${path}[${i}]`, out));
    return;
  }
  out.push(`${path}: ${JSON.stringify(a)?.slice(0, 160)} -> ${JSON.stringify(b)?.slice(0, 160)}`);
}

function diff(fa: string, fb: string) {
  const A = JSON.parse(readFileSync(fa, "utf8"));
  const B = JSON.parse(readFileSync(fb, "utf8"));
  let problems = 0;
  for (const key of [...new Set([...Object.keys(A.recording), ...Object.keys(B.recording)])].sort()) {
    const a = A.recording[key];
    const b = B.recording[key];
    if (!a || !b) {
      console.log(`~ ${key}: only in ${a ? "before" : "after"}`);
      continue;
    }
    const lines: string[] = [];
    if (a.status !== b.status) lines.push(`status ${a.status} -> ${b.status}`);
    const sd: string[] = [];
    walk(shape(a.body), shape(b.body), "", sd);
    for (const l of sd) lines.push(`shape ${l}`);
    const vd: string[] = [];
    walk(norm(a.body, STABLE.has(key)), norm(b.body, STABLE.has(key)), "", vd);
    for (const l of vd) lines.push(`value ${l}`);
    if (lines.length) {
      problems++;
      console.log(`! ${key}\n    ${lines.slice(0, 20).join("\n    ")}`);
    } else console.log(`= ${key} (${a.status})`);
  }
  const fa2 = (A.checks as any[]).filter((c) => !c.ok).map((c) => c.name);
  const fb2 = (B.checks as any[]).filter((c) => !c.ok).map((c) => c.name);
  console.log(`\nchecks: before ${A.checks.length - fa2.length}/${A.checks.length}, after ${B.checks.length - fb2.length}/${B.checks.length}`);
  if (fb2.length) console.log(`failing after: ${fb2.join("; ")}`);
  console.log(`${problems} endpoint(s) differ`);
}

const [mode, x, y] = process.argv.slice(2);
if (mode === "run" && x) await run(x);
else if (mode === "diff" && x && y) diff(x, y);
else {
  console.error("usage: smoke.ts run <out.json> | diff <before.json> <after.json>");
  process.exit(2);
}
