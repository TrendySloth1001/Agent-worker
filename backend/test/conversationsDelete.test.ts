import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import express from "express";
import type { AddressInfo } from "node:net";
import { closeDb, db, initDb, onDbUp } from "../src/db/prisma.js";
import { config } from "../src/config.js";
import { runAs } from "../src/auth/context.js";
import { errorMiddleware } from "../src/util/errors.js";
import { attachmentIds, chunks, deleteConversations } from "../src/conversations/delete.js";
import { BULK_DELETE_MAX, bulkDeleteSchema, conversationsRouter } from "../src/routes/conversations.js";

// ---- pure ----------------------------------------------------------------------

test("attachmentIds: ids of attachment objects only, numbers as JSON text", () => {
  const ids = attachmentIds([
    { attachments: [{ id: "a" }, { id: 7 }, { name: "no id" }, null, ["x"], { id: null }] },
    { attachments: "not an array" },
    { attachments: [{ id: "a" }, { id: "b" }] },
  ]);
  assert.deepEqual([...ids].sort(), ["7", "a", "b"]);
});

test("chunks splits evenly with a short tail", () => {
  assert.deepEqual(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepEqual(chunks([], 3), []);
});

test("bulkDeleteSchema: ids (uuid, 1..max) or all with defaults; nothing else", () => {
  const id = randomUUID();
  assert.deepEqual(bulkDeleteSchema.parse({ ids: [id] }), { ids: [id] });
  assert.deepEqual(bulkDeleteSchema.parse({ all: true }), { all: true, includeArchived: true, includePinned: true, archivedOnly: false });
  assert.equal((bulkDeleteSchema.parse({ all: true, includePinned: false }) as { includePinned: boolean }).includePinned, false);
  assert.throws(() => bulkDeleteSchema.parse({ ids: [] }));
  assert.throws(() => bulkDeleteSchema.parse({ ids: ["nope"] }));
  assert.throws(() => bulkDeleteSchema.parse({ ids: Array.from({ length: BULK_DELETE_MAX + 1 }, () => randomUUID()) }));
  assert.throws(() => bulkDeleteSchema.parse({ all: false }));
  assert.throws(() => bulkDeleteSchema.parse({}));
});

// ---- database ------------------------------------------------------------------

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

async function tempUser() {
  return (await db().user.create({ data: { email: `bulk-delete-test-${randomUUID()}@example.test` } })).id;
}
async function chat(userId: string, opts: { pinned?: boolean; archived?: boolean; attachments?: string[] } = {}) {
  const id = randomUUID();
  await db().conversation.create({
    data: {
      id,
      userId,
      title: "t",
      messageCount: 1,
      pinnedAt: opts.pinned ? new Date() : null,
      archivedAt: opts.archived ? new Date() : null,
      messages: { create: { position: 0, role: "user", content: "hi", attachments: (opts.attachments ?? []).map((f) => ({ id: f, name: "f.txt", kind: "document" })) } },
    },
  });
  return id;
}
async function file(userId: string, conversationId: string) {
  const id = randomUUID();
  await db().storedFile.create({ data: { id, userId, conversationId, name: "f.txt", mime: "text/plain", size: 1n, kind: "document", status: "ready", s3Key: `${id}/original.txt` } });
  return id;
}
const exists = async (ids: string[]) => (await db().conversation.findMany({ where: { id: { in: ids } }, select: { id: true } })).map((r) => r.id).sort();

test("db: deleteConversations removes only the caller's chats and their files; shared files move", needsDb, async (t) => {
  const a = await tempUser();
  const b = await tempUser();
  t.after(() => db().user.deleteMany({ where: { id: { in: [a, b] } } }));
  const c1 = await chat(a);
  const f1 = await file(a, c1);
  await db().conversationMessage.update({ where: { conversationId_position: { conversationId: c1, position: 0 } }, data: { attachments: [{ id: f1, name: "f.txt" }] } });
  const c2 = await chat(a);
  const shared = await file(a, c2);
  await db().conversationMessage.update({ where: { conversationId_position: { conversationId: c2, position: 0 } }, data: { attachments: [{ id: shared }] } });
  const fork = await chat(a, { attachments: [shared] }); // a fork that still uses c2's file
  const theirs = await chat(b);

  const n = await deleteConversations([c1, c2, theirs, c1], a);
  assert.equal(n, 2);
  assert.deepEqual(await exists([c1, c2, fork, theirs]), [fork, theirs].sort());
  assert.equal(await db().conversationMessage.count({ where: { conversationId: { in: [c1, c2] } } }), 0);
  assert.equal(await db().storedFile.count({ where: { id: f1 } }), 0); // only used in c1: deleted
  const moved = await db().storedFile.findUnique({ where: { id: shared }, select: { conversationId: true } });
  assert.equal(moved?.conversationId, fork); // still used by the fork: kept, now owned by it
  assert.equal(await deleteConversations([theirs], a), 0);
});

test("db: POST /conversations/bulk-delete by ids and all with filters", needsDb, async (t) => {
  const a = await tempUser();
  const b = await tempUser();
  t.after(() => db().user.deleteMany({ where: { id: { in: [a, b] } } }));
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.user = { id: String(req.headers["x-user"]), role: "user", sid: null, bypass: false };
    runAs(req.user, next);
  });
  app.use("/conversations", conversationsRouter);
  app.use(errorMiddleware);
  const server = app.listen(0);
  t.after(() => server.close());
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/conversations/bulk-delete`;
  const post = async (user: string, body: unknown) => {
    const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json", "x-user": user }, body: JSON.stringify(body) });
    return { status: res.status, body: (await res.json()) as Record<string, unknown> };
  };

  const one = await chat(a);
  const two = await chat(a);
  const theirs = await chat(b);
  assert.equal((await post(a, { ids: ["not-a-uuid"] })).status, 400);
  assert.deepEqual((await post(a, { ids: [one, theirs] })).body, { deleted: 1 });
  assert.deepEqual(await exists([one, two, theirs]), [two, theirs].sort());

  const pinned = await chat(a, { pinned: true });
  const archived = await chat(a, { archived: true });
  // Keep pinned, skip archived: only the plain chat goes.
  assert.deepEqual((await post(a, { all: true, includeArchived: false, includePinned: false })).body, { deleted: 1 });
  assert.deepEqual(await exists([two, pinned, archived]), [pinned, archived].sort());
  assert.deepEqual((await post(a, { all: true, archivedOnly: true })).body, { deleted: 1 });
  assert.deepEqual((await post(a, { all: true })).body, { deleted: 1 });
  assert.deepEqual(await exists([pinned, archived, theirs]), [theirs]);
});
