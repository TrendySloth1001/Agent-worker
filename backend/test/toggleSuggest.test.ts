import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyIntent } from "../src/nlp/intent.js";
import {
  KB_SUGGEST_MIN_SIM,
  detectDocSuggestion,
  kbRelevance,
  mayAsk,
  pickSuggestion,
  proposeDocTitle,
  referencesKb,
  resolveWebMode,
  toolsNote,
} from "../src/toggles/suggest.js";

const base = { smart: true, kbOn: false, docOn: false, suppressed: [] as string[], kbHasContent: true };
const pick = (text: string, o: Partial<Parameters<typeof pickSuggestion>[0]> = {}) =>
  pickSuggestion({ ...base, text, intent: classifyIntent(text), kb: null, ...o });

test("kbRelevance: needs two distinct documents over the threshold, or one strong match", () => {
  const weak = kbRelevance([{ title: "A", sim: KB_SUGGEST_MIN_SIM - 0.01 }, { title: "B", sim: 0.2 }]);
  assert.equal(weak.relevant, false);
  assert.equal(kbRelevance([{ title: "A", sim: 0.5 }]).relevant, false, "one mid match is noise");
  assert.equal(kbRelevance([{ title: "A", sim: 0.5 }, { title: "A", sim: 0.55 }]).relevant, false, "same document twice is one document");
  assert.equal(kbRelevance([{ title: "A", sim: 0.65 }]).relevant, true, "one very strong match");
  const r = kbRelevance([
    { title: "Trip plan", sim: 0.5 },
    { title: "Budget", sim: 0.45 },
    { title: "Trip plan", sim: 0.48 },
    { title: "Visa", sim: 0.43 },
    { title: "Other", sim: 0.44 },
  ]);
  assert.equal(r.relevant, true);
  assert.deepEqual(r.titles, ["Trip plan", "Budget", "Other"], "distinct, best first, capped at three");
});

test("kbRelevance: the threshold is inclusive and configurable", () => {
  assert.equal(kbRelevance([{ title: "A", sim: 0.3 }, { title: "B", sim: 0.3 }], 0.3).relevant, true);
  assert.equal(kbRelevance([{ title: "A", sim: 0.3 }, { title: "B", sim: 0.3 }], 0.31).relevant, false);
});

test("referencesKb recognises explicit phrasing", () => {
  for (const t of ["what do my notes say about the launch", "summarize the file I uploaded", "check from my knowledge base", "search my docs for invoices", "in my KB"]) {
    assert.equal(referencesKb(t), true, t);
  }
  for (const t of ["what is a knowledge base", "explain docker", "write notes about React"]) assert.equal(referencesKb(t), false, t);
});

test("detectDocSuggestion: long-form requests", () => {
  for (const t of [
    "Write a detailed report on the state of solar energy in India",
    "write me a full guide for onboarding new engineers",
    "Create comprehensive documentation for our REST API",
    "draft an essay about the causes of the French revolution",
    "I need a 10 page whitepaper on zero trust",
  ]) {
    const d = detectDocSuggestion(t, classifyIntent(t));
    assert.ok(d, t);
    assert.ok(d.proposedTitle.length > 2);
  }
});

test("detectDocSuggestion: ordinary chat, summaries and attachments do not suggest", () => {
  for (const t of ["what is docker", "fix this error in my code", "thanks!", "summarize this article for me please", "write a haiku about rain"]) {
    assert.equal(detectDocSuggestion(t, classifyIntent(t)), null, t);
  }
  const t = "write a detailed report on this";
  assert.equal(detectDocSuggestion(t, classifyIntent(t), { hasAttachments: true }), null);
});

test("proposeDocTitle takes the topic", () => {
  assert.equal(proposeDocTitle("write a detailed report on solar energy in India."), "Solar energy in India");
  assert.equal(proposeDocTitle("full guide for onboarding"), "Onboarding");
});

test("mayAsk: at most once per conversation, KB again only on explicit phrasing", () => {
  const on = { smart: true, alreadyOn: false };
  assert.equal(mayAsk("kb", { ...on, suppressed: [] }), true);
  assert.equal(mayAsk("kb", { ...on, suppressed: ["kb"] }), false);
  assert.equal(mayAsk("kb", { ...on, suppressed: ["kb"], explicit: true }), true);
  assert.equal(mayAsk("doc", { ...on, suppressed: ["doc"], explicit: true }), false, "docs never repeat");
  assert.equal(mayAsk("kb", { smart: false, alreadyOn: false, suppressed: [] }), false, "setting off");
  assert.equal(mayAsk("doc", { smart: true, alreadyOn: true, suppressed: [] }), false, "already on");
});

test("pickSuggestion: emits kb when relevant, once, and never when KB is on", () => {
  const kb = kbRelevance([{ title: "Trip plan", sim: 0.6 }, { title: "Budget", sim: 0.5 }]);
  const s = pick("how much did we budget for the trip", { kb });
  assert.deepEqual(s, { kind: "kb", reason: "matches your knowledge base", sampleTitles: ["Trip plan", "Budget"] });
  assert.equal(pick("how much did we budget for the trip", { kb, suppressed: ["kb"] }), null, "already suggested in this conversation");
  assert.equal(pick("how much did we budget for the trip", { kb, kbOn: true }), null);
  assert.equal(pick("how much did we budget for the trip", { kb, smart: false }), null);
  assert.equal(pick("how much did we budget for the trip", { kb: kbRelevance([]) }), null, "nothing similar");
});

test("pickSuggestion: explicit KB phrasing asks even without similarity, and again after a dismissal", () => {
  const s = pick("what do my notes say about pricing", { suppressed: ["kb"] });
  assert.equal(s?.kind, "kb");
  assert.equal(pick("what do my notes say about pricing", { kbHasContent: false }), null, "an empty knowledge base has nothing to offer");
});

test("pickSuggestion: doc suggestion once, kb wins when both apply", () => {
  const t = "write a detailed report on the history of the internet";
  const first = pick(t);
  assert.equal(first?.kind, "doc");
  assert.equal(pick(t, { suppressed: ["doc"] }), null);
  assert.equal(pick(t, { docOn: true }), null);
  const kb = kbRelevance([{ title: "Net notes", sim: 0.7 }]);
  assert.equal(pick(t, { kb })?.kind, "kb");
});

test("resolveWebMode: legacy boolean and explicit mode", () => {
  assert.equal(resolveWebMode({}), "auto");
  assert.equal(resolveWebMode({ webSearch: false }), "off");
  assert.equal(resolveWebMode({ webSearch: true }), "auto");
  assert.equal(resolveWebMode({ webSearch: false, webMode: "on" }), "on");
});

test("toolsNote tells the model what ran and never lets it claim the KB", () => {
  const off = toolsNote({ web: "auto-none", kb: "off" });
  assert.match(off, /Knowledge base: OFF/);
  assert.match(off, /never claim/);
  assert.doesNotMatch(off, /can check their knowledge base/);
  assert.match(toolsNote({ web: "off", kb: "off", kbSuggested: true }), /can check their knowledge base/);
  assert.match(toolsNote({ web: "searched", kb: "on" }), /Web search: used/);
  assert.match(toolsNote({ web: "off", kb: "off", docSuggested: true }), /expand it into a full Doc/);
});
