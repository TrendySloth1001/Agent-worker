import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, scryptSync } from "node:crypto";
import { config } from "../config.js";
import { parseKey } from "../connections/crypto.js";
import { db } from "../db/prisma.js";
import { AppError } from "../util/errors.js";
import { log } from "../util/logger.js";

/**
 * Envelope encryption of user content at rest.
 *
 *   DATA_KEY (env, master) --wraps--> per-user data key (users.data_key_enc) --seals--> field values
 *
 * Field values are stored as `enc:v1:<base64(iv[12] | tag[16] | ciphertext)>` (AES-256-GCM) with
 * AAD `<table>:<column>:<userId>`, so a ciphertext cannot be moved to another column, table or user.
 * Reads accept plaintext (legacy rows) and sealed values; writes always seal. JSON columns hold
 * `{"$enc": "enc:v1:..."}`. Wrapped data keys are `wk:v1:<masterKeyId>:<base64(iv|tag|ct)>` with AAD
 * `datakey:<userId>`; the key id names the master key that wrapped it, so a rotation can unwrap with
 * DATA_KEY_PREVIOUS and re-wrap (`pnpm data:encrypt --rewrap`). Keys and plaintext are never logged.
 */

export const SEALED_PREFIX = "enc:v1:";
const WRAPPED_PREFIX = "wk:v1:";
const IV_BYTES = 12;
const TAG_BYTES = 16;
/** Marker at the start of an encrypted object body (S3); anything else is a legacy plaintext object. */
const OBJECT_MAGIC = Buffer.from("SPKYENC1");

// ---- primitives (AES-256-GCM with AAD) ----------------------------------------------------------

function gcmSeal(key: Buffer, plain: Buffer, aad: string): Buffer {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const ct = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ct]);
}

function gcmOpen(key: Buffer, blob: Buffer, aad: string): Buffer {
  if (blob.length < IV_BYTES + TAG_BYTES) throw new Error("ciphertext too short");
  const decipher = createDecipheriv("aes-256-gcm", key, blob.subarray(0, IV_BYTES));
  decipher.setAAD(Buffer.from(aad, "utf8"));
  decipher.setAuthTag(blob.subarray(IV_BYTES, IV_BYTES + TAG_BYTES));
  return Buffer.concat([decipher.update(blob.subarray(IV_BYTES + TAG_BYTES)), decipher.final()]);
}

const decryptFailed = () => new AppError(500, "decrypt_failed", "Some saved data couldn't be read. Try again shortly.");

// ---- master keys --------------------------------------------------------------------------------

type MasterKey = { id: string; key: Buffer };
type Masters = { current: MasterKey; all: MasterKey[]; dev: boolean };

const keyId = (key: Buffer) => createHash("sha256").update("sparky-key-id").update(key).digest("hex").slice(0, 8);

let masters: Masters | null = null;

function loadMasters(): Masters {
  const current = parseKey(config.dataKey);
  let dev = false;
  let cur: Buffer;
  if (current) cur = current;
  else {
    if (config.production) throw new Error("DATA_KEY is required in production (32 bytes, base64 or hex)");
    // Dev only: a fixed derived key so local data survives restarts. Never used when NODE_ENV=production.
    dev = true;
    cur = scryptSync("sparky-dev-only-data-key", "sparky-dev-salt", 32);
    log.warn("DATA_KEY is not set: using a development-only key. Set DATA_KEY before deploying.");
  }
  const previous = (config.dataKeyPrevious ?? "")
    .split(",")
    .map((s) => parseKey(s))
    .filter((k): k is Buffer => !!k);
  const all = [cur, ...previous].map((key) => ({ id: keyId(key), key }));
  return { current: all[0], all, dev };
}

function getMasters(): Masters {
  masters ??= loadMasters();
  return masters;
}

/** Startup check: in production a missing/invalid DATA_KEY is fatal. */
export function assertDataKeyConfigured(): void {
  getMasters();
}

/** The current master key's short id (stored inside every wrapped data key). */
export const currentMasterKeyId = (): string => getMasters().current.id;

/** Tests: drop the cached master keys so the next call re-reads config. */
export function resetMasterKeysForTests(): void {
  masters = null;
  cache.clear();
}

export function wrapDataKey(userId: string, dataKey: Buffer, master: MasterKey = getMasters().current): string {
  return `${WRAPPED_PREFIX}${master.id}:${gcmSeal(master.key, dataKey, `datakey:${userId}`).toString("base64")}`;
}

