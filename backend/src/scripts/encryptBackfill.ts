/**
 * Seals existing plaintext user data (see src/crypto/userData.ts). Idempotent and resumable: every step only
 * touches values that are not sealed yet, in keyset-paginated batches, so it can be stopped and run again.
 * It logs counts only, never content.
 *
 *   pnpm data:encrypt --dry-run          count what would change; writes nothing (not even data keys)
 *   pnpm data:encrypt                    seal everything, then S3 objects
 *   pnpm data:encrypt --only=messages,memories   a subset (see STEPS)
 *   pnpm data:encrypt --no-objects       skip uploaded files in storage
 *   pnpm data:encrypt --rewrap           re-wrap data keys with the current DATA_KEY (after rotating it)
 *   --batch=200                          rows per batch
 *
 * In a production container: node dist/scripts/encryptBackfill.js [flags]  (DATA_KEY must be set).
 * Back up the database and DATA_KEY first: sealed data cannot be read without the key.
 */
import { config } from "../config.js";
import { MSG, CONV } from "../conversations/codec.js";
import { dbKeyStore, isSealed, isSealedJson, isSealedObject, rewrapDataKey, setKeyStore, userCrypto, type UserCrypto } from "../crypto/userData.js";
import { closeDb, db, initDb, onDbUp, Prisma } from "../db/prisma.js";
import { getObject, putObject } from "../storage/s3.js";
// Deliberately not importing files/store.js or the ingest modules: they register background jobs (re-indexing,
// icon backfill) that must not run inside this script.

// ---- pure transforms (unit-tested) ---------------------------------------------------------------

type Patch = Record<string, unknown>;

/** A sealed value for a plaintext string, or undefined when there is nothing to do. */
export function sealText(c: UserCrypto, table: string, column: string, v: string | null | undefined): string | undefined {
  return typeof v === "string" && v !== "" && !isSealed(v) ? c.seal(table, column, v) : undefined;
}

/** A sealed JSON value for plaintext JSON, or undefined when it is empty, null or already sealed. */
export function sealJsonValue(c: UserCrypto, table: string, column: string, v: unknown): unknown | undefined {
  if (v === null || v === undefined || isSealedJson(v)) return undefined;
  const sealed = c.sealJson(table, column, v);
  return sealed === v ? undefined : sealed;
}

/** Keyed form of a legacy plain hash (`h1:` values are already keyed). */
export function keyHash(c: UserCrypto, table: string, column: string, h: string | null | undefined): string | undefined {
  return typeof h === "string" && h !== "" && !h.startsWith("h1:") ? c.blindIndex(table, column, h) : undefined;
}

const compact = (p: Patch): Patch | null => {
  const out = Object.fromEntries(Object.entries(p).filter(([, v]) => v !== undefined));
  return Object.keys(out).length ? out : null;
};

export const conversationPatch = (c: UserCrypto, r: { title: string | null; preview: string | null; summary: string | null; summaryHash: string | null }) =>
  compact({
    title: sealText(c, CONV, "title", r.title),
    preview: sealText(c, CONV, "preview", r.preview),
    summary: sealText(c, CONV, "summary", r.summary),
    summaryHash: keyHash(c, CONV, "summary_hash", r.summaryHash),
  });

export const messagePatch = (c: UserCrypto, r: { content: string; citations: unknown; images: unknown; evidence: unknown; meta: unknown; table: unknown }) =>
  compact({
    content: sealText(c, MSG, "content", r.content),
    citations: sealJsonValue(c, MSG, "citations", r.citations),
    images: sealJsonValue(c, MSG, "images", r.images),
    evidence: sealJsonValue(c, MSG, "evidence", r.evidence),
    meta: sealJsonValue(c, MSG, "meta", r.meta),
    table: sealJsonValue(c, MSG, "table", r.table),
  });

export const memoryPatch = (c: UserCrypto, r: { text: string; slot: string | null; slotEnc: string | null }) => {
  const legacySlot = r.slot && !r.slot.startsWith("h1:") ? r.slot : null;
  return compact({
    text: sealText(c, "memories", "text", r.text),
    ...(legacySlot ? { slot: c.blindIndex("memories", "slot", legacySlot), slotEnc: c.seal("memories", "slot_enc", legacySlot) } : {}),
  });
};

