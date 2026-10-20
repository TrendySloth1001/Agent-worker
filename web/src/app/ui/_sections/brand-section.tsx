import { DotBackdrop } from "@/components/brand/dot-backdrop";
import { Mascot } from "@/components/brand/mascot";
import { Wordmark } from "@/components/brand/wordmark";
import { Section } from "./section";

export function BrandSection() {
  return (
    <Section title="Brand">
      <div className="flex flex-wrap items-center gap-xl">
        <Mascot size={72} />
        <Wordmark className="text-display" />
      </div>
      <DotBackdrop matrix className="h-72 rounded-card border border-border">
        <div className="flex h-full items-start p-lg">
          <p className="font-mono text-caption tracking-[0.1em] text-text-secondary uppercase">
            Dot matrix. Tap or drag.
          </p>
        </div>
      </DotBackdrop>
    </Section>
  );
}