export function unwrapDataKey(userId: string, wrapped: string): Buffer {
  if (!wrapped.startsWith(WRAPPED_PREFIX)) throw decryptFailed();
  const rest = wrapped.slice(WRAPPED_PREFIX.length);
  const sep = rest.indexOf(":");
  if (sep < 0) throw decryptFailed();
  const id = rest.slice(0, sep);
  const blob = Buffer.from(rest.slice(sep + 1), "base64");
  const { all } = getMasters();
  // The id names the wrapping key; fall back to trying every configured key (a fingerprint is only a hint).
  const ordered = [...all.filter((m) => m.id === id), ...all.filter((m) => m.id !== id)];
  for (const m of ordered) {
    try {
      return gcmOpen(m.key, blob, `datakey:${userId}`);
    } catch {
      /* try the next master key */
    }
  }
  throw decryptFailed();
}

/** The master key id a wrapped data key names (null when malformed). */
export function wrappedKeyId(wrapped: string): string | null {
  if (!wrapped.startsWith(WRAPPED_PREFIX)) return null;
  const rest = wrapped.slice(WRAPPED_PREFIX.length);
  const sep = rest.indexOf(":");
  return sep < 0 ? null : rest.slice(0, sep);
}

// ---- per-user data keys -------------------------------------------------------------------------

/** Where wrapped data keys live (users.data_key_enc); swappable for tests and scripts. */
export type KeyStore = {
  read(userId: string): Promise<string | null>;
  /** Stores [wrapped] only if the user has none yet; false when another writer got there first. */
  writeIfAbsent(userId: string, wrapped: string): Promise<boolean>;
  overwrite(userId: string, wrapped: string): Promise<void>;
};

export const dbKeyStore: KeyStore = {
  async read(userId) {
    const u = await db().user.findUnique({ where: { id: userId }, select: { dataKeyEnc: true } });
    if (!u) throw new AppError(404, "not_found", "Account not found");
    return u.dataKeyEnc ?? null;
  },
  async writeIfAbsent(userId, wrapped) {
    const r = await db().user.updateMany({ where: { id: userId, dataKeyEnc: null }, data: { dataKeyEnc: wrapped } });
    return r.count > 0;
  },
  async overwrite(userId, wrapped) {
    await db().user.updateMany({ where: { id: userId }, data: { dataKeyEnc: wrapped } });
  },
};

let store: KeyStore = dbKeyStore;
export function setKeyStore(s: KeyStore | null): void {
  store = s ?? dbKeyStore;
  cache.clear();
}

const KEY_TTL_MS = 5 * 60_000;
const KEY_CACHE_MAX = 2000;
const cache = new Map<string, { key: Buffer; exp: number }>();
const inflight = new Map<string, Promise<Buffer>>();

async function loadDataKey(userId: string): Promise<Buffer> {
  const wrapped = await store.read(userId);
  if (wrapped) return unwrapDataKey(userId, wrapped);
  const fresh = randomBytes(32);
  if (await store.writeIfAbsent(userId, wrapDataKey(userId, fresh))) return fresh;
  const winner = await store.read(userId); // lost a race with another request: use the key that won
  if (!winner) throw decryptFailed();
  return unwrapDataKey(userId, winner);
}

async function dataKeyOf(userId: string): Promise<Buffer> {
  const hit = cache.get(userId);
  if (hit && hit.exp > Date.now()) return hit.key;
  let p = inflight.get(userId);
  if (!p) {
    p = loadDataKey(userId)
      .then((key) => {
        if (cache.size >= KEY_CACHE_MAX) cache.delete(cache.keys().next().value!);
        cache.set(userId, { key, exp: Date.now() + KEY_TTL_MS });
        return key;
      })
      .finally(() => inflight.delete(userId));
    inflight.set(userId, p);
  }
  return p;
}

/** Re-wraps a user's data key with the current master key (rotation); false when it already is. */
export async function rewrapDataKey(userId: string): Promise<boolean> {
  const wrapped = await store.read(userId);
  if (!wrapped || wrappedKeyId(wrapped) === getMasters().current.id) return false;
  await store.overwrite(userId, wrapDataKey(userId, unwrapDataKey(userId, wrapped)));
  cache.delete(userId);
  return true;
}

// ---- field helpers ------------------------------------------------------------------------------

export const isSealed = (v: unknown): v is string => typeof v === "string" && v.startsWith(SEALED_PREFIX);

/** `{"$enc": "enc:v1:..."}`: how a JSON column value is stored. */
export const isSealedJson = (v: unknown): boolean => !!v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === 1 && isSealed((v as { $enc?: unknown }).$enc);

const aadOf = (table: string, column: string, userId: string) => `${table}:${column}:${userId}`;

