import type { SuggestToggle } from "../schemas/events";
import type { Attachment, Citation, Evidence, ImageRef } from "../schemas/message";

export type WaitLast = "start" | "status" | "model";

export interface UiMessage {
  id: string;
  role: "user" | "assistant" | "context";
  content: string;
  streaming: boolean;
  isError: boolean;
  interrupted: boolean;
  modelId?: string;
  candidates: string[];
  waitLast?: WaitLast;
  phase: string;
  attempt: number;
  tablePhase?: string;
  citations: Citation[];
  usedIds: string[];
  images: ImageRef[];
  evidence: Evidence[];
  attachments: Attachment[];
  suggestions: string[];
  toggle?: SuggestToggle;
  notice?: string;
  error?: string;
  webSearched: boolean;
  memoryOps: string[];
  latencyMs?: number;
  tokens?: number;
}

export interface ChatState {
  messages: UiMessage[];
}

export const emptyMessage = (id: string, role: UiMessage["role"]): UiMessage => ({
  id,
  role,
  content: "",
  streaming: false,
  isError: false,
  interrupted: false,
  candidates: [],
  phase: "",
  attempt: 1,
  citations: [],
  usedIds: [],
  images: [],
  evidence: [],
  attachments: [],
  suggestions: [],
  webSearched: false,
  memoryOps: [],
});
