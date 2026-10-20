"use client";

import { Icon } from "@/components/ui/icon";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetTitle,
} from "@/components/ui/sheet";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { FileInfo } from "../api/schemas";
import { formatBytes } from "../lib/limits";
import { OriginalView } from "./original-view";
import { SparkyView } from "./sparky-view";

interface FilePreviewSheetProps {
  file: FileInfo | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function FilePreviewSheet({ file, open, onOpenChange }: FilePreviewSheetProps) {
  return (
    <Sheet open={open && file !== null} onOpenChange={onOpenChange}>
      <SheetContent
        className="md:w-[min(52rem,calc(100vw-2rem))]"
        onOpenAutoFocus={(event) => event.preventDefault()}
      >
        {file && (
          <div className="flex min-h-0 flex-col gap-md pb-lg">
            <div className="flex items-start gap-md">
              <div className="min-w-0 flex-1">
                <SheetTitle className="truncate text-title font-medium">{file.name}</SheetTitle>
                <SheetDescription className="font-mono text-caption tracking-[0.08em] text-text-tertiary uppercase">
                  {file.kind} · {formatBytes(file.size)}
                </SheetDescription>
              </div>
              {file.url && (
                <a
                  href={file.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="Open in a new tab"
                  className="flex size-10 shrink-0 items-center justify-center rounded-full text-text-secondary hover:bg-surface-raised hover:text-text-primary"
                >
                  <Icon name="openExternal" />
                </a>
              )}
              <SheetClose
                aria-label="Close"
                className="flex size-10 shrink-0 items-center justify-center rounded-full text-text-secondary hover:bg-surface-raised hover:text-text-primary focus-visible:outline-2 focus-visible:outline-accent"
              >
                <Icon name="close" />
              </SheetClose>
            </div>
            <Tabs defaultValue="original" className="flex min-h-0 flex-col">
              <TabsList className="w-full">
                <TabsTrigger value="original">Original</TabsTrigger>
                <TabsTrigger value="sparky">sparky&apos;s view</TabsTrigger>
              </TabsList>
              <TabsContent value="original">
                <OriginalView file={file} />
              </TabsContent>
              <TabsContent value="sparky">
                <SparkyView file={file} />
              </TabsContent>
            </Tabs>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
