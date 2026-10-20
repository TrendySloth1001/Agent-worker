import { Tag } from "@/components/ui/tag";
import { cn } from "@/lib/cn";
import { statusLabel, statusTone, type KeyTone } from "../../lib/key-flow";
import type { KeyStatus } from "../../schemas/keys";

const TONE_CLASS: Record<KeyTone, string> = {
  ok: "bg-text-primary text-text-inverse",
  warn: "bg-accent/12 text-accent-text",
  bad: "bg-error/15 text-error",
  neutral: "",
};

export function KeyStatusTag({ status }: { status: KeyStatus }) {
  return <Tag className={cn(TONE_CLASS[statusTone(status)])}>{statusLabel(status)}</Tag>;
}
