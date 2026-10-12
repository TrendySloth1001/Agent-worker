// One chat turn's memory work: recall (before generation) and extraction
// (in parallel with generation, never blocking it). Both are best-effort: any
// failure is logged and the chat carries on without memory.
//
// Extraction is intent-based (src/nlp/memoryIntent.ts):
//   none / recall_query  -> nothing: no DB write, no embedding, no LLM call;
//   rule-based facts     -> slot ops (one memory per slot, updated in place),
//                           applied at once with no LLM call;
//   forget <slot>        -> delete that slot's memory; "forget everything about
//                           me" clears the unpinned memories;
//   explicit remember / correction / instruction the rules could not turn into
//                           clean ops -> one extractor call now, with the intent
//                           and the rule-based notes as hints;
//   other first-person statements -> batched extractor call (a few turns at once).
import { currentUser } from "../auth/context.js";
import { ask } from "../conversations/ask.js";
import { embedQueries } from "../embeddings/index.js";
import { extractionPlan, TurnBatcher } from "./batcher.js";
import { isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { analyzeMemory, type MemoryAnalysis, type MemoryIntent } from "../nlp/memoryIntent.js";
import { extractEntities, memoryHints } from "../nlp/entities.js";
import type { Message } from "../providers.js";
import {
  EXTRACTOR_SYSTEM,
  buildExtractorUser,
  explicitOf,
  formatMemoryBlock,
  mergeWithNearest,
  parseOps,
  planOps,
  type Explicit,
  type ExistingMemory,
  type Op,
  type RecalledMemory,
} from "./logic.js";
import { planSlotOps, resolveSlots, slotOf, slotsTouched } from "./slots.js";
import {
  countMemories,
  createMemory,
  deleteMemory,
  deleteUnpinnedMemories,
  embedMemory,
  identityMemories,
  kindMemories,
  memoryEnabled,
  pinnedMemories,
  recentMemories,
  similarMemories,
  slotMemories,
  touchMemories,
  updateMemory,
} from "./store.js";

// Small, fast models with generous quotas (same family as titles), best first.
const MEMORY_MODELS = ["groq:openai/gpt-oss-20b", "groq:openai/gpt-oss-120b", "ollama:gpt-oss:20b", "nvidia:nvidia/nemotron-3.5-lightning-30b-a3b"];
const TIMEOUT_MS = 20_000;
const RECALL_K = 6;
/** Below this cosine similarity a memory is not related enough to inject. */
const RECALL_MIN_SIM = 0.3;
const EXTRACT_CANDIDATES = 8;
/** "What do you know about me?": how many recent memories to show besides identity and pinned ones. */
const RECALL_QUERY_RECENT = 12;

export type MemoryChange = { op: "ADD" | "UPDATE" | "DELETE"; id: string; text: string };

export type MemoryTurn = {
  /** The message's memory intent (rule-based). */
  intent: MemoryIntent;
  /** The "What you know about the user" block, or null. Also marks the memories as used. [query] is the turn's standalone question, so its embedding is shared with the knowledge base and past-chat recall. */
  recall(query?: string, opts?: { embed?: boolean }): Promise<string | null>;
  /** Resolves with what changed; never rejects. Runs in the background from the start of the turn. */
  extraction: Promise<MemoryChange[]>;
};

export type TurnInput = {
  userText: string;
  /** The assistant message before the user's latest one (context for short replies like "yes"). */
  prevAssistant?: string;
  conversationId?: string;
};

/** Starts memory work for a turn. Null when memory is unavailable (no user, DB down). */
export function startMemoryTurn(input: TurnInput): MemoryTurn | null {
  const userId = currentUser()?.id ?? null;
  const text = input.userText.trim();
  if (!userId || !text || !isDbUp()) return null;

  const analysis = analyzeMemory(text);
  const recallQuery = analysis.intents.includes("recall_query");
  let enabled: Promise<boolean> | null = null;
  const isEnabled = () => (enabled ??= memoryEnabled(userId).catch(() => false));
  const embed = (q: string) => embedQueries([q.slice(0, 1000)]).then((v) => v[0], () => null);

  const recall = async (query?: string, opts: { embed?: boolean } = {}): Promise<string | null> => {
    try {
      if (!(await isEnabled())) return null;
      // Small talk needs no semantic match: pinned, identity and the latest memories are enough (no embedding call).
      const v = opts.embed === false ? null : await embed(query?.trim() || text);
      const [pinned, identity, related, recent] = await Promise.all([
        pinnedMemories(userId),
        identityMemories(userId, recallQuery ? 10 : 6),
        v ? similarMemories(userId, v, RECALL_K).then((r) => r.filter((m) => m.sim >= RECALL_MIN_SIM)) : recentMemories(userId, opts.embed === false ? 3 : RECALL_K),
        recallQuery ? recentMemories(userId, RECALL_QUERY_RECENT) : Promise.resolve([]),
      ]);
      const seen = new Set<string>();
      const picked: RecalledMemory[] = [];
      for (const m of [...identity, ...pinned, ...related, ...recent]) {
        if (!seen.has(m.id)) {
          seen.add(m.id);
          picked.push(m);
        }
      }
      const block = formatMemoryBlock(picked, recallQuery ? 2400 : 1600, { recallQuery });
      if (picked.length) void touchMemories(userId, picked.map((m) => m.id)).catch(() => {});
      return block;
    } catch (e) {
      log.warn("memory recall failed", { error: (e as Error).message?.slice(0, 120) });
      return null;
    }
  };

  const extraction = (async (): Promise<MemoryChange[]> => {
    const plan = extractionPlan(analysis);
    const ruleWork = analysis.forgetAll || analysis.facts.length > 0 || analysis.removals.length > 0 || analysis.instructions.length > 0;
    // Most turns: no rule-based work and nothing for the model. No DB, embedding or LLM call at all.
    if (!ruleWork && plan === "skip") {
      if (analysis.intent !== "none") log.info("memory route", { intent: analysis.intent, path: "none", reasons: analysis.reasons.join(",") });
      return [];
    }
    try {
      if (!(await isEnabled())) return [];
      const explicit = explicitOf(analysis);
      const changes: MemoryChange[] = [];
      if (analysis.forgetAll) {
        const ids = await deleteUnpinnedMemories(userId);
        log.info("memory route", { intent: "forget", path: "rules", forgetAll: true, deleted: ids.length });
        return ids.map((id) => ({ op: "DELETE" as const, id, text: "" }));
      }
      if (ruleWork) changes.push(...(await applyRules(userId, analysis, explicit, input.conversationId)));
      const path = plan === "skip" ? "rules" : ruleWork ? `rules+llm-${plan}` : `llm-${plan}`;
      log.info("memory route", { intent: analysis.intent, path, changes: changes.length, reasons: analysis.reasons.join(",") });
      if (plan === "skip") return changes;
      const item = { text, prevAssistant: input.prevAssistant };
      const hints = { intent: analysis.intent, candidates: changes.map((c) => (c.op === "DELETE" ? "(deleted a memory)" : `saved: ${c.text}`)) };
      if (plan === "batch") {
        // No model call now: one call per few personal turns of this conversation, or when it goes quiet.
        batcher.add(`${userId}|${input.conversationId ?? ""}`, { ...item, userId, conversationId: input.conversationId });
        return changes;
      }
      return [...changes, ...(await extractNow(userId, [item], explicit, input.conversationId, hints))];
    } catch (e) {
      log.warn("memory extraction error", { error: (e as Error).message?.slice(0, 120) });
      return [];
    }
  })();

  return { intent: analysis.intent, recall, extraction };
}

/** Rule-based slot ops: one indexed lookup of the touched slots, then the usual validation. No LLM, no similarity search. */
async function applyRules(userId: string, a: MemoryAnalysis, explicit: Explicit | null, conversationId: string | undefined): Promise<MemoryChange[]> {
  const [slotted, instructions] = await Promise.all([slotMemories(userId, slotsTouched(a)), a.instructions.length ? kindMemories(userId, "instruction", 50) : Promise.resolve([])]);
  // Instructions are checked against the saved ones so a repeated rule is a no-op.
  const existing = [...slotted, ...instructions];
  const ops = planSlotOps(a, slotted);
  if (!ops.length) return [];
  const plan = planOps(ops, existing, { explicit, total: await countMemories(userId) });
  return apply(userId, plan, conversationId);
}

type Pending = { text: string; prevAssistant?: string; userId: string; conversationId?: string };

/** One extraction call over [items] (one explicit turn, or a few batched ones). Never throws. */
async function extractNow(
  userId: string,
  items: Array<{ text: string; prevAssistant?: string }>,
  explicit: Explicit | null,
  conversationId: string | undefined,
  hints: { intent?: string; candidates?: string[] } = {},
): Promise<MemoryChange[]> {
  const last = items[items.length - 1]!;
  const userText = items.length === 1 ? last.text : items.map((i) => i.text.slice(0, 600)).join("\n---\n");
  const v = await embedQueries([last.text.slice(0, 1000)]).then((r) => r[0], () => null);
  const [near, identity] = await Promise.all([v ? similarMemories(userId, v, EXTRACT_CANDIDATES) : recentMemories(userId, EXTRACT_CANDIDATES), identityMemories(userId, 4)]);
  const existing = dedupeById([...near, ...identity]);
  const messages: Message[] = [
    { role: "system", content: EXTRACTOR_SYSTEM },
    {
      role: "user",
      content: buildExtractorUser({ userText, assistantText: items.length === 1 ? last.prevAssistant : undefined, existing, explicit, hints: memoryHints(extractEntities(userText)), intent: hints.intent, candidates: hints.candidates }),
    },
  ];
  let proposed: Op[] | null = null;
  for (const model of MEMORY_MODELS.slice(0, 3)) {
    try {
      const raw = await ask(model, messages, TIMEOUT_MS, "memory");
      if (!/\{/.test(raw)) continue;
      proposed = parseOps(raw, existing);
      break;
    } catch (e) {
      log.warn("memory extraction failed", { model, message: (e as Error).message?.slice(0, 120) });
    }
  }
  if (!proposed?.length) return [];
  // Slot-aware merge: a proposed "Lives in X." updates the location memory instead of adding a second one.
  const slots = [...new Set(proposed.flatMap((o) => (o.op === "DELETE" ? [] : [slotOf(o.text, o.kind)])).filter((s): s is string => !!s))];
  const owners = dedupeById([...existing, ...(await slotMemories(userId, slots))]);
  const plan = planOps(resolveSlots(proposed, owners), owners, { explicit, total: await countMemories(userId) });
  return apply(userId, plan, conversationId);
}

function dedupeById(list: ExistingMemory[]): ExistingMemory[] {
  const seen = new Set<string>();
  return list.filter((m) => !seen.has(m.id) && (seen.add(m.id), true));
}

const batcher = new TurnBatcher<Pending>(async (_key, items) => {
  const first = items[0]!;
  try {
    if (!(await memoryEnabled(first.userId).catch(() => false))) return;
    const changes = await extractNow(first.userId, items, null, first.conversationId, { intent: "self_disclosure" });
    log.info("memory batch", { turns: items.length, changes: changes.length });
  } catch (e) {
    log.warn("memory batch failed", { error: (e as Error).message?.slice(0, 120) });
  }
});

/** Applies a validated plan. Free-form ADDs get an embedding-level duplicate check first. */
async function apply(userId: string, plan: Op[], conversationId: string | undefined): Promise<MemoryChange[]> {
  const changes: MemoryChange[] = [];
  const deleted = new Set<string>();
  for (const op of plan) {
    try {
      if (op.op === "DELETE") {
        if (await deleteMemory(userId, op.id)) {
          deleted.add(op.id);
          changes.push({ op: "DELETE", id: op.id, text: "" });
        }
      } else if (op.op === "UPDATE") {
        const row = await updateMemory(userId, op.id, { text: op.text, kind: op.kind, ...(op.slot !== undefined ? { slot: op.slot } : {}) });
        if (row) changes.push({ op: "UPDATE", id: row.id, text: row.text });
      } else {
        const vec = await embedMemory(op.text);
        const nearest = vec ? ((await similarMemories(userId, vec, 1))[0] ?? null) : null;
        const final = mergeWithNearest(op, nearest, deleted);
        if (!final) continue;
        if (final.op === "UPDATE") {
          const row = await updateMemory(userId, final.id, { text: final.text, kind: final.kind, ...(final.slot !== undefined ? { slot: final.slot } : {}) }, vec);
          if (row) changes.push({ op: "UPDATE", id: row.id, text: row.text });
        } else if (final.op === "ADD") {
          const row = await createMemory(userId, { text: final.text, kind: final.kind, slot: final.slot ?? null, conversationId, vec, pinned: false });
          changes.push({ op: "ADD", id: row.id, text: row.text });
        }
      }
    } catch (e) {
      log.warn("memory apply failed", { op: op.op, error: (e as Error).message?.slice(0, 120) });
    }
  }
  return changes;
}
