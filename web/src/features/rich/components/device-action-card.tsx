"use client";

import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";
import type { DeviceActionView } from "../parsers/device-action";
import { copyText, RichFrame } from "./frame";

const PHONE_ONLY = "Runs on your phone in the sparky app";

export function DeviceActionCard({ data }: { data: DeviceActionView }) {
  return (
    <RichFrame label={data.kicker}>
      <div className="flex flex-wrap items-center justify-between gap-md">
        <div className="min-w-0">
          <p className="truncate text-title font-medium">{data.title}</p>
          {data.subtitle && (
            <p className="line-clamp-2 text-body-small text-text-secondary">{data.subtitle}</p>
          )}
          {data.kind === "phone" && (
            <p className="mt-xs text-label text-text-tertiary">{PHONE_ONLY}</p>
          )}
        </div>
        {data.kind === "link" && (
          <Button asChild size="sm">
            <a href={data.href} target="_blank" rel="noopener noreferrer">
              <Icon name="openExternal" size="sm" />
              {data.cta}
            </a>
          </Button>
        )}
        {data.kind === "copy" && (
          <Button size="sm" onClick={() => void copyText(data.text)}>
            <Icon name="copy" size="sm" />
            {data.cta}
          </Button>
        )}
      </div>
    </RichFrame>
  );
}
