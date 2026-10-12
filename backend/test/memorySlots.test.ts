import { test } from "node:test";
import assert from "node:assert/strict";
import { analyzeMemory } from "../src/nlp/memoryIntent.js";
import { explicitOf, formatMemoryBlock, mergeWithNearest, planOps, type ExistingMemory, type Op } from "../src/memory/logic.js";
import { mergeNameCards, parseNameCard, planSlotOps, renderNameCard, resolveSlots, slotOf, splitBySlot } from "../src/memory/slots.js";
import { extractionPlan } from "../src/memory/batcher.js";

let seq = 0;

/** The ops one user message produces against [db] (rules only, as turn.ts runs them), applied to [db]. */
function turn(db: ExistingMemory[], text: string): Op[] {
  const a = analyzeMemory(text);
  if (a.forgetAll) return db.filter((m) => !m.pinned).map((m) => ({ op: "DELETE", id: m.id }));
  const touched = new Set([...a.facts.map((f) => f.slot), ...a.removals.map((r) => r.slot)]);
  // turn.ts loads the touched slots, plus the instruction memories when the message holds an instruction.
  const existing = db.filter((m) => (m.slot && touched.has(m.slot)) || (a.instructions.length > 0 && m.kind === "instruction"));
  const ops = planOps(planSlotOps(a, existing), existing, { explicit: explicitOf(a), total: db.length });
  for (const op of ops) {
    if (op.op === "ADD") db.push({ id: `id-${++seq}`, text: op.text, kind: op.kind, pinned: false, slot: op.slot ?? null });
    else if (op.op === "UPDATE") Object.assign(db.find((m) => m.id === op.id)!, { text: op.text, kind: op.kind, ...(op.slot !== undefined ? { slot: op.slot } : {}) });
    else db.splice(db.findIndex((m) => m.id === op.id), 1);
  }
  return ops;
}

const strip = (ops: Op[]) => ops.map((o) => (o.op === "DELETE" ? { op: o.op } : { op: o.op, text: o.text, kind: o.kind, slot: o.slot }));

test("conversation: name + nickname, correction, move, forget, and no-ops", () => {
  const db: ExistingMemory[] = [];
  assert.deepEqual(strip(turn(db, "my name is nikhil and everyone calls me nick")), [{ op: "ADD", text: "Name is Nikhil; goes by Nick.", kind: "identity", slot: "name" }]);
  assert.deepEqual(strip(turn(db, "actually call me Nikhil")), [{ op: "UPDATE", text: "Name is Nikhil.", kind: "identity", slot: "name" }]);
  assert.deepEqual(strip(turn(db, "I live in Mumbai")), [{ op: "ADD", text: "Lives in Mumbai.", kind: "identity", slot: "location" }]);
  assert.deepEqual(strip(turn(db, "I moved to Pune")), [{ op: "UPDATE", text: "Lives in Pune.", kind: "identity", slot: "location" }]);
  assert.equal(db.length, 2, "never a second location or name memory");
  assert.deepEqual(strip(turn(db, "forget where I live")), [{ op: "DELETE" }]);
  assert.deepEqual(db.map((m) => m.text), ["Name is Nikhil."]);
  for (const t of ["remember me", "what's my name?", "my friend's name is Raj", "today I'm tired", "If I were rich I'd live in Paris"]) {
    assert.deepEqual(turn(db, t), [], t);
    assert.equal(extractionPlan(analyzeMemory(t)), "skip", t);
  }
  assert.deepEqual(db.map((m) => m.text), ["Name is Nikhil."]);
});

test("a nickname never overwrites the full name", () => {
  const db: ExistingMemory[] = [{ id: "n", text: "Name is Nikhil.", kind: "identity", pinned: false, slot: "name" }];
  assert.deepEqual(strip(turn(db, "you can call me Nick")), [{ op: "UPDATE", text: "Name is Nikhil; goes by Nick.", kind: "identity", slot: "name" }]);
  // Restating the nickname as "my name" keeps the real name.
  assert.deepEqual(turn(db, "my name is Nick"), []);
  assert.deepEqual(strip(turn(db, "stop calling me Nick")), [{ op: "UPDATE", text: "Name is Nikhil.", kind: "identity", slot: "name" }]);
  // Nickname first, full name later: both kept in one note.
  const db2: ExistingMemory[] = [];
  turn(db2, "call me Nick");
  assert.deepEqual(db2.map((m) => m.text), ["Goes by Nick."]);
  turn(db2, "my name is Nikhil");
  assert.deepEqual(db2.map((m) => m.text), ["Name is Nikhil; goes by Nick."]);
  // A real correction of the name replaces it and keeps the nickname.
  turn(db2, "no, my name is Nikhil Kumar");
  assert.deepEqual(db2.map((m) => m.text), ["Name is Nikhil Kumar; goes by Nick."]);
});

