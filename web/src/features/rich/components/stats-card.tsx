import { cn } from "@/lib/cn";
import type { StatsData } from "../parsers/playful";
import { RichFrame } from "./frame";

function Sparkline({ values }: { values: readonly number[] }) {
  if (values.length < 2) return null;
  const min = Math.min(...values);
  const span = Math.max(...values) - min || 1;
  const width = 88;
  const height = 24;
  const points = values.map(
    (value, i) =>
      `${(i / (values.length - 1)) * width},${height - 2 - ((value - min) / span) * (height - 4)}`,
  );
  const last = points[points.length - 1]?.split(",") ?? ["0", "0"];
  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="h-6 w-22" aria-hidden>
      <polyline
        points={points.join(" ")}
        fill="none"
        strokeWidth={1.5}
        strokeLinejoin="round"
        strokeLinecap="round"
        className="stroke-text-secondary"
      />
      <circle cx={last[0]} cy={last[1]} r={3} className="fill-accent" />
    </svg>
  );
}

export function StatsCard({ data }: { data: StatsData }) {
  return (
    <RichFrame label={data.title}>
      <div className="grid grid-cols-2 gap-sm">
        {data.stats.map((stat) => (
          <div
            key={stat.label}
            className="flex min-h-21 flex-col justify-between gap-xs rounded-md bg-surface px-md py-sm"
          >
            <p className="truncate font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
              {stat.label}
            </p>
            <div className="flex items-end justify-between gap-sm">
              <p className="font-mono text-metric leading-none break-all">{stat.value}</p>
              <Sparkline values={stat.spark} />
            </div>
            {stat.delta && (
              <p
                className={cn(
                  "font-mono text-caption",
                  stat.direction === "up" && "text-text-primary",
                  stat.direction === "down" && "text-accent-text",
                  stat.direction === "flat" && "text-text-secondary",
                )}
              >
                {stat.direction === "up" ? "▲ " : stat.direction === "down" ? "▼ " : ""}
                {stat.delta}
              </p>
            )}
          </div>
        ))}
      </div>
    </RichFrame>
  );
}
