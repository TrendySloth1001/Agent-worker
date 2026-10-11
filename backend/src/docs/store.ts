// Persistence for DOC mode. Every read and write is scoped by userId: another
// user's document reads as not found.
import { randomUUID } from "node:crypto";
import { db, Prisma } from "../db/prisma.js";
import type { DocSection, DocState, DocStatus, DocSummary, Highlight, Revision, RevisionReason } from "./types.js";

export const MAX_REVISIONS = 10;

export type DocPatch = Partial<Pick<DocState, "title" | "status" | "outline" | "glossary" | "sources" | "summary" | "words" | "version" | "options">>;
export type NewDoc = Pick<DocState, "userId" | "conversationId" | "prompt" | "options"> & { title?: string };
export type NewHighlight = Omit<Highlight, "id" | "docId" | "createdAt">;

export interface DocStore {
  create(input: NewDoc): Promise<DocState>;
  get(userId: string, id: string): Promise<DocState | null>;
  list(userId: string, conversationId?: string): Promise<DocSummary[]>;
  update(userId: string, id: string, patch: DocPatch): Promise<void>;
  /** Replaces all sections (after the outline is set or edited). */
  setSections(userId: string, id: string, sections: DocSection[]): Promise<void>;
  saveSection(userId: string, id: string, section: DocSection): Promise<void>;
  remove(userId: string, id: string): Promise<boolean>;
  /** Stores a revision and keeps only the newest MAX_REVISIONS for that section. */
  addRevision(userId: string, id: string, sectionId: string, version: number, markdown: string, reason: RevisionReason): Promise<void>;
  revisions(userId: string, id: string, sectionId: string): Promise<Revision[]>;
  highlights(userId: string, id: string): Promise<Highlight[]>;
  addHighlight(userId: string, id: string, h: NewHighlight): Promise<Highlight | null>;
  removeHighlight(userId: string, id: string, highlightId: string): Promise<boolean>;
  /** Marks docs left mid-run by a restart as interrupted (except `live` ones). */
  sweepInterrupted(live: Set<string>): Promise<number>;
}

const RUNNING: DocStatus[] = ["planning", "researching", "writing"];
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (s: string) => UUID_RE.test(s);

const json = (v: unknown) => v as Prisma.InputJsonValue;
const iso = (d: Date) => d.toISOString();

type DocRow = Awaited<ReturnType<ReturnType<typeof db>["doc"]["findFirst"]>> & {};
type SectionRow = Awaited<ReturnType<ReturnType<typeof db>["docSection"]["findFirst"]>> & {};

function toSection(r: SectionRow): DocSection {
  return {
    sectionId: r.sectionId,
    ord: r.ord,
    heading: r.heading,
    level: r.level,
    markdown: r.markdown,
    summary: r.summary,
    status: r.status as DocSection["status"],
    sourceIds: r.sourceIds ?? [],
    usedIds: r.usedIds ?? [],
    evidence: (r.evidence ?? []) as DocSection["evidence"],
    images: (r.images ?? []) as DocSection["images"],
    model: r.model,
    words: r.words,
    updatedAt: iso(r.updatedAt),
  };
}

function toDoc(r: DocRow, sections: SectionRow[]): DocState {
  const outline = r.outline as DocState["outline"] | Record<string, never>;
  return {
    id: r.id,
    userId: r.userId,
    conversationId: r.conversationId,
    title: r.title,
    prompt: r.prompt,
    options: r.options as DocState["options"],
    status: r.status as DocStatus,
    outline: outline && "sections" in outline ? (outline as DocState["outline"]) : null,
    glossary: (r.glossary ?? []) as DocState["glossary"],
    sources: (r.sources ?? []) as DocState["sources"],
    summary: r.summary,
    words: r.words,
    version: r.version,
    createdAt: iso(r.createdAt),
    updatedAt: iso(r.updatedAt),
    sections: sections.sort((a, b) => a.ord - b.ord).map(toSection),
  };
}

