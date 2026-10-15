import { Router } from "express";
import { z } from "zod";
import { requireOwner, userOf } from "../auth/context.js";
import { checkPassword } from "../auth/service.js";
import { config } from "../config.js";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";
import { AttemptLimiter, openVault, sealVault, serialized, type KdfParams } from "./crypto.js";

export const VAULT_KIND = "data_key";

export type VaultRow = { userId: string; kind: string; ciphertext: string; salt: string; params: KdfParams; createdAt: Date; updatedAt: Date };

export interface VaultStore {
  get(userId: string, kind: string): Promise<VaultRow | null>;
  put(userId: string, kind: string, v: { ciphertext: string; salt: string; params: KdfParams }): Promise<void>;
  markReseal(userId: string, kind: string): Promise<void>;
}

export const prismaStore: VaultStore = {
  async get(userId, kind) {
    const r = await db().ownerVault.findUnique({ where: { userId_kind: { userId, kind } } });
    return r ? { ...r, params: r.params as unknown as KdfParams } : null;
  },
  async put(userId, kind, v) {
    const params = v.params as unknown as object;
    await db().ownerVault.upsert({
      where: { userId_kind: { userId, kind } },
      create: { userId, kind, ciphertext: v.ciphertext, salt: v.salt, params },
      update: { ciphertext: v.ciphertext, salt: v.salt, params, updatedAt: new Date() },
    });
  },
  async markReseal(userId, kind) {
    const r = await prismaStore.get(userId, kind);
    if (r) await db().ownerVault.update({ where: { userId_kind: { userId, kind } }, data: { params: { ...r.params, needsReseal: true } as object } });
  },
};

export type VaultDeps = {
  store: VaultStore;
  /** The user's password hash (null: none set), or undefined when the user is unknown. */
  passwordHashOf: (userId: string) => Promise<string | null | undefined>;
  dataKey: () => string | undefined;
  limiter: AttemptLimiter;
};

const sharedLimiter = new AttemptLimiter();

const defaultDeps = (): VaultDeps => ({
  store: prismaStore,
  passwordHashOf: async (id) => (await db().user.findUnique({ where: { id }, select: { passwordHash: true } }))?.passwordHash,
  dataKey: () => config.dataKey,
  limiter: sharedLimiter,
});

const body = z.object({ password: z.string().min(1).max(200) });

/** Fresh password re-check: rate limited, constant-time verify. Logs metadata only. */
async function recheck(d: VaultDeps, userId: string, action: string, password: string): Promise<void> {
  const wait = d.limiter.lockedFor(userId);
  if (wait > 0) {
    log.warn("vault locked", { action, user: userId, retryAfterS: wait });
    throw new AppError(429, "vault_locked", `Too many wrong passwords. Try again in ${Math.ceil(wait / 60)} min.`, true);
  }
  const hash = await d.passwordHashOf(userId);
  if (hash === undefined) throw new AppError(401, "unauthorized", "Session expired");
  if (hash === null) throw new AppError(409, "password_not_set", "Set a password in Profile first");
  const ok = await checkPassword(hash, password);
  if (!ok) {
    d.limiter.fail(userId);
    log.warn("vault password rejected", { action, user: userId });
    throw new AppError(403, "wrong_password", "Password is wrong");
  }
  d.limiter.success(userId);
  log.info("vault password accepted", { action, user: userId });
}

/** Owner-only recovery vault, mounted at /admin/vault. Passwords are only ever read from the POST body. */
export function vaultRouter(deps: Partial<VaultDeps> = {}): Router {
  const d = { ...defaultDeps(), ...deps };
  const r = Router();
  r.use(requireOwner);
  r.use((req, res, next) => {
    res.setHeader("Cache-Control", "no-store");
    const u = userOf(req);
    if (!u.id || u.bypass) return next(new AppError(403, "forbidden", "Sign in as the owner with your password"));
    next();
  });

  r.get("/", async (req, res) => {
    const row = await d.store.get(userOf(req).id!, VAULT_KIND);
    res.json({ exists: !!row, kind: row?.kind ?? null, updatedAt: row?.updatedAt.toISOString() ?? null, needsReseal: !!row?.params.needsReseal });
  });

  r.post("/seed", async (req, res) => {
    const uid = userOf(req).id!;
    const { password } = body.parse(req.body ?? {});
    await recheck(d, uid, "seed", password);
    const key = d.dataKey();
    if (!key) throw new AppError(409, "no_data_key", "The server has no DATA_KEY to store");
    await d.store.put(uid, VAULT_KIND, await serialized(() => sealVault(password, key, uid, VAULT_KIND)));
    const row = await d.store.get(uid, VAULT_KIND);
    res.json({ exists: true, kind: VAULT_KIND, updatedAt: row?.updatedAt.toISOString() ?? null, needsReseal: false });
  });

  r.post("/reveal", async (req, res) => {
    const uid = userOf(req).id!;
    const { password } = body.parse(req.body ?? {});
    await recheck(d, uid, "reveal", password);
    const row = await d.store.get(uid, VAULT_KIND);
    if (!row) throw new AppError(404, "vault_empty", "The vault is not set up yet");
    if (row.params.needsReseal) throw new AppError(409, "needs_reseal", "Your password changed. Set up the vault again.");
    let secret: string;
    try {
      secret = await serialized(() => openVault(password, row, uid, VAULT_KIND));
    } catch {
      throw new AppError(409, "needs_reseal", "The vault could not be opened. Set it up again.");
    }
    res.json({ kind: row.kind, secret });
  });
  return r;
}

/**
 * Called after the owner changes their password: re-wraps the vault old -> new.
 * If it can't (no old password, undecryptable), marks it "needs re-seal". Never throws.
 */
export async function rewrapVault(userId: string, oldPassword: string | undefined, newPassword: string, store: VaultStore = prismaStore): Promise<"none" | "rewrapped" | "needs_reseal"> {
  try {
    const row = await store.get(userId, VAULT_KIND);
    if (!row) return "none";
    if (!oldPassword || row.params.needsReseal) {
      await store.markReseal(userId, VAULT_KIND);
      return "needs_reseal";
    }
    const plain = await serialized(() => openVault(oldPassword, row, userId, VAULT_KIND));
    await store.put(userId, VAULT_KIND, await serialized(() => sealVault(newPassword, plain, userId, VAULT_KIND)));
    return "rewrapped";
  } catch {
    log.warn("vault rewrap failed", { user: userId });
    await store.markReseal(userId, VAULT_KIND).catch(() => undefined);
    return "needs_reseal";
  }
}
