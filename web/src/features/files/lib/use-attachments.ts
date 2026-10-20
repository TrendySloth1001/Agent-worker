"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "@/components/ui/toaster";
import { uploadFile } from "../api/client";
import type { FileInfo } from "../api/schemas";
import { checkFile, MAX_CONCURRENT_UPLOADS, MAX_FILES_PER_MESSAGE, type FileKind } from "./limits";

export type AttachmentStatus = "uploading" | "ready" | "error";

export interface Attachment {
  key: string;
  name: string;
  size: number;
  kind: FileKind;
  status: AttachmentStatus;
  progress: number;
  error?: string;
  file?: FileInfo;
  localUrl?: string;
}

export interface AttachmentsController {
  items: Attachment[];
  uploading: boolean;
  files: FileInfo[];
  add: (files: Iterable<File>) => void;
  remove: (key: string) => void;
  retry: (key: string) => void;
  clear: () => void;
  max: number;
}

interface Options {
  conversationId?: string;
  max?: number;
  upload?: typeof uploadFile;
}

export function useAttachments({
  conversationId,
  max = MAX_FILES_PER_MESSAGE,
  upload = uploadFile,
}: Options = {}): AttachmentsController {
  const [items, setItems] = useState<Attachment[]>([]);
  const sources = useRef(new Map<string, File>());
  const controllers = useRef(new Map<string, AbortController>());
  const queue = useRef<string[]>([]);
  const active = useRef(0);
  const counter = useRef(0);
  const itemsRef = useRef(items);

  useEffect(() => {
    itemsRef.current = items;
  }, [items]);

  const patch = useCallback((key: string, change: Partial<Attachment>) => {
    setItems((current) =>
      current.map((item) => (item.key === key ? { ...item, ...change } : item)),
    );
  }, []);

  const pump = useCallback(
    function run() {
      while (active.current < MAX_CONCURRENT_UPLOADS && queue.current.length > 0) {
        const key = queue.current.shift();
        const source = key ? sources.current.get(key) : undefined;
        if (!key || !source) continue;
        const controller = new AbortController();
        controllers.current.set(key, controller);
        active.current++;
        patch(key, { status: "uploading", progress: 0, error: undefined });
        upload(source, {
          conversationId,
          signal: controller.signal,
          onProgress: (progress) => patch(key, { progress }),
        })
          .then((file) => patch(key, { status: "ready", progress: 1, file }))
          .catch((error: unknown) => {
            if (error instanceof DOMException && error.name === "AbortError") return;
            patch(key, {
              status: "error",
              error: error instanceof Error ? error.message : "Upload failed.",
            });
          })
          .finally(() => {
            active.current--;
            controllers.current.delete(key);
            run();
          });
      }
    },
    [conversationId, patch, upload],
  );

  const add = useCallback(
    (incoming: Iterable<File>) => {
      let room = max - itemsRef.current.length;
      const created: Attachment[] = [];
      for (const file of incoming) {
        if (room <= 0) {
          toast(`You can attach up to ${max} files.`);
          break;
        }
        const { kind, error } = checkFile(file);
        if (!kind || error) {
          toast(`${file.name}: ${error}`);
          continue;
        }
        const key = `attachment-${++counter.current}`;
        sources.current.set(key, file);
        queue.current.push(key);
        room--;
        created.push({
          key,
          name: file.name,
          size: file.size,
          kind,
          status: "uploading",
          progress: 0,
          localUrl: kind === "image" ? URL.createObjectURL(file) : undefined,
        });
      }
      if (created.length === 0) return;
      setItems((current) => [...current, ...created]);
      pump();
    },
    [max, pump],
  );

  const release = useCallback((item: Attachment) => {
    controllers.current.get(item.key)?.abort();
    sources.current.delete(item.key);
    queue.current = queue.current.filter((key) => key !== item.key);
    if (item.localUrl) URL.revokeObjectURL(item.localUrl);
  }, []);

  const remove = useCallback(
    (key: string) => {
      const item = itemsRef.current.find((candidate) => candidate.key === key);
      if (item) release(item);
      setItems((current) => current.filter((candidate) => candidate.key !== key));
    },
    [release],
  );

  const retry = useCallback(
    (key: string) => {
      queue.current.push(key);
      pump();
    },
    [pump],
  );

  const clear = useCallback(() => {
    itemsRef.current.forEach(release);
    setItems([]);
  }, [release]);

  useEffect(() => {
    const live = controllers.current;
    return () => live.forEach((controller) => controller.abort());
  }, []);

  return {
    items,
    uploading: items.some((item) => item.status === "uploading"),
    files: items.flatMap((item) => (item.file ? [item.file] : [])),
    add,
    remove,
    retry,
    clear,
    max,
  };
}