function sectionData(s: DocSection) {
  return {
    ord: s.ord,
    heading: s.heading,
    level: s.level,
    markdown: s.markdown,
    summary: s.summary,
    status: s.status,
    sourceIds: s.sourceIds,
    usedIds: s.usedIds,
    evidence: json(s.evidence),
    images: json(s.images),
    model: s.model,
    words: s.words,
  };
}

function toHighlight(r: { id: string; docId: string; sectionId: string; quote: string; prefix: string; suffix: string; color: string; note: string | null; createdAt: Date }): Highlight {
  return { id: r.id, docId: r.docId, sectionId: r.sectionId, quote: r.quote, prefix: r.prefix, suffix: r.suffix, color: r.color, note: r.note, createdAt: iso(r.createdAt) };
}

export const prismaStore: DocStore = {
  async create(input) {
    const row = await db().doc.create({
      data: { userId: input.userId, conversationId: input.conversationId, prompt: input.prompt, title: input.title ?? "", options: json(input.options), status: "planning" },
    });
    return toDoc(row, []);
  },

  async get(userId, id) {
    if (!isUuid(id)) return null;
    const row = await db().doc.findFirst({ where: { id, userId }, include: { sections: true } });
    return row ? toDoc(row, row.sections) : null;
  },

  async list(userId, conversationId) {
    const where: Prisma.DocWhereInput = { userId };
    if (conversationId) {
      where.OR = [
        ...(isUuid(conversationId) ? [{ conversationId }] : []),
        { options: { path: ["conversationId"], equals: conversationId } },
      ];
    }
    const rows = await db().doc.findMany({
      where,
      orderBy: { updatedAt: "desc" },
      take: 200,
      select: { id: true, title: true, status: true, words: true, conversationId: true, createdAt: true, updatedAt: true, options: true, _count: { select: { sections: true } } },
    });
    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      status: r.status as DocStatus,
      words: r.words,
      sections: r._count.sections,
      conversationId: r.conversationId ?? ((r.options as { conversationId?: string })?.conversationId ?? null),
      createdAt: iso(r.createdAt),
      updatedAt: iso(r.updatedAt),
    }));
  },

  async update(userId, id, patch) {
    const data: Prisma.DocUpdateManyMutationInput = {};
    if (patch.title !== undefined) data.title = patch.title;
    if (patch.status !== undefined) data.status = patch.status;
    if (patch.outline !== undefined) data.outline = json(patch.outline ?? {});
    if (patch.glossary !== undefined) data.glossary = json(patch.glossary);
    if (patch.sources !== undefined) data.sources = json(patch.sources);
    if (patch.summary !== undefined) data.summary = patch.summary;
    if (patch.words !== undefined) data.words = patch.words;
    if (patch.version !== undefined) data.version = patch.version;
    if (patch.options !== undefined) data.options = json(patch.options);
    data.updatedAt = new Date();
    await db().doc.updateMany({ where: { id, userId }, data });
  },

  async setSections(userId, id, sections) {
    await db().$transaction(async (t) => {
      const owned = await t.doc.count({ where: { id, userId } });
      if (!owned) return;
      await t.docSection.deleteMany({ where: { docId: id } });
      if (sections.length) await t.docSection.createMany({ data: sections.map((s) => ({ docId: id, sectionId: s.sectionId, ...sectionData(s) })) });
    });
  },

  async saveSection(userId, id, s) {
    const owned = await db().doc.count({ where: { id, userId } });
    if (!owned) return;
    await db().docSection.upsert({
      where: { docId_sectionId: { docId: id, sectionId: s.sectionId } },
      create: { docId: id, sectionId: s.sectionId, ...sectionData(s) },
      update: sectionData(s),
    });
  },

  async remove(userId, id) {
    if (!isUuid(id)) return false;
    const r = await db().doc.deleteMany({ where: { id, userId } });
    return r.count > 0;
  },

  async addRevision(userId, id, sectionId, version, markdown, reason) {
    const owned = await db().doc.count({ where: { id, userId } });
    if (!owned) return;
    await db().docRevision.create({ data: { docId: id, sectionId, version, markdown, reason } });
    const keep = await db().docRevision.findMany({
      where: { docId: id, sectionId },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: MAX_REVISIONS,
      select: { id: true },
    });
    await db().docRevision.deleteMany({ where: { docId: id, sectionId, id: { notIn: keep.map((k) => k.id) } } });
  },

  async revisions(userId, id, sectionId) {
    if (!isUuid(id)) return [];
    const rows = await db().docRevision.findMany({
      where: { docId: id, sectionId, doc: { userId } },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: MAX_REVISIONS,
    });
    return rows.map((r) => ({ version: r.version, markdown: r.markdown, reason: r.reason as RevisionReason, createdAt: iso(r.createdAt) }));
  },

  async highlights(userId, id) {
    if (!isUuid(id)) return [];
    const rows = await db().docHighlight.findMany({ where: { docId: id, userId, doc: { userId } }, orderBy: { createdAt: "asc" } });
    return rows.map(toHighlight);
  },

  async addHighlight(userId, id, h) {
    const owned = await db().doc.count({ where: { id, userId } });
    if (!owned) return null;
    const row = await db().docHighlight.create({ data: { docId: id, userId, sectionId: h.sectionId, quote: h.quote, prefix: h.prefix, suffix: h.suffix, color: h.color, note: h.note } });
    return toHighlight(row);
  },

  async removeHighlight(userId, id, highlightId) {
    if (!isUuid(highlightId) || !isUuid(id)) return false;
    const r = await db().docHighlight.deleteMany({ where: { id: highlightId, docId: id, userId } });
    return r.count > 0;
  },

  async sweepInterrupted(live) {
    const stuck = await db().doc.findMany({ where: { status: { in: RUNNING } }, select: { id: true } });
    const ids = stuck.map((s) => s.id).filter((id) => !live.has(id));
    if (!ids.length) return 0;
    await db().docSection.updateMany({ where: { docId: { in: ids }, status: "writing" }, data: { status: "failed" } });
    const r = await db().doc.updateMany({ where: { id: { in: ids }, status: { in: RUNNING } }, data: { status: "interrupted" } });
    return r.count;
  },
};

