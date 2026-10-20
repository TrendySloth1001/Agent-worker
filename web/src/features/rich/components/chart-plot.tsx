"use client";

import { categoryCount, categoryLabel, type ChartSpec } from "../parsers/chart";
import { seriesColor, seriesOpacity } from "../lib/palette";
import { compact, niceScale, shorten } from "../lib/scale";

export interface Selection {
  series: number;
  index: number;
}

interface PlotProps {
  spec: ChartSpec;
  hidden: ReadonlySet<number>;
  selected: Selection | null;
  onSelect: (selection: Selection | null) => void;
}

const HEIGHT = 220;
const LEFT = 42;
const BOTTOM = 26;
const TOP = 10;
const RIGHT = 8;
const SLOT = 34;
const MIN_WIDTH = 320;

const axisText = "fill-text-tertiary font-mono";

function fill(index: number) {
  return { fill: seriesColor(index), fillOpacity: seriesOpacity(index) };
}

function stroke(index: number) {
  return { stroke: seriesColor(index), strokeOpacity: seriesOpacity(index) };
}

function CartesianPlot({ spec, hidden, selected, onSelect }: PlotProps) {
  const count = categoryCount(spec);
  const visible = spec.series
    .map((item, index) => ({ item, index }))
    .filter(({ index }) => !hidden.has(index));
  const all = visible.flatMap(({ item }) => item.values).filter((v): v is number => v !== null);
  const scale = niceScale(Math.min(0, ...all), Math.max(0, ...all));
  const width = Math.max(MIN_WIDTH, LEFT + RIGHT + count * SLOT);
  const plotW = width - LEFT - RIGHT;
  const plotH = HEIGHT - TOP - BOTTOM;
  const slot = plotW / Math.max(count, 1);
  const y = (value: number) =>
    TOP + plotH - ((value - scale.min) / (scale.max - scale.min || 1)) * plotH;
  const cx = (i: number) => LEFT + slot * (i + 0.5);
  const every = Math.ceil(count / 8);
  const groupW = Math.min(slot * 0.8, 22 * Math.max(visible.length, 1));
  const barW = groupW / Math.max(visible.length, 1);

  return (
    <div className="overflow-x-auto">
      <svg
        viewBox={`0 0 ${width} ${HEIGHT}`}
        style={{ minWidth: width, width: "100%", maxWidth: Math.max(width, 544) }}
        className="mx-auto"
        role="img"
        aria-label={spec.title || "Chart"}
      >
        {scale.ticks.map((tick) => (
          <g key={tick}>
            <line
              x1={LEFT}
              x2={width - RIGHT}
              y1={y(tick)}
              y2={y(tick)}
              className="stroke-border"
              strokeWidth={1}
            />
            <text x={LEFT - 6} y={y(tick) + 3} textAnchor="end" fontSize={10} className={axisText}>
              {compact(tick)}
            </text>
          </g>
        ))}
        {Array.from({ length: count }, (_, i) =>
          i % every === 0 ? (
            <text
              key={i}
              x={cx(i)}
              y={HEIGHT - 8}
              textAnchor="middle"
              fontSize={10}
              className={axisText}
            >
              {shorten(categoryLabel(spec, i), every > 1 ? 6 : 8)}
            </text>
          ) : null,
        )}
        {spec.kind === "bar" &&
          visible.map(({ item, index }, order) =>
            item.values.map((value, i) => {
              if (value === null) return null;
              const top = y(Math.max(value, 0));
              const bottom = y(Math.min(value, 0));
              const active = selected?.series === index && selected.index === i;
              return (
                <rect
                  key={`${index}-${i}`}
                  x={cx(i) - groupW / 2 + order * barW + 1}
                  y={top}
                  width={Math.max(barW - 2, 1)}
                  height={Math.max(bottom - top, 1)}
                  rx={2}
                  {...fill(index)}
                  opacity={selected && !active ? 0.45 : 1}
                  onClick={() => onSelect(active ? null : { series: index, index: i })}
                  className="cursor-pointer"
                />
              );
            }),
          )}
        {spec.kind !== "bar" &&
          visible.map(({ item, index }) => {
            const points = item.values.flatMap((value, i) =>
              value === null ? [] : [{ x: cx(i), y: y(value), i }],
            );
            const path = points.map((p, n) => `${n === 0 ? "M" : "L"}${p.x},${p.y}`).join(" ");
            const first = points[0];
            const last = points[points.length - 1];
            return (
              <g key={index}>
                {spec.kind === "area" && first && last && (
                  <path
                    d={`${path} L${last.x},${y(0)} L${first.x},${y(0)} Z`}
                    {...fill(index)}
                    fillOpacity={0.15 * seriesOpacity(index)}
                  />
                )}
                <path
                  d={path}
                  fill="none"
                  strokeWidth={2}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                  {...stroke(index)}
                />
                {points.map((p) => {
                  const active = selected?.series === index && selected.index === p.i;
                  return (
                    <circle
                      key={p.i}
                      cx={p.x}
                      cy={p.y}
                      r={active ? 5 : 3}
                      {...fill(index)}
                      className="cursor-pointer"
                      onClick={() => onSelect(active ? null : { series: index, index: p.i })}
                    />
                  );
                })}
              </g>
            );
          })}
      </svg>
    </div>
  );
}

