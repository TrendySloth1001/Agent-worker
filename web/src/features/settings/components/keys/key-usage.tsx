"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { SettingsGroup, SettingsGroupHeader } from "@/components/ui/settings-group";
import { SettingsTile } from "@/components/ui/settings-tile";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { errorMessage } from "../../api/http";
import { fetchKeyUsage } from "../../api/keys";
import { settingsKeys } from "../../api/query-keys";
import { KEYS_COPY, USAGE_COPY } from "../../content/copy";
import { formatCount, formatLatency, shortDay } from "../../lib/format";
import { USAGE_DAYS, type KeyUsage, type UsageDays } from "../../schemas/keys";
import { EmptyNotice, ErrorNotice, LoadingRows } from "../query-notice";

interface KeyUsageProps {
  onHowItWorks: () => void;
}

const isUsageDays = (value: string): value is `${UsageDays}` =>
  USAGE_DAYS.some((d) => String(d) === value);

export function KeyUsageSection({ onHowItWorks }: KeyUsageProps) {
  const [days, setDays] = useState<UsageDays>(7);
  const usage = useQuery({
    queryKey: settingsKeys.keyUsage(days),
    queryFn: () => fetchKeyUsage(days),
  });

  return (
    <section className="flex flex-col gap-md">
      <div className="flex items-end justify-between gap-md">
        <div>
          <SettingsGroupHeader>{USAGE_COPY.title}</SettingsGroupHeader>
          <p className="px-lg text-body-small text-text-secondary">{USAGE_COPY.lead}</p>
        </div>
        <button
          type="button"
          onClick={onHowItWorks}
          className="px-lg font-mono text-caption tracking-[0.08em] text-accent-text uppercase hover:underline"
        >
          {KEYS_COPY.howItWorks}
        </button>
      </div>
      <Tabs
        value={String(days)}
        onValueChange={(v) => {
          if (isUsageDays(v)) setDays(Number(v) as UsageDays);
        }}
      >
        <TabsList className="w-full">
          {USAGE_DAYS.map((d) => (
            <TabsTrigger key={d} value={String(d)}>
              {USAGE_COPY.days[d]}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      {usage.isPending && <LoadingRows rows={2} />}
      {usage.isError && (
        <ErrorNotice
          message={errorMessage(usage.error) || USAGE_COPY.loadFailed}
          onRetry={() => void usage.refetch()}
        />
      )}
      {usage.data && <UsageBody usage={usage.data} />}
    </section>
  );
}

function UsageBody({ usage }: { usage: KeyUsage }) {
  if (!usage.enabled) return <EmptyNotice title={USAGE_COPY.disabled} />;
  if (usage.totals.requests === 0)
    return <EmptyNotice title={USAGE_COPY.empty} hint={USAGE_COPY.emptyHint} />;
  const peak = Math.max(1, ...usage.byDay.map((d) => d.requests));

  return (
    <div className="flex flex-col gap-lg">
      <dl className="grid grid-cols-2 gap-group-gap sm:grid-cols-4">
        <Metric label={USAGE_COPY.requests} value={formatCount(usage.totals.requests)} />
        <Metric label={USAGE_COPY.tokens} value={formatCount(usage.totals.tokens)} />
        <Metric label={USAGE_COPY.latency} value={formatLatency(usage.totals.avgLatencyMs)} />
        <Metric label={USAGE_COPY.failed} value={formatCount(usage.totals.errors)} />
      </dl>
      <figure className="flex flex-col gap-sm rounded-card bg-cell p-lg">
        <figcaption className="font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
          {USAGE_COPY.byDay}
        </figcaption>
        <ol className="flex h-28 items-end gap-xxs" aria-label={USAGE_COPY.byDay}>
          {usage.byDay.map((d) => (
            <li
              key={d.day}
              title={`${shortDay(d.day)}: ${d.requests}`}
              className="flex h-full min-w-0 flex-1 flex-col justify-end"
            >
              <span
                className="w-full rounded-sm bg-accent"
                style={{
                  height: `${Math.max(d.requests > 0 ? 4 : 1, (d.requests / peak) * 100)}%`,
                  opacity: d.requests > 0 ? 1 : 0.25,
                }}
              />
              <span className="sr-only">{`${shortDay(d.day)}: ${d.requests} requests`}</span>
            </li>
          ))}
        </ol>
        <div className="flex justify-between font-mono text-caption text-text-tertiary">
          <span>{shortDay(usage.byDay[0]?.day ?? "")}</span>
          <span>{shortDay(usage.byDay[usage.byDay.length - 1]?.day ?? "")}</span>
        </div>
      </figure>
      <div>
        <SettingsGroupHeader>{USAGE_COPY.byModel}</SettingsGroupHeader>
        <SettingsGroup>
          {usage.byModel.map((m) => (
            <SettingsTile
              key={`${m.provider}:${m.model}`}
              icon="models"
              title={m.model || m.provider}
              subtitle={`${m.provider} · ${USAGE_COPY.modelLine(m.requests, formatCount(m.tokens))}`}
              value={formatLatency(m.avgLatencyMs)}
            />
          ))}
        </SettingsGroup>
      </div>
      <div>
        <SettingsGroupHeader>{USAGE_COPY.byProvider}</SettingsGroupHeader>
        <SettingsGroup>
          {usage.byProvider.map((p) => (
            <SettingsTile
              key={p.provider}
              icon="server"
              title={p.provider}
              subtitle={USAGE_COPY.modelLine(p.requests, formatCount(p.tokens))}
              value={formatLatency(p.avgLatencyMs)}
            />
          ))}
        </SettingsGroup>
      </div>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-xxs rounded-group-inner bg-cell px-lg py-md first:rounded-tl-group-outer last:rounded-br-group-outer">
      <dt className="font-mono text-caption tracking-[0.08em] text-text-secondary uppercase">
        {label}
      </dt>
      <dd className="text-metric font-bold">{value}</dd>
    </div>
  );
}