// ---- runner --------------------------------------------------------------------------------------

type Counts = { scanned: number; sealed: number; skipped: number };
const STEPS = ["keys", "conversations", "messages", "recall", "memories", "kb", "notes", "files", "docs", "cache", "objects", "rewrap"] as const;
type Step = (typeof STEPS)[number];

type Opts = { dryRun: boolean; batch: number; only: Set<Step> | null; objects: boolean; rewrap: boolean };

export function parseArgs(argv: string[]): Opts {
  const flag = (n: string) => argv.includes(`--${n}`);
  const val = (n: string) => argv.find((a) => a.startsWith(`--${n}=`))?.split("=")[1];
  const only = val("only")?.split(",").map((s) => s.trim()).filter(Boolean) as Step[] | undefined;
  if (only?.some((s) => !STEPS.includes(s))) throw new Error(`--only takes: ${STEPS.join(", ")}`);
  const batch = Number(val("batch") ?? 200);
  return { dryRun: flag("dry-run"), batch: Number.isInteger(batch) && batch > 0 && batch <= 2000 ? batch : 200, only: only ? new Set(only) : null, objects: !flag("no-objects"), rewrap: flag("rewrap") };
}

const counts = new Map<Step, Counts>();
const tally = (step: Step): Counts => {
  let c = counts.get(step);
  if (!c) counts.set(step, (c = { scanned: 0, sealed: 0, skipped: 0 }));
  return c;
};

const UNSEALED = "NOT LIKE 'enc:v1:%'";
/** Keyset cursor start for uuid primary keys. */
const NIL = "00000000-0000-0000-0000-000000000000";

/** A user's crypto, or null when their data key cannot be unwrapped (wrong DATA_KEY): that user is skipped and counted once. */
const blocked = new Set<string>();
async function keyOf(userId: string | null): Promise<UserCrypto | null> {
  if (!userId || blocked.has(userId)) return null;
  try {
    return await userCrypto(userId);
  } catch {
    blocked.add(userId);
    return null;
  }
}

async function stepKeys(o: Opts) {
  const t = tally("keys");
  let after: string = NIL;
  for (;;) {
    const users = await db().user.findMany({ where: { id: { gt: after }, dataKeyEnc: null }, orderBy: { id: "asc" }, take: o.batch, select: { id: true } });
    if (!users.length) return;
    for (const u of users) {
      t.scanned++;
      if (!o.dryRun) await userCrypto(u.id); // creates and stores the user's data key
      t.sealed++;
    }
    after = users[users.length - 1].id;
  }
}

