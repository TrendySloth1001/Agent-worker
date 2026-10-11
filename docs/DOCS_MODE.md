# DOC mode: long-form documents

The AI writes a long, cited, structured document on its own full page (reader), not in a chat bubble. Design is based on STORM (research → outline → cited sections), LongWriter/AgentWrite (outline with per-section word targets, write section by section), Gemini Deep Research (editable plan, inline citations + reference list, export), Perplexity Pages (per-section rewrite) and ChatGPT Canvas (length/level/polish actions, edit a selection).

## 1. Triggers
- **DOC chip** in `chat_input.dart` next to WEB/KB/TABLE. With DOC on, sending calls `POST /docs` instead of `/chat` (WEB/KB settings still apply).
- **Intent suggestion**: message matches `/\b(write|draft|create|make)\b.{0,40}\b(document|report|guide|whitepaper|article|handbook|brief|paper)\b/i` while DOC is off → one-tap "WRITE AS DOCUMENT?" above the input. Never auto-starts (~10 calls).
- **"TURN INTO DOC"** in `message_sheet.dart` on long replies (reply becomes the brief).

## 2. Pipeline (`backend/src/docs/pipeline.ts`)
Runs as a background job in-process, not tied to the HTTP request; state persisted after every section; clients attach/detach via SSE.

0. **Context** (parallel, optional): KB `retrieve(prompt,{k:8})`, attachments `prepareMessages`, base `webSearch(topic)` + `webFetch` of pasted URLs.
1. **Outline** — 1 `ask()` call, models `["groq:openai/gpt-oss-120b","ollama:gpt-oss:120b", <fallback>]`, 30 s, maxTokens 3000, given base-search snippets. Parse with `parseJson(raw,"sections")` (exported from `table/roundTable.ts`); invalid JSON → retry once on next model, then retryable failure. JSON:
   ```json
   {"title":"","subtitle":"","audience":"","style":"report|guide|explainer|tutorial|brief",
    "glossary":[{"term":"","definition":""}],
    "sections":[{"id":"s1","heading":"","goal":"one sentence","keyPoints":["…"],
      "queries":["≤2 web queries"],"visual":"none|mermaid|table|image|math","words":250}]}
   ```
   Section count by length: short 4, standard 6–8, long 10. `words` 250–900 per section. Server appends **Key takeaways** (written last) and **References** (built by code). If `reviewOutline`, stop at status `outline_ready` until `POST /docs/:id/start` with the edited outline.
2. **Per-section research** (WEB on): each section's queries via `webSearch`, ≤3 concurrent, 600 ms stagger, 12 s timeout. One doc-wide source list deduped by URL; stable ids W1…Wn (K#, D# likewise). Section context = its top 4 + top 2 shared; snippets ≤1,500 chars; full text kept for evidence.
3. **Sections** — N streamed `runChat` calls with fallback (≤3 attempts/section). Concurrency: 2 sections per doc; global doc semaphore 3 section calls across all docs (leave room for chat). Prompt: system preamble (date/language from `buildSystemPrompt`), style card, full outline marked "YOU WRITE: §k", glossary, running summaries of finished sections, headings+goals of later sections ("do not cover these"), section sources. Rules: body only (server inserts `## heading`; `###` ok); every factual sentence ends with a valid tag like [W3], never invent sources; follow `visual` (≤1 mermaid with allowed types/quoted labels, tables for comparisons, `$…$` math, ≤1 `{{image:…}}`, `> [!NOTE]`/`> [!WARNING]` callouts); no "In conclusion"; last line `<!--summary: two sentences-->` (server strips + stores as running summary). Per section: own `TagStream`, `keepValid` tag filter (from chat.ts), `onReset` → `doc_section_reset`, `finishReason==="length"` → one "continue from: <last 400 chars>" call. On done: `computeEvidence` for that section, resolve `{{image:}}` server-side with `imagesForQuery`, persist.
4. **Finish** — 1 `ask` (gpt-oss-20b): 3–5 key takeaways + one-paragraph abstract from stored summaries. References = cited sources in first-use order (code). Status `done` or `partial`.

Budget: ≤13 LLM calls, ≤16 web searches, 8 min wall clock (→ `partial`), 150 s per section. Failures: failed section → `failed`, doc continues. Startup sweep marks `planning`/`writing` docs `interrupted`. `POST /docs/:id/resume` rewrites non-done sections from stored outline+sources. Cancel aborts → `partial`. Limits: `docs` counter on `UserDailyUsage`, `docLimit` (default 5/day, owner unlimited), one running doc per user, `rateLimit(5)` on POST. ETA via `recordLatency("doc_section", model, ms)` → `etaMs` in `doc_status`.

