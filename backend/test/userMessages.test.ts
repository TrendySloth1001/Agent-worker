import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { isUserSafe, USER_MSG, userMessage } from "../src/util/userMessages.js";
import { AppError, errorBody, errorMiddleware } from "../src/util/errors.js";
import { ALL_BUSY_MESSAGE, ALL_QUOTA_MESSAGE } from "../src/llm/router.js";

/** Words a user should never read in an error or notice. */
const BANNED = /\b(429|5\d\d|Exception|stack(?!\s*overflow)|undefined|null|provider|quota|ollama|groq|openrouter|nvidia)\b/i;

test("user messages: every friendly constant is free of developer words", () => {
  for (const [key, msg] of Object.entries(USER_MSG)) {
    assert.ok(!BANNED.test(msg), `${key}: ${msg}`);
    assert.ok(isUserSafe(msg), `${key} should pass isUserSafe: ${msg}`);
  }
  for (const msg of [ALL_BUSY_MESSAGE, ALL_QUOTA_MESSAGE]) assert.ok(!BANNED.test(msg), msg);
});

test("user messages: raw upstream and developer text is replaced", () => {
  const raw = [
    "Ollama quota exhausted until 2026-11-01T00:00:00.000Z",
    "429 Too Many Requests",
    "Model rejected the request: 400 invalid_request_error",
    "GitHub is not configured (GITHUB_TOKEN)",
    "Expected multipart/form-data with a `file` field",
    "groq:openai/gpt-oss-20b failed, trying nvidia:openai/gpt-oss-20b.",
    "fetch failed: ECONNRESET",
    "Cannot read properties of undefined (reading 'x')",
    "messages.0.content: content must not be empty",
  ];
  for (const r of raw) {
    assert.equal(isUserSafe(r), false, r);
    const out = userMessage("upstream_failed", r);
    assert.ok(!BANNED.test(out), out);
  }
  assert.equal(userMessage("rate_limited", "429"), USER_MSG.slowDown);
  assert.equal(userMessage("bad_request", "x: Required"), USER_MSG.badRequest);
  assert.equal(userMessage("weird_code", "HTTP 502"), USER_MSG.generic);
  // Friendly text passes through untouched.
  assert.equal(userMessage("not_found", "Conversation not found"), "Conversation not found");
  assert.equal(userMessage("daily_limit", "You've used all 50 chats for today."), "You've used all 50 chats for today.");
});

test("user messages: errorBody and the error middleware never leak raw text", () => {
  assert.equal(errorBody("unavailable", "Ollama quota exhausted until 2026-11-01").error.message, USER_MSG.unavailable);
  let sent: unknown = null;
  const res = { headersSent: false, status: () => res, json: (b: unknown) => (sent = b) } as never;
  errorMiddleware(new AppError(502, "upstream_failed", "GitHub error 502", true), {} as never, res, () => {});
  assert.equal((sent as { error: { message: string } }).error.message, USER_MSG.unavailable);
  errorMiddleware(new Error("Cannot read properties of null"), {} as never, res, () => {});
  assert.equal((sent as { error: { message: string } }).error.message, USER_MSG.generic);
});

// ---- source scan: the literal text of AppError messages and SSE notices ----------

function* tsFiles(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (name === "generated") continue;
    if (statSync(p).isDirectory()) yield* tsFiles(p);
    else if (p.endsWith(".ts")) yield p;
  }
}

/** Owner-only surfaces, where technical detail is wanted. */
const OWNER_ONLY = [/routes\/telemetry\.ts$/, /routes\/usage\.ts$/];

test("user messages: AppError and notice literals in src are user-safe", () => {
  const offenders: string[] = [];
  const src = join(import.meta.dirname, "..", "src");
  for (const file of tsFiles(src)) {
    if (OWNER_ONLY.some((r) => r.test(file))) continue;
    const text = readFileSync(file, "utf8");
    const patterns = [
      /new AppError\(\s*\d+,\s*"[a-z_]+",\s*(["`])((?:\\.|(?!\1).)*)\1/g,
      /send\("(?:notice|doc_notice|error|doc_error)",\s*\{[^}]*message:\s*(["`])((?:\\.|(?!\1).)*)\1/g,
      /notice\("[a-z_]+",\s*(["`])((?:\\.|(?!\1).)*)\1/g,
    ];
    for (const re of patterns) {
      for (const m of text.matchAll(re)) {
        // Interpolations are checked by type, not text: blank them out.
        const literal = m[2].replace(/\$\{[^}]*\}/g, "X");
        if (BANNED.test(literal) || !isUserSafe(literal)) offenders.push(`${file.slice(src.length + 1)}: ${m[2]}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});
