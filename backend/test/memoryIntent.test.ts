import { test } from "node:test";
import assert from "node:assert/strict";
import { analyzeMemory, expandContractions, forgetSlots, splitClauses, stripNonUser, techList, type MemoryIntent } from "../src/nlp/memoryIntent.js";

type Case = [text: string, intent: MemoryIntent, llm: "none" | "now" | "batch"];

// [message, primary intent, whether the LLM extractor runs]
const CASES: Case[] = [
  // explicit remember (English + Hinglish)
  ["remember that I use Neovim", "remember", "none"],
  ["Please remember: my dog is called Rex", "remember", "now"],
  ["Can you remember that I prefer dark mode?", "remember", "none"],
  ["keep in mind that I live in Pune", "remember", "none"],
  ["make a note that I hate Java", "remember", "none"],
  ["yaad rakhna, mera naam Nikhil hai", "remember", "none"],
  ["yaad rakh, main Bangalore mein rehta hoon", "remember", "none"],
  ["remember that the office closes early on Fridays", "remember", "now"],
  // explicit forget
  ["forget where I live", "forget", "none"],
  ["forget my location", "forget", "none"],
  ["please forget that I use VS Code", "forget", "none"],
  ["stop remembering my birthday", "forget", "none"],
  ["delete my location", "forget", "none"],
  ["bhool jao ki main Pune mein rehta hoon", "forget", "none"],
  ["forget what I told you about my old project", "forget", "now"],
  // corrections
  ["actually call me Nikhil", "correct", "none"],
  ["no, my name is Nikhil", "correct", "none"],
  ["my name is not Nick, it's Nikhil", "correct", "none"],
  ["I moved to Pune", "correct", "none"],
  ["I don't use VS Code anymore", "correct", "none"],
  ["I switched from VS Code to Neovim", "correct", "none"],
  ["I don't live in Pune", "correct", "none"],
  ["stop calling me Nick", "correct", "none"],
  ["I joined Microsoft last year", "correct", "none"],
  // self-disclosure handled by rules
  ["my name is nikhil and everyone calls me nick", "self_disclosure", "none"],
  ["Hi, I'm Nick", "self_disclosure", "none"],
  ["you can call me Nick", "self_disclosure", "none"],
  ["mujhe Nick bulao", "self_disclosure", "none"],
  ["I live in Pune, India with my family", "self_disclosure", "none"],
  ["I'm based in Berlin", "self_disclosure", "none"],
  ["main Pune mein rehta hoon", "self_disclosure", "none"],
  ["I'm from Delhi but I live in Mumbai", "self_disclosure", "none"],
  ["I work at Google as a backend engineer", "self_disclosure", "none"],
  ["I'm a software engineer at Infosys", "self_disclosure", "none"],
  ["I'm a student at IIT Bombay", "self_disclosure", "none"],
  ["I use Neovim and Docker", "self_disclosure", "none"],
  ["I love Python", "self_disclosure", "none"],
  ["I don't like Java", "self_disclosure", "none"],
  ["I prefer tabs over spaces", "self_disclosure", "none"],
  ["mujhe Python pasand hai", "self_disclosure", "none"],
  ["my pronouns are they/them", "self_disclosure", "none"],
  ["my birthday is 12 March", "self_disclosure", "none"],
  ["I speak Hindi, English and a little German", "self_disclosure", "none"],
  ["I'm a big fan of Rust", "self_disclosure", "none"],
  ["I live in Mumbai and work at Acme as a backend engineer", "self_disclosure", "none"],
  ["Ich spreche Deutsch und arbeite bei Siemens", "self_disclosure", "batch"],
  // self-disclosure the rules cannot structure: batched for the model
  ["I'm building sparky, a Flutter AI assistant", "self_disclosure", "batch"],
  ["my team uses Flutter for the mobile app", "self_disclosure", "batch"],
  ["I'm a vegetarian", "self_disclosure", "batch"],
  ["Ich heiße Nick und wohne in Berlin", "self_disclosure", "batch"],
  ["Me llamo Carlos y vivo en Madrid", "self_disclosure", "batch"],
  // standing instructions
  ["always answer in bullet points", "instruction", "none"],
  ["From now on, keep answers short", "instruction", "none"],
  ["keep answers short", "instruction", "none"],
  ["Never use emojis", "instruction", "none"],
  ["don't use markdown unless I ask", "instruction", "none"],
  ["aage se hamesha Hinglish mein jawab dena", "instruction", "now"],
  // recall questions: no write
  ["what's my name?", "recall_query", "none"],
  ["what do you know about me", "recall_query", "none"],
  ["do you remember my name?", "recall_query", "none"],
  ["where do I live?", "recall_query", "none"],
  ["mera naam kya hai?", "recall_query", "none"],
  // tricky negatives: nothing to store, no model call
  ["remember me", "none", "none"],
  ["remember me?", "none", "none"],
  ["my friend's name is Raj", "none", "none"],
  ["my brother lives in Delhi", "none", "none"],
  ["today I'm tired", "none", "none"],
  ["this week I'm in Goa", "none", "none"],
  ["I'm in Goa", "none", "none"],
  ["if I were rich I'd live in Paris", "none", "none"],
  ["I am thinking of moving to Bangalore", "none", "none"],
  ["I'd like a coffee", "none", "none"],
  ["I love you", "none", "none"],
  ["I like this answer", "none", "none"],
  ["Please call me back tomorrow", "none", "none"],
  ["call me crazy, but this works", "none", "none"],
  ["How do I forget a branch in my repo?", "none", "none"],
  ["forget it", "none", "none"],
  ["forget about it, let's move on", "none", "none"],
  ["never mind", "none", "none"],
  ["forget everything", "none", "none"],
  ["translate: my name is Nick", "none", "none"],
  ["Write a story where I am a pirate who lives in Goa", "none", "none"],
  ['what does "my name is Bob" mean in this test?', "none", "none"],
  ["```\nmy name is Bob\n```", "none", "none"],
  ["How do I reverse a linked list in Python?", "none", "none"],
  ["thanks!", "none", "none"],
  ["delete this file", "none", "none"],
  ["I always forget my keys", "none", "none"],
  ["I'm Indian", "self_disclosure", "batch"],
];

