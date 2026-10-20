"use client";

import { ToggleGroup } from "radix-ui";
import { cn } from "@/lib/cn";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { isTheme, type Theme } from "@/lib/theme";
import { useTheme } from "./theme-provider";

const OPTIONS: ReadonlyArray<{ value: Theme; icon: IconName; label: string }> = [
  { value: "system", icon: "themeSystem", label: "System theme" },
  { value: "light", icon: "themeLight", label: "Light theme" },
  { value: "dark", icon: "themeDark", label: "Dark theme" },
];

export function ThemeToggle({ className }: { className?: string }) {
  const { theme, setTheme } = useTheme();
  return (
    <ToggleGroup.Root
      type="single"
      value={theme}
      onValueChange={(value) => {
        if (isTheme(value)) setTheme(value);
      }}
      aria-label="Theme"
      className={cn(
        "inline-flex h-segment-height items-stretch rounded-pill border border-border-strong",
        className,
      )}
    >
      {OPTIONS.map((o) => (
        <ToggleGroup.Item
          key={o.value}
          value={o.value}
          aria-label={o.label}
          className={cn(
            "flex w-10 items-center justify-center rounded-pill text-text-secondary",
            "duration-fast transition-colors ease-standard",
            "data-[state=on]:bg-text-primary data-[state=on]:text-text-inverse",
            "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
          )}
        >
          <Icon name={o.icon} size="sm" />
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
