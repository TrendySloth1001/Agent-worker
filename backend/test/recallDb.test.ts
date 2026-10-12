import { after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { closeDb, db, initDb, onDbUp, tx } from "../src/db/prisma.js";
import { config } from "../src/config.js";
import { searchSql, upsertSql, type RecallRow } from "../src/recall/sql.js";
import { chatRecallEnabled, setChatRecallEnabled } from "../src/recall/index.js";

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

/** A 1024-dim unit vector along axis [i] (orthogonal for different i). */
const axis = (i: number) => Array.from({ length: 1024 }, (_, k) => (k === i ? 1 : 0));

async function tempUser() {
  return (await db().user.create({ data: { email: `recall-test-${randomUUID()}@example.test` } })).id;
}
async function chat(userId: string, title: string, archived = false) {
  const id = randomUUID();
  await db().conversation.create({ data: { id, userId, title, messageCount: 1, archivedAt: archived ? new Date() : null } });
  return id;
}
async function chunk(conversationId: string, uid: string, ord: number, vec: number[], content = `chunk ${ord}`) {
  await db().$executeRaw(upsertSql({ conversationId, uid, ord, kind: ord === 0 ? "header" : "turn", content, hash: `h${ord}`, vec }));
}
const search = (uid: string, vec: number[], exclude?: string) =>
  tx((c) => c.$queryRaw<RecallRow[]>(searchSql({ uid, vec, excludeConversationId: exclude, limit: 20 })));

test("db: recall search is per user, skips the current and archived chats", needsDb, async (t) => {
  const a = await tempUser();
  const b = await tempUser();
  t.after(() => db().user.deleteMany({ where: { id: { in: [a, b] } } }));
  const mineOld = await chat(a, "Redis caching");
  const mineCurrent = await chat(a, "Today");
  const mineArchived = await chat(a, "Old archived", true);
  const theirs = await chat(b, "Someone else's Redis chat");
  for (const id of [mineOld, mineCurrent, mineArchived]) await chunk(id, a, 1, axis(7));
  await chunk(theirs, b, 1, axis(7)); // identical vector, other owner

  const rows = await search(a, axis(7), mineCurrent);
  assert.deepEqual(rows.map((r) => r.conversation_id), [mineOld]);
  assert.ok(Number(rows[0].sim) > 0.99);
  assert.equal(rows[0].title, "Redis caching");

  // Without an exclusion the current chat is found too (and still never the other user's, or the archived one).
  assert.deepEqual((await search(a, axis(7))).map((r) => r.conversation_id).sort(), [mineCurrent, mineOld].sort());
  assert.deepEqual((await search(b, axis(7))).map((r) => r.conversation_id), [theirs]);

  // A chunk whose chat belongs to someone else never leaks, even if the chunk row names the wrong owner.
  await chunk(theirs, a, 2, axis(7), "mislabelled");
  assert.ok(!(await search(a, axis(7))).some((r) => r.conversation_id === theirs));
});

test("db: deleting a chat removes its index; switching recall off drops the user's index", needsDb, async (t) => {
  const a = await tempUser();
  t.after(() => db().user.deleteMany({ where: { id: a } }));
  const one = await chat(a, "one");
  const two = await chat(a, "two");
  await chunk(one, a, 0, axis(1));
  await chunk(two, a, 0, axis(2));
  await db().conversation.deleteMany({ where: { id: one } });
  assert.equal(await db().conversationChunk.count({ where: { conversationId: one } }), 0);
  assert.equal(await db().conversationChunk.count({ where: { conversationId: two } }), 1);

  assert.equal(await chatRecallEnabled(a), true);
  await setChatRecallEnabled(a, false);
  assert.equal(await chatRecallEnabled(a), false);
  assert.equal(await db().conversationChunk.count({ where: { userId: a } }), 0);
  assert.equal((await db().conversation.findUnique({ where: { id: two }, select: { recallIndexedAt: true } }))?.recallIndexedAt, null);
});
