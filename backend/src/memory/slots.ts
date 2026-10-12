// Slot-based memories: one memory per slot (name, location, work, role,
// pronouns, birthday, languages, tool:<tech>, taste:<thing>), updated in place
// and never duplicated. Pure: turns the rule-based facts from
// nlp/memoryIntent.ts into ADD/UPDATE/DELETE ops against the user's existing
// slot memories, and gives LLM-proposed ops their slot so they merge too.
import { techList, slotKey, type Fact, type Removal } from "../nlp/memoryIntent.js";
import type { ExistingMemory, Kind, Op } from "./logic.js";

const norm = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, " ").replace(/\s+/g, " ").trim();
const same = (a?: string, b?: string) => !!a && !!b && norm(a) === norm(b);

// ---- name card ---------------------------------------------------------------------------

export type NameCard = { full?: string; nick?: string };

/** "Name is Nikhil; goes by Nick." -> { full: "Nikhil", nick: "Nick" } (also reads "Goes by Nick." and "Prefers to be called Nick."). */
export function parseNameCard(text: string): NameCard {
  const full = /\bname is ([^;.,]+)/i.exec(text)?.[1]?.trim();
  const nick = /\b(?:goes by|prefers to be called|called|nickname is)\s+([^;.,]+)/i.exec(text)?.[1]?.trim();
  return { ...(full ? { full } : {}), ...(nick && !same(nick, full) ? { nick } : {}) };
}

export function renderNameCard(c: NameCard): string {
  const nick = c.nick && !same(c.nick, c.full) ? c.nick : undefined;
  if (c.full && nick) return `Name is ${c.full}; goes by ${nick}.`;
  if (c.full) return `Name is ${c.full}.`;
  if (nick) return `Goes by ${nick}.`;
  return "";
}

/** Merges a new name note into an existing one. A nickname never replaces the full name. */
export function mergeNameCards(cur: NameCard, next: NameCard): NameCard {
  const out: NameCard = { ...cur };
  // "my name is Nick" when Nick is already the known nickname: keep the real name.
  if (next.full && !(cur.full && same(next.full, cur.nick))) out.full = next.full;
  if (next.nick) out.nick = next.nick;
  if (same(out.nick, out.full)) delete out.nick;
  return out;
}

// ---- languages ----------------------------------------------------------------------------

export function parseLanguages(text: string): string[] {
  const m = /\bspeaks\s+(.+?)\.?$/i.exec(text);
  if (!m) return [];
  return m[1]
    .split(/\s*,\s*|\s+and\s+/i)
    .map((x) => x.trim())
    .filter(Boolean);
}

export function renderLanguages(langs: string[]): string {
  const u = [...new Map(langs.map((l) => [l.toLowerCase(), l])).values()];
  if (!u.length) return "";
  return `Speaks ${u.length === 1 ? u[0] : `${u.slice(0, -1).join(", ")} and ${u[u.length - 1]}`}.`;
}

// ---- slot of a memory text -------------------------------------------------------------------

const ROLE_IS = /^is an? (?:[\p{L}-]+ ){0,3}?(?:student|undergrad|undergraduate|graduate|postgrad|phd(?: student)?)\.?$/iu;

/** The slot a memory text fills, or null (projects, instructions and free-form facts have none). */
export function slotOf(text: string, kind?: Kind): string | null {
  const t = text.trim();
  if (kind === "instruction" || kind === "project") return null;
  if (/^(?:name is|goes by|prefers to be called)\b/i.test(t)) return "name";
  if (/^lives in\b/i.test(t)) return "location";
  if (/^(?:from|born in|originally from)\b/i.test(t)) return "hometown";
  if (/^(?:works at|works for|studies at|self-employed)\b/i.test(t)) return "work";
  if (/^works as\b/i.test(t) || ROLE_IS.test(t)) return "role";
  if (/^pronouns\b/i.test(t)) return "pronouns";
  if (/^(?:birthday|born on)\b/i.test(t)) return "birthday";
  if (/^speaks\b/i.test(t)) return "languages";
  let m = /^uses (.+?)\.?$/i.exec(t);
  if (m) {
    const techs = techList(m[1]);
    return techs?.length === 1 ? `tool:${slotKey(techs[0])}` : null;
  }
  m = /^(?:loves|likes|enjoys|prefers|hates|dislikes) (.+?)(?: over .+)?\.?$/i.exec(t);
  if (m && m[1].split(/\s+/).length <= 4) {
    const techs = techList(m[1]);
    if (techs?.length === 1) return `taste:${slotKey(techs[0])}`;
    if (!techs) return `taste:${slotKey(m[1])}`;
  }
  return null;
}

/** A memory's slot: the stored one, else inferred from its text. */
export const slotFor = (m: ExistingMemory): string | null => m.slot ?? slotOf(m.text, m.kind);

/** Slots an analysis reads or writes (for a single indexed lookup). */
export function slotsTouched(a: { facts: Fact[]; removals: Removal[] }): string[] {
  return [...new Set([...a.facts.map((f) => f.slot), ...a.removals.map((r) => r.slot)])];
}

// ---- planning --------------------------------------------------------------------------------

type State = { id?: string; text: string; kind: Kind; pinned: boolean; deleted: boolean; orig?: string };

