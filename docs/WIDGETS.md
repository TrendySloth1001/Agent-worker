# Widget kit spec (merged plan)

Scope: 8 new registry widgets + 5 leftover fixes + harness prompt/router work. Four builders work in parallel on disjoint files. Existing widgets (email, message, card, diff, ask, flow, mermaid, math) are unchanged except where noted.

## Scaffolding already done (do not redo)
- `lib/features/chat/widgets/rich/widget_registry.dart`: `Widget? buildRichWidget(String language, String source, {required bool streaming})`. Returns null for unknown languages; while streaming returns `RichPlaceholder("PREPARING <NAME>…")`; otherwise the widget. Wired into `markdown/code_block_builder.dart` (first check, before mermaid/ask/flow).
- Stub files (constructor `const X({super.key, required String source})`, each parses its own source and must fall back to a RichCard showing the raw source on parse failure): `chart_card.dart ChartCard`, `html_card.dart HtmlCard`, `quiz_card.dart QuizCard`, `flashcards_card.dart FlashcardsCard`, `calc_card.dart CalcCard`, `timeline_card.dart TimelineCard`, `stats_card.dart StatsCard`, `checklist_card.dart ChecklistCard`.
- `lib/core/constants/widget_kit.dart`: only `WidgetLang` ids and `WidgetKitStrings` (titles + `preparing()`). Builders do NOT edit it.
- Package added to pubspec: `fl_chart ^1.2.0` (resolves 1.2.0 on Flutter 3.38.7 / Dart 3.10). No other new package is needed. pubspec.yaml/lock are frozen.

## Rules for all widgets
- Nothing aesthetic: monochrome + one accent (`context.palette.accent`), flat, 1px borders, Space Mono caps labels (`context.text.caption/label`), Doto only for big numbers (score, stat values). No gradients/emoji. Light and dark. Wrap in `RichCard` (title = mono caps).
- Sizes/strings/durations/icons from constants. Each builder creates its OWN constants file `lib/core/constants/widget_<name>.dart` (new file) and may add icons to `app_icons.dart` only via a tiny targeted Edit (append one line, never rewrite).
- Every tap calls `Haptics.tap()` (correct answer `Haptics.received()`, wrong `Haptics.error()`).
- Parsing is tolerant: unknown keys ignored, caps on counts (see below), never throw; unparsable -> raw-source fallback card.
- Source format is line-based `key: value` (like existing flow/ask) except `chart` and `html`.
- Interactive state is local (State), not persisted. Widgets that send a chat message use `ChatActions.of(context)?.send(text)` and are active only when `ReplyScope` says latest reply (copy the ask_card pattern).
- Palette for multi-series: accent first, then 4 monochrome steps (`palette.textPrimary`, `textSecondary`, `textTertiary`, `border` strong). Never add new hues.

## Widget list (final)

### 1. ```chart  (CHARTS builder; fl_chart)
Source is a small JSON object (models handle JSON charts best):
```
{"type":"bar|line|area|pie|donut|scatter|radar","title":"...","x":["Mon","Tue"],"series":[{"name":"Sales","data":[3,5]}],"unit":"°C","xLabel":"","yLabel":""}
```
Scatter: `series[].points:[[x,y],...]`. Pie/donut: `series:[{"name":"A","data":[40]}...]` or one series with `x` as slice labels. Caps: 8 series, 60 points.
Behaviour: bar (grouped), line, area (line + 15% accent fill), pie/donut (center total in Doto), scatter, radar. Touch shows tooltip with value+unit and haptic tick. Legend row under chart (tap name toggles series visibility). Header action: TABLE toggle (shows data as a table; accessible fallback), COPY DATA (CSV). Animate in once (AppDurations constant). Streaming placeholder: `PREPARING CHART…`. Fallback: JSON parse fail or empty -> raw source card. Owns: chart_card.dart (+ private `chart_*.dart` helpers in rich/), `widget_chart.dart` constants.

### 2. ```html  (HTML builder; webview_flutter, url_launcher)
Source is a full or partial HTML document (model writes self-contained HTML/CSS/JS, inline only, no external requests except cdnjs).
Behaviour: inline card with a sandboxed WebView (`loadHtmlString`, JS enabled, no file access, `NavigationDelegate` blocks all navigation away from the document and opens http(s) links via url_launcher externally; a CSP `<meta>` injected into `<head>` allowing `default-src 'none'; img-src data: https:; style-src 'unsafe-inline'; script-src 'unsafe-inline' https://cdnjs.cloudflare.com; font-src data:; connect-src 'none'`). Injected viewport meta + base theme CSS vars (`--bg --fg --accent --border`) matching the current palette, and a tiny script that posts `document.documentElement.scrollHeight` to a JavaScriptChannel so the card auto-sizes (min 160, max 480 px; beyond max it scrolls internally). Header: title from `<title>`; actions: FULLSCREEN (new route, full WebView, back button), SOURCE (route with CodeBlock-style viewer of the raw HTML with COPY), COPY HTML, OPEN EXTERNAL (writes temp .html and launches via url_launcher if possible, else snack). Does not auto-run while streaming (placeholder `PREPARING HTML…`) so partial documents never render. Recreate-safe: controller disposed with State; keep alive within list via `AutomaticKeepAliveClientMixin` off (rebuild is acceptable). Fallback: empty source -> raw card. Size cap 200 KB, over that show SOURCE only. Owns: html_card.dart, `rich/html_fullscreen.dart`, `rich/html_source.dart`, `rich/html_doc.dart` (sanitize/inject helpers), `widget_html.dart` constants.

