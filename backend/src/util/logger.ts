import { createHash } from "node:crypto";
import { redactForLog } from "../nlp/pii.js";

// Meta fields that carry user content (search queries, prompts, message text): logged as length + short hash only,
// never the text, so logs stay useful for correlation without holding what users wrote.
const CONTENT_FIELDS = new Set(["query", "q", "text", "prompt", "question", "content", "input"]);
// Free-form fields (mostly error text) that may quote user text: scrubbed of PII.
const TEXT_FIELDS = new Set(["message", "error", "reason"]);
function scrub(meta?: object): object | undefined {
  if (!meta) return meta;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(meta)) {
    if (typeof v === "string" && CONTENT_FIELDS.has(k)) out[k] = `[${v.length} chars #${createHash("sha256").update(v).digest("hex").slice(0, 8)}]`;
    else out[k] = typeof v === "string" && TEXT_FIELDS.has(k) ? redactForLog(v, 400) : v;
  }
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
