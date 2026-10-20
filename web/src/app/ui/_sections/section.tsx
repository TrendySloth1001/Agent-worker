import type { ReactNode } from "react";

interface SectionProps {
  title: string;
  children: ReactNode;
}

export function Section({ title, children }: SectionProps) {
  return (
    <section className="flex flex-col gap-lg">
      <h2 className="flex items-center gap-sm font-mono text-label tracking-[0.14em] text-accent-text uppercase">
        <span className="size-[7px] rounded-full bg-accent" />
        {title}
      </h2>
      {children}
    </section>
  );
}
