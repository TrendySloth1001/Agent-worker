# Efficiency: calls per chat turn

Every provider is a free tier with tight limits (Groq 8k tokens/min per model and daily request caps, OpenRouter 50 requests/day, Ollama web search rate limited, NVIDIA generous), so every extra call costs quota and latency. This file lists every upstream call a turn can make, what was changed to cut them, and how to measure it.

Measure with `backend/scripts/turn-audit.ts` (see the end) and, in production, with the `turn cost` log line and the `turn-summary` rows in `usage_events`.

## 1. Audit: one chat turn (`routes/chat.ts`)

"Blocks first token" means the call sits on the critical path before the first answer token. Tokens are approximate (prompt + completion). "Before" is the code as of commit `54c8a44`; "now" is after this work. `purpose` is the `usage_events.purpose` label.

| # | Call | Where | Model | purpose | ~Tokens | Blocks first token | Before | Now |
|---|------|-------|-------|---------|---------|--------------------|--------|-----|
| 1 | Local NLP (language, intent, entities) | `nlp/*` | none (local, <5 ms) | n/a | 0 | yes, negligible | every turn | unchanged |
| 2 | History compaction summary | `memory/compact.ts` | gpt-oss-20b / 120b (Groq), ollama | `summary` | 2.5k in, 0.4k out | yes (up to 20 s) | every turn once the chat is over 6k tokens (the cut moves each turn) | about every 3rd turn: a cached summary up to 6 messages behind is reused |
| 3 | Standalone rewrite | `retrieval/rewrite.ts` via `context/turnContext.ts` | gpt-oss-20b | `kb-rewrite` | 0.4k | yes (<= 2 s) | follow-ups and short messages | merged into the preflight (row 6) |
| 4 | Search decision | `web/searchDecision.ts` | gpt-oss-20b | `search-decision` | 0.3k | yes (<= 4 s) | whenever the local rules were unsure and web is on | merged into the preflight |
| 5 | Web query plan | `web/plan.ts` | gpt-oss-20b | `search-plan` | 0.45k | yes (<= 2.5 s) | follow-ups and messages over 160 chars with a local decision | merged into the preflight |
| 6 | **Preflight** (new) | `context/preflight.ts` | gpt-oss-20b, then ollama gpt-oss:20b | `preflight` | 0.5k | yes (<= 2.5 s) | n/a | only when the local rules cannot settle rewrite / web / query; never for small talk |
| 7 | Memory recall embedding | `memory/turn.ts` | embedding model | `embedding` | 1 text | yes | one request | shared (row 9); none for small talk |
| 8 | Memory recall DB reads | `memory/store.ts` | Postgres | n/a | 0 | yes (parallel to tools) | pinned + similar | unchanged; small talk reads pinned + latest 3 only |
| 9 | Query embeddings (KB, past-chat recall, memory recall) | `embeddings/index.ts` | NVIDIA / OpenRouter embedding | `embedding` | 1-4 texts | yes | up to 3 requests per turn | **1 request**: texts are requested together, concurrent misses coalesce, in-flight texts are shared |
| 10 | RAG retrieve (vector + keyword legs, MMR) | `retrieval/search.ts` | Postgres | n/a | 0 | yes | even for "hi" | skipped for small talk and when the preflight says the KB is not needed |
| 11 | RAG rerank | `retrieval/rerank.ts` | gpt-oss-20b | `kb-rerank` | 1.5k | yes (<= 2.5 s) | off by default (`RAG_RERANK`) | unchanged |
| 12 | Past-chat recall | `recall/search.ts` | embedding + Postgres | `embedding` | 0 extra | yes | its own embedding | shares row 9 |
| 13 | GitHub grounding | `github/grounding.ts` | GitHub API | `github` | 0 | yes, only on GitHub questions | unchanged | unchanged |
| 14 | Web search providers | `web/pipeline.ts`, `web/providers.ts` | Ollama web_search (primary), Wikipedia, StackExchange, GitHub, arXiv, HN, Reddit | `web-search` | 0 | yes | 1-2 queries x Ollama + every matching secondary | 1 query (2 for comparisons); free sources first, Ollama only if they fall short; Postgres-backed shared cache |
| 15 | Page fetches | `web/pipeline.ts` | HTTP | `web-fetch` | 0 | yes (<= 6 s each) | top 4 | top 3, only hits whose snippet does not already answer, whole phase capped at 2.5 s |
| 16 | Image strip | `web/images.ts` | HTTP | n/a | 0 | no (1.5 s grace at the end) | visual questions only | unchanged |
| 17 | Main generation | `llm/router.ts` | Auto order or the chosen model | `chat` / `table-chair` | 1.5-8k in, up to 8k out | n/a (it is the answer) | `max_tokens` 8192 | 1536 for small talk, 4096 for a concise profile; small models first for small talk |
| 18 | Follow-up chips | `assist/suggest.ts` | gpt-oss-20b / 120b / nemotron lightning | `suggestions` | 1k | no (but holds `done` up to 3 s) | any reply over 40 chars | only replies of 400+ chars that are not small talk |
| 19 | Memory extraction | `memory/turn.ts`, `memory/batcher.ts` | gpt-oss-20b / 120b / ollama | `memory` | 0.8k | no (background) | every turn over 12 chars that is not confident small talk | explicit "remember" at once; personal statements batched (1 call per 3 such turns or after 90 s idle); everything else skipped |
| 20 | Memory writes (ADD embedding, dedupe) | `memory/turn.ts` | embedding | `embedding` | 1 text per ADD | no | unchanged | unchanged |
| 21 | Evidence | `web/evidence.ts` | local | n/a | 0 | no | local passage matching | unchanged |
| 22 | Title | `routes/conversations.ts`, `conversations/title.ts` | gpt-oss-20b, ollama | `title` | 0.5k | no (separate request, once per conversation) | once, always a model | once; 3-5 word specific openers are their own title (no call) |
| 23 | Turn summary | `db/usage.ts` | none | `turn-summary` | 0 | no | n/a | one `usage_events` row + log line per turn |

