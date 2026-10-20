import { memoryListSchema, memorySchema, memorySettingsSchema } from "../schemas/memory";
import type { MemoryDraft } from "../schemas/memory";
import { command, request } from "./http";

export const fetchMemories = (q: string) =>
  request("/memory", memoryListSchema, { query: { q: q || undefined, limit: 500 } });

export const createMemory = (draft: MemoryDraft) =>
  request("/memory", memorySchema, { method: "POST", body: draft });

export const updateMemory = (id: string, patch: Partial<MemoryDraft> & { pinned?: boolean }) =>
  request(`/memory/${encodeURIComponent(id)}`, memorySchema, { method: "PATCH", body: patch });

export const deleteMemory = (id: string) =>
  command(`/memory/${encodeURIComponent(id)}`, { method: "DELETE" });

export const clearMemories = () => command("/memory", { method: "DELETE" });

export const saveMemorySettings = (patch: { enabled?: boolean; chatRecall?: boolean }) =>
  request("/memory/settings", memorySettingsSchema, { method: "PUT", body: patch });
