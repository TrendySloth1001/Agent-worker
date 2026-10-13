import { Router } from "express";
import { z } from "zod";
import { userOf } from "../auth/context.js";
import { AppError } from "../util/errors.js";
import { decryptSecret, encryptSecret } from "../connections/crypto.js";
import { KEY_PROVIDERS, keyHintOf, keyProvider } from "../keys/catalog.js";
import { CHECK_MESSAGE, checkKey, type CheckResult } from "../keys/check.js";
import { cacheKey, keyRepo, type KeyRow, type KeyStatus } from "../keys/store.js";
import { USAGE_DAYS, userKeyUsage } from "../keys/usage.js";

/** Bring-your-own provider keys. Mounted at /me/keys; every route is the caller's own. */
export const keysRouter = Router();
/** The caller's own usage on their keys. Mounted at /me/usage. */
export const myUsageRouter = Router();

/** Test seam: the live check. */
export const deps = { check: checkKey as (p: Parameters<typeof checkKey>[0], key: string) => Promise<CheckResult> };

const uid = (req: Parameters<typeof userOf>[0]): string => {
  const id = userOf(req).id;
  if (!id) throw new AppError(403, "forbidden", "Keys need a signed-in account");
  return id;
};

const providerOf = (raw: string) => {
  const p = keyProvider(raw);
  if (!p) throw new AppError(404, "not_found", "Couldn't find that.");
  return p;
};

/** What the app may see of a stored key: never the key, only its last 4 characters and status. */
export function publicKey(r: KeyRow) {
  return { provider: r.provider, label: r.label, hint: r.keyHint, status: r.status, lastCheckedAt: r.lastCheckedAt?.toISOString() ?? null, createdAt: r.createdAt.toISOString() };
}

const putSchema = z.object({ key: z.string().max(400), label: z.string().max(40).optional() });

async function runCheck(userId: string, provider: string, plain: string): Promise<{ result: CheckResult; status: KeyStatus; checkedAt: Date }> {
  const result = await deps.check(provider as never, plain);
  const checkedAt = new Date();
  // "Couldn't reach provider" proves nothing about the key: keep whatever status it had.
  const status: KeyStatus | null = result === "network" ? null : result;
  if (status) {
    await keyRepo().setStatus(userId, provider, status, checkedAt);
    cacheKey(userId, provider, { key: plain, status, checkedAt: checkedAt.getTime() });
  }
  return { result, status: status ?? "untested", checkedAt };
}

keysRouter.get("/", async (req, res) => {
  const rows = new Map((await keyRepo().list(uid(req))).map((r) => [r.provider, r]));
  const providers = KEY_PROVIDERS.map((p) => ({ id: p.id, name: p.name, blurb: p.blurb, keyUrl: p.keyUrl, placeholder: p.placeholder, key: rows.has(p.id) ? publicKey(rows.get(p.id)!) : null }));
  res.json({ providers, hasValidKey: [...rows.values()].some((r) => r.status === "valid") });
});

keysRouter.put("/:provider", async (req, res) => {
  const userId = uid(req);
  const p = providerOf(req.params.provider);
  const body = putSchema.parse(req.body);
  const key = body.key.trim();
  if (!p.format.test(key)) throw new AppError(400, "bad_request", `That doesn't look like a ${p.name} key.`);
  const row = await keyRepo().upsert({ userId, provider: p.id, label: (body.label ?? "").trim(), keyEnc: encryptSecret(key), keyHint: keyHintOf(key) });
  cacheKey(userId, p.id, { key, status: "untested", checkedAt: 0 });
  const { result, status, checkedAt } = await runCheck(userId, p.id, key);
  res.json({ key: publicKey({ ...row, status, lastCheckedAt: result === "network" ? null : checkedAt }), result, message: CHECK_MESSAGE[result] });
});

keysRouter.post("/:provider/test", async (req, res) => {
  const userId = uid(req);
  const p = providerOf(req.params.provider);
  const row = await keyRepo().get(userId, p.id);
  if (!row) throw new AppError(404, "not_found", "Couldn't find that.");
  const { result, status, checkedAt } = await runCheck(userId, p.id, decryptSecret(row.keyEnc));
  res.json({ provider: p.id, status, result, message: CHECK_MESSAGE[result], checkedAt: result === "network" ? null : checkedAt.toISOString() });
});

keysRouter.delete("/:provider", async (req, res) => {
  const userId = uid(req);
  const p = providerOf(req.params.provider);
  await keyRepo().remove(userId, p.id);
  cacheKey(userId, p.id, null);
  res.json({ ok: true });
});

myUsageRouter.get("/keys", async (req, res) => {
  const userId = uid(req);
  const { days } = z.object({ days: z.coerce.number().refine((d) => (USAGE_DAYS as readonly number[]).includes(d), "days must be 7 or 30").default(7) }).parse(req.query);
  const hasKey = (await keyRepo().list(userId)).some((r) => r.status === "valid");
  res.json({ enabled: hasKey, ...(await userKeyUsage(userId, days)) });
});
