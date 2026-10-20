"use client";

import { Icon } from "@/components/ui/icon";
import type { IconName } from "@/components/ui/icons";
import { cn } from "@/lib/cn";
import { formatBytes, type FileKind } from "../lib/limits";
import type { Attachment } from "../lib/use-attachments";

const KIND_ICON: Record<FileKind, IconName> = {
  image: "image",
  video: "video",
  audio: "audio",
  document: "file",
};

export type AttachmentChipData = Pick<Attachment, "name" | "size" | "kind"> &
  Partial<Pick<Attachment, "status" | "progress" | "error" | "localUrl" | "file">>;

interface AttachmentChipProps {
  attachment: AttachmentChipData;
  onRemove?: () => void;
  onRetry?: () => void;
  onOpen?: () => void;
  className?: string;
}

export function AttachmentChip({
  attachment,
  onRemove,
  onRetry,
  onOpen,
  className,
}: AttachmentChipProps) {
  const { name, size, kind, status = "ready", progress = 1, error, localUrl, file } = attachment;
  const thumb = localUrl ?? file?.thumbUrl ?? (kind === "image" ? file?.url : undefined);
  const openable = Boolean(onOpen) && status === "ready";
  const caption =
    status === "uploading"
      ? `${Math.round(progress * 100)}%`
      : status === "error"
        ? (error ?? "Upload failed")
        : file?.status === "processing"
          ? "Processing"
          : formatBytes(size);

  return (
    <div
      className={cn(
        "relative flex h-12 max-w-64 min-w-0 items-center gap-sm overflow-hidden rounded-pill border bg-surface-raised pr-xs pl-xs",
        status === "error" ? "border-error" : "border-border",
        className,
      )}
    >
      <button
        type="button"
        disabled={!openable}
        onClick={onOpen}
        aria-label={openable ? `Preview ${name}` : name}
        className="flex min-w-0 flex-1 items-center gap-sm rounded-pill pr-sm text-left focus-visible:outline-2 focus-visible:outline-accent enabled:cursor-pointer"
      >
        <span
          role="img"
          aria-label=""
          className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full bg-surface-high bg-cover bg-center text-text-secondary"
          style={thumb ? { backgroundImage: `url("${thumb}")` } : undefined}
        >
          {!thumb && <Icon name={KIND_ICON[kind]} size="sm" />}
        </span>
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-label leading-tight font-medium">{name}</span>
          <span
            className={cn(
              "truncate font-mono text-caption leading-tight",
              status === "error" ? "text-error" : "text-text-tertiary",
            )}
          >
            {caption}
          </span>
        </span>
      </button>
      {status === "error" && onRetry && (
        <button
          type="button"
          onClick={onRetry}
          aria-label={`Retry ${name}`}
          className="flex size-7 shrink-0 items-center justify-center rounded-full text-text-secondary hover:bg-surface-high hover:text-text-primary"
        >
          <Icon name="retry" size="sm" />
        </button>
      )}
      {onRemove && (
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Remove ${name}`}
          className="flex size-7 shrink-0 items-center justify-center rounded-full text-text-secondary hover:bg-surface-high hover:text-text-primary focus-visible:outline-2 focus-visible:outline-accent"
        >
          <Icon name="close" size="sm" />
        </button>
      )}
      {status === "uploading" && (
        <span aria-hidden className="absolute inset-x-0 bottom-0 h-0.5 bg-border">
          <span
            className="duration-fast block h-full bg-accent transition-[width] ease-standard"
            style={{ width: `${progress * 100}%` }}
          />
        </span>
      )}
    </div>
  );
}
