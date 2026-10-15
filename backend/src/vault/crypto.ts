import { createCipheriv, createDecipheriv, randomBytes, scrypt } from "node:crypto";

/**
 * Recovery vault crypto. The secret is sealed with AES-256-GCM under a key derived from the owner's
 * password with scrypt. The derived key is never stored; only salt + KDF params + ciphertext are.
 *
 * KDF: scrypt N=2^17, r=8, p=1, 32-byte key, 16-byte random salt. Memory = 128*N*r = 128 MiB per
 * derivation (maxmem is set to 256 MiB), ~250-400 ms on a small VPS. Requests are serialized (one
 * derivation at a time) and rate limited, so peak extra memory stays ~128 MiB. The params are stored
 * per row, so they can be raised later without breaking existing vaults.
 */
export type KdfParams = { v: 1; kdf: "scrypt"; N: number; r: number; p: number; keyLen: 32; needsReseal?: boolean };
export const DEFAULT_PARAMS: KdfParams = { v: 1, kdf: "scrypt", N: 2 ** 17, r: 8, p: 1, keyLen: 32 };
const IV = 12;
const TAG = 16;

export const vaultAad = (userId: string, kind: string) => `vault:${userId}:${kind}`;

export function deriveKey(password: string, salt: Buffer, params: KdfParams = DEFAULT_PARAMS): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(Buffer.from(password.normalize("NFKC"), "utf8"), salt, params.keyLen, { N: params.N, r: params.r, p: params.p, maxmem: 256 * 1024 * 1024 }, (e, k) => (e ? reject(e) : resolve(k)));
  });
}

/** Seals [plain] under a key derived from [password]. */
export async function sealVault(password: string, plain: string, userId: string, kind: string, params: KdfParams = DEFAULT_PARAMS) {
  const salt = randomBytes(16);
  const key = await deriveKey(password, salt, params);
  const iv = randomBytes(IV);
  const c = createCipheriv("aes-256-gcm", key, iv);
  c.setAAD(Buffer.from(vaultAad(userId, kind)));
  const ct = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  const clean: KdfParams = { v: 1, kdf: "scrypt", N: params.N, r: params.r, p: params.p, keyLen: 32 };
  return { ciphertext: Buffer.concat([iv, c.getAuthTag(), ct]).toString("base64"), salt: salt.toString("base64"), params: clean };
}

/** Opens a sealed vault; throws if the password or the (user, kind) binding is wrong. */
export async function openVault(password: string, row: { ciphertext: string; salt: string; params: KdfParams }, userId: string, kind: string): Promise<string> {
  const key = await deriveKey(password, Buffer.from(row.salt, "base64"), row.params);
  const blob = Buffer.from(row.ciphertext, "base64");
  if (blob.length < IV + TAG) throw new Error("ciphertext too short");
  const d = createDecipheriv("aes-256-gcm", key, blob.subarray(0, IV));
  d.setAAD(Buffer.from(vaultAad(userId, kind)));
  d.setAuthTag(blob.subarray(IV, IV + TAG));
  return Buffer.concat([d.update(blob.subarray(IV + TAG)), d.final()]).toString("utf8");
}

/** Failed-attempt limiter: [max] failures per [windowMs] per user, then locked for [lockMs]. */
export class AttemptLimiter {
  private m = new Map<string, { fails: number[]; lockedUntil: number }>();
  constructor(
    private max = 5,
    private windowMs = 15 * 60_000,
    private lockMs = 15 * 60_000,
    private now: () => number = () => Date.now(),
  ) {}
  /** Seconds left on the lock, or 0. */
  lockedFor(id: string): number {
    const e = this.m.get(id);
    const t = this.now();
    if (!e || e.lockedUntil <= t) return 0;
    return Math.ceil((e.lockedUntil - t) / 1000);
  }
  fail(id: string): void {
    const t = this.now();
    const e = this.m.get(id) ?? { fails: [], lockedUntil: 0 };
    e.fails = e.fails.filter((x) => t - x < this.windowMs);
    e.fails.push(t);
    if (e.fails.length >= this.max) {
      e.lockedUntil = t + this.lockMs;
      e.fails = [];
    }
    this.m.set(id, e);
  }
  success(id: string): void {
    this.m.delete(id);
  }
}

/** One derivation at a time, so concurrent requests can't stack 128 MiB each. */
let chain: Promise<unknown> = Promise.resolve();
export function serialized<T>(fn: () => Promise<T>): Promise<T> {
  const r = chain.then(fn, fn);
  chain = r.catch(() => undefined);
  return r;
}