### Other surfaces

| Surface | Calls | Notes |
|---------|-------|-------|
| Round table (`table/*`) | seat query planner (1, `table-research`), 3 seat searches (each 1 query + providers + 1 page), 3 drafts (`table-draft`), 1 judge (`table-judge`), 3 reviews (`table-review`), chair (`table-chair`) | The planner call is skipped when the preflight already wrote two angles; identical seat queries are searched once and fanned out; seat searches read 1 page instead of 2; the provider cache (memory + Postgres) is shared by seats and users. Draft/review/judge/chair counts are unchanged: they are the feature. |
| Docs (`docs/*`) | outline (1, `doc-outline`), per section: web search + KB retrieve + the section generation (`doc-section`), finish (`doc-finish`), rewrite/follow-up on request | Uses `webSearch` (1 query, 1 page now) and the shared provider cache. Section generation is the product and is not touched. |
| Autocomplete (`routes/suggest.ts`) | 1 call per request (`autocomplete`), gpt-oss-20b, 220 max tokens, debounced by the app | Unchanged. |
| Starters | 1 call (`starters`) per request, 400 max tokens | Unchanged. |

### Volume, from the `usage_events` shape

The table is `provider, model, kind(chat|embed|search|fetch|...), purpose, ok, status, latency_ms, ttft_ms, count, prompt_tokens, completion_tokens, attempt, user_id, request_id, conversation_id`. Grouping by `request_id` gives calls per turn. Before this work a single web-enabled turn typically wrote: 1 `chat` + up to 4 auxiliary `chat` rows (`kb-rewrite`, `search-decision`, `search-plan`, `memory`, `suggestions`) + up to 3 `embed` rows + 2-6 `search` rows + up to 4 `fetch` rows. The auxiliary chat rows are small in tokens but each costs one request of the Groq/OpenRouter/Ollama daily request budget, which is the scarce resource (OpenRouter: 50/day). Auxiliary rows are also the ones most often seen failing with 429, because they hit the same per-model windows as the answer.

