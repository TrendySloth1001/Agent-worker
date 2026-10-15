import { Readable } from "node:stream";
import type { Response as ExpressResponse } from "express";
import type { DriveStream } from "./drive.js";

/** Response headers for a proxied Drive file: nothing from Google's reply except length/range, never a token. */
export function proxyHeaders(s: DriveStream): Record<string, string> {
  const name = encodeURIComponent(s.file.name.replace(/[\r\n"]/g, ""));
  const h: Record<string, string> = {
    "Content-Type": s.contentType,
    "Content-Disposition": `inline; filename*=UTF-8''${name}`,
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "sandbox; default-src 'none'",
    // The user's own file, cached by the app per (file, modifiedTime); never by shared caches.
    "Cache-Control": "private, max-age=0, must-revalidate",
    ...s.headers,
  };
  if (s.file.modifiedTime) h.ETag = `"${s.file.modifiedTime}"`;
  return h;
}

/** Streams [s] to the client (206 for a range). A matching `If-None-Match` answers 304 without a body. */
export async function sendDriveFile(res: ExpressResponse, s: DriveStream, ifNoneMatch?: string | null): Promise<void> {
  const h = proxyHeaders(s);
  if (s.status === 200 && ifNoneMatch && h.ETag && ifNoneMatch === h.ETag) {
    await s.body?.cancel().catch(() => undefined);
    res.status(304).set({ ETag: h.ETag, "Cache-Control": h["Cache-Control"] }).end();
    return;
  }
  res.status(s.status).set(h);
  if (!s.body) {
    res.end();
    return;
  }
  const src = Readable.fromWeb(s.body as import("node:stream/web").ReadableStream);
  res.on("close", () => src.destroy());
  await new Promise<void>((resolve) => {
    src.on("error", () => {
      res.destroy();
      resolve();
    });
    res.on("finish", resolve);
    res.on("close", resolve);
    src.pipe(res);
  });
}
