export { AttachmentChip, type AttachmentChipData } from "./components/attachment-chip";
export { AttachmentPicker } from "./components/attachment-picker";
export { FilePreviewSheet } from "./components/file-preview-sheet";
export { useAttachments, type Attachment, type AttachmentsController } from "./lib/use-attachments";
export { uploadFile, FilesApiError } from "./api/client";
export type { FileInfo } from "./api/schemas";
export { checkFile, formatBytes, ACCEPT, SIZE_LIMITS, MAX_FILES_PER_MESSAGE } from "./lib/limits";
