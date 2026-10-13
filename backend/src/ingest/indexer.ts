import { db, isDbUp, onDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { enqueue } from "./queue.js";
import { userCrypto } from "../crypto/userData.js";

/**
 * Keeps the user's generated docs and uploaded documents in the knowledge base:
 * one `sources` row per doc/file (type 'doc' | 'file', uri `<type>:<id>`),
 * ingested by the same queue as every other source. Hooks are fire-and-forget
 * and never throw into the caller.
 */

export type IndexKind = "doc" | "file";
const DEBOUNCE_MS = 4_000;
const timers = new Map<string, NodeJS.Timeout>();

/** Uploaded files worth searching as prose (not source code, logs or data dumps). */
export const isKnowledgeDoc = (name: string) => /\.(pdf|docx|md|markdown|txt|html?)$/i.test(name);

const uriOf = (kind: IndexKind, id: string) => `${kind}:${id}`;

async function upsertSource(kind: IndexKind, userId: string | null, id: string, title: string | null): Promise<string> {
  const uri = uriOf(kind, id);
  const patch = { status: "queued", error: null, progressDone: 0, progressTotal: null, updatedAt: new Date() };
  const existing = await db().source.findFirst({ where: { type: kind, uri, userId }, select: { id: true } });
  if (existing) {
    await db().source.update({ where: { id: existing.id }, data: patch });
    return existing.id;
  }
  try {
    // A generated doc's title is user text: sealed. A file's name is plaintext metadata (files.name).
    const stored = title && kind === "doc" ? (await userCrypto(userId)).seal("sources", "title", title.slice(0, 200)) : (title?.slice(0, 200) ?? null);
    const row = await db().source.create({ data: { type: kind, uri, title: stored, userId, options: {} }, select: { id: true } });
    return row.id;
  } catch (e) {
    // Lost a race with a concurrent hook: the other insert wins.
    const again = await db().source.findFirst({ where: { type: kind, uri, userId }, select: { id: true } });
    if (again) return again.id;
    throw e;
  }
}

/** Index (or re-index) now. Unchanged sections/chunks reuse their embeddings. */
export async function indexNow(kind: IndexKind, userId: string | null, id: string, title: string | null = null): Promise<void> {
  if (!isDbUp()) return;
  try {
    enqueue(await upsertSource(kind, userId, id, title));
  } catch (e) {
    log.warn("kb index failed", { kind, id, message: (e as Error).message?.slice(0, 120) });
  }
}

/** Debounced [indexNow]: bursts of edits to one doc become one re-index. */
export function scheduleIndex(kind: IndexKind, userId: string | null, id: string, title: string | null = null, delayMs = DEBOUNCE_MS): void {
  if (!isDbUp()) return;
  const key = uriOf(kind, id);
  clearTimeout(timers.get(key));
  const t = setTimeout(() => {
    timers.delete(key);
    void indexNow(kind, userId, id, title);
  }, delayMs);
  t.unref?.();
  timers.set(key, t);
}

/** Remove a doc/file from the knowledge base (chunks and documents cascade). */
export async function unindex(kind: IndexKind, id: string): Promise<void> {
  clearTimeout(timers.get(uriOf(kind, id)));
  timers.delete(uriOf(kind, id));
  if (!isDbUp()) return;
  try {
    await db().source.deleteMany({ where: { type: kind, uri: uriOf(kind, id) } });
  } catch (e) {
    log.warn("kb unindex failed", { kind, id, message: (e as Error).message?.slice(0, 120) });
  }
}

/**
 * Indexes every finished doc and ready document file that has no source yet,
 * and retries doc/file sources that failed. Idempotent; runs when the database
 * comes up. The ingest queue processes them one at a time.
 */
export async function backfillIndex(): Promise<{ docs: number; files: number; retried: number }> {
  const out = { docs: 0, files: 0, retried: 0 };
  if (!isDbUp()) return out;
  try {
    const existing = await db().source.findMany({ where: { type: { in: ["doc", "file"] } }, select: { id: true, uri: true, status: true } });
    const have = new Set(existing.map((s) => s.uri));
    for (const s of existing) {
      if (s.status === "failed") {
        await db().source.updateMany({ where: { id: s.id }, data: { status: "queued", error: null, updatedAt: new Date() } });
        enqueue(s.id);
        out.retried++;
      }
    }
    const docs = await db().doc.findMany({ where: { status: { in: ["done", "partial", "interrupted"] } }, select: { id: true, userId: true, title: true }, orderBy: { updatedAt: "desc" }, take: 1000 });
    for (const d of docs) {
      if (have.has(uriOf("doc", d.id))) continue;
      await indexNow("doc", d.userId, d.id, (await userCrypto(d.userId)).open("docs", "title", d.title));
      out.docs++;
    }
    const files = await db().storedFile.findMany({
      where: { kind: "document", status: "ready", text: { not: null } },
      select: { id: true, userId: true, name: true },
      orderBy: { createdAt: "desc" },
      take: 1000,
    });
    for (const f of files) {
      if (have.has(uriOf("file", f.id)) || !isKnowledgeDoc(f.name)) continue;
      await indexNow("file", f.userId, f.id, f.name);
      out.files++;
    }
    if (out.docs || out.files || out.retried) log.info("kb backfill", out);
  } catch (e) {
    log.warn("kb backfill failed", { message: (e as Error).message?.slice(0, 120) });
  }
  return out;
}

onDbUp(() => void backfillIndex());
