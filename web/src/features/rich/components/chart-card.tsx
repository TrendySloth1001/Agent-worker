"use client";

import { useState } from "react";
import { cn } from "@/lib/cn";
import { seriesColor, seriesOpacity } from "../lib/palette";
import { categoryCount, categoryLabel, chartToCsv, type ChartSpec } from "../parsers/chart";
import { formatNumber } from "../lib/text";
import { ChartPlot, type Selection } from "./chart-plot";
import { CopyAction, RichAction, RichFrame } from "./frame";

function readout(spec: ChartSpec, selected: Selection | null): string {
  const unit = spec.unit ? ` ${spec.unit}` : "";
  if (!selected)
    return spec.kind === "pie" || spec.kind === "donut"
      ? "Tap a slice"
      : "Tap a point for its value";
  if (spec.kind === "pie" || spec.kind === "donut") {
    const slice = spec.slices[selected.index];
    return slice ? `${slice.label}: ${formatNumber(slice.value)}${unit}` : "";
  }
  const series = spec.series[selected.series];
  if (!series) return "";
  if (spec.kind === "scatter") {
    const point = series.points[selected.index];
    return point ? `${series.name}: ${formatNumber(point.x)}, ${formatNumber(point.y)}${unit}` : "";
  }
  const value = series.values[selected.index];
  return `${series.name}, ${categoryLabel(spec, selected.index)}: ${value === null || value === undefined ? "-" : formatNumber(value)}${unit}`;
}

function ChartTable({ spec }: { spec: ChartSpec }) {
  const rows =
    spec.kind === "pie" || spec.kind === "donut"
      ? {
          head: [spec.xLabel || "X", spec.yLabel || "Y"],
          body: spec.slices.map((s) => [s.label, formatNumber(s.value)]),
        }
      : spec.kind === "scatter"
        ? {
            head: ["Series", "X", "Y"],
            body: spec.series.flatMap((s) =>
              s.points.map((p) => [s.name, formatNumber(p.x), formatNumber(p.y)]),
            ),
          }
        : {
            head: [spec.xLabel, ...spec.series.map((s) => s.name)],
            body: Array.from({ length: categoryCount(spec) }, (_, i) => [
              categoryLabel(spec, i),
              ...spec.series.map((s) => (s.values[i] == null ? "" : formatNumber(s.values[i]))),
            ]),
          };
  return (
    <div className="max-h-72 overflow-auto rounded-md border border-border">
      <table className="w-full border-collapse text-body-small">
        <thead>
          <tr className="bg-surface-raised">
            {rows.head.map((cell, i) => (
              <th
                key={i}
                className="px-md py-xs text-left font-mono text-caption tracking-[0.06em] whitespace-nowrap text-text-secondary uppercase"
              >
                {cell}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.body.map((row, r) => (
            <tr key={r} className="border-t border-border">
              {row.map((cell, c) => (
                <td key={c} className={cn("px-md py-xs whitespace-nowrap", c > 0 && "font-mono")}>
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function ChartCard({ spec }: { spec: ChartSpec }) {
  const [hidden, setHidden] = useState<ReadonlySet<number>>(new Set());
  const [selected, setSelected] = useState<Selection | null>(null);
  const [table, setTable] = useState(false);
  const pie = spec.kind === "pie" || spec.kind === "donut";
  const legend = pie
    ? spec.slices.map((slice, index) => ({ name: slice.label, index }))
    : spec.series.map((item, index) => ({ name: item.name, index }));

  function toggle(index: number) {
    setSelected(null);
    setHidden((current) => {
      const next = new Set(current);
      if (next.has(index)) next.delete(index);
      else if (next.size < legend.length - 1) next.add(index);
      return next;
    });
  }

  return (
    <RichFrame
      label={spec.title || "Chart"}
      actions={
        <>
          <RichAction
            icon={table ? "chart" : "table"}
            label={table ? "Chart" : "Table"}
            onRun={() => setTable((v) => !v)}
          />
          <CopyAction text={chartToCsv(spec)} label="Copy data" />
        </>
      }
    >
      {table ? (
        <ChartTable spec={spec} />
      ) : (
        <>
          <ChartPlot spec={spec} hidden={hidden} selected={selected} onSelect={setSelected} />
          <p className="mt-sm min-h-[18px] font-mono text-caption tracking-[0.04em] text-text-secondary">
            {readout(spec, selected)}
          </p>
          {(legend.length > 1 || spec.xLabel || spec.yLabel) && (
            <div className="mt-xs flex flex-wrap gap-x-md gap-y-xs">
              {legend.map(({ name, index }) => (
                <button
                  key={index}
                  type="button"
                  onClick={() => (pie ? undefined : toggle(index))}
                  className={cn(
                    "inline-flex items-center gap-xs text-label",
                    hidden.has(index) ? "opacity-35" : "text-text-secondary",
                    pie && "cursor-default",
                  )}
                >
                  <span
                    className="size-2 rounded-full"
                    style={{ background: seriesColor(index), opacity: seriesOpacity(index) }}
                  />
                  {name}
                </button>
              ))}
              {(spec.xLabel || spec.yLabel) && (
                <span className="ml-auto font-mono text-caption text-text-tertiary">
                  {[spec.xLabel, spec.yLabel].filter(Boolean).join(" / ")}
                </span>
              )}
            </div>
          )}
        </>
      )}
    </RichFrame>
  );
}
