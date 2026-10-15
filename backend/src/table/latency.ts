// Rolling per-model latencies for Round Table steps, kept in memory, used to
// estimate how long a running table still needs (the ETA shown in the app).

export type StepKind = "research" | "draft" | "chair" | "doc_section";

/** Starting guesses until a model has its own samples. */
const DEFAULT_MS: Record<StepKind, number> = {
  research: 6_000,
  draft: 15_000,
  chair: 45_000,
  doc_section: 35_000,
};
const SAMPLES = 12;
const MIN_MS = 500;
const MAX_MS = 180_000;

const samples = new Map<string, number[]>();
const keyOf = (kind: StepKind, model: string) => `${kind}|${model}`;

export function recordLatency(kind: StepKind, model: string, ms: number): void {
  if (!Number.isFinite(ms) || ms < MIN_MS) return;
  const key = keyOf(kind, model);
  const list = samples.get(key) ?? [];
  list.push(Math.min(ms, MAX_MS));
  if (list.length > SAMPLES) list.shift();
  samples.set(key, list);
}

/** Median of the model's recent samples for this step, or the default. */
export function expectedMs(kind: StepKind, model?: string): number {
  const list = model ? samples.get(keyOf(kind, model)) : undefined;
  if (!list?.length) return DEFAULT_MS[kind];
  const sorted = [...list].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}
