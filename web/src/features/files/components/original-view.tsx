"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/cn";
import { useExtractedText } from "../api/queries";
import type { FileInfo } from "../api/schemas";
import { useBlobUrl } from "../lib/use-blob-url";
import { previewTypeOf } from "../lib/preview-type";

export function Notice({
  title,
  hint,
  tone = "default",
}: {
  title: string;
  hint?: string;
  tone?: "default" | "error";
}) {
  return (
    <div className="flex min-h-48 flex-col items-center justify-center gap-xs px-lg text-center">
      <p
        className={cn(
          "font-mono text-label tracking-[0.1em] uppercase",
          tone === "error" ? "text-error" : "text-text-secondary",
        )}
      >
        {title}
      </p>
      {hint && <p className="max-w-[26rem] text-body-small text-text-tertiary">{hint}</p>}
    </div>
  );
}

function PdfView({ file }: { file: FileInfo }) {
  const blob = useBlobUrl(file.url);
  if (blob.status === "loading") return <Skeleton className="h-[calc(60dvh/var(--ui-zoom,1))] w-full" />;
  if (blob.status === "failed")
    return (
      <Notice
        tone="error"
        title="Couldn't load this PDF"
        hint="Check your connection and try again."
      />
    );
  return (
    <iframe
      title={file.name}
      src={blob.url}
      className="h-[calc(60dvh/var(--ui-zoom,1))] w-full rounded-md border border-border bg-surface"
    />
  );
}

function TextView({ file, hint }: { file: FileInfo; hint?: string }) {
  const text = useExtractedText(file.id, file.status === "ready");
  if (text.isPending && file.status === "ready") return <Skeleton className="h-64 w-full" />;
  if (!text.data)
    return <Notice title="No text to show" hint="sparky found no text in this file." />;
  return (
    <div className="flex flex-col gap-sm">
      {hint && <p className="text-label text-text-tertiary">{hint}</p>}
      <pre className="max-h-[calc(60dvh/var(--ui-zoom,1))] overflow-auto rounded-md border border-border bg-code-background p-md font-mono text-label leading-normal whitespace-pre-wrap">
        {text.data.text}
      </pre>
      {text.data.truncated && (
        <p className="text-label text-text-tertiary">
          Showing the first {text.data.text.length.toLocaleString("en-US")} characters.
        </p>
      )}
    </div>
  );
}

export function OriginalView({ file }: { file: FileInfo }) {
  if (!file.url)
    return <Notice title="Still processing" hint="This file isn't ready to view yet." />;
  switch (previewTypeOf(file)) {
    case "image":
      return (
        <div className="flex max-h-[calc(60dvh/var(--ui-zoom,1))] items-center justify-center overflow-hidden rounded-md bg-image-backdrop">
          {/* eslint-disable-next-line @next/next/no-img-element -- signed backend URL */}
          <img src={file.url} alt={file.name} className="max-h-[calc(60dvh/var(--ui-zoom,1))] max-w-full object-contain" />
        </div>
      );
    case "video":
      return (
        <video
          src={file.url}
          controls
          preload="metadata"
          className="max-h-[calc(60dvh/var(--ui-zoom,1))] w-full rounded-md bg-black"
        />
      );
    case "audio":
      return (
        <div className="flex min-h-32 items-center justify-center rounded-md border border-border bg-surface-raised p-lg">
          <audio src={file.url} controls preload="metadata" className="w-full" />
        </div>
      );
    case "pdf":
      return <PdfView file={file} />;
    case "office":
      return (
        <>
          <Notice
            title="This file can't be shown here"
            hint="Office files open best in another app. Below is the text sparky extracted."
          />
          <TextView file={file} />
        </>
      );
    case "text":
      return (
        <TextView
          file={file}
          hint="sparky read this text from the file. Layout and images are not shown."
        />
      );
  }
}