function ScatterPlot({ spec, hidden, selected, onSelect }: PlotProps) {
  const visible = spec.series
    .map((item, index) => ({ item, index }))
    .filter(({ index }) => !hidden.has(index));
  const points = visible.flatMap(({ item }) => item.points);
  const xs = niceScale(
    Math.min(...points.map((p) => p.x)),
    Math.max(...points.map((p) => p.x)),
    4,
    false,
  );
  const ys = niceScale(
    Math.min(...points.map((p) => p.y), 0),
    Math.max(...points.map((p) => p.y), 1),
  );
  const width = 360;
  const plotW = width - LEFT - 20;
  const plotH = HEIGHT - TOP - BOTTOM;
  const px = (v: number) => LEFT + ((v - xs.min) / (xs.max - xs.min || 1)) * plotW;
  const py = (v: number) => TOP + plotH - ((v - ys.min) / (ys.max - ys.min || 1)) * plotH;
  return (
    <svg
      viewBox={`0 0 ${width} ${HEIGHT}`}
      className="mx-auto w-full max-w-[34rem]"
      role="img"
      aria-label={spec.title || "Scatter chart"}
    >
      {ys.ticks.map((tick) => (
        <g key={`y${tick}`}>
          <line
            x1={LEFT}
            x2={width - RIGHT}
            y1={py(tick)}
            y2={py(tick)}
            className="stroke-border"
          />
          <text x={LEFT - 6} y={py(tick) + 3} textAnchor="end" fontSize={10} className={axisText}>
            {compact(tick)}
          </text>
        </g>
      ))}
      {xs.ticks.map((tick) => (
        <text
          key={`x${tick}`}
          x={px(tick)}
          y={HEIGHT - 8}
          textAnchor="middle"
          fontSize={10}
          className={axisText}
        >
          {compact(tick)}
        </text>
      ))}
      {visible.map(({ item, index }) =>
        item.points.map((p, i) => {
          const active = selected?.series === index && selected.index === i;
          return (
            <circle
              key={`${index}-${i}`}
              cx={px(p.x)}
              cy={py(p.y)}
              r={active ? 7 : 5}
              {...fill(index)}
              fillOpacity={0.8 * seriesOpacity(index)}
              className="cursor-pointer"
              onClick={() => onSelect(active ? null : { series: index, index: i })}
            />
          );
        }),
      )}
    </svg>
  );
}

function arc(
  cx: number,
  cy: number,
  outer: number,
  inner: number,
  start: number,
  end: number,
): string {
  const point = (r: number, a: number) => `${cx + r * Math.cos(a)},${cy + r * Math.sin(a)}`;
  const large = end - start > Math.PI ? 1 : 0;
  const outerPath = `M${point(outer, start)} A${outer},${outer} 0 ${large} 1 ${point(outer, end)}`;
  return inner > 0
    ? `${outerPath} L${point(inner, end)} A${inner},${inner} 0 ${large} 0 ${point(inner, start)} Z`
    : `${outerPath} L${cx},${cy} Z`;
}