Group the new rows for the owner dashboard:

```sql
-- calls per turn (aux = everything but the answer), last 24 h
SELECT date_trunc('hour', ts) AS hour, count(*) AS turns, avg(count) AS avg_aux_calls, avg(ttft_ms) AS avg_ttft_ms
FROM usage_events WHERE purpose = 'turn-summary' AND ts > now() - interval '24 hours' GROUP BY 1 ORDER BY 1;
```

## 2. What changed

### Preflight: one call instead of up to four

`context/preflight.ts` asks one small model for `{standalone, needsWeb, freshness, queries[], needsKb, pastRef}`.

- Local rules go first. The NLP intent, `decideSearchLocal` (explicit asks, time-sensitive questions, confident intents) and `needsRewrite` decide alone when sure. The model is called only if something is genuinely uncertain: a referential follow-up, an unsure web decision, or a long message to condense.
- Confident small talk never calls it.
- Time-boxed to 2.5 s with a heuristic fallback (`heuristicPreflight`: heuristic standalone, local web decision, heuristic queries). Worst-case blocking before search drops from about 8.5 s (2 s + 4 s + 2.5 s in series) to 2.5 s.
- Its `standalone` and `queries` feed the turn context, RAG variants, the web plan (`preplanned` skips query planning) and the round-table seed. `needsKb:false` skips the KB for greetings, thanks, pure math or writing. `pastRef` can trigger auto recall.
- The model is told to answer `needsKb:false` only for greetings, thanks and pure math/writing, so a user's KB is not skipped on real questions.

### One embedding request per turn

`embedQueries` coalesces misses into a single request (25 ms window) and shares in-flight texts. The route requests the standalone question, the raw message, the RAG variants and the recall text together, and memory recall and past-chat recall now use the standalone question, so they hit the same vectors. Small talk skips memory embedding (pinned + latest memories only).

### Memory

Extraction is skipped for short, chit-chat and non-personal turns (`extractionPlan`), runs at once only for explicit "remember/forget", and is batched for personal statements (3 turns or 90 s idle, per conversation). Follow-ups were not merged into the same post-turn call: extraction is now rare and background, follow-ups are per substantive turn and hold `done`; merging would put the extraction on the follow-up critical path.

### Web search

- Cache key = provider + freshness class + normalised query (`searchCacheKey`), shared by all users, with a Postgres L2 (`web_cache`, migration `20261013090000_web_cache`) so restarts and round-table seats reuse it. TTLs: breaking 2 min, recent 10 min, evergreen 12 h. Identical in-flight provider calls share one request.
- One query by default; a second only for comparisons / multi-entity questions.
- Free no-quota sources (Wikipedia, StackExchange, GitHub, arXiv, HN) run first when the intent fits (code, academic, repo, definitional); Ollama is asked only if they return fewer than 3 pages or no real body text. Hacker News no longer answers plain code questions. Circuit breakers and Ollama spacing are untouched.
- Page reads: top 3 (was 4), skip hits whose snippet already covers the question (`snippetAnswers`), whole phase capped at 2.5 s.
- Web evidence in the prompt is cut to the passages relevant to the question within ~10k characters (about 2.5k tokens) in total (`fitBudget`), best sources keeping the most.
- Round table: identical seat queries are searched once and fanned out; planner call skipped when the preflight already wrote the angles.

### Generation

