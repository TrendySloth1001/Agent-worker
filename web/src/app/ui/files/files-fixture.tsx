"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  AttachmentChip,
  AttachmentPicker,
  FilePreviewSheet,
  useAttachments,
  type Attachment,
  type FileInfo,
} from "@/features/files";
import { fileKeys } from "@/features/files/api/queries";
import type { InsightPayload, TextPage } from "@/features/files/api/schemas";
import { Textarea } from "@/components/ui/textarea";
import { FixtureQueryProvider } from "../_fixtures/fixture-query-provider";

const IMAGE: FileInfo = {
  id: "11111111-1111-4111-8111-111111111111",
  name: "mountain-lake.jpg",
  mime: "image/jpeg",
  size: 482_113,
  kind: "image",
  status: "ready",
  url: "https://picsum.photos/seed/sparky-file/900/600",
  thumbUrl: "https://picsum.photos/seed/sparky-file/120/120",
  meta: {},
};

const NOTES: FileInfo = {
  id: "22222222-2222-4222-8222-222222222222",
  name: "meeting-notes.md",
  mime: "text/markdown",
  size: 3_204,
  kind: "document",
  status: "ready",
  url: "https://example.com/meeting-notes.md",
  meta: {},
};

const NOTES_TEXT =
  "# Weekly sync\n\n- Ship the web beta to testers on Friday.\n- Rich answer cards: charts, quizzes and action cards are done.\n- Next: voice input and the settings screens.\n\nAction items\n1. Nikhil: finish the files module.\n2. Asha: review the BFF proxy.";

const IMAGE_INSIGHT: InsightPayload = {
  id: IMAGE.id,
  kind: "image",
  status: "ready",
  chars: 0,
  hasText: false,
  insight: {
    summary: "A calm mountain lake at sunrise.",
    caption: "A still mountain lake reflecting pine-covered slopes under a pale morning sky.",
    keyPoints: ["Snow-capped peaks in the distance", "Mist over the water", "No people visible"],
    ocr: "TRAIL CLOSED AFTER DARK",
  },
  video: null,
};

const NOTES_INSIGHT: InsightPayload = {
  id: NOTES.id,
  kind: "document",
  status: "ready",
  chars: NOTES_TEXT.length,
  hasText: true,
  insight: {
    summary: "Notes from a weekly sync about shipping the web beta and next steps.",
    keyPoints: [
      "Web beta ships Friday",
      "Rich answer cards are done",
      "Voice and settings come next",
    ],
  },
  video: null,
};

const NOTES_PAGE: TextPage = {
  text: NOTES_TEXT,
  offset: 0,
  truncated: false,
  chars: NOTES_TEXT.length,
};

const SEEDS = [
  [fileKeys.insight(IMAGE.id), IMAGE_INSIGHT],
  [fileKeys.insight(NOTES.id), NOTES_INSIGHT],
  [fileKeys.text(NOTES.id), NOTES_PAGE],
] as const;

function fakeUpload(
  file: File,
  options: { onProgress?: (ratio: number) => void; signal?: AbortSignal } = {},
): Promise<FileInfo> {
  return new Promise((resolve, reject) => {
    let ratio = 0;
    const timer = window.setInterval(() => {
      ratio = Math.min(1, ratio + 0.2);
      options.onProgress?.(ratio);
      if (ratio < 1) return;
      window.clearInterval(timer);
      resolve({
        id: crypto.randomUUID(),
        name: file.name,
        mime: file.type || "application/octet-stream",
        size: file.size,
        kind: file.type.startsWith("image/") ? "image" : "document",
        status: "ready",
        url: URL.createObjectURL(file),
        meta: {},
      });
    }, 350);
    options.signal?.addEventListener("abort", () => {
      window.clearInterval(timer);
      reject(new DOMException("cancelled", "AbortError"));
    });
  });
}

function Demo({ initial }: { initial: "image" | "document" | null }) {
  const controller = useAttachments({ upload: fakeUpload });
  const [preview, setPreview] = useState<FileInfo | null>(
    initial === "image" ? IMAGE : initial === "document" ? NOTES : null,
  );

  return (
    <>
      <Card className="flex flex-col gap-md">
        <p className="font-mono text-caption tracking-[0.14em] text-text-tertiary uppercase">
          Picker (drop, paste or browse)
        </p>
        <AttachmentPicker
          controller={controller}
          onPreview={(item: Attachment) => item.file && setPreview(item.file)}
        >
          <Textarea placeholder="Message sparky" rows={1} />
        </AttachmentPicker>
      </Card>
      <Card className="flex flex-col gap-md">
        <p className="font-mono text-caption tracking-[0.14em] text-text-tertiary uppercase">
          Chips
        </p>
        <div className="flex flex-wrap gap-sm">
          <AttachmentChip
            attachment={{
              name: "report.pdf",
              size: 2_400_000,
              kind: "document",
              status: "uploading",
              progress: 0.45,
            }}
            onRemove={() => undefined}
          />
          <AttachmentChip
            attachment={{
              name: "voice-note.m4a",
              size: 880_000,
              kind: "audio",
              status: "error",
              error: "Upload failed",
            }}
            onRemove={() => undefined}
            onRetry={() => undefined}
          />
          <AttachmentChip
            attachment={{ name: IMAGE.name, size: IMAGE.size, kind: "image", file: IMAGE }}
            onOpen={() => setPreview(IMAGE)}
          />
          <AttachmentChip
            attachment={{ name: NOTES.name, size: NOTES.size, kind: "document", file: NOTES }}
            onOpen={() => setPreview(NOTES)}
          />
        </div>
      </Card>
      <div className="flex flex-wrap gap-sm">
        <Button variant="secondary" onClick={() => setPreview(IMAGE)}>
          Preview image
        </Button>
        <Button variant="secondary" onClick={() => setPreview(NOTES)}>
          Preview document
        </Button>
      </div>
      <FilePreviewSheet
        file={preview}
        open={preview !== null}
        onOpenChange={(open) => !open && setPreview(null)}
      />
    </>
  );
}

export function FilesFixture({ initial = null }: { initial?: "image" | "document" | null }) {
  return (
    <FixtureQueryProvider seeds={SEEDS}>
      <Demo initial={initial} />
    </FixtureQueryProvider>
  );
}