async function stepConversations(o: Opts) {
  const t = tally("conversations");
  let after: string = NIL;
  for (;;) {
    const rows = await db().conversation.findMany({
      where: { id: { gt: after } },
      orderBy: { id: "asc" },
      take: o.batch,
      select: { id: true, userId: true, title: true, preview: true, summary: true, summaryHash: true },
    });
    if (!rows.length) return;
    for (const r of rows) {
      t.scanned++;
      if (!r.userId) {
        t.skipped++; // data from before accounts: no owner key yet
        continue;
      }
      const c = await keyOf(r.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const patch = conversationPatch(c, r);
      if (!patch) continue;
      if (!o.dryRun) await db().conversation.update({ where: { id: r.id }, data: patch });
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
}

async function stepMessages(o: Opts) {
  const t = tally("messages");
  let after: string = NIL;
  for (;;) {
    const convs = await db().conversation.findMany({ where: { id: { gt: after }, userId: { not: null } }, orderBy: { id: "asc" }, take: Math.max(1, Math.floor(o.batch / 10)), select: { id: true, userId: true } });
    if (!convs.length) return;
    for (const conv of convs) {
      const c = await keyOf(conv.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const msgs = await db().conversationMessage.findMany({ where: { conversationId: conv.id }, select: { position: true, content: true, citations: true, images: true, evidence: true, meta: true, table: true } });
      for (const m of msgs) {
        t.scanned++;
        const patch = messagePatch(c, m);
        if (!patch) continue;
        if (!o.dryRun) await db().conversationMessage.update({ where: { conversationId_position: { conversationId: conv.id, position: m.position } }, data: patch as Prisma.ConversationMessageUpdateInput });
        t.sealed++;
      }
    }
    after = convs[convs.length - 1].id;
  }
}

async function stepRecall(o: Opts) {
  const t = tally("recall");
  let after = 0n;
  for (;;) {
    const rows = await db().$queryRaw<Array<{ id: bigint; user_id: string | null; content: string; content_hash: string }>>`
      SELECT id, user_id::text, content, content_hash FROM conversation_chunks
      WHERE id > ${after} AND (content ${Prisma.raw(UNSEALED)} OR content_hash NOT LIKE 'h1:%') ORDER BY id LIMIT ${o.batch}`;
    if (!rows.length) return;
    for (const r of rows) {
      t.scanned++;
      if (!r.user_id) {
        t.skipped++;
        continue;
      }
      const c = await keyOf(r.user_id);
      if (!c) {
        t.skipped++;
        continue;
      }
      const content = sealText(c, "conversation_chunks", "content", r.content);
      const hash = keyHash(c, "conversation_chunks", "content_hash", r.content_hash);
      if (!o.dryRun) await db().$executeRaw`UPDATE conversation_chunks SET content = ${content ?? r.content}, content_hash = ${hash ?? r.content_hash} WHERE id = ${r.id}`;
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
}

async function stepMemories(o: Opts) {
  const t = tally("memories");
  let after: string = NIL;
  for (;;) {
    const rows = await db().memory.findMany({ where: { id: { gt: after } }, orderBy: { id: "asc" }, take: o.batch, select: { id: true, userId: true, text: true, slot: true, slotEnc: true, updatedAt: true } });
    if (!rows.length) return;
    for (const r of rows) {
      t.scanned++;
      const c = await keyOf(r.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const patch = memoryPatch(c, r);
      if (!patch) continue;
      if (!o.dryRun) await db().memory.update({ where: { id: r.id }, data: { ...patch, updatedAt: r.updatedAt } }); // keep the list order
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
}

/** chunks (text, heading, keyed hash, stripped tsv) and documents (keyed hash, sealed title for note/doc sources). */
async function stepKb(o: Opts) {
  const t = tally("kb");
  let after = 0n;
  for (;;) {
    const rows = await db().$queryRaw<Array<{ id: bigint; owner: string | null; content: string; heading_path: string | null; content_hash: string }>>`
      SELECT c.id, s.user_id::text AS owner, c.content, c.heading_path, c.content_hash
      FROM chunks c JOIN sources s ON s.id = c.source_id
      WHERE c.id > ${after}
        AND (c.content ${Prisma.raw(UNSEALED)} OR c.content_hash NOT LIKE 'h1:%' OR (c.heading_path IS NOT NULL AND c.heading_path ${Prisma.raw(UNSEALED)}))
      ORDER BY c.id LIMIT ${o.batch}`;
    if (!rows.length) break;
    for (const r of rows) {
      t.scanned++;
      if (!r.owner) {
        t.skipped++;
        continue;
      }
      const c = await keyOf(r.owner);
      if (!c) {
        t.skipped++;
        continue;
      }
      const plain = isSealed(r.content) ? c.open("chunks", "content", r.content) : r.content;
      const content = sealText(c, "chunks", "content", r.content) ?? r.content;
      const heading = r.heading_path === null ? null : (sealText(c, "chunks", "heading_path", r.heading_path) ?? r.heading_path);
      const hash = keyHash(c, "chunks", "content_hash", r.content_hash) ?? r.content_hash;
      // tsv keeps keyword search working: lexemes without positions, from the plaintext.
      if (!o.dryRun) await db().$executeRaw`UPDATE chunks SET content = ${content}, heading_path = ${heading}, content_hash = ${hash}, tsv = strip(to_tsvector('english'::regconfig, ${plain}::text)) WHERE id = ${r.id}`;
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
  // Documents: keyed content hash; titles of note/doc sources.
  let docAfter: string = NIL;
  for (;;) {
    const docs = await db().document.findMany({
      where: { id: { gt: docAfter } },
      orderBy: { id: "asc" },
      take: o.batch,
      select: { id: true, title: true, contentHash: true, source: { select: { userId: true, type: true } } },
    });
    if (!docs.length) return;
    for (const d of docs) {
      t.scanned++;
      if (!d.source.userId) continue;
      const c = await keyOf(d.source.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const patch = compact({
        contentHash: keyHash(c, "documents", "content_hash", d.contentHash),
        title: d.source.type === "note" || d.source.type === "doc" ? sealText(c, "documents", "title", d.title) : undefined,
      });
      if (!patch) continue;
      if (!o.dryRun) await db().document.update({ where: { id: d.id }, data: patch });
      t.sealed++;
    }
    docAfter = docs[docs.length - 1].id;
  }
}

/** Source rows of notes and generated docs: sealed title and (notes) options text. */
async function stepNotes(o: Opts) {
  const t = tally("notes");
  let after: string = NIL;
  for (;;) {
    const rows = await db().source.findMany({ where: { id: { gt: after }, type: { in: ["note", "doc"] }, userId: { not: null } }, orderBy: { id: "asc" }, take: o.batch, select: { id: true, type: true, userId: true, title: true, options: true } });
    if (!rows.length) return;
    for (const r of rows) {
      t.scanned++;
      const c = await keyOf(r.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const opts = (r.options ?? {}) as Record<string, unknown>;
      const nextOpts: Record<string, unknown> = { ...opts };
      let optsChanged = false;
      if (r.type === "note") {
        for (const k of ["content", "title", "question"] as const) {
          const sealed = typeof opts[k] === "string" ? sealText(c, "sources", `options.${k}`, opts[k] as string) : undefined;
          if (sealed !== undefined) (nextOpts[k] = sealed, (optsChanged = true));
        }
      }
      const patch = compact({ title: sealText(c, "sources", "title", r.title), ...(optsChanged ? { options: nextOpts as Prisma.InputJsonObject } : {}) });
      if (!patch) continue;
      if (!o.dryRun) await db().source.update({ where: { id: r.id }, data: patch });
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
}

/** files.text and file_chunks.content. File names, mime and sizes stay plaintext. */
async function stepFiles(o: Opts) {
  const t = tally("files");
  let after: string = NIL;
  for (;;) {
    const rows = await db().storedFile.findMany({ where: { id: { gt: after }, userId: { not: null }, text: { not: null } }, orderBy: { id: "asc" }, take: o.batch, select: { id: true, userId: true, text: true } });
    if (!rows.length) break;
    for (const r of rows) {
      t.scanned++;
      const c = await keyOf(r.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const sealed = sealText(c, "files", "text", r.text);
      if (sealed === undefined) continue;
      if (!o.dryRun) await db().storedFile.update({ where: { id: r.id }, data: { text: sealed } });
      t.sealed++;
    }
    after = rows[rows.length - 1].id;
  }
  let chunkAfter = 0n;
  for (;;) {
    const rows = await db().$queryRaw<Array<{ id: bigint; owner: string | null; content: string }>>`
      SELECT fc.id, f.user_id::text AS owner, fc.content FROM file_chunks fc JOIN files f ON f.id = fc.file_id
      WHERE fc.id > ${chunkAfter} AND fc.content ${Prisma.raw(UNSEALED)} ORDER BY fc.id LIMIT ${o.batch}`;
    if (!rows.length) return;
    for (const r of rows) {
      t.scanned++;
      if (!r.owner) {
        t.skipped++;
        continue;
      }
      const c = await keyOf(r.owner);
      if (!c) {
        t.skipped++;
        continue;
      }
      const sealed = sealText(c, "file_chunks", "content", r.content);
      if (sealed === undefined) continue;
      if (!o.dryRun) await db().$executeRaw`UPDATE file_chunks SET content = ${sealed} WHERE id = ${r.id}`;
      t.sealed++;
    }
    chunkAfter = rows[rows.length - 1].id;
  }
}

/** DOC mode: docs, sections, revisions, highlights. */
async function stepDocs(o: Opts) {
  const t = tally("docs");
  let after: string = NIL;
  for (;;) {
    const docs = await db().doc.findMany({ where: { id: { gt: after } }, orderBy: { id: "asc" }, take: Math.max(1, Math.floor(o.batch / 10)) });
    if (!docs.length) return;
    for (const d of docs) {
      t.scanned++;
      const c = await keyOf(d.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      const options = (d.options ?? {}) as Record<string, unknown>;
      const profile = "profile" in options ? sealJsonValue(c, "docs", "options.profile", options.profile) : undefined;
      const patch = compact({
        title: sealText(c, "docs", "title", d.title),
        prompt: sealText(c, "docs", "prompt", d.prompt),
        summary: sealText(c, "docs", "summary", d.summary),
        outline: sealJsonValue(c, "docs", "outline", d.outline),
        glossary: sealJsonValue(c, "docs", "glossary", d.glossary),
        sources: sealJsonValue(c, "docs", "sources", d.sources),
        ...(profile !== undefined ? { options: { ...options, profile } } : {}),
      });
      if (patch) {
        if (!o.dryRun) await db().doc.update({ where: { id: d.id }, data: { ...patch, updatedAt: d.updatedAt } as Prisma.DocUpdateInput });
        t.sealed++;
      }
      for (const s of await db().docSection.findMany({ where: { docId: d.id } })) {
        t.scanned++;
        const sp = compact({
          heading: sealText(c, "doc_sections", "heading", s.heading),
          markdown: sealText(c, "doc_sections", "markdown", s.markdown),
          summary: sealText(c, "doc_sections", "summary", s.summary),
          evidence: sealJsonValue(c, "doc_sections", "evidence", s.evidence),
          images: sealJsonValue(c, "doc_sections", "images", s.images),
        });
        if (!sp) continue;
        if (!o.dryRun) await db().docSection.update({ where: { docId_sectionId: { docId: d.id, sectionId: s.sectionId } }, data: { ...sp, updatedAt: s.updatedAt } as Prisma.DocSectionUpdateInput });
        t.sealed++;
      }
      for (const r of await db().docRevision.findMany({ where: { docId: d.id } })) {
        t.scanned++;
        const markdown = sealText(c, "doc_revisions", "markdown", r.markdown);
        if (markdown === undefined) continue;
        if (!o.dryRun) await db().docRevision.update({ where: { id: r.id }, data: { markdown } });
        t.sealed++;
      }
      for (const h of await db().docHighlight.findMany({ where: { docId: d.id } })) {
        t.scanned++;
        const hp = compact({
          quote: sealText(c, "doc_highlights", "quote", h.quote),
          prefix: sealText(c, "doc_highlights", "prefix", h.prefix),
          suffix: sealText(c, "doc_highlights", "suffix", h.suffix),
          note: sealText(c, "doc_highlights", "note", h.note),
          thread: sealJsonValue(c, "doc_highlights", "thread", h.thread),
        });
        if (!hp) continue;
        if (!o.dryRun) await db().docHighlight.update({ where: { id: h.id }, data: hp as Prisma.DocHighlightUpdateInput });
        t.sealed++;
      }
    }
    after = docs[docs.length - 1].id;
  }
}

/** The shared web cache was keyed by plaintext queries/URLs; entries are re-created under hashed keys on demand. */
async function stepCache(o: Opts) {
  const t = tally("cache");
  const where = { NOT: [{ key: { startsWith: "h:" } }, { key: { startsWith: "llm-quota|" } }] };
  t.scanned = await db().webCache.count({ where });
  if (!o.dryRun) t.sealed = (await db().webCache.deleteMany({ where })).count;
  else t.sealed = t.scanned;
}

/** Uploaded files, thumbnails and video frames in storage: sealed in place (an object without the marker is plaintext). */
/** A file's storage keys: original, thumbnail and video frames (same set as files/store.ts knownKeys). */
function objectKeys(row: { s3Key: string; thumbKey: string | null; meta: unknown }): string[] {
  const meta = row.meta as { frameKeys?: unknown } | null;
  const frames = Array.isArray(meta?.frameKeys) ? (meta.frameKeys as unknown[]).filter((k): k is string => typeof k === "string") : [];
  return [...new Set([row.s3Key, row.thumbKey, ...frames].filter((k): k is string => !!k))];
}

async function stepObjects(o: Opts) {
  const t = tally("objects");
  let after: string = NIL;
  for (;;) {
    const rows = await db().storedFile.findMany({
      where: { id: { gt: after }, userId: { not: null } },
      orderBy: { id: "asc" },
      take: Math.max(1, Math.floor(o.batch / 4)),
      select: { id: true, userId: true, mime: true, s3Key: true, thumbKey: true, meta: true },
    });
    if (!rows.length) return;
    for (const row of rows) {
      const c = await keyOf(row.userId);
      if (!c) {
        t.skipped++;
        continue;
      }
      for (const key of objectKeys(row)) {
        t.scanned++;
        let body: Buffer;
        try {
          body = await getObject(key);
        } catch {
          t.skipped++; // missing object (deleted, or a video not stored yet)
          continue;
        }
        if (isSealedObject(body)) continue;
        if (!o.dryRun) await putObject(key, c.sealBytes(key, body), key === row.s3Key ? row.mime : "image/jpeg");
        t.sealed++;
      }
    }
    after = rows[rows.length - 1].id;
  }
}

async function stepRewrap(o: Opts) {
  const t = tally("rewrap");
  let after: string = NIL;
  for (;;) {
    const users = await db().user.findMany({ where: { id: { gt: after }, dataKeyEnc: { not: null } }, orderBy: { id: "asc" }, take: o.batch, select: { id: true } });
    if (!users.length) return;
    for (const u of users) {
      t.scanned++;
      if (o.dryRun) {
        t.sealed++;
      } else if (await rewrapDataKey(u.id)) t.sealed++;
    }
    after = users[users.length - 1].id;
  }
}

export async function run(o: Opts): Promise<Map<Step, Counts>> {
  if (o.dryRun) {
    // Reads existing data keys; never writes one (a missing key is generated in memory only).
    setKeyStore({ read: dbKeyStore.read, writeIfAbsent: async () => true, overwrite: async () => undefined });
  }
  const want = (s: Step) => (o.only ? o.only.has(s) : true);
  const plan: Array<[Step, (o: Opts) => Promise<void>, boolean]> = [
    ["keys", stepKeys, want("keys")],
    ["conversations", stepConversations, want("conversations")],
    ["messages", stepMessages, want("messages")],
    ["recall", stepRecall, want("recall")],
    ["memories", stepMemories, want("memories")],
    ["kb", stepKb, want("kb")],
    ["notes", stepNotes, want("notes")],
    ["files", stepFiles, want("files")],
    ["docs", stepDocs, want("docs")],
    ["cache", stepCache, want("cache")],
    ["objects", stepObjects, want("objects") && o.objects],
    ["rewrap", stepRewrap, o.rewrap || !!o.only?.has("rewrap")],
  ];
  for (const [name, fn, enabled] of plan) {
    if (!enabled) continue;
    await fn(o);
    const c = tally(name);
    console.log(`${name}: scanned ${c.scanned}, ${o.dryRun ? "would seal" : "sealed"} ${c.sealed}, skipped ${c.skipped}`);
  }
  return counts;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!config.databaseUrl) throw new Error("DATABASE_URL is not set");
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("database not reachable")), 20_000);
    onDbUp(() => {
      clearTimeout(timer);
      resolve();
    });
    initDb();
  });
  console.log(`data:encrypt ${opts.dryRun ? "(dry run) " : ""}batch=${opts.batch}${config.dataKey ? "" : " (no DATA_KEY: development key)"}`);
  await run(opts);
  if (blocked.size) console.log(`${blocked.size} user(s) skipped: their data key could not be unwrapped with the configured DATA_KEY / DATA_KEY_PREVIOUS`);
  console.log("done");
}

// Only when executed directly (the tests import the transforms).
if (process.argv[1] && /encryptBackfill\.(ts|js)$/.test(process.argv[1])) {
  main()
    .catch((e) => {
      console.error(`data:encrypt failed: ${(e as Error).message}`);
      process.exitCode = 1;
    })
    .finally(() => closeDb());
}
