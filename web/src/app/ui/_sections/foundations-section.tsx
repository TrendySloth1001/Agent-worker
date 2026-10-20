import { Section } from "./section";

const SWATCHES = [
  ["background", "bg-background"],
  ["surface", "bg-surface"],
  ["surface-raised", "bg-surface-raised"],
  ["surface-high", "bg-surface-high"],
  ["border", "bg-border"],
  ["border-strong", "bg-border-strong"],
  ["text-primary", "bg-text-primary"],
  ["text-secondary", "bg-text-secondary"],
  ["text-tertiary", "bg-text-tertiary"],
  ["accent", "bg-accent"],
  ["disabled", "bg-disabled"],
  ["code-background", "bg-code-background"],
] as const;

const TYPE = [
  ["display", "text-display font-bold tracking-[-0.02em]", "Display"],
  ["headline", "text-headline font-bold", "Headline"],
  ["metric", "text-metric font-semibold", "1,284"],
  ["title", "text-title font-medium", "Title"],
  ["body", "text-body", "Body text reads in Space Grotesk."],
  ["body-small", "text-body-small text-text-secondary", "Secondary body text."],
  ["label", "font-mono text-label tracking-[0.1em] uppercase", "Label in Space Mono"],
  ["caption", "font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase", "Caption"],
] as const;

export function FoundationsSection() {
  return (
    <>
      <Section title="Colors">
        <div className="grid grid-cols-2 gap-md sm:grid-cols-3 lg:grid-cols-6">
          {SWATCHES.map(([name, cls]) => (
            <div key={name} className="flex flex-col gap-xs">
              <div className={`h-14 rounded-md border border-border ${cls}`} />
              <span className="font-mono text-caption text-text-secondary">{name}</span>
            </div>
          ))}
        </div>
      </Section>
      <Section title="Type">
        <div className="flex flex-col gap-md">
          {TYPE.map(([name, cls, sample]) => (
            <div
              key={name}
              className="flex flex-col gap-xxs sm:flex-row sm:items-baseline sm:gap-lg"
            >
              <span className="w-24 shrink-0 font-mono text-caption text-text-tertiary">
                {name}
              </span>
              <span className={cls}>{sample}</span>
            </div>
          ))}
        </div>
      </Section>
    </>
  );
}
