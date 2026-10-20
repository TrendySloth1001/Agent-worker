export const QUICK_ASK_STORAGE_KEY = "sparky-quick-ask";
export const QUICK_ASK_PARAM = "quick";
export const QUICK_ASK_URL = `/chat?${QUICK_ASK_PARAM}=1`;
export const QUICK_ASK_MAX = 4000;

type HandoffStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

const browserStorage = (): HandoffStorage | null => {
  try {
    return typeof sessionStorage === "undefined" ? null : sessionStorage;
  } catch {
    return null;
  }
};

export function stashQuickAsk(
  prompt: string,
  storage: HandoffStorage | null = browserStorage(),
): boolean {
  const text = prompt.trim().slice(0, QUICK_ASK_MAX);
  if (!text || !storage) return false;
  try {
    storage.setItem(QUICK_ASK_STORAGE_KEY, text);
    return true;
  } catch {
    return false;
  }
}

export function takeQuickAsk(storage: HandoffStorage | null = browserStorage()): string | null {
  if (!storage) return null;
  try {
    const text = storage.getItem(QUICK_ASK_STORAGE_KEY);
    storage.removeItem(QUICK_ASK_STORAGE_KEY);
    return text?.trim() ? text : null;
  } catch {
    return null;
  }
}

interface ShortcutEvent {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
}

export const isQuickAskShortcut = (event: ShortcutEvent): boolean =>
  event.key.toLowerCase() === "k" &&
  event.shiftKey &&
  !event.altKey &&
  (event.metaKey || event.ctrlKey);