/** Sync sealing/opening for one user (get it with userCrypto(); a null user passes everything through). */
export type UserCrypto = {
  userId: string | null;
  seal(table: string, column: string, text: string): string;
  /** Plaintext passes through; a sealed value is decrypted (throws decrypt_failed when it cannot be). */
  open(table: string, column: string, stored: string): string;
  sealNullable(table: string, column: string, text: string | null | undefined): string | null;
  openNullable(table: string, column: string, stored: string | null | undefined): string | null;
  sealJson(table: string, column: string, value: unknown): unknown;
  openJson<T = unknown>(table: string, column: string, stored: unknown): T;
  sealBytes(scope: string, bytes: Buffer): Buffer;
  openBytes(scope: string, stored: Buffer): Buffer;
  /** Deterministic keyed hash for equality lookups on a value that must stay unique (not reversible). */
  blindIndex(table: string, column: string, value: string): string;
};

function build(userId: string, key: Buffer): UserCrypto {
  const seal = (table: string, column: string, text: string) => (text === "" ? "" : SEALED_PREFIX + gcmSeal(key, Buffer.from(text, "utf8"), aadOf(table, column, userId)).toString("base64"));
  const open = (table: string, column: string, stored: string) => {
    if (!isSealed(stored)) return stored;
    try {
      return gcmOpen(key, Buffer.from(stored.slice(SEALED_PREFIX.length), "base64"), aadOf(table, column, userId)).toString("utf8");
    } catch {
      throw decryptFailed();
    }
  };
  const indexKey = createHmac("sha256", key).update("blind-index-v1").digest();
  const objectAad = (scope: string) => `object:${scope}:${userId}`;
  return {
    userId,
    seal,
    open,
    sealNullable: (t, c, v) => (v == null ? null : seal(t, c, v)),
    openNullable: (t, c, v) => (v == null ? null : open(t, c, v)),
    sealJson: (table, column, value) => {
      if (value === null || value === undefined) return value;
      if (Array.isArray(value) ? value.length === 0 : typeof value === "object" && Object.keys(value as object).length === 0) return value; // nothing to hide
      return { $enc: seal(table, column, JSON.stringify(value)) };
    },
    openJson: <T>(table: string, column: string, stored: unknown): T => {
      if (!isSealedJson(stored)) return stored as T;
      return JSON.parse(open(table, column, (stored as { $enc: string }).$enc)) as T;
    },
    sealBytes: (scope, bytes) => Buffer.concat([OBJECT_MAGIC, gcmSeal(key, bytes, objectAad(scope))]),
    openBytes: (scope, stored) => {
      if (!isSealedObject(stored)) return stored;
      try {
        return gcmOpen(key, stored.subarray(OBJECT_MAGIC.length), objectAad(scope));
      } catch {
        throw decryptFailed();
      }
    },
    blindIndex: (table, column, value) => `h1:${createHmac("sha256", indexKey).update(`${table}:${column}:${value}`).digest("hex").slice(0, 32)}`,
  };
}

/** Passthrough for rows that belong to no user yet (data from before accounts existed). */
const PASSTHROUGH: UserCrypto = {
  userId: null,
  seal: (_t, _c, text) => text,
  open: (_t, _c, stored) => stored,
  sealNullable: (_t, _c, v) => v ?? null,
  openNullable: (_t, _c, v) => v ?? null,
  sealJson: (_t, _c, v) => v,
  openJson: <T>(_t: string, _c: string, v: unknown) => v as T,
  sealBytes: (_s, b) => b,
  openBytes: (_s, b) => b,
  blindIndex: (_t, _c, v) => v,
};

export const isSealedObject = (b: Buffer): boolean => b.length > OBJECT_MAGIC.length + IV_BYTES + TAG_BYTES && b.subarray(0, OBJECT_MAGIC.length).equals(OBJECT_MAGIC);

/** The sealing/opening handle for [userId] (creates the user's data key on first use). */
export async function userCrypto(userId: string | null | undefined): Promise<UserCrypto> {
  if (!userId) return PASSTHROUGH;
  return build(userId, await dataKeyOf(userId));
}

/** Seals one field value for a user (async because the data key may need loading). */
export async function sealFor(userId: string | null | undefined, table: string, column: string, text: string): Promise<string> {
  return (await userCrypto(userId)).seal(table, column, text);
}

/** Opens one field value; plaintext (legacy) passes through. */
export async function openFor(userId: string | null | undefined, table: string, column: string, stored: string): Promise<string> {
  if (!isSealed(stored)) return stored;
  return (await userCrypto(userId)).open(table, column, stored);
}

/** Opens a user's rows with one key lookup. */
export async function openMany<T>(userId: string | null | undefined, rows: T[], fn: (c: UserCrypto, row: T) => T): Promise<T[]> {
  const c = await userCrypto(userId);
  return rows.map((r) => fn(c, r));
}

/** Server-only secret for signing short-lived file URLs, derived from the master key. */
export function urlSigningKey(): Buffer {
  return createHmac("sha256", getMasters().current.key).update("file-url-signing-v1").digest();
}
