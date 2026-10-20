export interface Scale {
  min: number;
  max: number;
  ticks: number[];
}

export function niceScale(low: number, high: number, count = 4, includeZero = true): Scale {
  const min = includeZero ? Math.min(low, 0) : low;
  const max = includeZero ? Math.max(high, 0) : high;
  const span = max - min || 1;
  const rough = span / count;
  const magnitude = Math.pow(10, Math.floor(Math.log10(rough)));
  const step =
    [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((s) => s >= rough) ?? magnitude * 10;
  const niceMin = Math.floor(min / step) * step;
  const niceMax = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let value = niceMin; value <= niceMax + step / 2; value += step)
    ticks.push(Number(value.toPrecision(12)));
  return { min: niceMin, max: niceMax, ticks };
}

export function compact(value: number): string {
  return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(
    value,
  );
}

export function shorten(label: string, max = 8): string {
  return label.length <= max ? label : `${label.slice(0, max - 1)}…`;
}
