"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Dialog } from "radix-ui";
import { useState, type ReactNode } from "react";
import { Wordmark } from "@/components/brand/wordmark";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Icon } from "@/components/ui/icon";
import { IconButton } from "@/components/ui/icon-button";
import { QuickAsk } from "@/features/quick-ask";
import { ApplyPreferences } from "@/features/settings/preferences/use-preferences";
import { HISTORY_COPY as COPY } from "@/features/history/grouping";
import { HistorySidebar } from "@/features/history/components/history-sidebar";
import { cn } from "@/lib/cn";

function SidebarBody({ onNavigate, onClose }: { onNavigate?: () => void; onClose?: () => void }) {
  const pathname = usePathname();
  return (
    <div className="flex h-full min-h-0 flex-col gap-lg py-lg">
      <div className="flex items-center justify-between px-lg">
        <Link href="/chat" onClick={onNavigate} aria-label="sparky">
          <Wordmark className="text-title" />
        </Link>
        {onClose && <IconButton icon="close" label={COPY.closeMenu} variant="ghost" onClick={onClose} />}
      </div>
      <HistorySidebar onNavigate={onNavigate} />
      <div className="flex items-center justify-between gap-md border-t border-border px-lg pt-md">
        <Link
          href="/settings"
          onClick={onNavigate}
          aria-current={pathname.startsWith("/settings") ? "page" : undefined}
          className={cn(
            "flex items-center gap-sm rounded-pill px-md py-sm text-body-small outline-none hover:bg-surface-raised focus-visible:outline-2 focus-visible:outline-accent",
            pathname.startsWith("/settings") ? "font-medium text-text-primary" : "text-text-secondary",
          )}
        >
          <Icon name="settings" size="sm" />
          {COPY.settings}
        </Link>
        <ThemeToggle />
      </div>
    </div>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const router = useRouter();

  return (
    <div className="flex h-app bg-background">
      <aside className="hidden w-[18.5rem] shrink-0 border-r border-border bg-surface md:block">
        <SidebarBody />
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 shrink-0 items-center justify-between border-b border-border px-md md:hidden">
          <IconButton icon="menu" label={COPY.openMenu} variant="ghost" onClick={() => setOpen(true)} />
          <Wordmark className="text-title" />
          <IconButton icon="newChat" label={COPY.newChat} variant="ghost" onClick={() => router.push("/chat")} />
        </header>
        <main className="min-h-0 flex-1">{children}</main>
      </div>

      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-40 animate-fade bg-scrim md:hidden" />
          <Dialog.Content
            aria-describedby={undefined}
            className="fixed inset-y-0 left-0 z-50 w-[min(20rem,86vw)] animate-fade border-r border-border bg-surface outline-none md:hidden"
          >
            <Dialog.Title className="sr-only">Chats</Dialog.Title>
            <SidebarBody onNavigate={() => setOpen(false)} onClose={() => setOpen(false)} />
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
      <QuickAsk />
      <ApplyPreferences />
    </div>
  );
}
