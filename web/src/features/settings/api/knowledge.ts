import {
  addSourceResponseSchema,
  sourcesSchema,
  statsSchema,
  type NoteDraft,
} from "../schemas/knowledge";
import { command, request } from "./http";

export const fetchSources = () => request("/knowledge/sources", sourcesSchema);

export const fetchStats = () => request("/knowledge/stats", statsSchema);

export const addSource = (input: string) =>
  request("/knowledge/sources", addSourceResponseSchema, { method: "POST", body: { input } });

export const addNote = (draft: NoteDraft) =>
  request("/knowledge/notes", addSourceResponseSchema, {
    method: "POST",
    body: { content: draft.content, ...(draft.title ? { title: draft.title } : {}) },
  });

export const refreshSource = (id: string) =>
  command(`/knowledge/sources/${encodeURIComponent(id)}/refresh`, { method: "POST" });

export const deleteSource = (id: string) =>
  command(`/knowledge/sources/${encodeURIComponent(id)}`, { method: "DELETE" });
