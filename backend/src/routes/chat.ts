import { Router } from "express";
import { z } from "zod";
import { config } from "../config.js";
import { MODELS } from "../models.js";
import { AppError, errorBody } from "../util/errors.js";
import { log } from "../util/logger.js";
import { openSse } from "../util/sse.js";
import { pickCandidates, preferForPrompt, runChat, ChatFailure, maxTokensForMode } from "../llm/router.js";
import { researchWeb, webFetch } from "../web/search.js";
import { computeEvidence } from "../web/evidence.js";
import { TagStream } from "../web/tagStream.js";
import { githubGround } from "../github/grounding.js";
import { decideSearch } from "../web/searchDecision.js";
import { setTelemetry, withTelemetry } from "../db/usage.js";
import { findImages, type ImageResult } from "../web/images.js";
import { intentHint } from "../prompts/intent.js";
import { safetyNote } from "../nlp/pii.js";
import { buildContextMessage, buildSystemPrompt, promptNeeds, MODES, TONES, LENGTHS, type ContextItem } from "../prompts/system.js";
import { retrieve, type KbHit } from "../retrieval/search.js";
import { embeddingsHealthy } from "../embeddings/index.js";
import type { Message } from "../providers.js";
import { ATTACH_PLACEHOLDER, loadRows, prepareMessages, waitForFiles } from "../files/context.js";
import { initialEtaMs, isTrivialTurn, runRoundTable, UnresolvedFilter, type SeatResearchInput, type TableRun } from "../table/roundTable.js";
import { planQueries, runSeatResearch, type SeatResearch } from "../table/research.js";
import { recordLatency } from "../table/latency.js";
import { compactHistory, summaryMessage } from "../memory/compact.js";
import { startMemoryTurn } from "../memory/turn.js";
import { analyze } from "../nlp/index.js";
import { languageInstruction } from "../nlp/language.js";
import { shapeHint } from "../nlp/intent.js";
import { generateFollowups } from "../assist/suggest.js";
import { buildTurnContext, imageQuery, renderContext, topicTerms, type AttachmentInfo } from "../context/turnContext.js";
import { recallPastChats, type PastCitation } from "../recall/search.js";
import { isUuid } from "../docs/store.js";

// Vision-capable models, best first. Auto uses only these when a request has images or video frames.
const VISION_MODELS = [
  "groq:qwen/qwen3.8-27b",
  "ollama:gemma4:31b",
  "nvidia:nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
  "openrouter:google/gemma-4-31b-it:free",
];

export type Citation = {
  id: string;
  kind: "kb" | "web" | "file" | "conversation";
  title: string;
  url: string;
  snippet: string;
  site: string;
  sourceType?: string;
  /** Knowledge-base hits from a generated doc: which doc and section. */
  docId?: string;
  sectionId?: string;
  /** Knowledge-base hits from an uploaded file. */
  fileId?: string;
  /** Past-conversation hits (kind "conversation"): the chat, also in `url` as `chat:<id>`. */
  conversationId?: string;
};

// Each profile field is lenient: an invalid value is dropped, never a 400.
const lenient = <T extends z.ZodTypeAny>(schema: T) => schema.optional().catch(undefined);
const text = (max: number) => lenient(z.string().max(max).transform((s) => s.trim() || undefined));
const profileSchema = z
  .object({
    name: text(60),
    role: text(80),
    about: text(600),
    tone: lenient(z.enum(TONES)),
    length: lenient(z.enum(LENGTHS)),
    language: text(40),
    instructions: text(1500),
    signature: text(300),
  })
  .catch({});

const bodySchema = z.object({
  messages: z
    .array(
      z
        .object({
          role: z.enum(["user", "assistant"]),
          content: z.string(),
          attachments: z.array(z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, "must be a file id")).max(10).optional(),
        })
        .refine((m) => m.content.length > 0 || (m.role === "user" && (m.attachments?.length ?? 0) > 0), { message: "content must not be empty", path: ["content"] }),
    )
    .min(1)
    .max(40),
  model: z.string().optional(),
  // Telemetry only: which saved conversation this turn belongs to.
  conversationId: z.string().max(64).optional(),
  webSearch: z.boolean().default(false),
  knowledge: z.boolean().default(false),
  sourceIds: z.array(z.string()).max(50).optional(),
  mode: z.enum(MODES as [string, ...string[]]).default("default"),
  profile: profileSchema.optional(),
  // Round Table: several models draft and cross-review, a chair writes the answer.
  roundTable: z.boolean().default(false),
  // Briefing from a merged chat, sent as background (never as a user/assistant turn).
  context: z.string().max(8000).optional(),
});

