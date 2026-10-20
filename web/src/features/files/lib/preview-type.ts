import type { FileInfo } from "../api/schemas";
import { extensionOf } from "./limits";

export type PreviewType = "image" | "video" | "audio" | "pdf" | "text" | "office";

const OFFICE = new Set(["docx", "xlsx", "doc", "xls", "ppt", "pptx"]);

export function previewTypeOf(file: Pick<FileInfo, "kind" | "name" | "mime">): PreviewType {
  if (file.kind === "image" || file.kind === "video" || file.kind === "audio") return file.kind;
  const extension = extensionOf(file.name);
  const mime = file.mime.toLowerCase();
  if (extension === "pdf" || mime === "application/pdf") return "pdf";
  if (OFFICE.has(extension) || mime.includes("officedocument")) return "office";
  return "text";
}