/**
 * Ops for rule-based facts and removals against the user's existing slot
 * memories: one memory per slot, updated in place; a removal with a value only
 * fires when the memory says that value. Instructions become plain ADDs (the
 * normal dedupe in planOps handles repeats).
 */
export function planSlotOps(a: { facts: Fact[]; removals: Removal[]; instructions?: string[] }, existing: ExistingMemory[]): Op[] {
  const state = new Map<string, State>();
  for (const m of existing) {
    const s = slotFor(m);
    if (s && !state.has(s)) state.set(s, { id: m.id, text: m.text, kind: m.kind, pinned: m.pinned, deleted: false, orig: m.text });
  }

  for (const r of a.removals) {
    const st = state.get(r.slot);
    if (!st || st.deleted) continue;
    if (r.slot === "name") {
      const card = parseNameCard(st.text);
      const nickOnly = r.nickOnly || (r.value && same(card.nick, r.value) && !same(card.full, r.value));
      if (nickOnly) {
        if (r.value && !same(card.nick, r.value)) continue;
        if (!card.nick) continue;
        const next = renderNameCard({ full: card.full });
        if (next) st.text = next;
        else st.deleted = true;
        continue;
      }
    }
    if (r.value && !norm(st.text).includes(norm(r.value))) continue;
    st.deleted = true;
  }

  for (const f of a.facts) {
    const st = state.get(f.slot);
    const live = st && !st.deleted ? st.text : "";
    let text: string;
    let kind: Kind = "identity";
    if (f.type === "name") text = renderNameCard(mergeNameCards(live ? parseNameCard(live) : {}, { full: f.full, nick: f.nick }));
    else if (f.type === "langs") text = renderLanguages([...(live ? parseLanguages(live) : []), ...f.langs]);
    else {
      text = f.text;
      kind = f.kind;
    }
    if (!text) continue;
    if (st) Object.assign(st, { text, kind, deleted: false });
    else state.set(f.slot, { text, kind, pinned: false, deleted: false });
  }

  const ops: Op[] = [];
  for (const [slot, st] of state) {
    if (st.id) {
      if (st.deleted) ops.push({ op: "DELETE", id: st.id });
      else if (st.text !== st.orig) ops.push({ op: "UPDATE", id: st.id, text: st.text, kind: st.kind, slot });
    } else if (!st.deleted) ops.push({ op: "ADD", text: st.text, kind: st.kind, slot });
  }
  for (const text of a.instructions ?? []) ops.push({ op: "ADD", text, kind: "instruction", slot: null });
  return ops;
}

/**
 * One note per slot: a model note that packs several topics ("Name is Nikhil.
 * Lives in Mumbai. Works at Acme.") is split into one op per slot. The first
 * part keeps the original op (an UPDATE stays on its memory); the rest are ADDs.
 */
export function splitBySlot(op: Op): Op[] {
  if (op.op === "DELETE") return [op];
  const sentences = op.text.split(/(?<=\.)\s+(?=\p{Lu})/u);
  if (sentences.length < 2) return [op];
  const groups: Array<{ slot: string | null; parts: string[] }> = [];
  for (const s of sentences) {
    const slot = slotOf(s, op.kind);
    const last = groups[groups.length - 1];
    if (last && (!slot || slot === last.slot)) last.parts.push(s);
    else groups.push({ slot, parts: [s] });
  }
  if (groups.length < 2) return [op];
  return groups.map((g, i) => {
    const text = g.parts.join(" ");
    const kind: Kind = g.slot && !g.slot.includes(":") ? "identity" : g.slot?.startsWith("taste:") ? "preference" : op.kind;
    return i === 0 ? { ...op, text } : { op: "ADD", text, kind };
  });
}

/**
 * Gives LLM-proposed ops their slot and folds them into the memory that already
 * holds it: an ADD for a taken slot becomes an UPDATE of that memory (name
 * notes are merged so a nickname never drops the full name); an UPDATE of a
 * different memory into a taken slot keeps no slot.
 */
export function resolveSlots(proposed: Op[], owners: ExistingMemory[]): Op[] {
  const ops = proposed.flatMap(splitBySlot);
  const bySlot = new Map<string, ExistingMemory>();
  for (const m of owners) {
    const s = slotFor(m);
    if (s && !bySlot.has(s)) bySlot.set(s, m);
  }
  const deleted = new Set(ops.filter((o) => o.op === "DELETE").map((o) => (o as { id: string }).id));
  const out: Op[] = [];
  const claimed = new Set<string>();
  for (const op of ops) {
    if (op.op === "DELETE") {
      out.push(op);
      continue;
    }
    const slot = op.slot ?? slotOf(op.text, op.kind);
    if (!slot) {
      out.push({ ...op, slot: null });
      continue;
    }
    const owner = bySlot.get(slot);
    if (claimed.has(slot)) continue; // two ops for one slot in a turn: the first wins
    claimed.add(slot);
    if (!owner || deleted.has(owner.id) || (op.op === "UPDATE" && op.id === owner.id)) {
      out.push({ ...op, slot });
      continue;
    }
    if (op.op === "UPDATE") {
      out.push({ ...op, slot: null });
      continue;
    }
    const text = slot === "name" ? renderNameCard(mergeNameCards(parseNameCard(owner.text), parseNameCard(op.text))) || op.text : op.text;
    if (norm(text) === norm(owner.text)) continue;
    out.push({ op: "UPDATE", id: owner.id, text, kind: op.kind, slot });
  }
  return out;
}
