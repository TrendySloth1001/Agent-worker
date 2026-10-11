/**
 * The ```html widget contract. The page renders in a phone-width WebView card
 * with the design kit (frontend/assets/html/kit.css) already loaded, so the
 * model writes semantic HTML plus kit classes and nothing else. Keep it short:
 * the free models follow a compact rule plus one skeleton far better than a
 * long list. KIT_REFERENCE must match the classes in kit.css.
 */
export const KIT_REFERENCE =
  "layout .container .stack .row .between .grid (cards, auto columns) .grid.tiles (2 per row on phones) .center | " +
  "sections .hero (.label + h1 + p.lead + .row of .btn) .nav .footer .card .card.accent .callout .divider .list (ul of rows with dividers) | " +
  "text .lead .label (mono caps) .muted .small .accent .kbd | " +
  "actions .btn .btn.primary .btn.ghost .btn.block .btn.sm | badges .tag .tag.accent .chip-list | " +
  'numbers .stats>.stat (.n short number + .label), bar chart .bars>.bar[style="--v:62%"] (span label + b value) | ' +
  'pricing .tiers>.tier (.featured) with h3, .price (with <small>/mo</small>), ul.checks, .btn | ' +
  "timeline ol.timeline>li with .when + h3 + p | forms .field (label + input/select/textarea), label.check (checkbox + text), .done (struck through) | " +
  "tables: plain <table> with <thead> (scrolls sideways by itself) | accordion: details>summary | code: pre>code. " +
  "Already styled: h1-h4 p ul ol table pre code details input select textarea button.";

const FENCE = "```";

export const HTML_RULE = `    - html (the user asks to build/make/show a page, landing page, dashboard, cheat sheet, reference, mockup, demo or interactive UI, or says "html"): one ${FENCE}html block after a one-line intro; nothing else after it. It renders in a phone-width card (360px) where the design kit below is ALREADY loaded with dark and light themes. Contract:
      1. Follow the skeleton below (a .hero header with an h1, then sections). Real, accurate, specific content (no lorem ipsum, no placeholders, no "save this file" tips inside the page). At most about 120 lines; always finish with </html>.
      2. No colors, fonts, backgrounds, borders, shadows or gradients of your own: kit classes and var(--bg|--surface|--surface-2|--text|--text-2|--border|--accent) only. A <style> block only for a few layout lines; no style="" except --v on .bar.
      3. Mobile-first single column; .grid .tiles .tiers .stats wrap by themselves. Never fixed widths, vh heights, position:fixed or side-by-side layouts that need more than 360px.
      4. Self-contained: no external scripts, stylesheets, fonts, frameworks or image URLs. Charts: .bars or inline SVG. Icons: <iconify-icon icon="hugeicons:home-01"></iconify-icon>. No emoji, no {{icon:...}} and no markdown inside the HTML.
      5. JS only when the user wants interactivity: one small vanilla <script> at the end of <body>, and render 3 realistic starter items on load (a todo list starts with 3 tasks, a tracker with 3 entries) so the page is never empty.
      Kit: ${KIT_REFERENCE}
      Do: h2/h3 for section titles, .tag only for 1-2 word badges, one .btn.primary per section. Don't: put .tag/.callout/.card on headings, invent classes (btn-primary, d-flex, container-fluid), style body or redefine the variables. Do not paste the same code in a second block.
      ${FENCE}html
      <!doctype html><html lang="en"><head><title>Tip calculator</title></head><body><main class="container stack">
      <header class="hero"><span class="label">Dinner for two</span><h1>Tip calculator</h1><p class="lead">Set the bill and tip to see the total.</p></header>
      <section class="card stack"><div class="field"><label for="bill">Bill</label><input id="bill" type="number" value="50"></div><div class="field"><label for="tip">Tip %</label><input id="tip" type="range" min="0" max="30" value="15"></div><div class="stat"><div class="n" id="total">57.50</div><div class="label">Total</div></div></section>
      </main><script>const f=()=>total.textContent=(bill.value*(1+tip.value/100)).toFixed(2);bill.oninput=tip.oninput=f;</script></body></html>
      ${FENCE}`;
