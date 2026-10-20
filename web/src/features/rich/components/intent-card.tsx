"use client";

import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { cn } from "@/lib/cn";
import { resolveIntent, type IntentRun } from "../lib/intent";
import type { CardAction, IntentCardData } from "../parsers/intent-card";
import { copyText, RichFrame } from "./frame";

const TYPE_ICON: Record<IntentCardData["type"], IconName> = {
  place: "location",
  event: "calendar",
  clock: "timer",
  contact: "call",
  product: "cart",
  ride: "ride",
  food: "cart",
  travel: "web",
  upi: "send",
};

const APP_ICON: Record<string, IconName> = {
  maps: "location",
  call: "call",
  share: "share",
  calendar: "calendar",
  sms: "chat",
  mail: "mail",
};

function download(run: Extract<IntentRun, { kind: "download" }>) {
  const url = URL.createObjectURL(new Blob([run.content], { type: run.type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = run.filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

async function share(text: string) {
  if (typeof navigator.share === "function") {
    try {
      await navigator.share({ text });
      return;
    } catch {
      return;
    }
  }
  await copyText(text);
}

function ActionButton({ action }: { action: CardAction }) {
  const run = resolveIntent(action.intent);
  const icon = APP_ICON[action.app] ?? (run?.kind === "link" ? "openExternal" : "copy");
  const className = cn(action.chip && "px-md");
  const variant = action.primary ? "primary" : "secondary";
  if (!run) return null;
  if (run.kind === "link") {
    return (
      <Button asChild size="sm" variant={variant} className={className}>
        <a href={run.href} target="_blank" rel="noopener noreferrer">
          <Icon name={icon} size="sm" />
          {action.label}
        </a>
      </Button>
    );
  }
  return (
    <Button
      size="sm"
      variant={variant}
      className={className}
      onClick={() => {
        if (run.kind === "download") download(run);
        else if (action.intent.action === "send") void share(run.text);
        else void copyText(run.text);
      }}
    >
      <Icon name={icon} size="sm" />
      {action.label}
    </Button>
  );
}

export function IntentCard({ data }: { data: IntentCardData }) {
  return (
    <RichFrame label={data.type}>
      <div className="flex items-start gap-md">
        <span className="flex size-icon-circle shrink-0 items-center justify-center rounded-full bg-surface-raised">
          <Icon name={TYPE_ICON[data.type]} size="md" />
        </span>
        <div className="min-w-0">
          <p className="text-title font-medium">{data.title}</p>
          {data.subtitle && <p className="text-body-small text-text-secondary">{data.subtitle}</p>}
        </div>
      </div>
      {data.rows && data.rows.length > 0 && (
        <dl className="mt-md flex flex-col">
          {data.rows.map((row) => (
            <div
              key={row.k}
              className="flex justify-between gap-md border-t border-border py-sm text-body-small"
            >
              <dt className="text-text-secondary">{row.k}</dt>
              <dd className="min-w-0 text-right break-words">{row.v}</dd>
            </div>
          ))}
        </dl>
      )}
      {data.notice && <p className="mt-sm text-label text-text-tertiary">{data.notice}</p>}
      <div className="mt-md flex flex-wrap gap-sm">
        {data.actions.map((action) => (
          <ActionButton key={action.id} action={action} />
        ))}
      </div>
    </RichFrame>
  );
}
