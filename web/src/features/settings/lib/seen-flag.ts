"use client";

import { useSyncExternalStore } from "react";

const PREFIX = "sparky-seen-";
const listeners = new Set<() => void>();
const memory = new Set<string>();

export const hasSeen = (name: string): boolean => {
  if (memory.has(name)) return true;
  try {
    return localStorage.getItem(PREFIX + name) === "1";
  } catch {
    return false;
  }
};

export const markSeen = (name: string): void => {
  memory.add(name);
  try {
    localStorage.setItem(PREFIX + name, "1");
  } catch {
    // storage unavailable: the flag lasts for this tab only
  }
  listeners.forEach((listener) => listener());
};

const subscribe = (listener: () => void): (() => void) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
};

export const useSeenFlag = (name: string): boolean =>
  useSyncExternalStore(
    subscribe,
    () => hasSeen(name),
    () => true,
  );
