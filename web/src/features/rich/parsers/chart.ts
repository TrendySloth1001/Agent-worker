import { z } from "zod";
import { looseJson, toNumber } from "../lib/text";

export const CHART_KINDS = ["bar", "line", "area", "pie", "donut", "scatter", "radar"] as const;
export type ChartKind = (typeof CHART_KINDS)[number];

const MAX_SERIES = 8;
const MAX_POINTS = 60;
const MAX_SLICES = 12;
const MIN_RADAR_AXES = 3;

const rawSchema = z.object({
  type: z.string().optional(),
  title: z.unknown().optional(),
  x: z.array(z.unknown()).optional(),
  unit: z.unknown().optional(),
  xLabel: z.unknown().optional(),
  xlabel: z.unknown().optional(),
  yLabel: z.unknown().optional(),
  ylabel: z.unknown().optional(),
  series: z.array(z.unknown()).min(1),
});

const rawSeriesSchema = z.object({
  name: z.unknown().optional(),
  data: z.array(z.unknown()).optional(),
  points: z.array(z.unknown()).optional(),
});

export interface Point {
  x: number;
  y: number;
}

export interface ChartSeries {
  name: string;
  values: Array<number | null>;
  points: Point[];
}

export interface ChartSlice {
  label: string;
  value: number;
}

export interface ChartSpec {
  kind: ChartKind;
  title: string;
  labels: string[];
  series: ChartSeries[];
  slices: ChartSlice[];
  unit: string;
  xLabel: string;
  yLabel: string;
}

const KIND_ALIASES: Record<string, ChartKind> = {
  bar: "bar",
  column: "bar",
  columns: "bar",
  histogram: "bar",
  line: "line",
  spline: "line",
  area: "area",
  pie: "pie",
  donut: "donut",
  doughnut: "donut",
  ring: "donut",
  scatter: "scatter",
  xy: "scatter",
  bubble: "scatter",
  radar: "radar",
  spider: "radar",
  polar: "radar",
};

const asText = (value: unknown): string =>
  value === null || value === undefined ? "" : String(value).trim();

function readPoint(raw: unknown): Point | null {
  if (Array.isArray(raw) && raw.length >= 2) {
    const x = toNumber(raw[0]);
    const y = toNumber(raw[1]);
    return x !== null && y !== null ? { x, y } : null;
  }
  if (raw && typeof raw === "object") {
    const record = raw as Record<string, unknown>;
    const x = toNumber(record.x);
    const y = toNumber(record.y);
    return x !== null && y !== null ? { x, y } : null;
  }
  return null;
}

function buildSlices(series: ChartSeries[], labels: string[]): ChartSlice[] {
  const single = series.length === 1 && (series[0]?.values.length ?? 0) > 1;
  const slices: ChartSlice[] = [];
  if (single) {
    (series[0]?.values ?? []).forEach((value, index) => {
      if (value !== null && value > 0)
        slices.push({ label: labels[index] || String(index + 1), value });
    });
  } else {
    for (const item of series) {
      const first = item.values.find((value) => value !== null);
      if (first !== undefined && first !== null && first > 0)
        slices.push({ label: item.name, value: first });
    }
  }
  slices.sort((a, b) => b.value - a.value);
  if (slices.length <= MAX_SLICES) return slices;
  const rest = slices.splice(MAX_SLICES - 1);
  slices.push({ label: "Other", value: rest.reduce((sum, slice) => sum + slice.value, 0) });
  return slices;
}

export function parseChart(code: string): ChartSpec | null {
  const raw = rawSchema.safeParse(looseJson(code));
  if (!raw.success) return null;
  const input = raw.data;
  const kind = KIND_ALIASES[(input.type ?? "bar").toLowerCase().trim()] ?? "bar";
  const labels = (input.x ?? []).slice(0, MAX_POINTS).map(asText);
  const series: ChartSeries[] = [];
  for (const item of input.series.slice(0, MAX_SERIES)) {
    const parsed = rawSeriesSchema.safeParse(item);
    if (!parsed.success) continue;
    const values = (parsed.data.data ?? []).slice(0, MAX_POINTS).map(toNumber);
    let points = (parsed.data.points ?? [])
      .slice(0, MAX_POINTS)
      .map(readPoint)
      .filter((point): point is Point => point !== null);
    if (kind === "scatter" && !parsed.data.points) {
      points = values.flatMap((y, index) => {
        if (y === null) return [];
        return [{ x: toNumber(labels[index]) ?? index, y }];
      });
    }
    series.push({
      name: asText(parsed.data.name) || `Series ${series.length + 1}`,
      values,
      points,
    });
  }
  if (series.length === 0) return null;

  const slices = kind === "pie" || kind === "donut" ? buildSlices(series, labels) : [];
  if ((kind === "pie" || kind === "donut") && slices.length === 0) return null;
  if (kind === "scatter" && !series.some((item) => item.points.length > 0)) return null;
  if (kind !== "pie" && kind !== "donut" && kind !== "scatter") {
    if (!series.some((item) => item.values.some((value) => value !== null))) return null;
    if (kind === "radar" && Math.max(...series.map((item) => item.values.length)) < MIN_RADAR_AXES)
      return null;
  }
  return {
    kind,
    title: asText(input.title),
    labels,
    series,
    slices,
    unit: asText(input.unit),
    xLabel: asText(input.xLabel ?? input.xlabel),
    yLabel: asText(input.yLabel ?? input.ylabel),
  };
}

export function categoryCount(spec: ChartSpec): number {
  return Math.max(spec.labels.length, ...spec.series.map((item) => item.values.length));
}

export function categoryLabel(spec: ChartSpec, index: number): string {
  return spec.labels[index] || String(index + 1);
}

export function chartToCsv(spec: ChartSpec): string {
  const quote = (cell: string) => (/[",\n]/.test(cell) ? `"${cell.replace(/"/g, '""')}"` : cell);
  const rows: string[][] = [];
  if (spec.kind === "pie" || spec.kind === "donut") {
    rows.push([spec.xLabel || "X", spec.yLabel || "Y"]);
    for (const slice of spec.slices) rows.push([slice.label, String(slice.value)]);
  } else if (spec.kind === "scatter") {
    rows.push(["series", "X", "Y"]);
    for (const item of spec.series)
      for (const p of item.points) rows.push([item.name, String(p.x), String(p.y)]);
  } else {
    rows.push([spec.xLabel, ...spec.series.map((item) => item.name)]);
    for (let i = 0; i < categoryCount(spec); i++) {
      rows.push([
        categoryLabel(spec, i),
        ...spec.series.map((item) => String(item.values[i] ?? "")),
      ]);
    }
  }
  return rows.map((row) => row.map(quote).join(",")).join("\n");
}
