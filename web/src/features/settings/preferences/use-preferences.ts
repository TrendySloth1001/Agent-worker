"use client";

import { useEffect, useSyncExternalStore } from "react";
import {
  applyTextSize,
  readPreferences,
  resetPreferences,
  serverPreferences,
  subscribePreferences,
  writePreferences,
} from "./store";
import type { Preferences } from "./schema";

export interface PreferencesApi {
  preferences: Preferences;
  update: (patch: Partial<Preferences>) => void;
  reset: () => void;
}

export function usePreferences(): PreferencesApi {
  const preferences = useSyncExternalStore(
    subscribePreferences,
    readPreferences,
    serverPreferences,
  );
  useEffect(() => applyTextSize(preferences.textSize), [preferences.textSize]);
  return {
    preferences,
    update: (patch) => void writePreferences(patch),
    reset: () => void resetPreferences(),
  };
}

export function ApplyPreferences() {
  usePreferences();
  return null;
}
