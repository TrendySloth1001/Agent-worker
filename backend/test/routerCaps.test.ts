import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { MODELS, clearCooldown } from "../src/models.js";
import { ChatFailure, diversify, runChat, type RunHooks } from "../src/llm/router.js";
import { resetQuota } from "../src/llm/quota.js";
import { UpstreamError, type Message, type StreamHandle } from "../src/providers.js";

const ALL = MODELS.map((m) => m.id);
const hooks: RunHooks = { onQueued() {}, onModel() {}, onDelta() {}, onReset() {}, onFallback() {} };
const prompt: Message[] = [{ role: "system", content: "s".repeat(4000) }, { role: "user", content: "hi" }];

beforeEach(() => {
  for (const id of ALL) clearCooldown(id);
  resetQuota();
});

function stream(seen: string[], fails: (id: string) => boolean) {
  return (async (id: string): Promise<StreamHandle> => {
    seen.push(id);
    if (fails(id)) throw new UpstreamError(429, "Rate limit reached: tokens per minute (TPM). Please try again in 1m0s");
    async function* gen() {
      yield "ok";
    }
    return { tokens: gen(), usage: { promptTokens: 1, completionTokens: 1, finishReason: "stop", completed: true } };
  }) as never;
}

test("diversify puts one model per provider first and keeps the order otherwise", () => {
  assert.deepEqual(diversify(["groq:a", "groq:b", "ollama:c", "nvidia:d", "ollama:e"]), ["groq:a", "ollama:c", "nvidia:d", "groq:b", "ollama:e"]);
  assert.deepEqual(diversify([]), []);
});

test("an account-wide 429 drops that provider's other models from the turn", async () => {
  const seen: string[] = [];
  const nvidia = ALL.filter((id) => id.startsWith("nvidia:"));
  const ollama = ALL.filter((id) => id.startsWith("ollama:"));
  await runChat([...nvidia, ...ollama], prompt, new AbortController().signal, hooks, true, { maxTokens: 1536, stream: stream(seen, (id) => id.startsWith("nvidia:")) });
  assert.equal(seen.filter((id) => id.startsWith("nvidia:")).length, 1, seen.join(","));
  assert.ok(seen.some((id) => id.startsWith("ollama:")));
});

test("sends are capped per turn across re-asks", async () => {
  const turn = { sends: 0 };
  const seen: string[] = [];
  for (let i = 0; i < 3; i++) {
    await runChat(ALL, prompt, new AbortController().signal, hooks, true, { maxTokens: 1536, turn, stream: stream(seen, () => true) }).catch((e) => assert.ok(e instanceof ChatFailure));
  }
  assert.ok(seen.length <= 4, `${seen.length} sends in one turn`);
});

test("an explicit (non-Auto) model is sent exactly once and fails fast", async () => {
  const seen: string[] = [];
  await assert.rejects(runChat(["groq:openai/gpt-oss-120b"], prompt, new AbortController().signal, hooks, false, { stream: stream(seen, () => true) }), ChatFailure);
  assert.equal(seen.length, 1);
});
