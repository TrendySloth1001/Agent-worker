# Attachments: images, documents, videos

Files live in Supabase Storage (private bucket `attachments`) via the S3 API.
Env (backend/.env): `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET`, optional `S3_MAX_OBJECT_BYTES` (largest object the storage accepts; default 50 MiB = Supabase Free plan's global limit).
Objects of a file live under `<file id>/` (`original.<ext>`, `thumb.jpg`, `frame-<n>.jpg`).
All routes need `Authorization: Bearer <access token>` (a signed-in user's JWT; the static API_TOKEN works as an owner dev bypass) like the rest of the API. Files belong to the uploading user.

## Kinds and limits

| kind | accepted | max size | processing |
|---|---|---|---|
| image | jpeg, png, webp, gif, heic | 15 MB | width/height; a 512px JPEG thumbnail stored next to it |
| document | pdf, docx, txt, md, csv, json, code files (ts, js, py, dart, java, go, rs, sql, yaml, html, css…), xlsx | 25 MB | text extraction (pages for PDF); chunked + embedded for retrieval when long |
| video | mp4, mov, webm, mkv, m4v, 3gp | 100 MB | ffmpeg: duration, up to 8 evenly spaced frames (JPEG, stored), poster thumbnail; audio → transcript (Groq whisper-large-v3-turbo) |
| audio | mp3, m4a, wav, ogg, opus, aac, flac | 25 MB | transcript (Groq whisper) |

Anything else → 415.

Uploads larger than `S3_MAX_OBJECT_BYTES` (phone videos often are): videos are not stored as uploaded but re-encoded while processing to H.264/AAC MP4 (≤1280 px, `+faststart`, bitrate chosen to fit), then stored as `original.mp4` with `mime: video/mp4` and the stored `size`; `meta.transcoded = true`. A video too long to fit at a watchable bitrate ends `failed`. Other kinds over the limit → 413. A storage write that fails → 503 (retryable), never a bare 500.

## FileInfo (JSON)

```json
{
  "id": "uuid",
  "name": "report.pdf",
  "mime": "application/pdf",
  "size": 123456,
  "kind": "image | document | video | audio",
  "status": "processing | ready | failed",
  "error": null,
  "url": "signed GET URL to the original, valid 1 hour",
  "thumbUrl": "signed GET URL to the thumbnail (images, videos) or null",
  "meta": { "width": 0, "height": 0, "pages": 0, "chars": 0, "durationS": 0, "frames": 0, "hasTranscript": false },
  "createdAt": "ISO"
}
```

## Endpoints

- `POST /files` — multipart/form-data, field `file` (one file), optional field `conversationId`. → `201 { "file": FileInfo }` (status usually `processing`; images may be `ready` immediately).
- `GET /files/:id` → `{ "file": FileInfo }` (fresh signed URLs every call).
- `GET /files/:id/text?limit=200000` → `{ "text": "...", "truncated": false, "chars": 1234 }`. Extracted document text, or the transcript for video/audio. `limit` 1..1000000 (default 200000). `404` when the file is unknown, not `ready`, or has no text (the app shows "still processing" and retries).
- `DELETE /files/:id` → `204`. Removes every object under `<id>/` (original, thumbnail, frames) and the rows; saved messages keep the attachment as a placeholder (`"deleted": true, "status": "deleted"`), which the app shows as a FILE DELETED tile. A deleted file in an older message of a later `/chat` request is skipped (the model sees a "deleted" note); only files of the newest user message must exist.

### Storage manager

- `GET /files?kind=&q=&sort=&cursor=&limit=` → `{ "files": [FileInfo & { "conversation": { "id", "title" } | null }], "nextCursor": "…" | null }`. The caller's files. `kind`: image|video|audio|document (plurals and `all` accepted); `q`: name contains (case-insensitive); `sort`: `newest` (default) | `largest` | `name`; `limit` 1..100 (default 40); `cursor` is opaque (keyset, from the previous page). `conversation` is the newest chat whose saved messages attach the file.
- `GET /files/usage` → `{ "totalBytes", "count", "byKind": { "image": { "count", "bytes" }, … }, "limits": { "storageBytes": n | null, "uploadsPerDay": n | null }, "today": { "uploads", "bytes" }, "resetsAt" }` (`null` limits = unlimited, the owner).
- `POST /files/bulk-delete` `{ "ids": ["uuid", …] }` (1..200) → `{ "deleted": n, "missing": ["uuid"] }`. Same as DELETE per file; unknown or foreign ids are listed in `missing`.
- `PATCH /files/:id` `{ "name": "new name" }` → `{ "file": FileInfo }`. Path parts and control characters are stripped, the original extension is kept, max 200 characters; saved messages show the new name.

## Chat

`POST /chat` user messages may carry attachments:

```json
{ "role": "user", "content": "What is in this?", "attachments": ["<file id>", "..."] }
```

- Up to 10 files per message. Content may be empty when attachments are present.
- The server waits (up to 90 s, sending `status { "phase": "processing_files" }`) for files still processing.
- Images (and video frames) go to a vision-capable model. Vision candidates, in order: `groq:qwen/qwen3.8-27b`, `ollama:gemma4:31b`, `nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`, `openrouter:google/gemma-4-31b-it:free`. When any message in the request has images/frames, Auto uses only these.
- Documents: text is injected in a `<documents>` block with tags `[D1]`, `[D2]`… (whole text when short, otherwise the most relevant chunks for the question). Citations for them use `kind: "file"`, `url: "file:<id>"`, `site: "document"`, `title: <file name>`; evidence works the same way as for `[W#]`/`[K#]`.
- Video: frames as images plus the transcript as text; audio: transcript as text.
- A new SSE event is NOT needed; `sources` includes the document citations.

## Conversations

Saved messages keep `attachments: FileInfo[]` (without signed URLs; the app calls `GET /files/:id` to refresh URLs when showing them). `GET /conversations/:id` returns them.