- `maxTokensFor`: 1536 for confident small talk, 4096 for a concise profile in default mode; other modes keep their cap (the cap counts against Groq's per-minute window).
- Small talk keeps only the last 6 messages and tries the small models first (`preferSmall`: gpt-oss-20b, nemotron lightning), keeping the big models' windows free. The Groq token-budget preflight in `preferForPrompt` still applies.
- History compaction no longer re-summarises every turn (see row 2).
- Prompt order is stable for provider prompt caching: the static base, profile and mode come first in the first system message and only the date line (last paragraph) changes between days; memory, summary, past chats, context blocks and hints are separate messages after it (`test/efficiency.test.ts` pins this). Optional sections (HTML, GitHub, widget examples) are already trimmed per intent.

System prompt size, default mode, no profile (from `turn-audit.ts`):

| Turn | chars | ~tokens |
|------|-------|---------|
| everything included | 25309 | 6328 |
| small talk / code / explain | 17373 | 4344 |
| UI / HTML | 22515 | 5629 |
| GitHub | 20167 | 5042 |

The remaining ~4.3k tokens are the base rules. Cutting them further changes answer behaviour and needs its own evaluation, so it was left alone; the biggest safe lever is that Groq's 8k tokens/min window rarely fits this prompt plus history, which is what `preferForPrompt` already routes around.

### Measurement

- `db/usage.ts` keeps per-turn counters in the telemetry scope. At the end of each turn the route logs `turn cost` with `{llmCalls, auxLlmCalls, embedCalls, searches, fetches, promptTokens, completionTokens, msToFirstToken, totalMs, auxCalls}` and writes one `usage_events` row (`kind=turn`, `purpose=turn-summary`, `provider=web`, `model=turn`; `count` = auxiliary calls, `latency_ms` = total, `ttft_ms` = time to first token). The SSE `usage` event is unchanged.

## 3. Before / after

`cd backend && pnpm exec tsx scripts/turn-audit.ts` simulates 10 representative prompts. LLM, embeddings, search and page fetches are stubbed. "After" runs the real decision code; "before" re-states the previous rules. Reply lengths, model answers, snippet quality and whether free sources suffice are fixtures; time to first token is modelled from assumed latencies (LLM 700 ms, embed 350 ms, search 1100 ms, fetch 900 ms), not measured.

```
prompt               llm b/a    embed b/a  search b/a  fetch b/a  aux b/a   aux tok b/a   ttft ms b/a (modelled)
greeting             1/0        2/0        0/0         0/0        3/0       950/0         1050/600
thanks               2/0        2/0        0/0         0/0        4/0       1350/0        1750/600
code question        2/1        3/1        0/0         0/0        5/2       1750/950      1050/1050
fresh fact           2/0        3/1        5/3         3/2        13/6      1750/0        2600/2600
follow-up            4/1        3/1        3/2         3/3        13/7      2450/520      4000/3300
explain concept      3/2        3/1        0/0         0/0        6/3       2050/1470     1750/1750
comparison           3/2        3/1        4/5         3/3        13/11     2050/1470     3300/3300
personal statement   3/1.3      3/1        0/0         0/0        6/2.3     2050/787      1750/1750
past chat            3/2        3/1        0/0         0/0        6/3       2050/1470     1750/1750
round table          4/3.3      3/1        12/13       9/6        28/23.3   2450/2137     5100/5100
TOTAL (10 turns)     27/12.7    28/8       24/23       18/14      97/57.7   18900/8803    2410/2180 (mean)
```

- Auxiliary calls (aux LLM + embeddings + searches + page fetches): 97 to 57.7, **41% fewer**.
- Auxiliary LLM calls: 27 to 12.7, **53% fewer**; auxiliary LLM tokens 18.9k to 8.8k.
- Embedding requests: 28 to 8.
- Searches barely move (24 to 23): comparisons now legitimately run two queries, the saving comes from fewer secondaries and year-variant queries. The saved quota is mostly Ollama's, since free-first skips it when the free sources suffice.
- Mean modelled time to first token: 2410 ms to 2180 ms (10% lower). Small-talk turns improve most (1050 to 600 ms, 1750 to 600 ms); web turns improve where a decision/plan chain collapsed (follow-up 4000 to 3300 ms). Worst cases improve more than the mean: the model-call chain before search is capped at 2.5 s (was up to 8.5 s) and page reads at 2.5 s (was 6 s per page).

## 4. Not done / follow-ups

- Real production numbers were not available here; the audit is a simulation. Check `turn-summary` rows after deploy and compare to the table above.
- The system prompt base (~4.3k tokens) was not shortened.
- Follow-ups and memory extraction were not merged into one call (reasons above).
- `needsKb` from the model is honoured only when it is explicit `false`; a user with a KB asking a general question still searches it.