### 3. ```quiz  (PLAYFUL builder)
```
title: Capitals
q: Capital of France?
a: Berlin
a: *Paris
a: Rome
why: Paris has been the capital since 987.
q: ...
```
`*` marks the correct answer (exactly one; first `*` wins; none -> question dropped). Caps 12 questions, 6 options. One question at a time: progress bar (2px, accent), option tiles flat 1px border; tap reveals: correct tile accent border + check icon, wrong tile struck mono, `why` shown, NEXT button. Streak counter. End screen: big Doto score `7/10`, rating word, RETRY (same order shuffled) and ASK FOR HARDER (sends "Give me a harder quiz on <title>" via ChatActions, latest reply only). Options shuffled with a seed from the source hash (stable across rebuilds).

### 4. ```flashcards  (PLAYFUL builder)
```
title: Spanish verbs
card: hablar | to speak
card: comer | to eat
```
Caps 40 cards. Tap flips (Transform rotateY, short duration constant); swipe/arrow buttons next/prev; "KNEW IT" / "AGAIN" marks; deck progress `4/12` and known count in Doto; SHUFFLE and RESTART actions; a finished state with count of known/again and "STUDY AGAIN CARDS ONLY".

### 5. ```calc  (PLAYFUL builder)
Mini live calculator for the model to create parameterised "what-if" tools (loan, tip, BMI, unit conversion).
```
title: Loan payment
input: principal | Loan amount | 10000 | 0..1000000 | $
input: rate | Annual rate | 5 | 0..30 | %
input: years | Years | 10 | 1..40 |
out: Monthly payment | principal*(rate/1200)/(1-(1+rate/1200)^(-years*12)) | $ | 2
out: Total paid | principal*(rate/1200)/(1-(1+rate/1200)^(-years*12))*years*12 | $ | 0
```
`input: id | label | default | min..max | suffix`; `out: label | expression | suffix | decimals`. Inputs render as slider + tappable numeric value (editable via small dialog/keypad field). Outputs recompute on every change, large Doto numbers. Expression evaluator is a hand-written recursive-descent parser in `calc_eval.dart` (numbers, ids, + - * / ^ %, parentheses, functions `min max abs round floor ceil sqrt pow log ln exp sin cos tan pi e`), NEVER eval of strings. Division by zero/NaN shows em dash. Caps 8 inputs, 8 outputs. Action: RESET, COPY RESULTS.

### 6. ```timeline  (PLAYFUL builder)
```
title: History of the web
1991 | First website | Tim Berners-Lee publishes it at CERN
1995 | JavaScript | Created in 10 days
```
`when | title | optional detail`. Vertical rail (1px line, accent dot on the selected/latest), tap to expand detail with animation; first item expanded by default. Caps 30 events. Action: EXPAND ALL / COLLAPSE.

### 7. ```stats  (PLAYFUL builder)
```
title: Q3 snapshot
stat: Revenue | 1.2M | +12% | up
stat: Churn | 3.1% | -0.4% | down
stat: Users | 48,201 | | 
spark: Revenue | 3,4,4,6,7,9
```
Grid of 2 columns of tiles: label (mono caps), value (Doto), delta chip (accent only for `up`/`down` direction arrow icon; neutral otherwise), optional sparkline drawn with CustomPaint from a `spark:` row matching the label. Tap tile toggles a tooltip with the sparkline enlarged. Caps 8 tiles.

### 8. ```checklist  (PLAYFUL builder)
```
title: Packing list
[ ] Passport
[x] Charger
```
Tap toggles (haptic tick), progress `3/8` + 2px bar, auto strike-through, at 100% a brief accent flash and "ALL DONE" mono label. Actions: COPY (markdown checkboxes), SEND PROGRESS (latest reply only: sends remaining items to chat). Caps 40 items. Local state only.

