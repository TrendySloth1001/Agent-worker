import { KEYS_COPY } from "../content/copy";
import type { CheckResult, KeyStatus } from "../schemas/keys";

export type KeyTone = "ok" | "warn" | "bad" | "neutral";

export interface KeyOutcome {
  tone: KeyTone;
  message: string;
}

export const describeResult = (result: CheckResult): KeyOutcome => {
  switch (result) {
    case "valid":
      return { tone: "ok", message: KEYS_COPY.result.valid };
    case "invalid":
      return { tone: "bad", message: KEYS_COPY.result.invalid };
    case "quota":
      return { tone: "warn", message: KEYS_COPY.result.quota };
    case "network":
      return { tone: "neutral", message: KEYS_COPY.result.network };
  }
};

export const statusTone = (status: KeyStatus): KeyTone => {
  switch (status) {
    case "valid":
      return "ok";
    case "invalid":
      return "bad";
    case "quota":
      return "warn";
    case "untested":
      return "neutral";
  }
};

export const statusLabel = (status: KeyStatus): string => KEYS_COPY.status[status];