test("negations delete only a matching memory; corrections keep pinned memories", () => {
  const db: ExistingMemory[] = [{ id: "l", text: "Lives in Mumbai.", kind: "identity", pinned: false, slot: "location" }];
  assert.deepEqual(turn(db, "I don't live in Pune"), []);
  assert.deepEqual(strip(turn(db, "I don't live in Mumbai")), [{ op: "DELETE" }]);
  const pinned: ExistingMemory[] = [{ id: "t", text: "Uses VS Code.", kind: "fact", pinned: true, slot: "tool:vs-code" }];
  assert.deepEqual(turn(pinned, "I don't use VS Code anymore"), [], "a correction does not delete a pinned memory");
  assert.deepEqual(strip(turn(pinned, "forget that I use VS Code")), [{ op: "DELETE" }], "an explicit forget does");
});

test("tools, tastes and languages: one memory per slot, updated in place", () => {
  const db: ExistingMemory[] = [];
  turn(db, "I use VS Code and Docker");
  assert.deepEqual(db.map((m) => [m.slot, m.text]), [
    ["tool:vs-code", "Uses VS Code."],
    ["tool:docker", "Uses Docker."],
  ]);
  turn(db, "I switched from VS Code to Neovim");
  assert.deepEqual(db.map((m) => m.text).sort(), ["Uses Docker.", "Uses Neovim."]);
  turn(db, "I love Java");
  turn(db, "actually I hate Java");
  assert.deepEqual(db.filter((m) => m.slot === "taste:java").map((m) => m.text), ["Hates Java."]);
  turn(db, "I speak Hindi and English");
  turn(db, "I also speak German");
  assert.deepEqual(db.filter((m) => m.slot === "languages").map((m) => m.text), ["Speaks Hindi, English and German."]);
  // Saying the same thing again changes nothing.
  assert.deepEqual(turn(db, "I use Docker"), []);
});

test("work and role are separate slots; instructions are plain adds", () => {
  const db: ExistingMemory[] = [];
  turn(db, "I'm a backend engineer at Acme");
  assert.deepEqual(db.map((m) => m.text), ["Works as a backend engineer.", "Works at Acme."]);
  turn(db, "I joined Google");
  assert.deepEqual(db.map((m) => m.text), ["Works as a backend engineer.", "Works at Google."]);
  const ops = turn(db, "From now on, keep answers short");
  assert.deepEqual(strip(ops), [{ op: "ADD", text: "Keep answers short.", kind: "instruction", slot: null }]);
  assert.deepEqual(turn(db, "keep answers short"), [], "a repeated instruction is a no-op");
});

test("forget everything about me spares pinned memories; plain 'forget everything' does nothing", () => {
  const db: ExistingMemory[] = [
    { id: "a", text: "Name is Nikhil.", kind: "identity", pinned: true, slot: "name" },
    { id: "b", text: "Lives in Pune.", kind: "identity", pinned: false, slot: "location" },
  ];
  assert.deepEqual(turn(db, "forget everything"), []);
  assert.deepEqual(turn(db, "forget everything about me"), [{ op: "DELETE", id: "b" }]);
});

test("slotOf reads back every rendered slot text", () => {
  const cases: Array<[string, string | null]> = [
    ["Name is Nikhil; goes by Nick.", "name"],
    ["Goes by Nick.", "name"],
    ["Lives in Pune, India.", "location"],
    ["From Delhi.", "hometown"],
    ["Works at Google.", "work"],
    ["Studies at IIT Bombay.", "work"],
    ["Works as a backend engineer.", "role"],
    ["Is a student.", "role"],
    ["Pronouns: they/them.", "pronouns"],
    ["Birthday: 12 March.", "birthday"],
    ["Speaks Hindi and English.", "languages"],
    ["Uses Neovim.", "tool:neovim"],
    ["Uses VS Code.", "tool:vs-code"],
    ["Prefers tabs over spaces.", "taste:tab"],
    ["Dislikes Java.", "taste:java"],
    ["Building sparky, a Flutter AI assistant app.", null],
    ["Is a vegetarian.", null],
  ];
  for (const [text, slot] of cases) assert.equal(slotOf(text), slot, text);
  assert.equal(slotOf("Always answer in bullets.", "instruction"), null);
});

