import type { UserCrypto } from "../crypto/userData.js";

/**
 * What is sealed in conversations and their messages (see src/crypto/userData.ts). Ids, roles, models,
 * positions, counts, timestamps, usedIds, error flags and the `attachments` list (file id/name/mime/size,
 * which the files table holds in plaintext anyway and SQL joins on) stay plaintext.
 */
export const CONV = "conversations";
export const MSG = "conversation_messages";

type Json = unknown;

export type MessageFields = {
  content: string;
  citations: Json;
  images: Json;
  evidence: Json;
  meta: Json;
  table: Json | null | undefined;
};

/** Message columns as stored (sealed). */
export function sealMessage<T extends MessageFields>(c: UserCrypto, m: T): T {
  return {
    ...m,
    content: c.seal(MSG, "content", m.content),
    citations: c.sealJson(MSG, "citations", m.citations),
    images: c.sealJson(MSG, "images", m.images),
    evidence: c.sealJson(MSG, "evidence", m.evidence),
    meta: c.sealJson(MSG, "meta", m.meta),
    table: m.table == null ? m.table : c.sealJson(MSG, "table", m.table),
  };
}

/** Message columns as the app uses them (plaintext). Legacy plaintext rows pass through. */
export function openMessage<T extends Partial<MessageFields>>(c: UserCrypto, m: T): T {
  const out: Record<string, unknown> = { ...m };
  if (typeof m.content === "string") out.content = c.open(MSG, "content", m.content);
  for (const k of ["citations", "images", "evidence", "meta", "table"] as const) if (k in m && m[k] != null) out[k] = c.openJson(MSG, k, m[k]);
  return out as T;
}

export type ConversationText = { title?: string | null; preview?: string | null; summary?: string | null };

export function sealConversation<T extends ConversationText>(c: UserCrypto, r: T): T {
  const out: Record<string, unknown> = { ...r };
  for (const k of ["title", "preview", "summary"] as const) if (k in r && r[k] != null) out[k] = c.seal(CONV, k, r[k] as string);
  return out as T;
}

export function openConversationText<T extends ConversationText>(c: UserCrypto, r: T): T {
  const out: Record<string, unknown> = { ...r };
  for (const k of ["title", "preview", "summary"] as const) if (k in r && r[k] != null) out[k] = c.open(CONV, k, r[k] as string);
  return out as T;
}
