export const settingsKeys = {
  me: ["settings", "me"] as const,
  sessions: ["settings", "sessions"] as const,
  signIn: ["settings", "sign-in"] as const,
  models: ["settings", "models"] as const,
  keys: ["settings", "keys"] as const,
  keyUsage: (days: number) => ["settings", "key-usage", days] as const,
  memory: (query: string) => ["settings", "memory", query] as const,
  memoryAll: ["settings", "memory"] as const,
  sources: ["settings", "sources"] as const,
  stats: ["settings", "knowledge-stats"] as const,
  connections: ["settings", "connections"] as const,
};