test(`memory intent classifier: ${CASES.length} sentences`, () => {
  const wrong: string[] = [];
  for (const [text, intent, llm] of CASES) {
    const a = analyzeMemory(text);
    if (a.intent !== intent || a.llm !== llm) wrong.push(`${JSON.stringify(text)}: got ${a.intent}/${a.llm}, want ${intent}/${llm} (${a.reasons.join(",")})`);
  }
  assert.deepEqual(wrong, []);
  assert.ok(CASES.length >= 40);
});

test("slot facts: name and nickname from one message", () => {
  const a = analyzeMemory("my name is nikhil and everyone calls me nick");
  assert.deepEqual(a.facts, [
    { type: "name", slot: "name", full: "Nikhil" },
    { type: "name", slot: "name", nick: "Nick" },
  ]);
  assert.deepEqual(analyzeMemory("My name is Nikhil, but you can call me Nick").facts.map((f) => f.type === "name" && (f.full ?? f.nick)), ["Nikhil", "Nick"]);
});

test("slot facts: location, hometown, work, role, tools, tastes, languages", () => {
  const texts = (t: string) => analyzeMemory(t).facts.map((f) => (f.type === "simple" ? `${f.slot}=${f.text}` : f.type === "langs" ? `languages=${f.langs.join("|")}` : `name=${f.full ?? ""}/${f.nick ?? ""}`));
  assert.deepEqual(texts("I live in pune, india"), ["location=Lives in Pune, India."]);
  assert.deepEqual(texts("I'm from Delhi but I live in Mumbai"), ["hometown=From Delhi.", "location=Lives in Mumbai."]);
  assert.deepEqual(texts("I work at Google as a backend engineer"), ["work=Works at Google.", "role=Works as a backend engineer."]);
  assert.deepEqual(texts("I'm an ML engineer"), ["role=Works as an ML engineer."]);
  assert.deepEqual(texts("I'm a student at IIT Bombay"), ["role=Is a student.", "work=Studies at IIT Bombay."]);
  assert.deepEqual(texts("I work for myself"), ["work=Self-employed."]);
  assert.deepEqual(texts("I use Neovim and Docker daily"), ["tool:neovim=Uses Neovim.", "tool:docker=Uses Docker."]);
  assert.deepEqual(texts("I don't like Java"), ["taste:java=Dislikes Java."]);
  assert.deepEqual(texts("I prefer tabs over spaces"), ["taste:tab=Prefers tabs over spaces."]);
  assert.deepEqual(texts("I love hiking"), ["taste:hike=Loves hiking."]);
  assert.deepEqual(texts("I speak fluent Hindi and English"), ["languages=Hindi|English"]);
  assert.deepEqual(texts("my pronouns are He / Him"), ["pronouns=Pronouns: he/him."]);
  // A tool list with something that is not a known technology goes to the model instead.
  assert.deepEqual(texts("I use Neovim with a custom Lua config"), []);
  assert.equal(analyzeMemory("I use Neovim with a custom Lua config").llm, "batch");
});

