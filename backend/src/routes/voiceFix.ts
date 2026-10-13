import { Router } from "express";
import { z } from "zod";
import { userOf } from "../auth/context.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { fixTranscript, MAX_FIX_CHARS, noteLocalSamples, type ModelCall } from "../assist/fixTranscript.js";
import { slotMemories } from "../memory/store.js";
import { parseNameCard } from "../memory/slots.js";
import { allMyRepos } from "../github/service.js";
import { perUser } from "./suggest.js";

const turn = z.object({ role: z.enum(["user", "assistant"]), content: z.string().max(4_000) });
const bodySchema = z.object({
  text: z.string().max(MAX_FIX_CHARS * 2),
  // Privacy: only the last two messages are ever read.
  context: z.array(turn).max(10).optional(),
  language: z.string().max(20).optional(),
  exact: z.boolean().optional(),
  vocab: z.array(z.string().max(60)).max(60).optional(),
  confident: z.boolean().optional(),
  /** On-device pass timings since the last request (ms), for owner telemetry. */
  localMs: z.array(z.number().min(0).max(60_000)).max(50).optional(),
});

const VOCAB_TIMEOUT_MS = 2_500;
const MAX_REPOS = 30;

/** [fake] replaces the model in tests. */
export function voiceFixRouter(fake?: ModelCall): Router {
  const r = Router();

  // POST /assist/fix-transcript {text, context?, language?, exact?, vocab?} -> {text, changes[], source, ms}
  r.post("/fix-transcript", perUser(120), async (req, res) => {
    const body = bodySchema.safeParse(req.body);
    if (!body.success) throw new AppError(400, "bad_request", "Nothing to fix.");
    const b = body.data;
    noteLocalSamples(b.localMs);
    const ctl = new AbortController();
    res.on("close", () => {
      if (!res.writableFinished) ctl.abort();
    });
    const out = await fixTranscript(
      { text: b.text, context: b.context?.slice(-2), language: b.language, exact: b.exact, vocab: b.vocab, confident: b.confident },
      { signal: ctl.signal, ...(fake ? { call: fake, models: ["fake:model"] } : {}) },
    );
    // Lengths and timings only: the transcript itself is never logged.
    log.info("transcript-fix", { source: out.source, ms: out.ms, chars: b.text.length, changes: out.changes.length, ...(out.reason ? { reason: out.reason } : {}) });
    if (!ctl.signal.aborted) res.json(out);
  });

  // GET /assist/voice-vocab -> {words[]}: names and repositories the recognizer should spell right.
  r.get("/voice-vocab", perUser(20), async (req, res) => {
    const uid = userOf(req).id;
    const words: string[] = [];
    try {
      for (const m of uid ? await slotMemories(uid, ["name"]) : []) {
        const card = parseNameCard(m.text);
        if (card.full) words.push(card.full);
        if (card.nick) words.push(card.nick);
      }
    } catch {
      // No database: no names.
    }
    try {
      const repos = await Promise.race([allMyRepos(), new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), VOCAB_TIMEOUT_MS).unref())]);
      for (const repo of repos.slice(0, MAX_REPOS)) words.push(repo.name);
    } catch {
      // No GitHub connection (or slow): names only.
    }
    res.json({ words: [...new Set(words.map((w) => w.trim()).filter((w) => w.length >= 2 && w.length <= 40))] });
  });

  return r;
}
