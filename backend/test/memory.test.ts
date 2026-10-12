import { test } from "node:test";
import assert from "node:assert/strict";
import {
  detectExplicit,
  formatMemoryBlock,
  jaccard,
  looksSensitive,
  mergeWithNearest,
  parseOps,
  planOps,
  MAX_ADDS_PER_TURN,
  type ExistingMemory,
  type Op,
} from "../src/memory/logic.js";
import { fingerprint, splitPoint } from "../src/memory/compact.js";

const mem = (id: string, text: string, extra: Partial<ExistingMemory> = {}): ExistingMemory => ({ id, text, kind: "fact", pinned: false, ...extra });
const EXISTING = [mem("id-1", "User lives in Berlin."), mem("id-2", "User prefers TypeScript over JavaScript.", { kind: "preference" }), mem("id-3", "User likes tea.", { pinned: true })];
const opts = { explicit: null, total: 3 };

test("parseOps maps m-refs to ids, tolerates fences, drops garbage", () => {
  const raw = 'Sure!\n```json\n{"memories":[{"op":"update","id":"m1","text":"User lives in Paris.","kind":"fact"},{"op":"DELETE","id":"m2"},{"op":"ADD","text":"User builds a Flutter app.","kind":"project"},{"op":"DELETE","id":"m99"},{"nope":1},{"op":"ADD","text":"x","kind":"weird"}]}\n```';
  const ops = parseOps(raw, EXISTING);
  assert.deepEqual(ops[0], { op: "UPDATE", id: "id-1", text: "Lives in Paris.", kind: "fact" });
  assert.deepEqual(ops[1], { op: "DELETE", id: "id-2" });
  assert.deepEqual(ops[2], { op: "ADD", text: "Builds a Flutter app.", kind: "project" });
  assert.equal(ops.length, 4); // unknown DELETE and the object without op are dropped; the weird kind falls back to fact
  assert.equal((ops[3] as { kind: string }).kind, "fact");
});

test("parseOps: unparsable or NOOP replies give no ops; an UPDATE with an unknown id becomes an ADD", () => {
  assert.deepEqual(parseOps("I could not decide", EXISTING), []);
  assert.deepEqual(parseOps('{"memories":[]}', EXISTING), []);
  const ops = parseOps('{"memories":[{"op":"UPDATE","id":"m42","text":"User owns a dog.","kind":"fact"}]}', EXISTING);
  assert.deepEqual(ops, [{ op: "ADD", text: "Owns a dog.", kind: "fact" }]);
});

test("planOps: ADD of an existing fact is a NOOP; a longer rewording becomes an UPDATE", () => {
  const same: Op[] = [{ op: "ADD", text: "user lives in berlin", kind: "fact" }];
  assert.deepEqual(planOps(same, EXISTING, opts), []);
  const richer: Op[] = [{ op: "ADD", text: "User lives in Berlin, Germany.", kind: "fact" }];
  assert.deepEqual(planOps(richer, EXISTING, opts), [{ op: "UPDATE", id: "id-1", text: "User lives in Berlin, Germany.", kind: "fact" }]);
});

test("planOps: UPDATE with unchanged text is dropped; unknown ids are dropped", () => {
  const ops: Op[] = [
    { op: "UPDATE", id: "id-1", text: "User lives in Berlin.", kind: "fact" },
    { op: "UPDATE", id: "nope", text: "User lives in Rome.", kind: "fact" },
    { op: "DELETE", id: "nope" },
  ];
  assert.deepEqual(planOps(ops, EXISTING, opts), []);
});

test("planOps: pinned memories survive automatic DELETE but not an explicit forget", () => {
  const del: Op[] = [{ op: "DELETE", id: "id-3" }];
  assert.deepEqual(planOps(del, EXISTING, opts), []);
  assert.deepEqual(planOps(del, EXISTING, { ...opts, explicit: { type: "forget", subject: "tea" } }), del);
});

test("planOps: one op per memory id, duplicate ADDs collapse, per-turn and total caps hold", () => {
  const twice: Op[] = [
    { op: "UPDATE", id: "id-1", text: "User lives in Paris.", kind: "fact" },
    { op: "DELETE", id: "id-1" },
  ];
  assert.equal(planOps(twice, EXISTING, opts).length, 1);
  const dupAdds: Op[] = [
    { op: "ADD", text: "User owns a red bicycle.", kind: "fact" },
    { op: "ADD", text: "user owns a red bicycle", kind: "fact" },
  ];
  assert.equal(planOps(dupAdds, [], { explicit: null, total: 0 }).length, 1);
  const many: Op[] = Array.from({ length: 9 }, (_, i) => ({ op: "ADD", text: `User has unique hobby number ${"x".repeat(i + 1)} ${i * 7919}`, kind: "fact" }) as Op);
  assert.equal(planOps(many, [], { explicit: null, total: 0 }).length, MAX_ADDS_PER_TURN);
  assert.equal(planOps(many, [], { explicit: null, total: 500 }).length, 0);
});

