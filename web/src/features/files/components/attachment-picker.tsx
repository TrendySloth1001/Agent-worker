"use client";

import { useRef, useState, type ClipboardEvent, type DragEvent, type ReactNode } from "react";
import { IconButton } from "@/components/ui/icon-button";
import { cn } from "@/lib/cn";
import { ACCEPT } from "../lib/limits";
import type { Attachment, AttachmentsController } from "../lib/use-attachments";
import { AttachmentChip } from "./attachment-chip";

interface AttachmentPickerProps {
  controller: AttachmentsController;
  onPreview?: (attachment: Attachment) => void;
  disabled?: boolean;
  className?: string;
  children?: ReactNode;
}

function hasFiles(event: DragEvent): boolean {
  return Array.from(event.dataTransfer.types).includes("Files");
}

export function AttachmentPicker({
  controller,
  onPreview,
  disabled = false,
  className,
  children,
}: AttachmentPickerProps) {
  const input = useRef<HTMLInputElement>(null);
  const depth = useRef(0);
  const [dragging, setDragging] = useState(false);
  const full = controller.items.length >= controller.max;

  function onDragEnter(event: DragEvent) {
    if (disabled || !hasFiles(event)) return;
    event.preventDefault();
    depth.current++;
    setDragging(true);
  }

  function onDragLeave(event: DragEvent) {
    if (!hasFiles(event)) return;
    depth.current = Math.max(0, depth.current - 1);
    if (depth.current === 0) setDragging(false);
  }

  function onDrop(event: DragEvent) {
    if (!hasFiles(event)) return;
    event.preventDefault();
    depth.current = 0;
    setDragging(false);
    if (!disabled) controller.add(Array.from(event.dataTransfer.files));
  }

  function onPaste(event: ClipboardEvent) {
    if (disabled || event.clipboardData.files.length === 0) return;
    event.preventDefault();
    controller.add(Array.from(event.clipboardData.files));
  }

  return (
    <div
      className={cn("relative flex flex-col gap-sm", className)}
      onDragEnter={onDragEnter}
      onDragOver={(event) => hasFiles(event) && event.preventDefault()}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      onPaste={onPaste}
    >
      {controller.items.length > 0 && (
        <ul className="flex flex-wrap gap-sm" aria-label="Attachments">
          {controller.items.map((item) => (
            <li key={item.key} className="min-w-0">
              <AttachmentChip
                attachment={item}
                onRemove={() => controller.remove(item.key)}
                onRetry={() => controller.retry(item.key)}
                onOpen={onPreview ? () => onPreview(item) : undefined}
              />
            </li>
          ))}
        </ul>
      )}
      <div className="flex items-end gap-sm">
        <input
          ref={input}
          type="file"
          multiple
          hidden
          accept={ACCEPT}
          onChange={(event) => {
            controller.add(Array.from(event.target.files ?? []));
            event.target.value = "";
          }}
        />
        <IconButton
          icon="attach"
          label="Attach files"
          disabled={disabled || full}
          onClick={() => input.current?.click()}
        />
        <div className="min-w-0 flex-1">{children}</div>
      </div>
      {dragging && (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center rounded-card border-2 border-dashed border-accent bg-background/85 font-mono text-label tracking-[0.12em] text-accent-text uppercase"
        >
          Drop files to attach
        </div>
      )}
    </div>
  );
}