test("negation and correction produce removals, not facts", () => {
  assert.deepEqual(analyzeMemory("I don't live in Pune").removals, [{ slot: "location", value: "Pune" }]);
  assert.deepEqual(analyzeMemory("I no longer live in Pune").removals, [{ slot: "location", value: "Pune" }]);
  assert.deepEqual(analyzeMemory("I don't use VS Code anymore").removals, [{ slot: "tool:vs-code" }]);
  assert.deepEqual(analyzeMemory("stop calling me Nick").removals, [{ slot: "name", value: "Nick", nickOnly: true }]);
  const sw = analyzeMemory("I switched from VS Code to Neovim");
  assert.deepEqual(sw.removals, [{ slot: "tool:vs-code" }]);
  assert.equal(sw.facts.length, 1);
  assert.deepEqual(analyzeMemory("I quit Google").removals, [{ slot: "work", value: "Google" }]);
});

test("forget subjects map to slots; forget-all needs an explicit phrase", () => {
  assert.deepEqual(forgetSlots("where I live"), [{ slot: "location" }]);
  assert.deepEqual(forgetSlots("my nickname"), [{ slot: "name", nickOnly: true }]);
  assert.deepEqual(forgetSlots("my name"), [{ slot: "name" }]);
  assert.deepEqual(forgetSlots("my job"), [{ slot: "work" }]);
  assert.deepEqual(forgetSlots("that I use Neovim"), [{ slot: "tool:neovim" }, { slot: "taste:neovim" }]);
  assert.equal(forgetSlots("the thing we discussed"), null);
  assert.equal(analyzeMemory("forget everything about me").forgetAll, true);
  assert.equal(analyzeMemory("forget everything you know about me").forgetAll, true);
  assert.equal(analyzeMemory("delete all my memories").forgetAll, true);
  assert.equal(analyzeMemory("sab kuch bhool jao").forgetAll, true);
  assert.equal(analyzeMemory("forget everything").forgetAll, false);
  assert.equal(analyzeMemory("forget everything I said, new topic").forgetAll, false);
});

test("instructions are written as standing notes", () => {
  assert.deepEqual(analyzeMemory("From now on, keep answers short please").instructions, ["Keep answers short."]);
  assert.deepEqual(analyzeMemory("always answer in bullet points").instructions, ["Always answer in bullet points."]);
  // Pronouns that point at something else need the model.
  const a = analyzeMemory("always do it like that");
  assert.deepEqual(a.instructions, []);
  assert.equal(a.llm, "now");
});

test("text helpers: contractions, non-user text, clauses, tech lists", () => {
  assert.equal(expandContractions("I'm sure I don't, what's up"), "i am sure I do not, what is up");
  assert.equal(expandContractions("I’m here"), "i am here");
  assert.equal(stripNonUser('He said "my name is Bob" and `code`').replace(/\s+/g, " ").trim(), "He said and");
  assert.deepEqual(
    splitClauses("I live in Pune and I use Neovim. What about you?").map((c) => [c.text, c.question]),
    [
      ["I live in Pune", false],
      ["I use Neovim", false],
      ["What about you", true],
    ],
  );
  assert.deepEqual(techList("Neovim, Docker and VS Code"), ["Neovim", "Docker", "VS Code"]);
  assert.equal(techList("Neovim and pizza"), null);
});

test("classifier is fast", () => {
  const msg = "Hey! my name is Nikhil and everyone calls me Nick. I live in Pune and work at Acme as a backend engineer. I use Neovim and Docker.";
  const t0 = performance.now();
  for (let i = 0; i < 200; i++) analyzeMemory(msg);
  const per = (performance.now() - t0) / 200;
  assert.ok(per < 5, `${per.toFixed(2)} ms per message`);
});
