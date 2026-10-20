export function splitLines(code: string): string[] {
  return code.replace(/\r\n?/g, "\n").split("\n");
}

export function splitPipe(value: string): string[] {
  return value.split("|").map((part) => part.trim());
}

export function readKeyed(line: string, key: string): string | null {
  const match = new RegExp(`^\\s*${key}\\s*:\\s?(.*)$`, "i").exec(line);
  return match ? (match[1] ?? "").trim() : null;
}

export function looseJson(code: string): unknown {
  const start = code.indexOf("{");
  const end = code.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  const body = code.slice(start, end + 1);
  try {
    return JSON.parse(body);
  } catch {
    try {
      return JSON.parse(body.replace(/,\s*([}\]])/g, "$1"));
    } catch {
      return null;
    }
  }
}

export function toNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value !== "string" || value.trim() === "") return null;
  const parsed = Number(value.trim().replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
}

export function formatNumber(value: number, decimals?: number): string {
  if (decimals !== undefined) {
    return value.toLocaleString("en-US", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    });
  }
  if (Number.isInteger(value) && Math.abs(value) < 1e15) return value.toLocaleString("en-US");
  return Number(value.toPrecision(6)).toLocaleString("en-US", { maximumFractionDigits: 4 });
}
