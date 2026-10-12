import { Router } from "express";
import { z } from "zod";
import { config } from "../config.js";
import { MODELS } from "../models.js";
import { AppError, errorBody } from "../util/errors.js";
import { log } from "../util/logger.js";
import { openSse } from "../util/sse.js";
import { pickCandidates, preferForPrompt, preferSmall, runChat, ChatFailure, maxTokensFor } from "../llm/router.js";
import { researchWeb, webFetch } from "../web/search.js";
import { computeEvidence } from "../web/evidence.js";
import { TagStream } from "../web/tagStream.js";
import { githubGround } from "../github/grounding.js";
import { appsGround } from "../connections/oauth/tools.js";
import { decideSearchLocal, type SearchDecision } from "../web/searchDecision.js";
import { fitBudget } from "../web/budget.js";
import { newTurnCounters, recordTurnSummary, setTelemetry, withTelemetry } from "../db/usage.js";
import { findImages, type ImageResult } from "../web/images.js";
import { intentHint } from "../prompts/intent.js";
import { safetyNote } from "../nlp/pii.js";
import { buildContextMessage, buildSystemPrompt, promptNeeds, MODES, TONES, LENGTHS, type ContextItem } from "../prompts/system.js";
import { retrieve, type KbHit } from "../retrieval/search.js";
import { embeddingsHealthy, embedQueries } from "../embeddings/index.js";
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
import { kbRelevance, pickSuggestion, referencesKb, resolveWebMode, toolsNote, type SuggestToggle } from "../toggles/suggest.js";
import { peekKb } from "../retrieval/peek.js";
import { generateFollowups, worthFollowups } from "../assist/suggest.js";
import { screenContextMessage, screenSchema } from "../context/screen.js";
import { decideWeb, embedTextsForTurn, preflightNeeds, runPreflight, type Preflight } from "../context/preflight.js";
import { buildTurnContext, imageQuery, renderContext, topicTerms, type AttachmentInfo } from "../context/turnContext.js";
import { recallPastChats, recallQueryText, type PastCitation } from "../recall/search.js";
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
  // Legacy on/off; `webMode` supersedes it: auto (the harness decides), on (always search), off (never).
  webSearch: z.boolean().optional(),
  webMode: z.enum(["auto", "on", "off"]).optional(),
  // Smart suggestions: offer the knowledge base / a Doc instead of assuming. `suppressSuggest` lists the kinds already offered in this conversation.
  smartSuggestions: z.boolean().default(true),
  suppressSuggest: z.array(z.enum(["kb", "doc"])).max(4).default([]),
  knowledge: z.boolean().default(false),
  sourceIds: z.array(z.string()).max(50).optional(),
  mode: z.enum(MODES as [string, ...string[]]).default("default"),
  profile: profileSchema.optional(),
  // Round Table: several models draft and cross-review, a chair writes the answer.
  roundTable: z.boolean().default(false),
  // Briefing from a merged chat, sent as background (never as a user/assistant turn).
  context: z.string().max(8000).optional(),
  // Assistant overlay: the screen the user chose to share (text, app, URL); the screenshot is an attachment.
  screen: screenSchema.optional(),
  // Connected-app items the user attached ("Ask Sparky about this page"): read live, cited as documents.
  apps: z
    .array(z.object({ provider: z.enum(["google_drive", "notion"]), id: z.string().min(10).max(200), title: z.string().max(200).optional() }))
    .max(3)
    .optional(),
});

