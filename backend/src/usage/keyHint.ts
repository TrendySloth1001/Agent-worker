/** Shows enough of a secret to recognise it: "gsk_…uBwv". Never the whole key. */
export function keyHint(key: string | undefined): string | null {
  if (!key) return null;
  if (key.length < 16) return "••••";
  const prefix = key.match(/^[a-z]+(?:[-_][a-z0-9]{1,3})?[-_]/i)?.[0] ?? key.slice(0, 4);
  return `${prefix.slice(0, 10)}…${key.slice(-4)}`;
}