/** In-memory store with the same semantics (tests, and a fallback shape reference). */
export function memoryStore(): DocStore & { docs: Map<string, DocState>; revs: Map<string, Array<Revision & { seq: number }>>; marks: Highlight[] } {
  const docs = new Map<string, DocState>();
  const revs = new Map<string, Array<Revision & { seq: number }>>();
  const marks: Highlight[] = [];
  let seq = 0;
  const own = (userId: string, id: string) => {
    const d = docs.get(id);
    return d && d.userId === userId ? d : null;
  };
  const clone = <T>(v: T): T => structuredClone(v);
  return {
    docs,
    revs,
    marks,
    async create(input) {
      const now = new Date().toISOString();
      const d: DocState = {
        id: randomUUID(),
        userId: input.userId,
        conversationId: input.conversationId,
        title: input.title ?? "",
        prompt: input.prompt,
        options: clone(input.options),
        status: "planning",
        outline: null,
        glossary: [],
        sources: [],
        summary: "",
        words: 0,
        version: 1,
        createdAt: now,
        updatedAt: now,
        sections: [],
      };
      docs.set(d.id, d);
      return clone(d);
    },
    async get(userId, id) {
      const d = own(userId, id);
      return d ? clone(d) : null;
    },
    async list(userId, conversationId) {
      return [...docs.values()]
        .filter((d) => d.userId === userId && (!conversationId || d.conversationId === conversationId || d.options.conversationId === conversationId))
        .map((d) => ({ id: d.id, title: d.title, status: d.status, words: d.words, sections: d.sections.length, conversationId: d.conversationId ?? d.options.conversationId ?? null, createdAt: d.createdAt, updatedAt: d.updatedAt }));
    },
    async update(userId, id, patch) {
      const d = own(userId, id);
      if (d) Object.assign(d, clone(patch), { updatedAt: new Date().toISOString() });
    },
    async setSections(userId, id, sections) {
      const d = own(userId, id);
      if (d) d.sections = clone(sections).sort((a, b) => a.ord - b.ord);
    },
    async saveSection(userId, id, s) {
      const d = own(userId, id);
      if (!d) return;
      const i = d.sections.findIndex((x) => x.sectionId === s.sectionId);
      if (i >= 0) d.sections[i] = clone(s);
      else d.sections.push(clone(s));
      d.sections.sort((a, b) => a.ord - b.ord);
    },
    async remove(userId, id) {
      return own(userId, id) ? docs.delete(id) : false;
    },
    async addRevision(userId, id, sectionId, version, markdown, reason) {
      if (!own(userId, id)) return;
      const key = `${id}/${sectionId}`;
      const list = revs.get(key) ?? [];
      list.unshift({ version, markdown, reason, createdAt: new Date().toISOString(), seq: ++seq });
      revs.set(key, list.slice(0, MAX_REVISIONS));
    },
    async revisions(userId, id, sectionId) {
      if (!own(userId, id)) return [];
      return (revs.get(`${id}/${sectionId}`) ?? []).map(({ seq: _s, ...r }) => r);
    },
    async highlights(userId, id) {
      if (!own(userId, id)) return [];
      return marks.filter((m) => m.docId === id).map(clone);
    },
    async addHighlight(userId, id, h) {
      if (!own(userId, id)) return null;
      const m: Highlight = { id: randomUUID(), docId: id, createdAt: new Date().toISOString(), sectionId: h.sectionId, quote: h.quote, prefix: h.prefix, suffix: h.suffix, color: h.color, note: h.note };
      marks.push(m);
      return clone(m);
    },
    async removeHighlight(userId, id, highlightId) {
      if (!own(userId, id)) return false;
      const i = marks.findIndex((m) => m.id === highlightId && m.docId === id);
      if (i < 0) return false;
      marks.splice(i, 1);
      return true;
    },
    async sweepInterrupted(live) {
      let n = 0;
      for (const d of docs.values()) {
        if (!RUNNING.includes(d.status) || live.has(d.id)) continue;
        d.status = "interrupted";
        for (const s of d.sections) if (s.status === "writing") s.status = "failed";
        n++;
      }
      return n;
    },
  };
}