const URL_RE = /https?:\/\/[^\s<>"')\]]+/i;

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
};
const snippet = (s: string) => s.replace(/\s+/g, " ").trim().slice(0, 200);
/** URL identity for merging search results (no scheme, www, fragment or trailing slash). */
const urlKey = (url: string) => url.replace(/^https?:\/\/(www\.)?/i, "").replace(/#.*$/, "").replace(/\/+$/, "").toLowerCase();

function retrievalQuery(messages: Message[]): string {
  const lastUser = [...messages].reverse().find((m) => m.role === "user")?.content.trim() ?? "";
  if (lastUser.length >= 40) return lastUser.slice(0, 500);
  const lastAssistant = [...messages].reverse().find((m) => m.role === "assistant")?.content.slice(0, 300) ?? "";
  return `${lastAssistant}\n${lastUser}`.trim();
}

/** The user message before the latest one, for resolving follow-up questions into standalone search queries. */
function previousUser(messages: Message[]): string {
  const users = messages.filter((m) => m.role === "user");
  return users.length > 1 ? users[users.length - 2].content.slice(0, 400) : "";
}

function searchQuery(text: string): string {
  const stripped = text.replace(new RegExp(URL_RE, "gi"), " ").replace(/\s+/g, " ").trim();
  const q = stripped.length >= 8 ? stripped : text.trim();
  return q.slice(0, 200);
}

export const chatRouter = Router();

chatRouter.post("/", async (req, res) => {
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) {
    throw new AppError(400, "bad_request", parsed.error.issues.map((i) => `${i.path.join(".") || "body"}: ${i.message}`).join("; "));
  }
  const body = parsed.data;
  // Long chats: older turns become a rolling summary, only recent turns are sent as messages.
  const compacted = await compactHistory(body.messages, body.conversationId);
  if (compacted) body.messages = compacted.recent;
  if (body.messages.reduce((n, m) => n + m.content.length, 0) + (body.context?.length ?? 0) > 60_000) {
    throw new AppError(413, "payload_too_large", "Conversation is too long (limit 60k characters).");
  }
  const requested = body.model && body.model !== "auto" ? body.model : undefined;
  if (requested && !MODELS.some((m) => m.id === requested)) throw new AppError(400, "bad_request", "Unknown model");

  const attachmentIds = [...new Set(body.messages.flatMap((m) => (m.role === "user" ? (m.attachments ?? []).map((a) => a.toLowerCase()) : [])))];
  for (const m of body.messages) m.attachments = m.attachments?.map((a) => a.toLowerCase());
  // Files of the newest user message must exist; older ones may have been deleted since (placeholders).
  const latestIds = [...body.messages].reverse().find((m) => m.role === "user")?.attachments ?? [];
  let fileRows = await loadRows(attachmentIds, latestIds);
  const wantsVision = [...fileRows.values()].some((r) => r.kind === "image" || r.kind === "video");
  let candidates = await pickCandidates(requested);
  let visionSwitched = false;
  if (wantsVision && !(requested && VISION_MODELS.includes(requested))) {
    const avail = new Set(await pickCandidates(undefined));
    candidates = VISION_MODELS.filter((id) => avail.has(id));
    visionSwitched = !!requested;
  }
  const auto = !requested || visionSwitched;
  const requestId = Math.random().toString(36).slice(2, 10);
  setTelemetry({ requestId, conversationId: body.conversationId });
  const started = Date.now();
  const lastUser = [...body.messages].reverse().find((m) => m.role === "user")?.content ?? "";
  const lastUserText = lastUser.trim() === ATTACH_PLACEHOLDER ? "" : lastUser;
  // Local NLP (no network, <1 ms): language, intent labels and entities for this turn.
  const nlp = analyze(
    lastUserText,
    body.messages.filter((m) => m.role === "user").slice(0, -1).reverse().map((m) => m.content),
    { hasImages: latestIds.some((id) => fileRows.get(id)?.kind === "image"), hasAttachments: latestIds.length > 0 },
  );
  log.info("nlp", {
    requestId,
    intent: nlp.intent.top,
    confidence: nlp.intent.confidence,
    labels: nlp.intent.labels.map((l) => l.label).join(","),
    lang: nlp.language.code,
    langConfidence: nlp.language.confidence,
    entities: nlp.entities.length,
    ms: nlp.ms,
  });
  // Long-term memory: extraction runs in the background alongside generation; recall happens below.
  const memTurn = startMemoryTurn({
    userText: lastUserText,
    prevAssistant: [...body.messages].reverse().find((m) => m.role === "assistant")?.content,
    conversationId: body.conversationId,
  });

  const citations: Citation[] = [];
  const ctl = new AbortController();
  const sse = openSse(res);
  res.on("close", () => {
    if (!res.writableFinished) ctl.abort();
  });

  try {
    sse.send("start", { requestId, candidates });
    if (visionSwitched) sse.send("notice", { code: "vision_model", message: "The selected model cannot see images, using a vision model instead." });

    // ---- attachments: wait for processing, then resolve ---------------------
    if ([...fileRows.values()].some((r) => r.status === "processing")) {
      sse.send("status", { phase: "processing_files" });
      fileRows = await waitForFiles(attachmentIds, ctl.signal, undefined, latestIds);
    }
    const prepared = await prepareMessages(body.messages, fileRows, retrievalQuery(body.messages.map((m) => ({ role: m.role, content: m.content }))));
    if (prepared.failed.length > 0) {
      sse.send("notice", { code: "attachment_failed", message: `Could not read: ${prepared.failed.join(", ")}` });
    }
    const docItems = prepared.docs;
    docItems.forEach((d) =>
      citations.push({ id: d.id, kind: "file", title: d.title, url: d.url, snippet: snippet(d.text), site: "document" }),
    );

    // ---- conversation context: built once, shared by every tool -------------
    // Memory recall runs while the standalone question is being resolved.
    const memoryP = memTurn?.recall() ?? Promise.resolve(null);
    const attachmentInfo: AttachmentInfo[] = [...fileRows.values()].map((r) => ({ id: r.id, name: r.name, kind: r.kind }));
    const built = await buildTurnContext({
      messages: body.messages.map((m) => ({ role: m.role, content: m.content, attachments: m.attachments })),
      summary: compacted?.summary,
      lastUserText,
      nlp,
      attachments: attachmentInfo,
    });
    const ctx = { ...built, memory: await memoryP };
    log.info("turn context", {
      requestId,
      rewrite: ctx.rewrittenBy,
      repos: ctx.topics.repos.length,
      entities: ctx.topics.entities.length,
      past: ctx.pastRef.explicit,
      summary: !!ctx.summary,
    });

    // ---- context: knowledge base + web (parallel, non-fatal) -------------
    const kbItems: ContextItem[] = [];
    const webItems: ContextItem[] = [];
    // Live GitHub data as [G#] sources, only when the message is about GitHub.
    const githubItems: ContextItem[] = [];
    let githubHint: string | null = null;

    // A question about attached files is answered from the files, not the web
    // or the knowledge base (which only add unrelated sources).
    const lastUserMsg = [...body.messages].reverse().find((m) => m.role === "user");
    const aboutAttachments = (lastUserMsg?.attachments?.length ?? 0) > 0;

    const kbTask = async () => {
      if (!body.knowledge || aboutAttachments) return;
      sse.send("status", { phase: "retrieving" });
      let hits: KbHit[] = [];
      try {
        // With rewriting on, the raw question is sent and resolved against the history by a small model.
        const raw = lastUser.trim().slice(0, 500);
        // The standalone question and its variants were resolved once for the whole turn.
        const rewrites = [ctx.standalone, ...ctx.queries].filter((q, i, a) => q && q !== raw && a.indexOf(q) === i).slice(0, 4);
        hits = await retrieve(config.ragRewrite && raw ? raw : retrievalQuery(body.messages), {
          k: config.ragTopK,
          sourceIds: body.sourceIds,
          history: body.messages.slice(-7).map((m) => ({ role: m.role, content: m.content })),
          ...(config.ragRewrite && raw ? { rewrites } : {}),
        });
      } catch (e) {
        const down = embeddingsHealthy() === "down";
        sse.send("notice", {
          code: down ? "embeddings_down" : "kb_unavailable",
          message: down ? "Embeddings are unavailable, answering without the knowledge base." : "Knowledge base is unavailable, answering without it.",
        });
        log.warn("kb retrieval failed", { requestId, message: (e as Error).message?.slice(0, 120) });
        return;
      }
      hits.forEach((h, i) => {
        const id = `K${i + 1}`;
        kbItems.push({ id, title: h.title || h.url, url: h.url, heading: h.headingPath, text: h.content });
        citations.push({
          id,
          kind: "kb",
          title: h.title || h.url,
          url: h.url,
          snippet: snippet(h.content),
          site: h.site || hostOf(h.url),
          sourceType: h.sourceType,
          ...(h.docId ? { docId: h.docId, sectionId: h.sectionId } : {}),
          ...(h.fileId ? { fileId: h.fileId } : {}),
        });
      });
    };

    // WEB on means "search when needed": explicit asks and time-sensitive
    // questions search directly, anything else is decided by a small model.
    // WEB off never searches (a pasted link is still read).
    const lastAssistant = [...body.messages].reverse().find((m) => m.role === "assistant")?.content ?? "";
    const decision =
      body.webSearch && !aboutAttachments
        ? await decideSearch(ctx.rewrittenBy === "model" ? ctx.standalone : lastUser, lastAssistant, nlp.intent)
        : { search: false, query: "", reason: "none" as const };
    const searching = decision.search;
    if (searching) log.info("web search", { requestId, reason: decision.reason });

    // Round Table with web research: each seat also searches its own angle.
    const tableWanted = body.roundTable && !(isTrivialTurn(lastUserText) && !(lastUserMsg?.attachments?.length ?? 0));
    const seatResearch: SeatResearchInput[] = [];
    const sharedWebIds = new Set<string>();
    const researchTask = async (): Promise<SeatResearch[]> => {
      if (!tableWanted || !searching || !lastUserText) return [];
      const at = Date.now();
      const eta = () => Math.round(Math.max(initialEtaMs(true) - (Date.now() - at), 0));
      sse.send("table", { phase: "researching", elapsedMs: Date.now() - started, etaMs: eta() });
      try {
        const queries = await planQueries(lastUserText, searchQuery(decision.query || lastUser), ctl.signal);
        if (queries.length === 0) return [];
        sse.send("table", {
          phase: "researching",
          research: queries.map((q, i) => ({ seat: "ABC"[i], queries: [q] })),
          elapsedMs: Date.now() - started,
          etaMs: eta(),
        });
        return await runSeatResearch(queries, ctl.signal);
      } catch (e) {
        log.warn("table research failed", { requestId, message: (e as Error).message?.slice(0, 120) });
        return [];
      }
    };

    const webTask = async () => {
      const urlMatch = lastUser.match(URL_RE);
      if (!searching && !urlMatch) return;
      if (searching) sse.send("status", { phase: "searching" });
      const [search, fetched, research] = await Promise.allSettled([
        searching
          ? researchWeb({
              question: searchQuery(lastUser),
              focused: decision.reason === "model" ? searchQuery(decision.query) : undefined,
              context: {
                previousUser: previousUser(body.messages),
                previousAssistant: lastAssistant,
                language: nlp.language,
                standalone: ctx.rewrittenBy === "model" ? ctx.standalone : undefined,
                topics: topicTerms(ctx, "web"),
              },
              signal: ctl.signal,
            })
          : Promise.resolve([]),
        urlMatch ? webFetch(urlMatch[0].replace(/[.,;:]+$/, ""), ctl.signal) : Promise.resolve(null),
        researchTask(),
      ]);
      const results = search.status === "fulfilled" ? [...search.value] : [];
      if (fetched.status === "fulfilled" && fetched.value) results.unshift(fetched.value);
      if (searching && search.status === "rejected") {
        sse.send("notice", { code: "web_search_failed", message: "Web search failed, answering without it." });
        log.warn("web search failed", { requestId });
      }
      results.forEach((r, i) => {
        const id = `W${i + 1}`;
        webItems.push({ id, title: r.title, url: r.url, text: r.content, full: r.full });
        citations.push({ id, kind: "web", title: r.title, url: r.url, snippet: snippet(r.content), site: hostOf(r.url) });
        sharedWebIds.add(id);
      });
      // Seat results join the one citation list (deduped by URL, ids continue);
      // a seat sees the shared sources plus every result it found itself.
      const byUrl = new Map(webItems.map((w) => [urlKey(w.url), w.id]));
      for (const r of research.status === "fulfilled" ? research.value : []) {
        const own: SeatResearchInput = { seat: r.seat, queries: r.queries, items: [], tags: [] };
        for (const w of r.results) {
          let id = byUrl.get(urlKey(w.url));
          if (!id) {
            id = `W${webItems.length + 1}`;
            byUrl.set(urlKey(w.url), id);
            webItems.push({ id, title: w.title, url: w.url, text: w.content, full: w.full });
            citations.push({ id, kind: "web", title: w.title, url: w.url, snippet: snippet(w.content), site: hostOf(w.url) });
          }
          if (own.tags.includes(id)) continue;
          own.tags.push(id);
          const item = webItems.find((x) => x.id === id);
          if (item && !sharedWebIds.has(id)) own.items.push({ id, title: item.title, url: item.url, text: item.text });
        }
        seatResearch.push(own);
      }
      if (seatResearch.length) log.info("table research", { requestId, seats: seatResearch.map((r) => `${r.seat}:${r.tags.length}`).join(" ") });
    };

    const githubTask = async () => {
      if (aboutAttachments || !lastUserText) return;
      try {
        const g = await githubGround(lastUserText, ctl.signal, { repos: ctx.topics.repos });
        if (!g) return;
        githubItems.push(...g.items);
        githubHint = g.hint;
        for (const i of g.items) citations.push({ id: i.id, kind: "web", title: i.title, url: i.url, snippet: snippet(i.text), site: "github.com" });
      } catch (e) {
        log.warn("github grounding failed", { requestId, message: (e as Error).message?.slice(0, 120) });
      }
    };

    // Past conversations: always searched when the user refers to one, otherwise only a clearly related chat is surfaced.
    let pastBlock: string | null = null;
    const recallTask = async () => {
      const explicit = ctx.pastRef.explicit;
      const chitchat = nlp.intent.top === "chitchat" && nlp.intent.confidence >= 0.6;
      if (!explicit && (aboutAttachments || chitchat || ctx.standalone.length < 12)) return;
      const exclude = body.conversationId && isUuid(body.conversationId) ? body.conversationId : undefined;
      const r = await recallPastChats({ query: ctx.standalone, topic: ctx.pastRef.topic, explicit, excludeConversationId: exclude });
      pastBlock = r.block;
      for (const c of r.citations as PastCitation[]) {
        citations.push({ id: c.id, kind: "conversation", title: c.title, url: c.url, snippet: c.snippet, site: "chat", conversationId: c.conversationId });
      }
    };

    await Promise.all([kbTask(), webTask(), githubTask(), recallTask()]);
    if (ctl.signal.aborted) return;
    const rank = { kb: 0, web: 1, file: 2, conversation: 3 } as const;
    citations.sort((a, b) => rank[a.kind] - rank[b.kind]);
    if (citations.length > 0) sse.send("sources", { citations });

    // Explanatory images are found alongside generation and never delay it.
    // They are sent at the end, and skipped when the reply placed its own
    // inline images, so the same picture never shows twice.
    // Only visual questions get the strip; otherwise the model places relevant
    // images inline itself, and generic searches return unrelated photos.
    const visual = /\b(images?|pictures?|photos?|illustrat\w*|drawings?|look(s)? like|what does .{1,40} look)\b/i.test(lastUser);
    const imagesTask: Promise<ImageResult[]> = searching && visual
      ? findImages(imageQuery(lastUser, ctx), webItems.map((w) => ({ url: w.url, title: w.title }))).catch(() => [])
      : Promise.resolve([]);

    // ---- generation -------------------------------------------------------
    // Optional prompt sections (HTML, GitHub, widget examples) only when the turn needs them.
    const needs = promptNeeds(`${previousUser(body.messages)}\n${lastUser}`, githubItems.length > 0, nlp.intent);
    const prompt: Message[] = [{ role: "system", content: buildSystemPrompt(body.mode as never, body.profile, undefined, needs) }];
    if (ctx.memory) prompt.push({ role: "system", content: ctx.memory });
    if (compacted) prompt.push({ role: "system", content: summaryMessage(compacted.summary) });
    if (pastBlock) prompt.push({ role: "system", content: pastBlock });
    if (body.context?.trim()) {
      prompt.push({
        role: "system",
        content: `Background the user merged in from earlier conversations (a summary, not the full chats; use it as shared context):\n\n${body.context.trim()}`,
      });
    }
    const context = buildContextMessage(kbItems, webItems, docItems, githubItems);
    if (context) prompt.push({ role: "system", content: context });
    const hint = lastUserText ? intentHint(lastUserText, nlp.intent) : null;
    if (hint) prompt.push({ role: "system", content: hint });
    // Secrets in the user's message are not redacted (answers would break); the model is told not to echo them.
    const secretNote = lastUserText ? safetyNote(lastUserText) : null;
    if (secretNote) prompt.push({ role: "system", content: secretNote });
    // Reply language (unless the profile sets one) and a length/shape nudge from the local classifier.
    const langLine = lastUserText ? languageInstruction(nlp.language, body.profile?.language) : null;
    if (langLine) prompt.push({ role: "system", content: langLine });
    const shape = lastUserText ? shapeHint(nlp.intent) : null;
    if (shape) prompt.push({ role: "system", content: shape });
    if (githubHint) prompt.push({ role: "system", content: githubHint });
    prompt.push(...prepared.messages);

    const promptChars = prompt.reduce((n, m) => n + m.content.length + (m.images?.length ?? 0) * 1500, 0);

    // ---- round table (optional): drafts + cross-review, then the chair ----
    let table: TableRun | null = null;
    if (body.roundTable) {
      if (!tableWanted) {
        sse.send("notice", { code: "round_table_skipped", message: "Short message, answering without the round table." });
      } else {
        sse.send("status", { phase: "round_table" });
        // With seat research, seats share only the main sources; each adds its own.
        const tableContext = seatResearch.length ? buildContextMessage(kbItems, webItems.filter((w) => sharedWebIds.has(w.id)), docItems, githubItems) : context;
        const shared = prompt
          .slice(1, prompt.length - prepared.messages.length)
          .filter((m) => m.content !== hint)
          .map((m) => (m.content === context ? tableContext : m.content))
          .filter((c): c is string => !!c);
        table = await runRoundTable({
          history: prepared.messages,
          context: shared.join("\n\n") || null,
          research: seatResearch,
          startedAt: started,
          question: lastUserText,
          preamble: buildSystemPrompt(body.mode as never, body.profile).split("\n\n").filter((p) => /^(Today's date|Language:)/.test(p)).join("\n\n"),
          promptChars,
          vision: wantsVision ? candidates : null,
          signal: ctl.signal,
          emit: (e) => sse.send("table", e),
        });
        if (!table) sse.send("notice", { code: "round_table_degraded", message: "Not enough models answered, using a single model instead." });
      }
    }
    const unresolved = new UnresolvedFilter();
    let chairCalls = 0;

    sse.send("status", { phase: "generating" });
    let text = "";
    const tags = new TagStream();
    // The chair only keeps tags that exist in the citation list.
    const validTags = new Set(citations.map((c) => c.id));
    const keepValid = (s: string) => (table ? s.replace(/\[([KWDC]\d+)\]/g, (m, id: string) => (validTags.has(id) ? m : "")) : s);
    const chairAt = Date.now();
    const result = await withTelemetry({ purpose: table ? "table-chair" : "chat" }, () => runChat(
      table ? table.candidates : auto ? preferForPrompt(candidates, promptChars) : candidates,
      table ? [...prompt, table.chairMessage] : prompt,
      ctl.signal,
      {
        onQueued: () => sse.send("status", { phase: "queued" }),
        onModel: (model, attempt) => {
          chairCalls = attempt;
          sse.send("model", { model, attempt });
        },
        onDelta: (chunk) => {
          const raw = table ? unresolved.push(chunk) : chunk;
          if (!raw) return;
          const t = keepValid(tags.push(raw));
          if (!t) return;
          text += t;
          sse.send("delta", { text: t });
        },
        onReset: () => {
          tags.reset();
          unresolved.reset();
          text = "";
          sse.send("reset", { reason: "fallback" });
        },
        onFallback: (from, to) => sse.send("notice", { code: "fallback", message: `${from} failed, trying ${to}.` }),
      },
      auto || !!table,
      { maxTokens: maxTokensForMode(body.mode) },
    ));

    const held = table ? unresolved.flush() : "";
    if (held) {
      const t = keepValid(tags.push(held));
      if (t) {
        text += t;
        sse.send("delta", { text: t });
      }
    }
    const tail = keepValid(tags.flush());
    if (tail) {
      text += tail;
      sse.send("delta", { text: tail });
    }

    // Follow-up prompt chips: a fast model, bounded so it never holds `done` for long.
    const followupsTask = text.trim().length >= 40 && lastUserText
      ? generateFollowups(lastUserText, text, 3_000, ctl.signal, nlp.language, renderContext(ctx, "followups") || undefined).catch(() => [] as string[])
      : Promise.resolve([] as string[]);
    // Give late images a moment so they arrive before `done`.
    const strip = await Promise.race([imagesTask, new Promise<ImageResult[]>((r) => setTimeout(() => r([]), 1_500))]);
    if (strip.length > 0 && !/\{\{image:/.test(text)) sse.send("images", { images: strip });
    const followups = await followupsTask;
    if (followups.length > 0) sse.send("suggestions", { items: followups });
    const sent = new Set(citations.map((c) => c.id));
    const used = [...new Set([...text.matchAll(/\[([KWDGC]\d+)\]/g)].map((m) => m[1]))].filter((id) => sent.has(id));
    try {
      const evidence = computeEvidence(
        text,
        [...kbItems, ...webItems, ...docItems, ...githubItems].filter((i) => sent.has(i.id)).map((i) => ({ id: i.id, text: i.full ?? i.text })),
      );
      if (evidence.length > 0) sse.send("evidence", { items: evidence });
    } catch (e) {
      log.warn("evidence failed", { requestId, error: String(e) });
    }
    sse.send("usage", { promptTokens: result.promptTokens, completionTokens: result.completionTokens });
    const latencyMs = Date.now() - started;
    if (table) {
      recordLatency("chair", result.model, Date.now() - chairAt);
      table.finish(result.model, chairCalls, unresolved.items(), text);
    }
    // Extraction started with the turn, so it is normally finished; never wait long for it.
    const memChanges = memTurn ? await Promise.race([memTurn.extraction, new Promise<[]>((r) => setTimeout(() => r([]), 400))]) : [];
    if (memChanges.length > 0) sse.send("memory", { changes: memChanges });
    sse.send("done", { model: result.model, used, finishReason: result.finishReason, latencyMs, ...(table ? { table: true } : {}) });
    log.info("chat", { requestId, model: result.model, latencyMs, status: 200 });
  } catch (e) {
    if (ctl.signal.aborted) return;
    let payload;
    if (e instanceof ChatFailure) payload = errorBody(e.code, e.message, e.retryable);
    else if (e instanceof AppError) payload = errorBody(e.code, e.message, e.retryable);
    else payload = errorBody("internal", "Something went wrong while generating the answer.", true);
    sse.send("error", payload);
    log.warn("chat failed", { requestId, latencyMs: Date.now() - started, code: payload.error.code });
  } finally {
    sse.end();
  }
});
