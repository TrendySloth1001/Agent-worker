import type { SessionStore, StoredTokens } from "../session-store";
import type { SessionTokens } from "../session-cookies";

export function memorySessionStore(initial: Partial<StoredTokens> = {}) {
  let current: StoredTokens = {
    accessToken: initial.accessToken ?? null,
    refreshToken: initial.refreshToken ?? null,
  };
  const writes: SessionTokens[] = [];
  let cleared = 0;
  const store: SessionStore = {
    read: () => current,
    write: (tokens) => {
      writes.push(tokens);
      current = { accessToken: tokens.accessToken, refreshToken: tokens.refreshToken };
    },
    clear: () => {
      cleared += 1;
      current = { accessToken: null, refreshToken: null };
    },
  };
  return { store, writes, cleared: () => cleared };
}
