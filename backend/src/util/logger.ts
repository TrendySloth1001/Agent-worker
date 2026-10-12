import { redactForLog } from "../nlp/pii.js";

// Meta fields that can carry user text; scrubbed of PII before they reach the log.
const TEXT_FIELDS = new Set(["query", "q", "text", "prompt", "question", "content", "message", "input"]);
function scrub(meta?: object): object | undefined {
  if (!meta) return meta;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(meta)) out[k] = typeof v === "string" && TEXT_FIELDS.has(k) ? redactForLog(v, 400) : v;
  return out;
}

function emit(level: "info" | "warn" | "error", msg: string, rawMeta?: object) {
  const meta = scrub(rawMeta);
  const line = `${new Date().toISOString()} ${level.toUpperCase()} ${msg}${meta ? " " + JSON.stringify(meta) : ""}`;
  (level === "info" ? console.log : level === "warn" ? console.warn : console.error)(line);
}

export const log = {
  info: (msg: string, meta?: object) => emit("info", msg, meta),
  warn: (msg: string, meta?: object) => emit("warn", msg, meta),
  error: (msg: string, meta?: object) => emit("error", msg, meta),
};
