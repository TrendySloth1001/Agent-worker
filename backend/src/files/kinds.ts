export type FileKind = "image" | "document" | "video" | "audio";

const MB = 1024 * 1024;
export const SIZE_LIMITS: Record<FileKind, number> = { image: 15 * MB, document: 25 * MB, video: 100 * MB, audio: 25 * MB };
export const MAX_UPLOAD_BYTES = 100 * MB;

const EXT: Record<string, { kind: FileKind; mime: string }> = {};
const add = (kind: FileKind, entries: Record<string, string>) => {
  for (const [ext, mime] of Object.entries(entries)) EXT[ext] = { kind, mime };
};
add("image", {
  jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", heic: "image/heic", heif: "image/heif",
});
add("document", {
  pdf: "application/pdf",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  txt: "text/plain", md: "text/markdown", markdown: "text/markdown", csv: "text/csv", json: "application/json",
  html: "text/html", css: "text/css", xml: "application/xml", yaml: "text/yaml", yml: "text/yaml", toml: "text/plain",
  ts: "text/plain", tsx: "text/plain", js: "text/javascript", jsx: "text/plain", mjs: "text/javascript",
  py: "text/x-python", dart: "text/plain", java: "text/x-java", kt: "text/plain", go: "text/plain", rs: "text/plain",
  sql: "text/plain", sh: "text/x-shellscript", c: "text/plain", h: "text/plain", cpp: "text/plain", cs: "text/plain",
  rb: "text/plain", php: "text/plain", swift: "text/plain", log: "text/plain", ini: "text/plain", env: "text/plain",
});
add("video", { mp4: "video/mp4", mov: "video/quicktime", webm: "video/webm", mkv: "video/x-matroska", m4v: "video/x-m4v", "3gp": "video/3gpp" });
add("audio", { mp3: "audio/mpeg", m4a: "audio/mp4", wav: "audio/wav", ogg: "audio/ogg", opus: "audio/opus", aac: "audio/aac", flac: "audio/flac" });

const MIME_KIND: Record<string, FileKind> = {
  "image/jpeg": "image", "image/png": "image", "image/webp": "image", "image/gif": "image", "image/heic": "image", "image/heif": "image",
  "application/pdf": "document", "text/plain": "document", "text/markdown": "document", "text/csv": "document", "application/json": "document",
  "video/mp4": "video", "video/quicktime": "video", "video/webm": "video", "video/x-matroska": "video",
  "video/x-m4v": "video", "video/3gpp": "video",
  "audio/mpeg": "audio", "audio/mp4": "audio", "audio/x-m4a": "audio", "audio/wav": "audio", "audio/x-wav": "audio", "audio/ogg": "audio",
  "audio/opus": "audio", "audio/aac": "audio", "audio/flac": "audio", "audio/x-flac": "audio",
};

export const extOf = (name: string) => (name.includes(".") ? name.split(".").pop()!.toLowerCase() : "");

/** Extension decides (apps often send application/octet-stream); the mime type is a fallback. */
export function classify(name: string, mime: string): { kind: FileKind; mime: string } | null {
  const e = EXT[extOf(name)];
  if (e) return { kind: e.kind, mime: mime && mime !== "application/octet-stream" && MIME_KIND[mime] === e.kind ? mime : e.mime };
  const k = MIME_KIND[mime.toLowerCase()];
  return k ? { kind: k, mime: mime.toLowerCase() } : null;
}
