/**
 * Public pages on the app's domain: home, privacy policy and terms of service.
 * Google's OAuth consent screen (and Notion's public connection listing) link
 * here. Self-contained HTML (no external assets), light and dark, in the same
 * look as the OAuth return pages.
 */

export const SITE = {
  name: "sparky",
  tagline: "Your engineering sidekick.",
  contact: "nkumawat8956@gmail.com",
  effective: "13 October 2026",
} as const;

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const STYLE = `
:root{--bg:#f5f5f2;--fg:#111;--muted:#5f5f5b;--line:#d6d6d0;--dot:#d9d9d3;--card:#fff;--accent:#d71921}
@media (prefers-color-scheme:dark){:root{--bg:#000;--fg:#f2f2f2;--muted:#9a9a9a;--line:#2a2a2a;--dot:#161616;--card:#0d0d0d}}
*{box-sizing:border-box}
html,body{margin:0}
body{background:var(--bg) radial-gradient(var(--dot) 1px,transparent 1px) 0 0/14px 14px;color:var(--fg);
font-family:"Space Grotesk",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;line-height:1.6}
.wrap{max-width:760px;margin:0 auto;padding:28px 16px 64px}
nav{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:40px}
.brand{font-weight:700;font-size:22px;letter-spacing:-.02em;text-decoration:none;color:var(--fg)}
.brand b{color:var(--accent)}
nav .links a{color:var(--muted);text-decoration:none;margin-left:16px;font-size:14px}
nav .links a:hover{color:var(--fg)}
h1{font-size:clamp(34px,7vw,56px);line-height:1.05;letter-spacing:-.03em;margin:0 0 12px}
h2{font-size:20px;margin:36px 0 8px;letter-spacing:-.01em}
h3{font-size:16px;margin:20px 0 4px}
p,li{color:var(--muted);font-size:16px}
strong{color:var(--fg)}
a{color:var(--fg)}
ul{padding-left:20px}
.mono{font-family:"Space Mono",ui-monospace,Menlo,monospace;font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:20px 22px;margin:14px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px;margin-top:20px}
.grid .card{margin:0}
.grid h3{margin-top:0}
.notice{border-left:3px solid var(--accent);padding-left:14px}
footer{margin-top:56px;padding-top:20px;border-top:1px solid var(--line);font-size:14px;color:var(--muted);display:flex;flex-wrap:wrap;gap:16px}
footer a{color:var(--muted)}
`;

