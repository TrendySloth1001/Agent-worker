import { Icon } from "@/components/ui/icon";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tag } from "@/components/ui/tag";
import { Wordmark } from "@/components/brand/wordmark";
import { ABOUT_COPY } from "../content/copy";
import { CREDITS, FEATURES, PRIVACY } from "../content/about";
import { RELEASES } from "../content/changelog";
import { SettingsPage } from "./settings-page";

interface AboutScreenProps {
  version: string;
  backHref?: string | null;
}

export function AboutScreen({ version, backHref }: AboutScreenProps) {
  return (
    <SettingsPage title={ABOUT_COPY.title} backHref={backHref}>
      <header className="flex flex-col items-center gap-xs py-xl text-center">
        <Wordmark className="text-display" />
        <p className="text-body text-text-secondary">{ABOUT_COPY.tagline}</p>
        <Tag className="mt-sm">{ABOUT_COPY.version(version)}</Tag>
      </header>
      <section>
        <SettingsGroupHeader>{ABOUT_COPY.whatItDoes}</SettingsGroupHeader>
        <SettingsGroup>
          {FEATURES.map((item) => (
            <SettingsTile
              key={item.title}
              icon={item.icon}
              title={item.title}
              subtitle={item.detail}
            />
          ))}
        </SettingsGroup>
      </section>
      <section>
        <SettingsGroupHeader>{ABOUT_COPY.privacy}</SettingsGroupHeader>
        <SettingsGroup>
          {PRIVACY.map((item) => (
            <SettingsTile
              key={item.title}
              icon={item.icon}
              title={item.title}
              subtitle={item.detail}
            />
          ))}
        </SettingsGroup>
      </section>
      <section>
        <SettingsGroupHeader>{ABOUT_COPY.changelog}</SettingsGroupHeader>
        <ol className="flex flex-col gap-md">
          {RELEASES.map((release, index) => (
            <li key={release.version} className="flex flex-col gap-md rounded-card bg-cell p-lg">
              <div className="flex items-baseline justify-between gap-md">
                <span className="text-title font-bold">{`v${release.version}`}</span>
                <span className="font-mono text-caption tracking-[0.06em] text-text-secondary uppercase">
                  {index === 0 ? `${ABOUT_COPY.latest} · ${release.date}` : release.date}
                </span>
              </div>
              <p className="text-body text-text-secondary">{release.headline}</p>
              <ul className="flex flex-col gap-sm">
                {release.items.map((change) => (
                  <li key={change.title} className="flex items-start gap-md">
                    <Tag accent={change.kind === "added"} className="mt-xxs shrink-0">
                      {ABOUT_COPY.kinds[change.kind]}
                    </Tag>
                    <div className="flex flex-col">
                      <span className="text-body font-medium">{change.title}</span>
                      <span className="text-body-small text-text-secondary">{change.detail}</span>
                    </div>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      </section>
      <section>
        <SettingsGroupHeader>{ABOUT_COPY.credits}</SettingsGroupHeader>
        <SettingsGroup>
          {CREDITS.map((credit) => (
            <a
              key={credit.value}
              href={credit.url}
              target="_blank"
              rel="noopener noreferrer"
              className="duration-fast flex min-h-touch-target items-center gap-md px-lg py-sm transition-colors ease-standard hover:bg-cell-high/50"
            >
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
                  {credit.label}
                </span>
                <span className="text-body-small">{credit.value}</span>
              </span>
              <Icon name="openExternal" size="sm" className="shrink-0 text-text-tertiary" />
            </a>
          ))}
        </SettingsGroup>
      </section>
    </SettingsPage>
  );
}
