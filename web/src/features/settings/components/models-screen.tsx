"use client";

import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tag } from "@/components/ui/tag";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { fetchModels } from "../api/models";
import { errorMessage } from "../api/http";
import { settingsKeys } from "../api/query-keys";
import { MODELS_COPY } from "../content/copy";
import { formatContext } from "../lib/format";
import {
  INSTRUCTIONS_MAX,
  LANGUAGE_MAX,
  LENGTHS,
  MODES,
  MODEL_PRESETS,
  TONES,
  type WorkMode,
} from "../preferences/schema";
import { usePreferences } from "../preferences/use-preferences";
import { FieldLabel } from "./form-sheet";
import { OptionChips } from "./option-chips";
import { ErrorNotice, LoadingRows } from "./query-notice";
import { SettingsPage } from "./settings-page";

const PRESET_ICON: Record<(typeof MODEL_PRESETS)[number], IconName> = {
  auto: "modelAuto",
  fast: "modelFast",
  smart: "modelSmart",
};

const Check = () => <Icon name="check" className="text-accent-text" />;

export function ModelsScreen({ backHref }: { backHref?: string | null }) {
  const { preferences, update } = usePreferences();
  const models = useQuery({ queryKey: settingsKeys.models, queryFn: fetchModels });

  return (
    <SettingsPage title={MODELS_COPY.title} backHref={backHref}>
      <section>
        <SettingsGroupHeader>{MODELS_COPY.modelGroup}</SettingsGroupHeader>
        <SettingsGroup>
          {MODEL_PRESETS.map((preset) => (
            <SettingsTile
              key={preset}
              icon={PRESET_ICON[preset]}
              title={MODELS_COPY[preset].title}
              subtitle={MODELS_COPY[preset].help}
              trailing={preferences.model === preset ? <Check /> : undefined}
              onClick={() => update({ model: preset })}
            />
          ))}
        </SettingsGroup>
      </section>
      <section>
        <SettingsGroupHeader>{MODELS_COPY.specific}</SettingsGroupHeader>
        {models.isPending && <LoadingRows />}
        {models.isError && (
          <ErrorNotice message={errorMessage(models.error)} onRetry={() => void models.refetch()} />
        )}
        {models.data && (
          <SettingsGroup>
            {models.data.models.map((model) => (
              <SettingsTile
                key={model.id}
                icon="models"
                title={model.name}
                subtitle={`${model.maker} · ${MODELS_COPY.speeds[model.speed]} · ${formatContext(model.contextTokens)} ${MODELS_COPY.context}`}
                badge={model.cooldownUntil ? <Tag>{MODELS_COPY.cooldown}</Tag> : undefined}
                value={model.provider}
                trailing={preferences.model === model.id ? <Check /> : undefined}
                onClick={() => update({ model: model.id })}
              />
            ))}
          </SettingsGroup>
        )}
      </section>
      <section className="flex flex-col gap-md">
        <SettingsGroupHeader>{MODELS_COPY.styleGroup}</SettingsGroupHeader>
        <div className="flex flex-col gap-lg rounded-card bg-cell p-lg">
          <ChoiceBlock label={MODELS_COPY.toneLabel} help={MODELS_COPY.toneHelp}>
            <OptionChips
              label={MODELS_COPY.toneLabel}
              value={preferences.tone}
              options={TONES.map((value) => ({ value, label: MODELS_COPY.tones[value] }))}
              onChange={(tone) => update({ tone })}
            />
          </ChoiceBlock>
          <ChoiceBlock label={MODELS_COPY.lengthLabel} help={MODELS_COPY.lengthHelp}>
            <OptionChips
              label={MODELS_COPY.lengthLabel}
              value={preferences.length}
              options={LENGTHS.map((value) => ({ value, label: MODELS_COPY.lengths[value] }))}
              onChange={(length) => update({ length })}
            />
          </ChoiceBlock>
          <ChoiceBlock label={MODELS_COPY.modeLabel}>
            <OptionChips<WorkMode | "none">
              label={MODELS_COPY.modeLabel}
              value={preferences.mode ?? "none"}
              options={[
                { value: "none", label: MODELS_COPY.modeNone },
                ...MODES.map((value) => ({ value, label: MODELS_COPY.modes[value] })),
              ]}
              onChange={(mode) => update({ mode: mode === "none" ? null : mode })}
            />
          </ChoiceBlock>
        </div>
      </section>
      <section className="flex flex-col gap-md">
        <SettingsGroupHeader>{MODELS_COPY.languageGroup}</SettingsGroupHeader>
        <div className="flex flex-col gap-md rounded-card bg-cell p-lg">
          <div className="flex flex-col gap-xs">
            <FieldLabel htmlFor="reply-language">{MODELS_COPY.languageLabel}</FieldLabel>
            <Input
              id="reply-language"
              value={preferences.language}
              maxLength={LANGUAGE_MAX}
              placeholder={MODELS_COPY.languageHint}
              onChange={(event) => update({ language: event.target.value })}
            />
          </div>
          <div className="flex flex-col gap-xs">
            <FieldLabel htmlFor="reply-instructions">{MODELS_COPY.instructionsLabel}</FieldLabel>
            <Textarea
              id="reply-instructions"
              rows={3}
              value={preferences.instructions}
              maxLength={INSTRUCTIONS_MAX}
              placeholder={MODELS_COPY.instructionsHint}
              onChange={(event) => update({ instructions: event.target.value })}
            />
          </div>
        </div>
      </section>
    </SettingsPage>
  );
}

function ChoiceBlock({
  label,
  help,
  children,
}: {
  label: string;
  help?: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-sm">
      <div className="flex flex-col">
        <span className="text-body">{label}</span>
        {help && <span className="text-body-small text-text-secondary">{help}</span>}
      </div>
      {children}
    </div>
  );
}
