# Attachments: images, documents, videos

Files live in Supabase Storage (private bucket `attachments`) via the S3 API.
Env (backend/.env): `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET`.
All routes need `Authorization: Bearer <API_TOKEN>` like the rest of the API.

## Kinds and limits

| kind | accepted | max size | processing |
|---|---|---|---|
| image | jpeg, png, webp, gif, heic | 15 MB | width/height; a 512px JPEG thumbnail stored next to it |
| document | pdf, docx, txt, md, csv, json, code files (ts, js, py, dart, java, go, rs, sql, yaml, html, css…), xlsx | 25 MB | text extraction (pages for PDF); chunked + embedded for retrieval when long |
| video | mp4, mov, webm, mkv | 100 MB | ffmpeg: duration, up to 8 evenly spaced frames (JPEG, stored), poster thumbnail; audio → transcript (Groq whisper-large-v3-turbo) |
| audio | mp3, m4a, wav, ogg | 25 MB | transcript (Groq whisper) |

Anything else → 415.

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
- `DELETE /files/:id` → `204` (removes objects and rows).

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
