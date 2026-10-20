"use client";

import { useTheme } from "@/components/theme/theme-provider";
import { Icon } from "@/components/ui/icon";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { THEMES, type Theme } from "@/lib/theme";
import { APPEARANCE_COPY } from "../content/copy";
import { TEXT_SIZES } from "../preferences/schema";
import { usePreferences } from "../preferences/use-preferences";
import { OptionChips } from "./option-chips";
import { SettingsPage } from "./settings-page";

const THEME_ICON = { system: "themeSystem", light: "themeLight", dark: "themeDark" } as const;

export function AppearanceScreen({ backHref }: { backHref?: string | null }) {
  const { theme, setTheme } = useTheme();
  const { preferences, update } = usePreferences();

  return (
    <SettingsPage title={APPEARANCE_COPY.title} backHref={backHref}>
      <section>
        <SettingsGroupHeader>{APPEARANCE_COPY.themeGroup}</SettingsGroupHeader>
        <SettingsGroup>
          {THEMES.map((value: Theme) => (
            <SettingsTile
              key={value}
              icon={THEME_ICON[value]}
              title={APPEARANCE_COPY.themeNames[value]}
              subtitle={APPEARANCE_COPY.themeHelp[value]}
              trailing={
                theme === value ? <Icon name="check" className="text-accent-text" /> : undefined
              }
              onClick={() => setTheme(value)}
            />
          ))}
        </SettingsGroup>
      </section>
      <section className="flex flex-col gap-md">
        <SettingsGroupHeader>{APPEARANCE_COPY.textGroup}</SettingsGroupHeader>
        <div className="flex flex-col gap-md rounded-card bg-cell p-lg">
          <div className="flex flex-col">
            <span className="text-body">{APPEARANCE_COPY.textSizeLabel}</span>
            <span className="text-body-small text-text-secondary">
              {APPEARANCE_COPY.textSizeHelp}
            </span>
          </div>
          <OptionChips
            label={APPEARANCE_COPY.textSizeLabel}
            value={preferences.textSize}
            options={TEXT_SIZES.map((value) => ({
              value,
              label: APPEARANCE_COPY.textSizes[value],
            }))}
            onChange={(textSize) => update({ textSize })}
          />
          <p className="rounded-menu bg-surface px-lg py-md text-body-small">
            {APPEARANCE_COPY.preview}
          </p>
        </div>
      </section>
    </SettingsPage>
  );
}