/** Messages of history kept for a confident small-talk turn. */
const SMALL_TALK_TURNS = 6;

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
  if (body.messages.reduce((n, m) => n + m.content.length, 0) + (body.context?.length ?? 0) + (body.screen?.text.length ?? 0) > 60_000) {
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
  const counters = newTurnCounters();
  setTelemetry({ requestId, conversationId: body.conversationId, turn: counters });
  const started = Date.now();
  let summarized = false;
  /** One "turn cost" line + usage row per turn: calls made, tokens and time to first token. */
  const summarize = (firstTokenAt: number | null) => {
    if (summarized) return;
    summarized = true;
    recordTurnSummary({ ...counters, msToFirstToken: firstTokenAt ? firstTokenAt - started : null, totalMs: Date.now() - started }, (m, meta) => log.info(m, { requestId, ...meta }));
  };
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
    const docItems: ContextItem[] = prepared.docs;
    docItems.forEach((d) =>
      citations.push({ id: d.id, kind: "file", title: d.title, url: d.url, snippet: snippet(d.text), site: "document" }),
    );

    // ---- conversation context: built once, shared by every tool -------------
    const lastUserMsg = [...body.messages].reverse().find((m) => m.role === "user");
    const aboutAttachments = (lastUserMsg?.attachments?.length ?? 0) > 0;
    const lastAssistant = [...body.messages].reverse().find((m) => m.role === "assistant")?.content ?? "";
    const smallTalk = nlp.intent.top === "chitchat" && !nlp.intent.uncertain && nlp.intent.confidence >= 0.6;

    // ---- preflight: ONE small-model call replaces the standalone rewrite, search decision, web query plan and RAG variants.
    // The local NLP and rules decide alone when they are confident; the model is asked only for what they cannot settle.
    const webMode = resolveWebMode(body);
    const wantWeb = webMode !== "off" && !aboutAttachments;
    // On: always search (except small talk); auto: the local rules / preflight decide; off: never.
    const webLocal: SearchDecision | null = !wantWeb
      ? { search: false, query: "", reason: "none" }
      : webMode === "on" && lastUserText && !smallTalk
        ? { search: true, query: lastUserText.slice(0, 200), reason: "explicit" }
        : decideSearchLocal(lastUser, nlp.intent);
    const lastUserIdx = body.messages.map((m) => m.role).lastIndexOf("user");
    const history = body.messages.slice(0, Math.max(lastUserIdx, 0)).map((m) => ({ role: m.role, content: m.content }));
    let pre: Preflight | null = null;
    if (preflightNeeds({ text: lastUserText, history, wantWeb, webLocal, smallTalk }).any) {
      pre = await runPreflight({ text: lastUserText, history, wantWeb, webLocal });
    }
    const attachmentInfo: AttachmentInfo[] = [...fileRows.values()].map((r) => ({ id: r.id, name: r.name, kind: r.kind }));
    const built = await buildTurnContext({
      messages: body.messages.map((m) => ({ role: m.role, content: m.content, attachments: m.attachments })),
      summary: compacted?.summary,
      lastUserText,
      nlp,
      attachments: attachmentInfo,
    }, pre ? { rewrite: async () => ({ standalone: pre!.standalone, queries: pre!.via === "model" ? pre!.queries : [], via: pre!.via }) } : undefined);
    const ctx = { ...built, memory: null as string | null };
    // One embedding call per turn: the texts the knowledge base, past-chat recall and memory recall all need are requested
    // together now (misses are coalesced into one request; each consumer then reuses the cached vector).
    const recallText = ctx.pastRef.explicit || (!smallTalk && !aboutAttachments && ctx.standalone.length >= 12) ? recallQueryText({ query: ctx.standalone.slice(0, 500), topic: ctx.pastRef.topic, explicit: ctx.pastRef.explicit }) : undefined;
    const embedNow = embedTextsForTurn({ hasMemory: !!memTurn, knowledge: body.knowledge, ragRewrite: config.ragRewrite, smallTalk, aboutAttachments, lastUser, standalone: ctx.standalone, queries: ctx.queries, recallText });
    if (embedNow.length) void embedQueries(embedNow).catch(() => {});
    // Memory recall runs alongside the other tools; small talk needs no semantic match, so it skips the embedding.
    const memoryP = memTurn?.recall(ctx.standalone.slice(0, 500), { embed: !smallTalk }) ?? Promise.resolve(null);
    log.info("turn context", {
      requestId,
      rewrite: ctx.rewrittenBy,
      repos: ctx.topics.repos.length,
      entities: ctx.topics.entities.length,
      past: ctx.pastRef.explicit,
      summary: !!ctx.summary,
      preflight: pre ? pre.via : "skipped",
    });

    // ---- context: knowledge base + web (parallel, non-fatal) -------------
    const kbItems: ContextItem[] = [];
    const webItems: ContextItem[] = [];
    // Live GitHub data as [G#] sources, only when the message is about GitHub.
    const githubItems: ContextItem[] = [];
    let githubHint: string | null = null;

    // A question about attached files is answered from the files, not the web
    // or the knowledge base (which only add unrelated sources).

    const kbTask = async () => {
      if (!body.knowledge || aboutAttachments) return;
      // Greetings and thanks never need the knowledge base.
      if (smallTalk || (pre?.via === "model" && pre.needsKb === false)) return;
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
    // Local rules first (also on the resolved standalone question), then the preflight's verdict; a failed preflight means no search.
    const decision = decideWeb({ wantWeb, webLocal, standalone: ctx.standalone, rewrittenByModel: ctx.rewrittenBy === "model", pre, decideLocal: (q) => decideSearchLocal(q, nlp.intent) });
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
        const queries = await planQueries(lastUserText, searchQuery(decision.query || lastUser), ctl.signal, pre?.via === "model" ? pre.queries : []);
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
              preplanned: pre?.via === "model" && pre.queries.length ? { queries: pre.queries, fresh: pre.freshness } : undefined,
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
      // About 2.5k tokens of web evidence in total: cut the sources to the passages that matter for the question.
      fitBudget(webItems, ctx.standalone).forEach((w, i) => (webItems[i].text = w.text));
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

    // Connected apps (Drive, Notion): read-only tools, run when the message is about them or an item is attached.
    let appsHint: string | null = null;
    const appsTask = async () => {
      if (!lastUserText && !body.apps?.length) return;
      try {
        const g = await appsGround(req.user?.id ?? null, aboutAttachments ? "" : lastUserText, body.apps ?? [], { prefix: "D", firstId: docItems.length + 1 });
        if (!g) return;
        appsHint = g.hint;
        for (const i of g.items) {
          docItems.push(i);
          citations.push({ id: i.id, kind: "web", title: i.title, url: i.url, snippet: snippet(i.text), site: hostOf(i.url) });
        }
      } catch (e) {
        log.warn("apps grounding failed", { requestId, message: (e as Error).message?.slice(0, 120) });
      }
    };

    // Past conversations: always searched when the user refers to one, otherwise only a clearly related chat is surfaced.
    let pastBlock: string | null = null;
    const recallTask = async () => {
      const explicit = ctx.pastRef.explicit;
      const chitchat = nlp.intent.top === "chitchat" && nlp.intent.confidence >= 0.6;
      const modelSaysPast = pre?.via === "model" && pre.pastRef === true;
      if (!explicit && !modelSaysPast && (aboutAttachments || chitchat || ctx.standalone.length < 12)) return;
      const exclude = body.conversationId && isUuid(body.conversationId) ? body.conversationId : undefined;
      const r = await recallPastChats({ query: ctx.standalone.slice(0, 500), topic: ctx.pastRef.topic, explicit, excludeConversationId: exclude });
      pastBlock = r.block;
      for (const c of r.citations as PastCitation[]) {
        citations.push({ id: c.id, kind: "conversation", title: c.title, url: c.url, snippet: c.snippet, site: "chat", conversationId: c.conversationId });
      }
    };

    // Smart suggestions: never silently switches a tool on; the app asks the user (see toggles/suggest.ts).
    const suggestTask = async (): Promise<SuggestToggle | null> => {
      if (!body.smartSuggestions || !lastUserText || smallTalk) return null;
      try {
        const explicitKb = referencesKb(lastUserText);
        const askKb = !body.knowledge && !aboutAttachments && (!body.suppressSuggest.includes("kb") || explicitKb);
        const peek = askKb
          ? await Promise.race([peekKb(ctx.standalone), new Promise<null>((r) => setTimeout(() => r(null), 1_500))])
          : null;
        return pickSuggestion({
          smart: true,
          kbOn: body.knowledge,
          docOn: false,
          suppressed: body.suppressSuggest,
          text: lastUserText,
          intent: nlp.intent,
          kb: peek ? kbRelevance(peek.hits) : null,
          kbHasContent: !!peek?.hasContent,
          hasAttachments: aboutAttachments,
        });
      } catch (e) {
        log.warn("suggest toggle failed", { requestId, message: (e as Error).message?.slice(0, 120) });
        return null;
      }
    };

    const [, , , , suggestion] = await Promise.all([kbTask(), webTask(), githubTask(), recallTask(), suggestTask(), appsTask()]);
    if (suggestion && !ctl.signal.aborted) {
      sse.send("suggest_toggle", suggestion);
      log.info("suggest_toggle", { requestId, conversationId: body.conversationId, event: "shown", kind: suggestion.kind, reason: suggestion.reason });
    }
    // Which tools actually ran this turn (the app shows "Searched the web" after an automatic search).
    sse.send("tools", { web: searching && webItems.length > 0, webMode, kb: body.knowledge && kbItems.length > 0 });
    ctx.memory = await memoryP;
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
    const screenNote = screenContextMessage(body.screen);
    if (screenNote) prompt.push({ role: "system", content: screenNote });
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
    if (appsHint) prompt.push({ role: "system", content: appsHint });
    prompt.push({
      role: "system",
      content: toolsNote({
        web: searching && webItems.length > 0 ? "searched" : webMode === "off" ? "off" : "auto-none",
        kb: body.knowledge ? "on" : "off",
        kbSuggested: suggestion?.kind === "kb",
        docSuggested: suggestion?.kind === "doc",
      }),
    });
    // Small talk does not need the whole history: the last few turns are enough (fewer prompt tokens against Groq's per-minute window).
    const noFiles = !prepared.messages.some((m) => (m.images?.length ?? 0) > 0) && attachmentIds.length === 0;
    let turnsSent = prepared.messages;
    if (smallTalk && noFiles && turnsSent.length > SMALL_TALK_TURNS) {
      turnsSent = turnsSent.slice(-SMALL_TALK_TURNS);
      while (turnsSent.length > 1 && turnsSent[0].role !== "user") turnsSent = turnsSent.slice(1);
    }
    prompt.push(...turnsSent);

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
          .slice(1, prompt.length - turnsSent.length)
          .filter((m) => m.content !== hint)
          .map((m) => (m.content === context ? tableContext : m.content))
          .filter((c): c is string => !!c);
        table = await runRoundTable({
          history: turnsSent,
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
    let firstTokenAt: number | null = null;
    const trivialAuto = auto && smallTalk && !table && !wantsVision;
    const result = await withTelemetry({ purpose: table ? "table-chair" : "chat" }, () => runChat(
      table ? table.candidates : auto ? preferForPrompt(trivialAuto ? preferSmall(candidates) : candidates, promptChars) : candidates,
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
          firstTokenAt ??= Date.now();
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
      { maxTokens: maxTokensFor({ mode: body.mode, intent: nlp.intent, length: body.profile?.length }) },
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
    const followupsTask = worthFollowups(text, nlp.intent) && lastUserText
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
    summarize(firstTokenAt);
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
    summarize(null);
    sse.end();
  }
});

// The app reports what the user did with a `suggest_toggle` prompt (the "shown" side is logged when it is sent).
const suggestionOutcome = z.object({
  kind: z.enum(["kb", "doc"]),
  outcome: z.enum(["accepted", "dismissed"]),
  conversationId: z.string().max(64).optional(),
});
chatRouter.post("/suggestion", (req, res) => {
  const p = suggestionOutcome.safeParse(req.body);
  if (!p.success) throw new AppError(400, "bad_request", "invalid suggestion outcome");
  log.info("suggest_toggle", { event: p.data.outcome, kind: p.data.kind, conversationId: p.data.conversationId, userId: req.user?.id });
  res.status(204).end();
});
