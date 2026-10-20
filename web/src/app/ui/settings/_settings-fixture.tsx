"use client";

import { QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { AboutScreen } from "@/features/settings/components/about-screen";
import { AppearanceScreen } from "@/features/settings/components/appearance-screen";
import { ConnectionsScreen } from "@/features/settings/components/connections/connections-screen";
import { KeysScreen } from "@/features/settings/components/keys/keys-screen";
import { KnowledgeScreen } from "@/features/settings/components/knowledge/knowledge-screen";
import { MemoryScreen } from "@/features/settings/components/memory/memory-screen";
import { ModelsScreen } from "@/features/settings/components/models-screen";
import { ProfileScreen } from "@/features/settings/components/profile/profile-screen";
import { SettingsIndex } from "@/features/settings/components/settings-index";
import { APP_VERSION } from "@/features/settings/content/version";
import { createFixtureClient } from "./_fixtures";

const SCREENS: ReadonlyArray<{ id: string; label: string; render: () => ReactNode }> = [
  { id: "index", label: "Index", render: () => null },
  { id: "profile", label: "Profile", render: () => <ProfileScreen backHref={null} /> },
  { id: "appearance", label: "Appearance", render: () => <AppearanceScreen backHref={null} /> },
  { id: "models", label: "Models", render: () => <ModelsScreen backHref={null} /> },
  {
    id: "api-keys",
    label: "API keys",
    render: () => <KeysScreen backHref={null} autoIntro={false} />,
  },
  { id: "memory", label: "Memory", render: () => <MemoryScreen backHref={null} /> },
  { id: "knowledge", label: "Knowledge", render: () => <KnowledgeScreen backHref={null} /> },
  { id: "connections", label: "Connections", render: () => <ConnectionsScreen backHref={null} /> },
  {
    id: "about",
    label: "About",
    render: () => <AboutScreen version={APP_VERSION} backHref={null} />,
  },
];

export function SettingsFixture({ initial }: { initial: string }) {
  const [client] = useState(createFixtureClient);
  const [screen, setScreen] = useState(SCREENS.some((s) => s.id === initial) ? initial : "index");
  const current = SCREENS.find((s) => s.id === screen);

  return (
    <QueryClientProvider client={client}>
      <div className="mx-auto flex max-w-[40rem] items-center gap-md px-lg pt-lg">
        <nav
          aria-label="Fixture screens"
          className="flex min-w-0 flex-1 gap-xs overflow-x-auto pb-xs"
        >
          {SCREENS.map((s) => (
            <button
              key={s.id}
              type="button"
              onClick={() => setScreen(s.id)}
              aria-pressed={s.id === screen}
              className="h-segment-height shrink-0 rounded-pill border border-border-strong px-md font-mono text-caption uppercase aria-pressed:bg-text-primary aria-pressed:text-text-inverse"
            >
              {s.label}
            </button>
          ))}
        </nav>
        <ThemeToggle />
      </div>
      {screen === "index" ? (
        <SettingsIndex onNavigate={(path) => setScreen(path.split("/").pop() ?? "index")} />
      ) : (
        current?.render()
      )}
    </QueryClientProvider>
  );
}