### 9. GitHub live cards  (```github-*; fetch through backend `/github`)
Unlike the others, these blocks carry only a reference; the card loads LIVE data from the backend (`frontend/lib/data/github_api.dart` -> `backend/src/routes/github.ts`, token `GITHUB_TOKEN`, 5 min server cache). Every card: RichCard frame, skeleton while loading, error + RETRY, VISIT (browser picker via `visitUrl`) and COPY actions, octicons via `InlineIcon` (`octicon:*-16`), monochrome with the red accent only for removals/merged/closed. Constants: `lib/core/constants/widget_github.dart`. Code: `lib/features/chat/widgets/github/`.
| Block | Body | Card |
|---|---|---|
| `github-repo` | `owner/repo` (or a github.com URL) | avatar, name, description, stars/forks/watching/issues, license, default branch, last push, language bar, topics, latest release |
| `github-search` | `type: repos\|code\|issues\|commits` + `q: <GitHub search syntax>` (`sort: stars` optional; a lone line = repo query) | total + result rows; tap to expand (repo details, code fragments, issue body, commit body) |
| `github-commits` | `owner/repo[@branch][:path]` | commit rail (avatar, message, sha chip, author, age, +/-); tap -> body + changed files, each file expands to a diff (`DiffLines`, shared with ```diff) |
| `github-graph` | `owner/repo`, optional lines `branches: a, b` and `limit: 100` (10-300, default 150) | VS Code "Git Graph"-style table (`GET /github/repos/:o/:r/graph`): lane column painted by a `CustomPainter` (one color per lane from `GithubGraphColors`, red reserved for the default branch, bezier curves for branch-offs/merges, filled dots, hollow dots + dimmer text for merge commits, ring on branch heads, max 8 lanes then an overflow marker), then subject with branch ref pills, date+time, author, sha chip (tap copies). Virtualized rows in a 480 px box with horizontal scroll on narrow screens; tap a row -> changed files with diffs (`GhCommitDetail`, shared with `github-commits`). Toolbar: branch chips (toggle -> refetch with `branches=`), REFRESH, FULLSCREEN. 404 -> "Repository not found…" |
| `github-tree` | `owner/repo[@ref][:path]` | collapsible lazy tree (dirs first, sizes); tap a file -> highlighted viewer (`CodeBlock`), back arrow |
| `github-compare` | `owner/repo base...head` | refs, commits/changed/ahead/behind, +/-, commit rail, file diffs |
| `github-prs` / `github-issues` | `owner/repo [open\|closed\|all]` | OPEN/CLOSED/ALL switch, state octicons, labels (color dot), comments; tap -> body, VISIT, (PR) FILES with diffs and REVIEW (expands the AI review inline) |
| `github-review` | `owner/repo#123` (or a PR URL) | AI review (`POST /github/repos/:o/:r/pulls/:n/review`, strong model, strict JSON, cached per head sha): title/author/+-, verdict badge, 3-step risk meter, comments grouped by file with severity octicons; tap a comment -> its diff hunk (`DiffLines`) + suggestion; COPY = whole review as markdown; RE-RUN skips the cache |
| `github-my-repos` | `all\|private\|public` | the token owner's repositories (`GET /github/my/repos`), lock badge on private ones; account row from `GET /github/me` |

Grounding: when the user's message is about GitHub (github.com link, `owner/repo` next to repo words, "find a repo/library for X"), `backend/src/github/grounding.ts` adds live data as `[G#]` sources (`<github>` context block, chips with site github.com) and a one-line hint suggesting the matching block. Unrelated questions never call GitHub. "Review owner/repo#123" (or a PR link + review words) adds the PR as a source and hints `github-review`; "my repos" / "my private repos" hints `github-my-repos`, and "my repo X" resolves X against the token's account (private repos work whenever the token can read them). "git graph", "branch/commit graph", "branch history" or "how did the branches merge" next to an `owner/repo` adds a graph summary source (branches, merge commits) and hints `github-graph`.

Git graph backend: `backend/src/github/graph.ts`. With a token it uses GraphQL (default branch history paginated past 100, plus up to 8 branches: the most recently pushed ones from the repository activity feed, else heads by commit date; or the requested `branches`), otherwise REST (`/branches`, `/activity`, `/commits?sha=`). Histories are merged into one DAG deduped by sha, ordered by committer date with children always above parents, capped at `limit` (`truncated` when more history exists), cached 60 s per auth key. Response: `{repo, defaultBranch, branches:[{name, sha, isDefault}], commits:[{sha, parents, subject, author, authorAvatar, date, refs}], truncated}`. Lane assignment runs in the app (`lib/features/chat/widgets/github/git_graph_layout.dart`, pure Dart, tested in `test/git_graph_layout_test.dart`).

### Cut on purpose
Kanban/board, drawing canvas, polls with persistence, map, audio player, code sandbox with JS execution, mini-games (cannot be built robustly in one pass; html widget covers interactive one-offs). Chart types heatmap/candlestick/sankey cut. Persistence of widget state across app restarts cut.

## Streaming
All registry languages show `PREPARING <NAME>…` placeholder until streaming ends (done in the registry; widgets only ever see complete sources).

## Backend/harness (HARNESS builder)
1. `backend/src/prompts/system.ts`: add a "WIDGETS" section teaching each fenced language with the exact syntax above plus 1 tight example each and when to use (chart for numeric comparisons/trends; html when the user asks for a page/reference/demo/mockup/landing/calculator UI/anything best shown as a document, one complete self-contained doc; quiz when asked to test/quiz; flashcards for memorising; calc for what-if numeric tools; timeline for chronology; stats for a KPI snapshot; checklist for to-do/packing/steps they will tick). Never emit a widget AND repeat the same data as a table. Keep existing ask/flow/card/email rules. Escape backticks as \`, never write `${`.
2. FLOW nudge (leftover 1): make the rule firm and positional: "If the question asks how/why something works as a process, pipeline, algorithm or data flow (RNN, HTTP request, compile steps, auth handshake) you MUST open with a ```flow block before prose" and include a compact flow example inside the rule; list trigger words.
3. CASUAL opener (leftover 2): rule "Match the user's register: if the message is casual (slang, 'bro', lowercase, no punctuation) the first sentence is a short casual opener in their voice (e.g. 'Bro, ...'), before any heading. Headings never come first for casual messages." Add 2 examples.
4. `backend/src/routes/chat.ts` small isolated function `intentHint(text): string | null` (pure, exported for testing, regex-based) adding at most one extra system line per request: process/how-it-works -> "Open with a flow block."; compare/trend/numbers/percent -> "Use a chart block."; "quiz me|test me" -> quiz; "flashcards|memorize" -> flashcards; "calculate|what if|how much would" -> calc; "timeline|history of" -> timeline; "build|make|create ... (page|html|website|landing|reference|demo|mockup)" -> html; casual register detector (`/\b(bro|dude|yo|man|bruh)\b/i` or all-lowercase short message without punctuation) -> casual opener hint. Appended as an extra system message, never visible, no change to request/response shape. Verify with a temporary script against the running :3000 dev server (no new server).

## Leftover fixes (HARNESS builder, markdown folder)
3. Inline math baseline: in `math_syntax.dart`/`math_view.dart`, render inline math as `WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic)` inside the paragraph (not `middle`), with the Math widget wrapped so its baseline is its text baseline; font size equals surrounding text style.
4. `|` inside `$...$` in a table cell: in `md_blocks.dart`/`md_table.dart` cell splitting must treat `|` within an unescaped `$...$` pair (and inside backtick code) as literal; implement a small state-machine splitter replacing the naive split; also handle `\|`. Add a unit-style self-check via a temporary test.
5. Long formulas in tables: in `md_table.dart` measure column intrinsic widths for math cells; render math cells with `FittedBox(fit: BoxFit.scaleDown)` up to a min scale constant (0.75) and only beyond that keep horizontal scroll; wrap formula cells with `Math.tex` options `mathStyle: text` (not display). Keep text readable first, scroll as last resort.

## File ownership (no overlaps)
| Builder | May create/edit ONLY |
|---|---|
| CHARTS | `rich/chart_card.dart`, `rich/chart_*.dart` (new), `lib/core/constants/widget_chart.dart` (new) |
| HTML | `rich/html_card.dart`, `rich/html_*.dart` (new), `lib/core/constants/widget_html.dart` (new). May add `<queries>`/intent to AndroidManifest only if essential for url_launcher https (already in use elsewhere, expected unnecessary). |
| PLAYFUL | `rich/quiz_card.dart`, `flashcards_card.dart`, `calc_card.dart`, `calc_eval.dart` (new), `timeline_card.dart`, `stats_card.dart`, `checklist_card.dart`, `rich/playful_*.dart` (new shared helpers), `lib/core/constants/widget_playful.dart` (new) |
| HARNESS | `backend/src/prompts/system.ts`, `backend/src/routes/chat.ts` (only the `intentHint` function + its single call site), `markdown/app_markdown.dart`, `md_blocks.dart`, `md_table.dart`, `math_syntax.dart`, `math_view.dart` |

Nobody edits: `widget_registry.dart`, `code_block_builder.dart`, `widget_kit.dart`, `rich_frame.dart`, pubspec.yaml/lock (frozen), `rich_cards.dart`, `app_sizes.dart`. If a builder needs a shared change it uses its own constants file or private widget. `app_icons.dart`: single-line appends only (Edit, not rewrite); prefer `HugeIcons.*` directly inside own constants file to avoid even that.

## Verification (every builder)
`cd frontend && dart format lib && flutter analyze` clean; HARNESS also `cd backend && pnpm exec tsc --noEmit`. Optional temporary widget tests (add flutter_test, then restore pubspec.yaml/lock exactly and delete tests). Never `flutter run`/adb, never start a server on :3000.
