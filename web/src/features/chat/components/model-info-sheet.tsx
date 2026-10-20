"use client";

import { Sheet, SheetClose, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { Tag } from "@/components/ui/tag";
import { IconButton } from "@/components/ui/icon-button";
import type { AiModel } from "../api/models";
import { MODEL_INFO_COPY as COPY } from "../lib/copy";
import { ModelMark } from "./model-mark";

interface ModelInfoSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  modelId: string;
  name: string;
  model?: AiModel;
  latencyMs?: number;
  tokens?: number;
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-xs">
      <span className="font-mono text-caption tracking-[0.1em] text-text-tertiary uppercase">{label}</span>
      <span className="text-body-small text-text-primary">{children}</span>
    </div>
  );
}

export function ModelInfoSheet({ open, onOpenChange, modelId, name, model, latencyMs, tokens }: ModelInfoSheetProps) {
  const hasInfo = Boolean(model?.maker || model?.about || model?.contextTokens || model?.speed);
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent>
        <div className="flex flex-col gap-lg pb-md">
          <div className="flex items-start justify-between gap-md">
            <div className="flex min-w-0 items-center gap-md">
              <ModelMark modelId={modelId} className="size-10 text-body" />
              <div className="min-w-0">
                <p className="font-mono text-caption tracking-[0.1em] text-accent-text uppercase">{COPY.title}</p>
                <SheetTitle className="truncate text-title font-bold">{name}</SheetTitle>
              </div>
            </div>
            <SheetClose asChild>
              <IconButton icon="close" label="Close" variant="ghost" />
            </SheetClose>
          </div>
          <SheetDescription className="sr-only">{COPY.title}</SheetDescription>
          {hasInfo ? (
            <div className="flex flex-col gap-md">
              {model?.maker && <Row label={COPY.madeBy}>{model.maker}</Row>}
              {model?.about && <Row label={COPY.goodAt}>{model.about}</Row>}
              {model?.contextTokens ? <Row label={COPY.memory}>{COPY.memoryOf(model.contextTokens)}</Row> : null}
              {model?.speed && <Row label={COPY.feel}>{COPY.speeds[model.speed]}</Row>}
            </div>
          ) : (
            <p className="text-body-small text-text-secondary">{COPY.noInfo}</p>
          )}
          <div className="flex flex-wrap gap-sm">
            <Tag title={COPY.modelId}>{modelId}</Tag>
            {latencyMs !== undefined && <Tag>{(latencyMs / 1000).toFixed(1)}s</Tag>}
            {tokens ? <Tag>{tokens} tokens</Tag> : null}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}
