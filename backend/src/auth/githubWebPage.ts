import type { WebCallback } from "./githubWeb.js";

/**
 * The page GitHub's redirect lands on: it sends the browser straight on to the
 * sparky:// deep link and, in case the browser blocks that (some do without a
 * tap), shows a RETURN TO SPARKY button and a short fallback note.
 * Self-contained (no external assets), light and dark.
 */

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

export function callbackPage(cb: WebCallback, nonce: string): string {
  const href = esc(cb.link);
  const title = cb.ok ? "Back to sparky" : "GitHub sign-in stopped";
  const lead = cb.ok ? "GitHub approved. Returning you to sparky…" : esc(cb.message);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="color-scheme" content="light dark">
<title>${title}</title>
<style nonce="${nonce}">
:root{--bg:#f5f5f2;--fg:#111;--muted:#6b6b6b;--line:#d6d6d0;--dot:#d0d0ca;--accent:#d71921}
@media (prefers-color-scheme:dark){:root{--bg:#000;--fg:#f2f2f2;--muted:#8d8d8d;--line:#2a2a2a;--dot:#1c1c1c}}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{background:var(--bg) radial-gradient(var(--dot) 1px,transparent 1px) 0 0/14px 14px;color:var(--fg);
font-family:"Space Grotesk",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
display:flex;align-items:center;justify-content:center;padding:24px 16px}
main{width:100%;max-width:420px;background:var(--bg);border:1px solid var(--line);border-radius:20px;padding:28px 22px}
.mark{font-family:"Space Mono",ui-monospace,Menlo,monospace;font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--muted)}
.mark b{color:${cb.ok ? "var(--fg)" : "var(--accent)"}}
h1{font-size:24px;font-weight:600;margin:14px 0 8px;letter-spacing:-.01em}
p{margin:0 0 22px;line-height:1.5;color:var(--muted);font-size:15px}
a.btn{display:block;text-align:center;text-decoration:none;background:var(--fg);color:var(--bg);border-radius:999px;
padding:15px 18px;font-family:"Space Mono",ui-monospace,Menlo,monospace;font-weight:700;font-size:13px;letter-spacing:.12em}
.note{margin:18px 0 0;font-size:13px}
</style>
</head>
<body>
<main>
<div class="mark"><b>●</b> sparky · github</div>
<h1>${title}</h1>
<p>${lead}</p>
<a class="btn" id="go" href="${href}">RETURN TO SPARKY</a>
<p class="note">Nothing happened? Tap the button. If sparky still doesn't open, go back to the app and start again.</p>
</main>
<script nonce="${nonce}">location.replace(document.getElementById("go").href);</script>
</body>
</html>`;
}
