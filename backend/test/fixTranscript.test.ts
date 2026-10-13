import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import express from "express";
import type { AddressInfo } from "node:net";
import {
  acceptFix,
  buildMessages,
  diffChanges,
  fixModels,
  fixTranscript,
  maxTokensFor,
  percentile,
  resetTranscriptFix,
  transcriptFixSnapshot,
  type ModelCall,
} from "../src/assist/fixTranscript.js";
import { voiceFixRouter } from "../src/routes/voiceFix.js";
import { errorMiddleware } from "../src/util/errors.js";

beforeEach(() => resetTranscriptFix());

const reply = (text: string, changes: unknown[] = []) => JSON.stringify({ text, changes });
const fake =
  (out: string | ((user: string) => string), delayMs = 0): ModelCall =>
  async (_model, messages, opts) => {
    if (delayMs) {
      await new Promise<void>((resolve, reject) => {
        const t = setTimeout(resolve, delayMs);
        opts.signal.addEventListener("abort", () => {
          clearTimeout(t);
          reject(new Error("aborted"));
        });
      });
    }
    return typeof out === "string" ? out : out(messages[1]!.content);
  };
const deps = (call: ModelCall, timeoutMs = 1_200) => ({ call, models: ["fake:model"], timeoutMs });

test("fix: applies a valid JSON correction and diffs the words", async () => {
  const out = await fixTranscript(
    { text: "Can you check the flutter analyse output for the chat input." },
    deps(fake('```json\n{"text":"Can you check the flutter analyze output for the chat input?","changes":[{"from":"analyse","to":"analyze"}]}\n```')),
  );
  assert.equal(out.source, "llm");
  assert.equal(out.text, "Can you check the flutter analyze output for the chat input?");
  assert.deepEqual(out.changes, [{ from: "analyse", to: "analyze" }]);
});

test("fix: a slow model times out and the local text is kept", async () => {
  const text = "please summarize the last three commits in agent worker";
  const out = await fixTranscript({ text }, deps(fake(reply("Please summarize the last three commits in Agent-worker."), 400), 120));
  assert.equal(out.source, "timeout");
  assert.equal(out.text, text);
  assert.ok(out.ms < 400, `took ${out.ms} ms`);
});

test("fix: a slow first request is raced by a hedge and the first valid reply wins", async () => {
  let calls = 0;
  const call: ModelCall = (_m, _msgs, opts) => {
    const n = ++calls;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => resolve(reply(n === 1 ? "First reply here now." : "Hedged reply here now.")), n === 1 ? 900 : 30);
      opts.signal.addEventListener("abort", () => {
        clearTimeout(t);
        reject(new Error("aborted"));
      });
    });
  };
  const out = await fixTranscript({ text: "hedged reply here now" }, { call, models: ["fake:a"], timeoutMs: 1_200, hedgeMs: 100 });
  assert.equal(out.source, "llm");
  assert.equal(out.text, "Hedged reply here now.");
  assert.equal(calls, 2);
  assert.ok(out.ms < 600, `took ${out.ms} ms`);
});

test("fix: a fast failure moves on to the fallback model", async () => {
  const seen: string[] = [];
  const call: ModelCall = async (model) => {
    seen.push(model);
    if (model === "fake:a") throw new Error("budget: fake:a skipped (tpm)");
    return reply("Book a table for two at eight.");
  };
  const out = await fixTranscript({ text: "book a table for two at eight" }, { call, models: ["fake:a", "fake:b"], timeoutMs: 1_200 });
  assert.equal(out.source, "llm");
  assert.equal(out.model, "fake:b");
  assert.deepEqual(seen, ["fake:a", "fake:b"]);
});

test("fix: unparseable replies fall back to the local text", async () => {
  const text = "what is the weather like in pune today";
  const out = await fixTranscript({ text }, deps(fake("Sure! Here is the corrected text: what is the weather")));
  assert.equal(out.source, "error");
  assert.equal(out.reason, "unparseable");
  assert.equal(out.text, text);
});

test("fix: a Hinglish transcript translated to English is rejected", async () => {
  const text = "kal subah meeting hai to mujhe 9 baje yaad dila dena";
  const out = await fixTranscript({ text }, deps(fake(reply("There is a meeting tomorrow morning, so remind me at 9."))));
  assert.equal(out.source, "rejected");
  assert.equal(out.text, text);
});

test("fix: Hindi in Devanagari rewritten in Latin script is rejected", () => {
  const v = acceptFix("मुझे कल की मीटिंग के बारे में बताओ", "mujhe kal ki meeting ke baare mein batao");
  assert.equal(v.ok, false);
});

test("fix: added content is rejected", async () => {
  const text = "send the report to rahul by friday";
  const out = await fixTranscript({ text }, deps(fake(reply("Send the report to Rahul by Friday, and also copy the whole finance team and the managers on it."))));
  assert.equal(out.source, "rejected");
});

