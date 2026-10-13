// Long-term memory API. Every route is scoped to the caller; another user's
// memory reads as 404.
import { Router } from "express";
import { z } from "zod";
import { userOf } from "../auth/context.js";
import { AppError } from "../util/errors.js";
import { chatRecallEnabled, setChatRecallEnabled } from "../recall/index.js";
import { MAX_MEMORIES, MAX_TEXT, KINDS, cleanText, looksSensitive } from "../memory/logic.js";
import { slotOf } from "../memory/slots.js";
import {
  countMemories,
  createMemory,
  deleteAllMemories,
  deleteMemory,
  listMemories,
  memoryEnabled,
  publicMemory,
  setMemoryEnabled,
  updateMemory,
} from "../memory/store.js";
import { USER_MSG } from "../util/userMessages.js";

export const memoryRouter = Router();

const uid = (req: Parameters<typeof userOf>[0]): string => {
  const id = userOf(req).id;
  if (!id) throw new AppError(403, "forbidden", "Memory needs a signed-in account");
  return id;
};

const textField = z.string().transform(cleanText).refine((s) => s.length >= 2, "text is too short").refine((s) => !looksSensitive(s), "looks like a secret; not saved");

const createSchema = z.object({
  text: textField,
  kind: z.enum(KINDS).default("fact"),
  pinned: z.boolean().default(false),
});

const patchSchema = z
  .object({ text: textField.optional(), kind: z.enum(KINDS).optional(), pinned: z.boolean().optional() })
  .refine((b) => Object.keys(b).length > 0, "nothing to change");

const listSchema = z.object({
  q: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(200),
  offset: z.coerce.number().int().min(0).default(0),
});

function parse<T extends z.ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) throw new AppError(400, "bad_request", USER_MSG.badRequest);
  return r.data;
}

// GET /memory?q=&limit=&offset= -> { enabled, total, items }
memoryRouter.get("/", async (req, res) => {
  const userId = uid(req);
  const q = parse(listSchema, req.query);
  const [{ items, total }, enabled, chatRecall] = await Promise.all([listMemories(userId, q), memoryEnabled(userId), chatRecallEnabled(userId)]);
  res.json({ enabled, chatRecall, total, max: MAX_MEMORIES, maxTextLength: MAX_TEXT, items: items.map(publicMemory) });
});

// GET /memory/settings -> { enabled, count, chatRecall }
memoryRouter.get("/settings", async (req, res) => {
  const userId = uid(req);
  const [enabled, count, chatRecall] = await Promise.all([memoryEnabled(userId), countMemories(userId), chatRecallEnabled(userId)]);
  res.json({ enabled, count, chatRecall });
});

// PUT /memory/settings { enabled?, chatRecall? }
// chatRecall: search the user's past chats ("have we talked about this?"). Turning it off drops the index; on rebuilds it.
memoryRouter.put("/settings", async (req, res) => {
  const userId = uid(req);
  const body = parse(z.object({ enabled: z.boolean().optional(), chatRecall: z.boolean().optional() }), req.body);
  if (body.enabled !== undefined) await setMemoryEnabled(userId, body.enabled);
  if (body.chatRecall !== undefined) await setChatRecallEnabled(userId, body.chatRecall);
  const [enabled, count, chatRecall] = await Promise.all([memoryEnabled(userId), countMemories(userId), chatRecallEnabled(userId)]);
  res.json({ enabled, count, chatRecall });
});

// POST /memory { text, kind?, pinned? }
memoryRouter.post("/", async (req, res) => {
  const userId = uid(req);
  const body = parse(createSchema, req.body);
  if ((await countMemories(userId)) >= MAX_MEMORIES) throw new AppError(409, "limit_reached", `Memory is full (${MAX_MEMORIES} items). Delete some first.`);
  // Hand-written notes get their slot too ("Lives in Pune." is the location), so chat updates it in place.
  const row = await createMemory(userId, { ...body, slot: slotOf(body.text, body.kind) });
  res.status(201).json(publicMemory(row));
});

// PATCH /memory/:id { text?, kind?, pinned? }
memoryRouter.patch("/:id", async (req, res) => {
  const userId = uid(req);
  const patch = parse(patchSchema, req.body);
  const row = await updateMemory(userId, String(req.params.id), patch.text !== undefined ? { ...patch, slot: slotOf(patch.text, patch.kind) } : patch);
  if (!row) throw new AppError(404, "not_found", "Memory not found");
  res.json(publicMemory(row));
});

// DELETE /memory  -> clears everything (registered before /:id)
memoryRouter.delete("/", async (req, res) => {
  const deleted = await deleteAllMemories(uid(req));
  res.json({ deleted });
});

// DELETE /memory/:id
memoryRouter.delete("/:id", async (req, res) => {
  if (!(await deleteMemory(uid(req), String(req.params.id)))) throw new AppError(404, "not_found", "Memory not found");
  res.status(204).end();
});
