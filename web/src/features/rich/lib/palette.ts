const STEPS = [
  "var(--accent)",
  "var(--text-primary)",
  "var(--text-secondary)",
  "var(--text-tertiary)",
  "var(--border-strong)",
] as const;

export function seriesColor(index: number): string {
  return STEPS[index % STEPS.length] ?? STEPS[0];
}

export function seriesOpacity(index: number): number {
  const tier = Math.floor(index / STEPS.length);
  if (tier === 0) return 1;
  return tier === 1 ? 0.55 : 0.3;
}
