import Image from "next/image";
import { cn } from "@/lib/cn";

interface AvatarProps {
  name?: string;
  src?: string;
  size?: number;
  bordered?: boolean;
  className?: string;
}

const initialsOf = (name?: string): string => {
  const parts = name?.trim().split(/\s+/).filter(Boolean) ?? [];
  if (parts.length === 0) return "?";
  const first = parts[0]?.[0] ?? "";
  const last = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? "") : "";
  return (first + last).toUpperCase();
};

export function Avatar({ name, src, size = 40, bordered = true, className }: AvatarProps) {
  return (
    <span
      style={{ width: size, height: size }}
      className={cn(
        "relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface-raised",
        bordered && "border border-border-strong",
        className,
      )}
    >
      {src ? (
        <Image
          src={src}
          alt={name ?? ""}
          fill
          sizes={`${size}px`}
          unoptimized
          className="object-cover"
        />
      ) : (
        <span style={{ fontSize: size * 0.36 }} className="font-medium text-text-primary">
          {initialsOf(name)}
        </span>
      )}
    </span>
  );
}
