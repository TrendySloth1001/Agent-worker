"use client";

import { createContext, useCallback, useContext, useMemo, useSyncExternalStore } from "react";
import {
  applyTheme,
  readStoredTheme,
  resolveTheme,
  writeStoredTheme,
  type ResolvedTheme,
  type Theme,
} from "@/lib/theme";

interface ThemeContextValue {
  theme: Theme;
  resolved: ResolvedTheme;
  setTheme: (theme: Theme) => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

const listeners = new Set<() => void>();

const subscribe = (fn: () => void): (() => void) => {
  listeners.add(fn);
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", fn);
  window.addEventListener("storage", fn);
  return () => {
    listeners.delete(fn);
    mq.removeEventListener("change", fn);
    window.removeEventListener("storage", fn);
  };
};

const getTheme = (): Theme => readStoredTheme();
const getServerTheme = (): Theme => "system";
const getResolved = (): ResolvedTheme => resolveTheme(readStoredTheme());
const getServerResolved = (): ResolvedTheme => "light";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useSyncExternalStore(subscribe, getTheme, getServerTheme);
  const resolved = useSyncExternalStore(subscribe, getResolved, getServerResolved);

  const setTheme = useCallback((next: Theme) => {
    writeStoredTheme(next);
    applyTheme(next);
    listeners.forEach((fn) => fn());
  }, []);

  const value = useMemo(() => ({ theme, resolved, setTheme }), [theme, resolved, setTheme]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used inside ThemeProvider");
  return ctx;
}
