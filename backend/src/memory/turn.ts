// One chat turn's memory work: recall (before generation) and extraction
// (in parallel with generation, never blocking it). Both are best-effort: any
// failure is logged and the chat carries on without memory.
import { currentUser } from "../auth/context.js";
import { ask } from "../conversations/ask.js";
import { embedQueries } from "../embeddings/index.js";
import { extractionPlan, TurnBatcher } from "./batcher.js";
import { isDbUp } from "../db/prisma.js";
import { log } from "../util/logger.js";
import { classifyIntent } from "../nlp/intent.js";
import { extractEntities, memoryHints } from "../nlp/entities.js";
import type { Message } from "../providers.js";
import {
  EXTRACTOR_SYSTEM,
  buildExtractorUser,
  detectExplicit,
  formatMemoryBlock,
  mergeWithNearest,
  parseOps,
  planOps,
  type ExistingMemory,
  type Op,
  type RecalledMemory,
} from "./logic.js";
import {
  countMemories,
  createMemory,
  deleteMemory,
  embedMemory,
  memoryEnabled,
  pinnedMemories,
  recentMemories,
  similarMemories,
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

export type MemoryChange = { op: "ADD" | "UPDATE" | "DELETE"; id: string; text: string };

export type MemoryTurn = {
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

  let enabled: Promise<boolean> | null = null;
  const isEnabled = () => (enabled ??= memoryEnabled(userId).catch(() => false));
  const embed = (q: string) => embedQueries([q.slice(0, 1000)]).then((v) => v[0], () => null);

  const recall = async (query?: string, opts: { embed?: boolean } = {}): Promise<string | null> => {
    try {
      if (!(await isEnabled())) return null;
      // Small talk needs no semantic match: pinned and the latest memories are enough (no embedding call).
      const v = opts.embed === false ? null : await embed(query?.trim() || text);
      const [pinned, related] = await Promise.all([
        pinnedMemories(userId),
        v ? similarMemories(userId, v, RECALL_K).then((r) => r.filter((m) => m.sim >= RECALL_MIN_SIM)) : recentMemories(userId, opts.embed === false ? 3 : RECALL_K),
      ]);
      const seen = new Set<string>();
      const picked: RecalledMemory[] = [];
      for (const m of [...pinned, ...related]) {
        if (!seen.has(m.id)) {
          seen.add(m.id);
          picked.push(m);
        }
      }
      const block = formatMemoryBlock(picked);
      if (block) void touchMemories(userId, picked.map((m) => m.id)).catch(() => {});
      return block;
    } catch (e) {
      log.warn("memory recall failed", { error: (e as Error).message?.slice(0, 120) });
      return null;
    }
  };

  const extraction = (async (): Promise<MemoryChange[]> => {
    try {
      if (!(await isEnabled())) return [];
      const explicit = detectExplicit(text);
      const plan = extractionPlan(text, !!explicit, classifyIntent(text));
      if (plan === "skip") return [];
      const item = { text, prevAssistant: input.prevAssistant };
      if (plan === "batch") {
        // No model call now: one call per few personal turns of this conversation, or when it goes quiet.
        batcher.add(`${userId}|${input.conversationId ?? ""}`, { ...item, userId, conversationId: input.conversationId });
        return [];
      }
      return await extractNow(userId, [item], explicit, input.conversationId);
    } catch (e) {
      log.warn("memory extraction error", { error: (e as Error).message?.slice(0, 120) });
      return [];
    }
  })();

  return { recall, extraction };
}

type Pending = { text: string; prevAssistant?: string; userId: string; conversationId?: string };

/** One extraction call over [items] (one explicit turn, or a few batched ones). Never throws. */
async function extractNow(userId: string, items: Array<{ text: string; prevAssistant?: string }>, explicit: ReturnType<typeof detectExplicit>, conversationId: string | undefined): Promise<MemoryChange[]> {
  const last = items[items.length - 1]!;
  const userText = items.length === 1 ? last.text : items.map((i) => i.text.slice(0, 600)).join("\n---\n");
  const v = await embedQueries([last.text.slice(0, 1000)]).then((r) => r[0], () => null);
  const existing: ExistingMemory[] = v ? await similarMemories(userId, v, EXTRACT_CANDIDATES) : await recentMemories(userId, EXTRACT_CANDIDATES);
  const messages: Message[] = [
    { role: "system", content: EXTRACTOR_SYSTEM },
    { role: "user", content: buildExtractorUser({ userText, assistantText: items.length === 1 ? last.prevAssistant : undefined, existing, explicit, hints: memoryHints(extractEntities(userText)) }) },
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
  const plan = planOps(proposed, existing, { explicit, total: await countMemories(userId) });
  return apply(userId, plan, conversationId);
}

const batcher = new TurnBatcher<Pending>(async (_key, items) => {
  const first = items[0]!;
  try {
    if (!(await memoryEnabled(first.userId).catch(() => false))) return;
    const changes = await extractNow(first.userId, items, null, first.conversationId);
    log.info("memory batch", { turns: items.length, changes: changes.length });
  } catch (e) {
    log.warn("memory batch failed", { error: (e as Error).message?.slice(0, 120) });
  }
});

/** Applies a validated plan. ADDs get an embedding-level duplicate check first. */
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
        const row = await updateMemory(userId, op.id, { text: op.text, kind: op.kind });
        if (row) changes.push({ op: "UPDATE", id: row.id, text: row.text });
      } else {
        const vec = await embedMemory(op.text);
        const nearest = vec ? (await similarMemories(userId, vec, 1))[0] ?? null : null;
        const final = mergeWithNearest(op, nearest, deleted);
        if (!final) continue;
        if (final.op === "UPDATE") {
          const row = await updateMemory(userId, final.id, { text: final.text, kind: final.kind }, vec);
          if (row) changes.push({ op: "UPDATE", id: row.id, text: row.text });
        } else if (final.op === "ADD") {
          const row = await createMemory(userId, { text: final.text, kind: final.kind, conversationId, vec, pinned: false });
          changes.push({ op: "ADD", id: row.id, text: row.text });
        }
      }
    } catch (e) {
      log.warn("memory apply failed", { op: op.op, error: (e as Error).message?.slice(0, 120) });
    }
  }
  return changes;
}
