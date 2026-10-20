import { DEFAULT_PREFERENCES, TEXT_SCALE, preferencesSchema, type Preferences } from "./schema";

export const PREFERENCES_KEY = "sparky-preferences";

type Listener = () => void;
const listeners = new Set<Listener>();
let cache: Preferences | null = null;

export const parsePreferences = (raw: string | null): Preferences => {
  if (!raw) return DEFAULT_PREFERENCES;
  try {
    return preferencesSchema.parse({ ...DEFAULT_PREFERENCES, ...JSON.parse(raw) });
  } catch {
    return DEFAULT_PREFERENCES;
  }
};

export const readPreferences = (): Preferences => {
  if (cache) return cache;
  try {
    cache = parsePreferences(localStorage.getItem(PREFERENCES_KEY));
  } catch {
    cache = DEFAULT_PREFERENCES;
  }
  return cache;
};

export const applyTextSize = (size: Preferences["textSize"]): void => {
  document.documentElement.style.setProperty("zoom", String(TEXT_SCALE[size]));
};

export const writePreferences = (patch: Partial<Preferences>): Preferences => {
  const next = preferencesSchema.parse({ ...readPreferences(), ...patch });
  cache = next;
  try {
    localStorage.setItem(PREFERENCES_KEY, JSON.stringify(next));
  } catch {
    // storage unavailable: the choice lasts for this tab only
  }
  applyTextSize(next.textSize);
  listeners.forEach((listener) => listener());
  return next;
};

export const resetPreferences = (): Preferences => {
  cache = null;
  try {
    localStorage.removeItem(PREFERENCES_KEY);
  } catch {
    // storage unavailable
  }
  cache = DEFAULT_PREFERENCES;
  applyTextSize(DEFAULT_PREFERENCES.textSize);
  listeners.forEach((listener) => listener());
  return cache;
};

export const subscribePreferences = (listener: Listener): (() => void) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};

export const serverPreferences = (): Preferences => DEFAULT_PREFERENCES;