test("fix: exact mode only allows punctuation and case", async () => {
  const text = "um so like check the build logs";
  const bad = await fixTranscript({ text, exact: true }, deps(fake(reply("So check the build logs."))));
  assert.equal(bad.source, "rejected");
  resetTranscriptFix();
  const good = await fixTranscript({ text, exact: true }, deps(fake(reply("Um, so like, check the build logs."))));
  assert.equal(good.source, "llm");
  assert.equal(good.text, "Um, so like, check the build logs.");
});

test("fix: short commands and confident local passes skip the model", async () => {
  let calls = 0;
  const call: ModelCall = async () => {
    calls++;
    return reply("x");
  };
  assert.equal((await fixTranscript({ text: "open settings" }, deps(call))).source, "skipped");
  assert.equal((await fixTranscript({ text: "this one is long enough to send", confident: true }, deps(call))).source, "skipped");
  assert.equal(calls, 0);
});

test("fix: identical requests are served from the cache", async () => {
  let calls = 0;
  const call: ModelCall = async () => {
    calls++;
    return reply("Remind me to call Nikhil at five.");
  };
  const input = { text: "remind me to call nikil at five" };
  assert.equal((await fixTranscript(input, deps(call))).source, "llm");
  const again = await fixTranscript(input, deps(call));
  assert.equal(again.source, "cache");
  assert.equal(again.text, "Remind me to call Nikhil at five.");
  assert.equal(calls, 1);
});

test("fix: only the last two context messages reach the prompt, with the vocabulary", () => {
  const msgs = buildMessages({
    text: "hello there my friend",
    context: [
      { role: "user", content: "FIRST secret" },
      { role: "assistant", content: "second" },
      { role: "user", content: "third" },
    ],
    vocab: ["Nikhil", "Agent-worker", "Nikhil"],
  });
  assert.ok(!msgs[1]!.content.includes("FIRST"));
  assert.ok(msgs[1]!.content.includes("assistant: second\nuser: third"));
  assert.ok(msgs[0]!.content.includes("Nikhil, Agent-worker"));
  assert.ok(/NEVER translate/.test(msgs[0]!.content));
});

test("fix: helpers", () => {
  assert.deepEqual(diffChanges("call nikil at five", "Call Nikhil at five."), [{ from: "nikil", to: "Nikhil" }]);
  assert.deepEqual(diffChanges("a b c", "a x y c"), [{ from: "b", to: "x y" }]);
  assert.equal(percentile([1, 2, 3, 4, 100], 50), 3);
  assert.equal(percentile([1, 2, 3, 4, 100], 95), 100);
  assert.ok(maxTokensFor("x".repeat(70), "groq:openai/gpt-oss-20b") > maxTokensFor("x".repeat(70), "nvidia:small"));
  assert.deepEqual(fixModels("groq:a, bad ,nvidia:b"), ["groq:a", "nvidia:b"]);
  assert.deepEqual(diffChanges("the chat in put widget", "the chat input widget"), [{ from: "in put", to: "input" }]);
  assert.ok(fixModels("").length > 0);
});

test("fix: telemetry records local samples and model latency", async () => {
  await fixTranscript({ text: "this is a fine sentence today" }, deps(fake(reply("This is a fine sentence today."))));
  const snap = transcriptFixSnapshot();
  assert.equal(snap.llm.count, 1);
  assert.equal(snap.outcomes.llm, 1);
});

// ---- endpoint ---------------------------------------------------------------

async function withServer(call: ModelCall, fn: (post: (body: unknown) => Promise<Response>) => Promise<void>) {
  const app = express();
  app.use(express.json());
  app.use("/assist", voiceFixRouter(call));
  app.use(errorMiddleware);
  const server = app.listen(0);
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/assist/fix-transcript`;
  try {
    await fn((body) => fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }));
  } finally {
    server.closeAllConnections();
    server.close();
  }
}

test("endpoint: returns the fix and records local timings", () =>
  withServer(fake(reply("Kal subah meeting hai, to mujhe 9 baje yaad dila dena.")), async (post) => {
    const res = await post({ text: "kal subah meeting hai to mujhe 9 baje yaad dila dena", localMs: [2, 3, 4] });
    assert.equal(res.status, 200);
    const json = (await res.json()) as { text: string; source: string };
    assert.equal(json.source, "llm");
    assert.equal(json.text, "Kal subah meeting hai, to mujhe 9 baje yaad dila dena.");
    assert.equal(transcriptFixSnapshot().local.count, 3);
  }));

test("endpoint: a translation from the model keeps the user's words", () =>
  withServer(fake(reply("Tomorrow morning there is a meeting, remind me at 9.")), async (post) => {
    const text = "kal subah meeting hai to mujhe 9 baje yaad dila dena";
    const json = (await (await post({ text })).json()) as { text: string; source: string };
    assert.equal(json.source, "rejected");
    assert.equal(json.text, text);
  }));

test("endpoint: bad body is a 400", () =>
  withServer(fake(reply("x")), async (post) => {
    const res = await post({ text: 5 });
    assert.equal(res.status, 400, await res.text());
  }));
