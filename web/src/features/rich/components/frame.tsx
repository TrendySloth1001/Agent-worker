"use client";

import { useEffect, useRef, useState, type ComponentProps, type ReactNode } from "react";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { cn } from "@/lib/cn";

interface FrameProps {
  label: string;
  trailing?: ReactNode;
  actions?: ReactNode;
  flush?: boolean;
  className?: string;
  children: ReactNode;
}

export function RichFrame({
  label,
  trailing,
  actions,
  flush = false,
  className,
  children,
}: FrameProps) {
  return (
    <section
      className={cn(
        "my-sm overflow-hidden rounded-md border border-border bg-code-background",
        className,
      )}
    >
      <header className="flex h-10 items-center gap-sm border-b border-border px-md">
        <span className="min-w-0 flex-1 truncate font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
          {label}
        </span>
        {trailing}
      </header>
      <div className={cn(!flush && "p-md")}>{children}</div>
      {actions && (
        <footer className="flex flex-wrap gap-x-lg border-t border-border px-md">{actions}</footer>
      )}
    </section>
  );
}

interface ActionProps extends Omit<ComponentProps<"button">, "onClick" | "children"> {
  icon: IconName;
  label: string;
  doneLabel?: string;
  onRun: () => boolean | void | Promise<boolean | void>;
}

export function RichAction({ icon, label, doneLabel, onRun, className, ...props }: ActionProps) {
  const [done, setDone] = useState(false);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);

  async function run() {
    const ok = await onRun();
    if (ok === false || !doneLabel) return;
    setDone(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setDone(false), 1600);
  }

  return (
    <button
      type="button"
      onClick={run}
      className={cn(
        "inline-flex min-h-8 items-center gap-xs font-mono text-caption tracking-[0.08em] uppercase",
        "duration-fast transition-colors ease-standard hover:text-text-primary disabled:opacity-40",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        done ? "text-accent-text" : "text-text-tertiary",
        className,
      )}
      {...props}
    >
      <Icon name={done ? "check" : icon} size="sm" />
      {done && doneLabel ? doneLabel : label}
    </button>
  );
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export function CopyAction({ text, label = "Copy" }: { text: string; label?: string }) {
  return <RichAction icon="copy" label={label} doneLabel="Copied" onRun={() => copyText(text)} />;
}

export function MonoButton({ className, ...props }: ComponentProps<"button">) {
  return (
    <button
      type="button"
      className={cn(
        "inline-flex h-segment-height items-center justify-center gap-xs rounded-pill border border-border-strong px-lg",
        "font-mono text-caption tracking-[0.08em] text-text-primary uppercase",
        "duration-fast transition-colors ease-standard hover:border-text-primary disabled:pointer-events-none disabled:opacity-40",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        className,
      )}
      {...props}
    />
  );
}

export function CodeFallback({ code, lang }: { code: string; lang: string }) {
  return (
    <RichFrame label={lang || "text"} flush actions={<CopyAction text={code} />}>
      <pre className="overflow-x-auto p-md font-mono text-body-small leading-normal whitespace-pre text-syn-plain">
        <code>{code}</code>
      </pre>
    </RichFrame>
  );
}