function PiePlot({ spec, selected, onSelect }: PlotProps) {
  const total = spec.slices.reduce((sum, slice) => sum + slice.value, 0);
  const donut = spec.kind === "donut";
  const size = 210;
  const spans = spec.slices.reduce<Array<{ start: number; end: number }>>((acc, slice) => {
    const start = acc.length ? (acc[acc.length - 1]?.end ?? 0) : -Math.PI / 2;
    const sweep =
      spec.slices.length === 1 ? Math.PI * 2 - 0.001 : (slice.value / total) * Math.PI * 2;
    return [...acc, { start, end: start + sweep }];
  }, []);
  const chosen = selected ? spec.slices[selected.index] : undefined;
  return (
    <svg
      viewBox={`0 0 ${size} ${size}`}
      className="mx-auto block h-52 w-auto"
      role="img"
      aria-label={spec.title || "Pie chart"}
    >
      {spec.slices.map((slice, i) => {
        const { start, end } = spans[i] ?? { start: 0, end: 0 };
        const active = selected?.index === i;
        return (
          <path
            key={slice.label}
            d={arc(
              size / 2,
              size / 2,
              active ? 82 : 76,
              donut ? 52 : 0,
              start,
              end - (spec.slices.length > 1 ? 0.02 : 0),
            )}
            {...fill(i)}
            className="cursor-pointer stroke-code-background"
            strokeWidth={2}
            onClick={() => onSelect(active ? null : { series: 0, index: i })}
          />
        );
      })}
      {donut && (
        <text
          x={size / 2}
          y={size / 2 + 8}
          textAnchor="middle"
          fontSize={22}
          className="fill-text-primary font-mono"
        >
          {compact(chosen?.value ?? total)}
        </text>
      )}
    </svg>
  );
}

function RadarPlot({ spec, hidden }: PlotProps) {
  const axes = categoryCount(spec);
  const size = 250;
  const center = size / 2;
  const radius = 84;
  const all = spec.series.flatMap((item) => item.values).filter((v): v is number => v !== null);
  const max = niceScale(0, Math.max(...all, 1), 4).max;
  const at = (i: number, ratio: number) => {
    const a = -Math.PI / 2 + (i / axes) * Math.PI * 2;
    return `${center + radius * ratio * Math.cos(a)},${center + radius * ratio * Math.sin(a)}`;
  };
  const ring = (ratio: number) => Array.from({ length: axes }, (_, i) => at(i, ratio)).join(" ");
  return (
    <svg
      viewBox={`0 0 ${size} ${size}`}
      className="mx-auto block h-60 w-auto"
      role="img"
      aria-label={spec.title || "Radar chart"}
    >
      {[0.25, 0.5, 0.75, 1].map((ratio) => (
        <polygon key={ratio} points={ring(ratio)} fill="none" className="stroke-border" />
      ))}
      {Array.from({ length: axes }, (_, i) => {
        const [lx = "0", ly = "0"] = at(i, 1.18).split(",");
        return (
          <text
            key={i}
            x={lx}
            y={Number(ly) + 3}
            textAnchor="middle"
            fontSize={10}
            className={axisText}
          >
            {shorten(categoryLabel(spec, i), 9)}
          </text>
        );
      })}
      {spec.series.map((item, index) =>
        hidden.has(index) ? null : (
          <polygon
            key={index}
            points={Array.from({ length: axes }, (_, i) =>
              at(i, Math.max(item.values[i] ?? 0, 0) / max),
            ).join(" ")}
            {...fill(index)}
            fillOpacity={0.12}
            {...stroke(index)}
            strokeWidth={2}
          />
        ),
      )}
    </svg>
  );
}

export function ChartPlot(props: PlotProps) {
  switch (props.spec.kind) {
    case "pie":
    case "donut":
      return <PiePlot {...props} />;
    case "scatter":
      return <ScatterPlot {...props} />;
    case "radar":
      return <RadarPlot {...props} />;
    default:
      return <CartesianPlot {...props} />;
  }
}