function page(title: string, description: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="description" content="${esc(description)}">
<title>${esc(title)}</title>
<style>${STYLE}</style>
</head>
<body>
<div class="wrap">
<nav><a class="brand" href="/">sparky<b>.</b></a><span class="links"><a href="/privacy">Privacy</a><a href="/terms">Terms</a></span></nav>
${body}
<footer><span>© 2026 sparky</span><a href="/privacy">Privacy policy</a><a href="/terms">Terms of service</a><a href="mailto:${SITE.contact}">${SITE.contact}</a></footer>
</div>
</body>
</html>`;
}

export function homePage(): string {
  return page(
    "sparky: your engineering sidekick",
    "sparky is a personal AI assistant app for Android: chat, web search, documents, GitHub, Google Drive and Notion.",
    `<p class="mono">Android app</p>
<h1>sparky<span style="color:var(--accent)">.</span><br>${SITE.tagline}</h1>
<p>sparky is a personal AI assistant for Android. Ask questions, search the web with citations, write long documents, review code on GitHub, and bring in files from Google Drive and pages from Notion that you choose to share.</p>
<div class="grid">
<div class="card"><h3>Chat that cites</h3><p>Answers grounded in the web and in your own knowledge base, with sources you can open.</p></div>
<div class="card"><h3>Your apps, your choice</h3><p>Connect GitHub, Google Drive or Notion. sparky only sees what you pick, and you can disconnect at any time.</p></div>
<div class="card"><h3>Documents</h3><p>Long-form docs written section by section, saved to your account or to Drive and Notion.</p></div>
<div class="card"><h3>Private by default</h3><p>Your chats and files live in your account. Tokens are encrypted. Delete anything, any time.</p></div>
</div>
<h2>How sparky uses Google</h2>
<p>sparky offers <strong>Sign in with Google</strong> (your name, email and profile picture) and an optional <strong>Google Drive</strong> connection. The Drive connection uses the <code>drive.file</code> permission: sparky can only see files you pick in the Google file picker or files sparky saves for you. It is used to read those files when you ask about them, add them to your knowledge base, and save sparky documents to your Drive. See the <a href="/privacy">privacy policy</a> for details.</p>
<h2>Contact</h2>
<p>Questions, feedback or data requests: <a href="mailto:${SITE.contact}">${SITE.contact}</a>.</p>`,
  );
}

export function privacyPage(): string {
  return page(
    "Privacy policy · sparky",
    "How sparky collects, uses, stores, shares and deletes your data, including data from Google, GitHub and Notion.",
    `<p class="mono">Effective ${SITE.effective}</p>
<h1>Privacy policy</h1>
<p>This policy explains what the sparky app and its server at sparky.cloudnsofts.com ("sparky", "we") collect, why, and the choices you have. sparky is operated by its developer, who can be reached at <a href="mailto:${SITE.contact}">${SITE.contact}</a>.</p>

<h2>What we collect</h2>
<ul>
<li><strong>Account:</strong> your name, email address and profile picture, and a password hash if you sign up with email. If you sign in with Google or GitHub we receive your name, email address and profile picture from that service.</li>
<li><strong>Your content:</strong> the messages you send, the replies sparky generates, documents, files and images you attach, notes in your knowledge base, and memories sparky saves about you (you can see, edit and delete them in the app).</li>
<li><strong>Connected apps (only if you connect them):</strong> an access token for GitHub, Google Drive or Notion, stored encrypted, plus the account name and email of that service. sparky reads data from these services only to provide the features you use (see below).</li>
<li><strong>Usage and diagnostics:</strong> which AI model answered, token counts, timings and errors, used to run and improve the service. These records do not contain your message text.</li>
<li><strong>Device:</strong> the device name and app version shown in your list of signed-in sessions.</li>
</ul>

<h2>How we use it</h2>
<ul>
<li>To provide the app: answer your questions, keep your chat history, search your knowledge base, and show your connected files and pages.</li>
<li>To keep it secure: sign-in, rate limits and abuse prevention.</li>
<li>To operate and improve the service: reliability and cost monitoring from usage records.</li>
</ul>
<p>We do not sell your data, we do not use it for advertising, and we do not use your content to train AI models.</p>

<h2>Google user data</h2>
<div class="card notice">
<p><strong>sparky's use and transfer to any other app of information received from Google APIs will adhere to the <a href="https://developers.google.com/terms/api-services-user-data-policy">Google API Services User Data Policy</a>, including the Limited Use requirements.</strong></p>
</div>
<ul>
<li><strong>Sign in with Google</strong> gives sparky your name, email address and profile picture, used only to create and identify your account.</li>
<li><strong>Google Drive</strong> (optional) uses the <code>https://www.googleapis.com/auth/drive.file</code> scope. sparky can access only the files you select in the Google file picker and files sparky creates in your Drive (for example a document you save from sparky). We use this access to list those files in the app, read a file's content when you open it, ask sparky about it, or add it to your knowledge base, and to upload documents you choose to save to Drive.</li>
<li>When you ask sparky about a Drive file, the relevant text is sent to the AI model provider that generates the answer (see "Sharing"), only to answer that request.</li>
<li>We do not use Google user data to develop, improve or train generalized AI or machine-learning models, for advertising, or for any purpose other than the user-facing features described here. Humans do not read your Google data, except with your explicit permission, when needed for security, or to comply with the law.</li>
<li>You can disconnect Google Drive at any time in sparky (Apps → Google Drive → Disconnect), which revokes sparky's access and deletes the stored token. You can also remove access at <a href="https://myaccount.google.com/permissions">myaccount.google.com/permissions</a>.</li>
</ul>

<h2>GitHub and Notion</h2>
<p>If you connect GitHub, sparky uses your token to show your repositories, pull requests, issues and activity, and to take actions you start in the app (such as commenting or merging). If you connect Notion, you choose which pages to share during connection; sparky reads, searches and creates pages only within what you shared. Disconnecting deletes the stored token and, where the service allows it, revokes it.</p>

<h2>Sharing</h2>
<ul>
<li><strong>AI model providers</strong> (such as Groq, Ollama Cloud, NVIDIA and OpenRouter) receive the messages and context needed to generate each reply. They process it to return the answer.</li>
<li><strong>Web search providers</strong> receive search queries when sparky searches the web for you.</li>
<li><strong>Hosting:</strong> sparky's server and database run on infrastructure operated by the developer; files are kept in private storage and opened through expiring links.</li>
<li>We may disclose information if required by law, or to protect the safety and security of users and the service.</li>
</ul>

<h2>Retention and deletion</h2>
<ul>
<li>Your content is kept until you delete it. You can delete single chats, many chats, or all chats; delete files in Storage; and edit or delete memories.</li>
<li>Deleting your account (Profile → Delete account) removes your account, chats, files, memories, knowledge base and connected-app tokens.</li>
<li>You can also email <a href="mailto:${SITE.contact}">${SITE.contact}</a> to request access to or deletion of your data. We respond within 30 days.</li>
</ul>

<h2>Security</h2>
<p>Traffic is encrypted in transit (HTTPS). Connected-app tokens are encrypted at rest. Files are stored privately. No system is perfectly secure, but we work to protect your data and will notify affected users of a breach as required by law.</p>

<h2>Children</h2>
<p>sparky is not intended for children under 13 (or the minimum age in your country), and we do not knowingly collect their data.</p>

<h2>Changes</h2>
<p>We will update this page if this policy changes and change the date above. Significant changes will be announced in the app.</p>

<h2>Contact</h2>
<p><a href="mailto:${SITE.contact}">${SITE.contact}</a></p>`,
  );
}

export function termsPage(): string {
  return page(
    "Terms of service · sparky",
    "The terms for using the sparky app and service.",
    `<p class="mono">Effective ${SITE.effective}</p>
<h1>Terms of service</h1>
<p>These terms govern your use of the sparky app and its service at sparky.cloudnsofts.com. By creating an account or using sparky you agree to them. If you do not agree, do not use sparky.</p>

<h2>Your account</h2>
<p>You are responsible for your account and for keeping your sign-in details safe. Give accurate information and tell us at <a href="mailto:${SITE.contact}">${SITE.contact}</a> if you think your account has been misused. You must be at least 13 years old (or the minimum age in your country).</p>

<h2>Your content</h2>
<p>You keep all rights to what you send to sparky and to the files and pages you connect. You give sparky permission to store and process that content only to provide the service to you, as described in the <a href="/privacy">privacy policy</a>.</p>

<h2>Acceptable use</h2>
<ul>
<li>Do not use sparky to break the law, infringe others' rights, or harm, harass or deceive people.</li>
<li>Do not try to break, overload or get around the security or rate limits of the service, or access other users' data.</li>
<li>Do not use sparky to create malware, spam, or content that sexualises minors.</li>
<li>Follow the terms of the services you connect (Google, GitHub, Notion) and of the AI model providers.</li>
</ul>

<h2>AI-generated answers</h2>
<p>sparky's replies are generated by AI models and can be wrong, incomplete or out of date. Check important information, especially for medical, legal, financial or safety decisions, and review code and actions before you rely on them. Actions in connected apps (for example merging a pull request) happen only when you confirm them, and you are responsible for them.</p>

<h2>Third-party services</h2>
<p>sparky works with services run by others, such as Google, GitHub, Notion, AI model providers and web search providers. Their own terms and policies apply to your use of them, and we are not responsible for them.</p>

<h2>Availability and changes</h2>
<p>sparky is provided as is and may change, be interrupted or be discontinued. We may update these terms; we will change the date above and, for significant changes, tell you in the app. Continuing to use sparky after a change means you accept the new terms.</p>

<h2>Ending use</h2>
<p>You can stop using sparky and delete your account at any time in the app. We may suspend or close accounts that break these terms or put the service or other users at risk.</p>

<h2>Disclaimer and liability</h2>
<p>To the extent the law allows, sparky is provided without warranties of any kind, and the developer is not liable for indirect, incidental or consequential losses, or for loss of data, arising from your use of sparky. Nothing in these terms limits rights you have under consumer law that cannot be limited.</p>

<h2>Governing law</h2>
<p>These terms are governed by the laws of India.</p>

<h2>Contact</h2>
<p><a href="mailto:${SITE.contact}">${SITE.contact}</a></p>`,
  );
}