test("name cards parse, merge and render", () => {
  assert.deepEqual(parseNameCard("Name is Nikhil; goes by Nick."), { full: "Nikhil", nick: "Nick" });
  assert.deepEqual(parseNameCard("Prefers to be called Nick."), { nick: "Nick" });
  assert.equal(renderNameCard(mergeNameCards({ full: "Nikhil" }, { nick: "Nick" })), "Name is Nikhil; goes by Nick.");
  assert.equal(renderNameCard(mergeNameCards({ full: "Nikhil", nick: "Nick" }, { nick: "nikhil" })), "Name is Nikhil.");
  assert.equal(renderNameCard({}), "");
});

test("resolveSlots folds model-proposed ops into existing slot memories", () => {
  const owners: ExistingMemory[] = [
    { id: "n", text: "Name is Nikhil.", kind: "identity", pinned: false, slot: "name" },
    { id: "l", text: "Lives in Mumbai.", kind: "identity", pinned: false, slot: "location" },
  ];
  const out = resolveSlots(
    [
      { op: "ADD", text: "Lives in Goa.", kind: "identity" },
      { op: "ADD", text: "Goes by Nick.", kind: "identity" },
      { op: "ADD", text: "Building sparky, a Flutter app.", kind: "project" },
      { op: "ADD", text: "Lives in Delhi.", kind: "identity" },
    ],
    owners,
  );
  assert.deepEqual(out, [
    { op: "UPDATE", id: "l", text: "Lives in Goa.", kind: "identity", slot: "location" },
    { op: "UPDATE", id: "n", text: "Name is Nikhil; goes by Nick.", kind: "identity", slot: "name" },
    { op: "ADD", text: "Building sparky, a Flutter app.", kind: "project", slot: null },
  ]);
  // A deleted owner frees its slot for a new memory.
  assert.deepEqual(resolveSlots([{ op: "DELETE", id: "l" }, { op: "ADD", text: "Lives in Goa.", kind: "identity" }], owners), [
    { op: "DELETE", id: "l" },
    { op: "ADD", text: "Lives in Goa.", kind: "identity", slot: "location" },
  ]);
});

test("a model note that mixes topics is split into one op per slot", () => {
  const owners: ExistingMemory[] = [{ id: "n", text: "Name is Nikhil; goes by Nick.", kind: "identity", pinned: false, slot: "name" }];
  const out = resolveSlots([{ op: "UPDATE", id: "n", text: "Name is Nikhil; goes by Nick. Lives in Mumbai. Works as a backend engineer at Acme.", kind: "identity" }], owners);
  // The name note keeps its text (planOps drops the unchanged UPDATE); location and role become their own notes.
  assert.deepEqual(planOps(out, owners, { explicit: null, total: 1 }), [
    { op: "ADD", text: "Lives in Mumbai.", kind: "identity", slot: "location" },
    { op: "ADD", text: "Works as a backend engineer at Acme.", kind: "identity", slot: "role" },
  ]);
  assert.deepEqual(splitBySlot({ op: "ADD", text: "Building sparky. It uses Flutter.", kind: "project" }), [{ op: "ADD", text: "Building sparky. It uses Flutter.", kind: "project" }]);
});

test("recall questions get an answerable memory block, or an honest empty one", () => {
  const block = formatMemoryBlock([{ id: "1", text: "Name is Nikhil; goes by Nick.", kind: "identity" }], 2400, { recallQuery: true })!;
  assert.match(block, /- Name is Nikhil; goes by Nick\./);
  assert.match(block, /asking what you know or remember about them/);
  assert.match(formatMemoryBlock([], 2400, { recallQuery: true })!, /nothing is saved about the user yet/);
  assert.equal(formatMemoryBlock([]), null);
});

test("embedding dedupe never merges different slots", () => {
  const add = { op: "ADD", text: "From Pune.", kind: "identity", slot: "hometown" } as const;
  assert.deepEqual(mergeWithNearest(add, { id: "x", text: "Lives in Pune.", sim: 0.95, slot: "location" }, new Set()), add);
  assert.deepEqual(mergeWithNearest(add, { id: "x", text: "Originally from Pune.", sim: 0.95, slot: null }, new Set()), null);
});
