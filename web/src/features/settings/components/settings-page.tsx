import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/icon";

interface SettingsPageProps {
  title: string;
  backHref?: string | null;
  children: ReactNode;
}

export function SettingsPage({ title, backHref = "/settings", children }: SettingsPageProps) {
  return (
    <div className="mx-auto flex w-full max-w-[40rem] flex-col gap-lg px-lg pt-lg pb-xxxl">
      <header className="flex items-center gap-md">
        {backHref && (
          <Link
            href={backHref}
            aria-label="Back to settings"
            className="duration-fast inline-flex size-10 shrink-0 items-center justify-center rounded-full text-text-secondary transition-colors ease-standard hover:bg-surface-raised hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            <Icon name="back" />
          </Link>
        )}
        <h1 className="text-title font-bold">{title}</h1>
      </header>
      {children}
    </div>
  );
}
