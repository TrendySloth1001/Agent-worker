/**
 * Live check of POST /assist/fix-transcript's model pass against the real
 * providers: ~10 noisy transcripts per model, with latency and before/after.
 *   pnpm exec tsx scripts/fix-transcript-live.ts [model ...]
 * Needs the provider keys in .env. No database is used.
 */
import { fixModels, fixTranscript, resetTranscriptFix, transcriptFixSnapshot, type ContextTurn } from "../src/assist/fixTranscript.js";
import { percentile, type ModelCall } from "../src/assist/fixTranscript.js";
import { ask } from "../src/llm/ask.js";

type Case = { text: string; context?: ContextTurn[]; exact?: boolean };

// What the on-device recognizer typically hands over (after the app's local pass).
const CASES: Case[] = [
  { text: "Can you check the flutter analyse output and tell me why the chat in put widget is failing" },
  { text: "Remind me to call nikil tomorrow at 5 pm about the agent worker deploy", context: [{ role: "user", content: "What's left on the Agent-worker deploy?" }, { role: "assistant", content: "Only the Coolify redeploy and the migration check." }] },
  { text: "Kal subah meeting hai to mujhe 9 baje yaad dila dena or agenda bhi bhej dena" },
  { text: "What is the difference between a cash and a hash map in java script" },
  { text: "Write a male to the team saying the release is delayed by two days", context: [{ role: "user", content: "The release is slipping." }, { role: "assistant", content: "Want me to draft a note to the team?" }] },
  { text: "Bhai ye code chal nahi raha hai can you fix the null pointer error in the log in screen" },
  { text: "How do I reverse a linked list in pie thon with out using recursion" },
  { text: "Is it going to rain in pune this weekend I want to go trekking" },
  { text: "Summarize the last three commits in my repo and tell me if any of them touch the data base migrations", context: [{ role: "assistant", content: "Your newest commits are on the Agent-worker repo." }, { role: "user", content: "ok" }] },
  { text: "Mujhe ek recipe batao paneer butter masala ki jo 30 minute mein ban jaye" },
  { text: "um so like check the build logs", exact: true },
];

/** 1200 = the production budget; raise it (TIMEOUT_MS=4000) to see the model's full latency spread. */
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS ?? 1_200);
// Same request as production, minus the shared aux cache (which would hand model B model A's answers).
const call: ModelCall = (model, messages, opts) =>
  ask(model, messages, { timeoutMs: opts.timeoutMs, maxTokens: opts.maxTokens, reasoningEffort: "low", temperature: 0, signal: opts.signal, purpose: "transcript-fix-bench" });
const PAUSE_MS =Number(process.env.PAUSE_MS ?? 4_000);
const VOCAB =["Nick", "Nikhil", "Agent-worker", "sparky"];

async function main() {
  const models = process.argv.slice(2).length ? process.argv.slice(2) : fixModels();
  for (const model of models) {
    resetTranscriptFix();
    const ms: number[] = [];
    console.log(`\n=== ${model} ===`);
    // One warm-up call so connection setup is not counted.
    await fixTranscript({ text: "this is a warm up sentence only", vocab: VOCAB }, { models: [model], call, timeoutMs: TIMEOUT_MS });
    resetTranscriptFix();
    for (const c of CASES) {
      // Real dictation is seconds apart; keeps the per-minute token budget from deferring calls.
      await new Promise((r) => setTimeout(r, PAUSE_MS));
      const out = await fixTranscript({ ...c, vocab: VOCAB }, { models: [model], call, timeoutMs: TIMEOUT_MS });
      ms.push(out.ms);
      console.log(`\n[${out.source}${out.reason ? `:${out.reason}` : ""}] ${out.ms} ms`);
      console.log(`  before: ${c.text}`);
      console.log(`  after:  ${out.text}`);
      if (out.changes.length) console.log(`  changes: ${out.changes.map((x) => `${x.from || "∅"} → ${x.to || "∅"}`).join("; ")}`);
    }
    const sorted = [...ms].sort((a, b) => a - b);
    console.log(`\n${model}: p50 ${percentile(sorted, 50)} ms, p95 ${percentile(sorted, 95)} ms, outcomes ${JSON.stringify(transcriptFixSnapshot().outcomes)}`);
  }
  process.exit(0);
}

void main();
