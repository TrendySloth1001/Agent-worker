import { cn } from "@/lib/cn";

const DOTS: ReadonlyArray<readonly [number, number]> = [
  [42, 38],
  [50, 38],
  [58, 38],
  [66, 38],
  [34, 46],
  [42, 54],
  [50, 54],
  [58, 54],
  [66, 62],
  [34, 70],
  [42, 70],
  [50, 70],
  [58, 70],
];

const SPARK: readonly [number, number] = [74, 70];

interface MascotProps {
  size?: number;
  className?: string;
}

export function Mascot({ size = 64, className }: MascotProps) {
  return (
    <svg
      role="img"
      aria-label="sparky"
      viewBox="29 33 50 42"
      width={size}
      height={(size * 42) / 50}
      className={cn("text-text-primary", className)}
    >
      {DOTS.map(([cx, cy]) => (
        <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r={3.3} fill="currentColor" />
      ))}
      <circle cx={SPARK[0]} cy={SPARK[1]} r={3.3} className="fill-accent" />
    </svg>
  );
}
