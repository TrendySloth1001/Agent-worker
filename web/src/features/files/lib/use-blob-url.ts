"use client";

import { useEffect, useState } from "react";
import { proxiedBlobPath } from "../api/client";

export type BlobUrlState =
  { status: "loading" } | { status: "ready"; url: string } | { status: "failed" };

interface Settled {
  source: string | undefined;
  state: BlobUrlState;
}

export function useBlobUrl(source: string | undefined): BlobUrlState {
  const [settled, setSettled] = useState<Settled | null>(null);
  const path = source ? proxiedBlobPath(source) : null;

  useEffect(() => {
    if (!path) return;
    const controller = new AbortController();
    let objectUrl: string | null = null;
    fetch(path, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("blob");
        return response.blob();
      })
      .then((blob) => {
        objectUrl = URL.createObjectURL(blob);
        setSettled({ source, state: { status: "ready", url: objectUrl } });
      })
      .catch(() => {
        if (!controller.signal.aborted) setSettled({ source, state: { status: "failed" } });
      });
    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path, source]);

  if (!path) return { status: "failed" };
  return settled && settled.source === source ? settled.state : { status: "loading" };
}
