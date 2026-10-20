"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getText } from "../api/client";
import { useExtractedText, useInsight, useReadWithSparky } from "../api/queries";
import type { FileInfo, InsightPayload } from "../api/schemas";
import { Notice } from "./original-view";

function Block({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-sm">
      <h3 className="font-mono text-caption tracking-[0.12em] text-accent-text uppercase">
        {title}
      </h3>
      {children}
    </section>
  );
}

function clock(seconds: number): string {
  const total = Math.max(0, Math.round(seconds));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function BodyText({ file, payload }: { file: FileInfo; payload: InsightPayload }) {
  const first = useExtractedText(file.id, payload.hasText);
  const [more, setMore] = useState("");
  const [moreDone, setMoreDone] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(false);
  if (!payload.hasText) return null;
  if (first.isPending) return <Skeleton className="h-40 w-full" />;
  if (!first.data) return null;
  const text = first.data.text + more;
  const truncated = moreDone === null ? first.data.truncated : !moreDone;

  async function loadMore() {
    setLoading(true);
    try {
      const page = await getText(file.id, text.length);
      setMore((value) => value + page.text);
      setMoreDone(!page.truncated);
    } finally {
      setLoading(false);
    }
  }

  return (
    <Block title="Text">
      <p className="text-body-small leading-relaxed whitespace-pre-wrap text-text-primary">
        {text}
      </p>
      {truncated && (
        <Button
          size="sm"
          variant="secondary"
          disabled={loading}
          onClick={loadMore}
          className="self-start"
        >
          Load more
        </Button>
      )}
    </Block>
  );
}

function Content({ file, payload }: { file: FileInfo; payload: InsightPayload }) {
  const read = useReadWithSparky(file.id);
  const { insight, video } = payload;

  if (payload.status === "processing") {
    return (
      <Notice
        title="sparky is still reading this file"
        hint="Give it a moment, then check again."
      />
    );
  }
  if (payload.kind !== "image" && !payload.hasText && !video) {
    return (
      <Notice
        title="sparky found no text in this file"
        hint="It may be a scan or an empty file. The original view still works."
      />
    );
  }

  const action = (label: string, busyLabel: string) => (
    <Button
      size="sm"
      disabled={read.isPending}
      onClick={() => read.mutate()}
      className="self-start"
    >
      {read.isPending ? busyLabel : label}
    </Button>
  );

  return (
    <div className="flex flex-col gap-xl">
      {read.isError && (
        <p className="text-label text-error">sparky couldn&apos;t read this just now.</p>
      )}
      {!insight && (
        <Block title={payload.kind === "image" ? "Not read yet" : "Summary"}>
          <p className="text-body-small text-text-secondary">
            {payload.kind === "image"
              ? "Let sparky take a look and it'll keep a short reading of it here."
              : "sparky has the text. Ask for a short summary and key points."}
          </p>
          {action(payload.kind === "image" ? "Read it now" : "Summarize", "Reading…")}
        </Block>
      )}
      {insight && payload.kind !== "image" && (
        <>
          <Block title="Summary">
            <p className="text-body-small leading-relaxed">{insight.summary}</p>
          </Block>
          {insight.keyPoints.length > 0 && (
            <Block title="Key points">
              <ul className="flex flex-col gap-xs">
                {insight.keyPoints.map((point) => (
                  <li key={point} className="flex gap-sm text-body-small">
                    <span aria-hidden className="mt-[9px] size-1 shrink-0 rounded-full bg-accent" />
                    {point}
                  </li>
                ))}
              </ul>
            </Block>
          )}
        </>
      )}
      {insight && payload.kind === "image" && (
        <>
          <Block title="What's in the picture">
            <p className="text-body-small leading-relaxed">{insight.caption ?? insight.summary}</p>
          </Block>
          {insight.keyPoints.length > 0 && (
            <Block title="Key points">
              <ul className="flex flex-col gap-xs">
                {insight.keyPoints.map((point) => (
                  <li key={point} className="text-body-small">
                    {point}
                  </li>
                ))}
              </ul>
            </Block>
          )}
          {insight.ocr && (
            <Block title="Text in the picture">
              <p className="text-body-small whitespace-pre-wrap text-text-secondary">
                {insight.ocr}
              </p>
            </Block>
          )}
        </>
      )}
      {video && (
        <Block title="Timeline">
          <ol className="flex flex-col gap-sm">
            {video.frames.map((frame) => (
              <li key={`f${frame.t}`} className="flex gap-md text-body-small">
                <span className="w-10 shrink-0 font-mono text-caption text-accent-text">
                  {clock(frame.t)}
                </span>
                <span>{frame.caption ?? "Frame"}</span>
              </li>
            ))}
            {video.segments.map((segment) => (
              <li
                key={`s${segment.start}`}
                className="flex gap-md text-body-small text-text-secondary"
              >
                <span className="w-10 shrink-0 font-mono text-caption text-text-tertiary">
                  {clock(segment.start)}
                </span>
                <span>{segment.text}</span>
              </li>
            ))}
          </ol>
        </Block>
      )}
      {(payload.kind === "document" || payload.kind === "audio") && (
        <BodyText file={file} payload={payload} />
      )}
    </div>
  );
}

export function SparkyView({ file }: { file: FileInfo }) {
  const query = useInsight(file.id);
  if (query.isPending) {
    return (
      <div role="status" aria-label="sparky is reading…" className="flex flex-col gap-md">
        <Skeleton className="h-4 w-1/3" />
        <Skeleton className="h-20 w-full" />
        <Skeleton className="h-4 w-1/2" />
      </div>
    );
  }
  if (!query.data) {
    return (
      <div className="flex flex-col items-center gap-md">
        <Notice
          tone="error"
          title="Couldn't get sparky's reading"
          hint="Check your connection and try again."
        />
        <Button size="sm" variant="secondary" onClick={() => void query.refetch()}>
          Retry
        </Button>
      </div>
    );
  }
  return <Content file={file} payload={query.data} />;
}