test("planOps: drops secrets and too-short text", () => {
  const ops: Op[] = [
    { op: "ADD", text: "User's password is hunter2", kind: "fact" },
    { op: "ADD", text: "User's card is 4111 1111 1111 1111", kind: "fact" },
    { op: "ADD", text: "ok", kind: "fact" },
  ];
  assert.deepEqual(planOps(ops, [], { explicit: null, total: 0 }), []);
  assert.ok(looksSensitive("my api key: sk-abcdefghijklmnopqrstuvwxyz123"));
  assert.ok(!looksSensitive("User prefers dark mode."));
});

test("mergeWithNearest: embedding-close ADDs merge into the existing memory", () => {
  const add = { op: "ADD", text: "User works as a backend engineer at a bank.", kind: "fact" } as const;
  assert.deepEqual(mergeWithNearest(add, null, new Set()), add);
  assert.deepEqual(mergeWithNearest(add, { id: "a", text: "User is a backend engineer.", sim: 0.5 }, new Set()), add);
  assert.deepEqual(mergeWithNearest(add, { id: "a", text: "User is a backend engineer.", sim: 0.95 }, new Set()), { op: "UPDATE", id: "a", text: add.text, kind: "fact" });
  // a less informative duplicate changes nothing
  assert.equal(mergeWithNearest({ ...add, text: "User is an engineer." }, { id: "a", text: "User is a backend engineer at a bank.", sim: 0.96 }, new Set()), null);
  // the neighbour was deleted in this same plan: add as new
  assert.deepEqual(mergeWithNearest(add, { id: "a", text: "x", sim: 0.99 }, new Set(["a"])), add);
});

test("detectExplicit finds remember/forget commands at the start of a message", () => {
  assert.deepEqual(detectExplicit("Remember that I use Neovim"), { type: "remember", subject: "I use Neovim" });
  assert.deepEqual(detectExplicit("Please remember: my dog is called Rex"), { type: "remember", subject: "my dog is called Rex" });
  assert.deepEqual(detectExplicit("Can you forget about my old address?"), { type: "forget", subject: "my old address?" });
  assert.equal(detectExplicit("What do you remember about Rome?"), null);
  assert.equal(detectExplicit("How do I forget a git branch?"), null);
});

test("jaccard and formatMemoryBlock", () => {
  assert.equal(jaccard("lives in berlin", "lives in berlin"), 1);
  assert.equal(jaccard("", "x"), 0);
  assert.equal(formatMemoryBlock([]), null);
  const block = formatMemoryBlock([
    { id: "1", text: "User lives in Berlin.", kind: "fact" },
    { id: "2", text: "Answer in short bullets.", kind: "instruction" },
  ])!;
  assert.match(block, /^What you know about the user/);
  assert.match(block, /- User lives in Berlin\./);
  assert.match(block, /- \(standing instruction\) Answer in short bullets\./);
  const long = Array.from({ length: 50 }, (_, i) => ({ id: String(i), text: `User fact number ${i} with some padding text here.`, kind: "fact" as const }));
  assert.ok(formatMemoryBlock(long, 300)!.length < 600);
});

// ---- rolling summary --------------------------------------------------------------

const turns = (n: number, size: number) => Array.from({ length: n }, (_, i) => ({ role: (i % 2 === 0 ? "user" : "assistant") as "user" | "assistant", content: "x".repeat(size) }));

test("splitPoint: short chats are untouched, long ones keep a recent tail starting on a user turn", () => {
  assert.equal(splitPoint(turns(6, 100)), null);
  assert.equal(splitPoint(turns(3, 40_000)), null); // too few messages to cut
  const long = turns(20, 3000); // ~15000 tokens
  const cut = splitPoint(long)!;
  assert.ok(cut >= 1 && cut < long.length);
  assert.equal(long[cut].role, "user");
  assert.ok(long.length - cut >= 4 && long.length - cut <= 11);
});

test("fingerprint changes when history is edited", () => {
  const a = turns(4, 10);
  const b = a.map((m, i) => (i === 1 ? { ...m, content: "edited" } : m));
  assert.equal(fingerprint(a), fingerprint(turns(4, 10)));
  assert.notEqual(fingerprint(a), fingerprint(b));
  assert.notEqual(fingerprint(a.slice(0, 3)), fingerprint(a));
});

test("memories read like a contact card and never describe memory itself", async () => {
  const { naturalize, isMetaMemory, planOps } = await import("../src/memory/logic.js");
  assert.equal(naturalize("User is named Nick."), "Name is Nick.");
  assert.equal(naturalize("User's name is Nikhil."), "Name is Nikhil.");
  assert.equal(naturalize("The user prefers tea."), "Prefers tea.");
  assert.equal(naturalize("Name is Nikhil; goes by Nick."), "Name is Nikhil; goes by Nick.");
  assert.ok(isMetaMemory("User wants to be remembered."));
  assert.ok(isMetaMemory("Asked Sparky to remember things."));
  assert.ok(!isMetaMemory("Name is Nikhil; goes by Nick."));
  const plan = planOps(
    [
      { op: "ADD", text: "Wants to be remembered.", kind: "fact" },
      { op: "ADD", text: "Name is Nikhil; goes by Nick.", kind: "identity" },
    ],
    [],
    { explicit: { type: "remember", subject: "me" }, total: 0 },
  );
  assert.deepEqual(plan, [{ op: "ADD", text: "Name is Nikhil; goes by Nick.", kind: "identity" }]);
});
