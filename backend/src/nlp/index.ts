// One-call NLP analysis of a chat turn: language, intent and entities.
export * from "./entities.js";
export * from "./intent.js";
export * from "./language.js";

import { classifyIntent, type IntentOpts, type IntentResult } from "./intent.js";
import { detectLanguage, type LangResult } from "./language.js";
import { extractEntities, type Entity } from "./entities.js";

export type Analysis = { language: LangResult; intent: IntentResult; entities: Entity[]; ms: number };

/** [history] is the user's earlier messages, newest first. */
export function analyze(text: string, history: string[] = [], opts: IntentOpts = {}): Analysis {
  const t0 = performance.now();
  const language = detectLanguage(text, history);
  const intent = classifyIntent(text, opts);
  const entities = extractEntities(text);
  return { language, intent, entities, ms: Math.round((performance.now() - t0) * 100) / 100 };
}
