import { Router, type NextFunction, type Request, type Response } from "express";
import { clientIp } from "../util/rateLimit.js";
import { z } from "zod";
import { db } from "../db/prisma.js";
import { userOf } from "../auth/context.js";
import { AppError } from "../util/errors.js";
import { completeText, endsInUrl, generateStarters } from "../assist/suggest.js";
import { detectLanguage } from "../nlp/language.js";

export const suggestRouter = Router();

const COMPLETE_TIMEOUT_MS = 1_500;
const STARTERS_TTL_MS = 10 * 60_000;

/** Per-user fixed-window limiter (the shared one is per IP). */
function perUser(max: number, windowMs = 60_000) {
  const hits = new Map<string, { count: number; resetAt: number }>();
  setInterval(() => {
    const now = Date.now();
    for (const [k, v] of hits) if (v.resetAt <= now) hits.delete(k);
  }, windowMs).unref();
  return (req: Request, _res: Response, next: NextFunction) => {
    const key = req.user?.id ?? clientIp(req);
    const now = Date.now();
    const e = hits.get(key);
    if (!e || e.resetAt <= now) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (++e.count > max) return next(new AppError(429, "rate_limited", "Too many requests, slow down.", true));
    next();
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const bodySchema = z.object({ text: z.string().max(2000), conversationId: z.string().max(64).optional() });

/** The last few turns of one of the caller's conversations, as compact text ("" if not theirs). */
async function recentContext(conversationId: string | undefined, uid: string | null): Promise<string> {
  if (!conversationId || !UUID_RE.test(conversationId)) return "";
  const id = conversationId.toLowerCase();
  try {
    const own = await db().conversation.findFirst({ where: { id, userId: uid }, select: { id: true } });
    if (!own) return "";
    const rows = await db().conversationMessage.findMany({
      where: { conversationId: id, role: { in: ["user", "assistant"] } },
      orderBy: { position: "desc" },
      take: 4,
      select: { role: true, content: true },
    });
    return rows
      .reverse()
      .map((r) => `${r.role}: ${r.content.replace(/\s+/g, " ").slice(0, 300)}`)
      .join("\n");
  } catch {
    return "";
  }
}

// POST /assist/complete {text, conversationId?} -> {completion, nextWords[]}
suggestRouter.post("/complete", perUser(90), async (req, res) => {
  const body = bodySchema.safeParse(req.body);
  if (!body.success) throw new AppError(400, "bad_request", "text: required");
  const { text, conversationId } = body.data;
  if (text.trim().length < 3 || endsInUrl(text)) {
    res.json({ completion: "", nextWords: [] });
    return;
  }
  const ctl = new AbortController();
  res.on("close", () => {
    if (!res.writableFinished) ctl.abort();
  });
  const context = await recentContext(conversationId, userOf(req).id);
  // The typed text decides the language; short text falls back to the recent conversation.
  const out = await completeText(text, context, COMPLETE_TIMEOUT_MS, ctl.signal, detectLanguage(text, context ? [context.slice(-600)] : []));
  if (!ctl.signal.aborted) res.json(out ?? { completion: "", nextWords: [] });
});

const starters = new Map<string, { at: number; prompts: string[] }>();

// GET /assist/starters -> {prompts[]} from the caller's recent chats ([] = use the built-in ones)
suggestRouter.get("/starters", perUser(20), async (req, res) => {
  const uid = userOf(req).id;
  const key = uid ?? "owner";
  const hit = starters.get(key);
  if (hit && Date.now() - hit.at < STARTERS_TTL_MS) {
    res.json({ prompts: hit.prompts });
    return;
  }
  const rows = await db().conversation.findMany({
    where: { userId: uid, archivedAt: null, title: { not: null } },
    orderBy: { updatedAt: "desc" },
    take: 8,
    select: { title: true },
  });
  const titles = rows.map((r) => r.title!).filter(Boolean);
  const prompts = titles.length >= 2 ? await generateStarters(titles, 6_000) : [];
  if (prompts.length > 0 || titles.length < 2) starters.set(key, { at: Date.now(), prompts });
  res.json({ prompts });
});