/**
 * W3C text-quote anchoring: where [quote] sits in [text], using prefix/suffix
 * to pick between repeated occurrences. Whitespace-insensitive. null = orphaned.
 */
export function anchorQuote(text: string, sel: { quote: string; prefix?: string; suffix?: string }): { start: number; end: number } | null {
  const norm = (s: string) => s.replace(/\s+/g, " ");
  // Map normalized offsets back to the original text.
  const map: number[] = [];
  let flat = "";
  for (let i = 0; i < text.length; i++) {
    if (/\s/.test(text[i])) {
      if (flat.endsWith(" ")) continue;
      flat += " ";
    } else flat += text[i];
    map.push(i);
  }
  map.push(text.length);
  const q = norm(sel.quote).trim();
  if (!q) return null;
  const hits: number[] = [];
  for (let at = flat.indexOf(q); at >= 0; at = flat.indexOf(q, at + 1)) hits.push(at);
  if (!hits.length) return null;
  const pre = norm(sel.prefix ?? "").trimStart();
  const suf = norm(sel.suffix ?? "").trimEnd();
  const score = (at: number) => {
    let s = 0;
    const before = flat.slice(Math.max(0, at - pre.length - 1), at);
    const after = flat.slice(at + q.length, at + q.length + suf.length + 1);
    for (let k = 1; k <= pre.length && before.trimEnd().endsWith(pre.trimEnd().slice(-k)); k++) s++;
    for (let k = 1; k <= suf.length && after.trimStart().startsWith(suf.trimStart().slice(0, k)); k++) s++;
    return s;
  };
  const best = hits.reduce((a, b) => (score(b) > score(a) ? b : a));
  return { start: map[best], end: map[best + q.length - 1] + 1 };
}