## 3. Data model (one Prisma migration; every query scoped by userId)
- `Document` (`documents`): id uuid, userId FK cascade, conversationId? (set null), title, prompt, options Json (length, web, kb, sourceIds, model), status CHECK (planning|outline_ready|researching|writing|done|partial|failed|interrupted), outline Json, glossary Json, sources Json (Citation shape), summary, words, version Int, createdAt, updatedAt.
- `DocumentSection`: docId, sectionId, ord, heading, level, markdown, summary, status (pending|writing|done|failed), sourceIds[], usedIds[], evidence Json, images Json, model, words, updatedAt; PK (docId, sectionId).
- `DocumentRevision`: docId, sectionId, version, markdown, reason (generate|regenerate|expand|shorten|simplify|edit|custom), createdAt; keep last 10 per section.
- `DocumentHighlight`: id, docId, userId, sectionId, quote, prefix, suffix, color, note?, createdAt (W3C text-quote anchoring; orphaned if quote not found).
- Chat link: the assistant message's existing `meta` Json gets `{doc:{id,title,status,words,sections}}` (no conversations PUT change).

## 4. API (`routes/docs.ts`, mounted `/docs`)
- `POST /docs {prompt, conversationId?, length: short|standard|long, webSearch, knowledge, sourceIds?, attachments?, model?, profile?, reviewOutline?}` → 202 `{id}`.
- `GET /docs/:id/events` SSE: `doc_snapshot` (full state) first, then live events; idempotent reconnect.
- `GET /docs?conversationId=`, `GET /docs/:id`, `PATCH /docs/:id {title}`, `DELETE /docs/:id`.
- `POST /docs/:id/start | resume | cancel`.
- `POST /docs/:id/sections/:sid/rewrite {op: regenerate|expand|shorten|simplify|custom, instruction?, selection?}` → streams the same section events, saves a revision, bumps version.
- `PUT /docs/:id/sections/:sid {markdown}` (manual edit, saves revision); `POST /docs/:id/sections {after, heading, goal}` (add section).
- `GET /docs/:id/versions/:sid`.
- `GET/POST/DELETE /docs/:id/highlights`.
- `GET /docs/:id/export?format=md|docx`.

SSE events (`event:` name, JSON `data:`):
`doc_snapshot {doc}` · `doc_status {phase, done, total, elapsedMs, etaMs}` · `doc_outline {title, subtitle, sections[], glossary}` · `doc_sources {citations[]}` (append) · `doc_section_start {sectionId, model, sourceIds}` · `doc_section_delta {sectionId, text}` · `doc_section_reset {sectionId}` · `doc_section_done {sectionId, markdown, words, used, evidence, images}` · `doc_section_failed {sectionId, message, retryable}` · `doc_notice {code, message}` · `doc_done {status, words, used, latencyMs}` · `doc_error {message}`.
Live jobs: `docs/registry.ts` `Map<docId,{ctl, emitter, state}>` + semaphore.

## 5. Flutter (`features/docs/*`)
- `doc_screen.dart`: full-screen reader, max width 720. Header: title, subtitle, mono caps meta "14 MIN READ · 3,420 WORDS · 18 SOURCES · DONE". Body: `CustomScrollView`, one `AppMarkdown` per section (only the writing section `streaming: true`). Pending sections = skeleton cards (goal + `DotMeter`).
- TOC: wide (≥900) sticky rail; phone: pinned pill "§3/8 Heading" → TOC sheet with per-section status dots; jump via `Scrollable.ensureVisible`; current section from scroll position.
- Live progress bar: phase, done/total, ETA, STOP, RESUME.
- Citations → existing citation chip / evidence sheet with the doc's sources+evidence. References from `sources` filtered by used ids.
- Images, media lists, mermaid (fullscreen viewer), math, callouts, tables via existing markdown pipeline.
- Highlights (`doc_highlights.dart`): `SelectionArea` menu HIGHLIGHT, NOTE, ASK AI (custom rewrite with selection), COPY WITH CITATION; render by wrapping matched quotes in `==…==` (existing highlight syntax); notes as margin markers.
- Section menu (⋯ by heading): REGENERATE, EXPAND, SHORTEN, SIMPLIFY, INSTRUCT…, EDIT (markdown editor like `message_editor.dart`), VERSIONS.
- Chat card (`doc_card.dart`) rendered by `message_bubble.dart` when `meta.doc` is set: title, status, section dots, word count, OPEN; stays live via a `DocRegistry` (like background round tables).
- Export (`doc_export.dart`): PDF on device (refactor `_Writer` in `chat_pdf.dart` into reusable `MarkdownPdfWriter`; add cover, TOC, References), Markdown, DOCX from server; all via `share_sheet.dart`.

## 6. Files
Backend new: `src/prompts/doc.ts`, `src/docs/{registry,pipeline,outline,research,section,store,export}.ts` (export uses npm `docx` + `remark-parse`; mermaid/math as captioned code in phase 1), `src/routes/docs.ts`, tests. Changed: `index.ts` (mount, docLimit, startup sweep), `auth/limits.ts`, `prisma/schema.prisma` + migration.
Flutter new: `data/docs_api.dart`, `data/doc_models.dart` (Doc, DocSection, sealed DocEvent), `features/docs/{doc_controller,doc_registry,doc_screen,doc_toc,doc_progress,doc_section_menu,doc_highlights,doc_card,doc_export}.dart`. Changed: `chat_input.dart`, `chat_controller.dart`, `message_bubble.dart`, `message_sheet.dart`, `chat_pdf.dart`, constants (`DocStrings`, `AppIcons.doc`, `DocSizes`, `DocConfig`, share/export labels).

Phase 2: DOCX with real diagram images; per-section source picker.
