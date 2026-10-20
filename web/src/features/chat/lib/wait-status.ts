import type { UiMessage } from "../state/types";
import { WAIT_COPY, WAIT_PHASES } from "./copy";

export type WaitKind = "picking" | "model" | "switching" | "phase" | "think";

export interface WaitStep {
  kind: WaitKind;
  text: string;
  modelIds: string[];
}

const MAX_LOGOS = 3;
const THINK: WaitStep = { kind: "think", text: "", modelIds: [] };

type WaitInput = Pick<UiMessage, "waitLast" | "phase" | "modelId" | "attempt" | "candidates">;

export function resolveWait(m: WaitInput, nameOf: (id: string) => string | null): WaitStep {
  switch (m.waitLast) {
    case "status": {
      const text = WAIT_PHASES[m.phase];
      if (text) return { kind: "phase", text, modelIds: [] };
      break;
    }
    case "model": {
      const name = m.modelId ? nameOf(m.modelId) : null;
      if (m.modelId && name) {
        return m.attempt > 1
          ? { kind: "switching", text: WAIT_COPY.switchingTo(name), modelIds: [m.modelId] }
          : { kind: "model", text: WAIT_COPY.goingWith(name), modelIds: [m.modelId] };
      }
      if (m.attempt > 1) return { kind: "switching", text: WAIT_COPY.switching, modelIds: [] };
      break;
    }
    case "start": {
      if (m.candidates.length === 0) break;
      const seen = new Set<string>();
      const ids: string[] = [];
      for (const id of m.candidates) {
        const key = nameOf(id) ?? id;
        if (!seen.has(key)) {
          seen.add(key);
          ids.push(id);
        }
        if (ids.length === MAX_LOGOS) break;
      }
      return { kind: "picking", text: WAIT_COPY.picking, modelIds: ids };
    }
    default:
      break;
  }
  return THINK;
}
