export type FileKind = "image" | "document" | "video" | "audio";

const MB = 1024 * 1024;

export const MAX_FILES_PER_MESSAGE = 10;
export const MAX_CONCURRENT_UPLOADS = 3;
export const UPLOAD_TIMEOUT_MS = 10 * 60 * 1000;
export const TEXT_PAGE_CHARS = 200_000;

export const SIZE_LIMITS: Readonly<Record<FileKind, number>> = {
  image: 15 * MB,
  document: 25 * MB,
  video: 100 * MB,
  audio: 25 * MB,
};

const EXTENSIONS: Readonly<Record<FileKind, readonly string[]>> = {
  image: ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif"],
  video: ["mp4", "mov", "webm", "mkv", "m4v", "3gp"],
  audio: ["mp3", "m4a", "wav", "ogg", "opus", "aac", "flac"],
  document: [
    "pdf",
    "docx",
    "xlsx",
    "txt",
    "md",
    "markdown",
    "csv",
    "json",
    "html",
    "css",
    "xml",
    "yaml",
    "yml",
    "toml",
    "ts",
    "tsx",
    "js",
    "jsx",
    "mjs",
    "py",
    "dart",
    "java",
    "kt",
    "go",
    "rs",
    "sql",
    "sh",
    "c",
    "h",
    "cpp",
    "cs",
    "rb",
    "php",
    "swift",
    "log",
    "ini",
    "env",
  ],
};

export const ACCEPT = Object.values(EXTENSIONS)
  .flat()
  .map((extension) => `.${extension}`)
  .join(",");

export function extensionOf(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot < 0 ? "" : name.slice(dot + 1).toLowerCase();
}

export function classifyFile(name: string, mime: string): FileKind | null {
  const extension = extensionOf(name);
  for (const kind of Object.keys(EXTENSIONS) as FileKind[]) {
    if (EXTENSIONS[kind].includes(extension)) return kind;
  }
  const family = mime.split("/")[0];
  if (family === "image" || family === "video" || family === "audio") return family;
  return mime === "application/pdf" || mime.startsWith("text/") ? "document" : null;
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < MB) return `${(bytes / 1024).toFixed(bytes < 10 * 1024 ? 1 : 0)} KB`;
  if (bytes < 1024 * MB) return `${(bytes / MB).toFixed(bytes < 10 * MB ? 1 : 0)} MB`;
  return `${(bytes / (1024 * MB)).toFixed(1)} GB`;
}

export interface FileCheck {
  kind: FileKind | null;
  error: string | null;
}

export function checkFile(file: Pick<File, "name" | "type" | "size">): FileCheck {
  const kind = classifyFile(file.name, file.type);
  if (!kind) return { kind, error: "sparky can't open this kind of file." };
  if (file.size === 0) return { kind, error: "This file is empty." };
  if (file.size > SIZE_LIMITS[kind]) {
    return {
      kind,
      error: `${kind[0]?.toUpperCase()}${kind.slice(1)} files can be at most ${formatBytes(SIZE_LIMITS[kind])}.`,
    };
  }
  return { kind, error: null };
}
