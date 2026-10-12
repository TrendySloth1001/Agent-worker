import { log } from "../util/logger.js";
import { askSmall, extractJson, SMALL_MODELS } from "./smallModel.js";

const TIMEOUT_MS = 2_500;

const PROMPT = `You rank passages by how well they answer a question.
Given the question and numbered passages, return the numbers of the most relevant passages, best first. Omit passages that are irrelevant.
Reply with only JSON: {"ranking": [3, 1, 7]}`;

/**
 * LLM rerank of candidates (already ordered by fusion). Returns the candidate
 * ids best-first; any id the model left out keeps its relative order after the
 * ranked ones. Time-boxed: on any failure the input order is returned.
 */
export async function rerank<K>(query: string, items: Array<{ id: K; text: string }>): Promise<K[]> {
  const order = items.map((i) => i.id);
  if (items.length < 4) return order;
  const list = items.map((it, i) => `[${i + 1}] ${it.text.replace(/\s+/g, " ").slice(0, 280)}`).join("\n");
  const messages = [
    { role: "system" as const, content: PROMPT },
    { role: "user" as const, content: `Question: ${query.slice(0, 500)}\n\nPassages:\n${list}` },
  ];
  for (const model of SMALL_MODELS) {
    try {
      const raw = await askSmall(model, messages, "kb-rerank", TIMEOUT_MS);
      const parsed = extractJson(raw, "{") as { ranking?: unknown };
      if (!Array.isArray(parsed.ranking)) throw new Error("bad ranking");
      const picked: K[] = [];
      for (const n of parsed.ranking) {
        const it = items[Number(n) - 1];
        if (it && !picked.includes(it.id)) picked.push(it.id);
      }
      if (picked.length === 0) return order;
      return [...picked, ...order.filter((id) => !picked.includes(id))];
    } catch (e) {
      log.warn("rerank failed", { model, message: (e as Error).message?.slice(0, 100) });
    }
  }
  return order;
}
