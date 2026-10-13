import { randomBytes } from "node:crypto";
import { config } from "../../config.js";
import { AppError } from "../../util/errors.js";
import { log } from "../../util/logger.js";
import { sha256 } from "../../auth/githubWeb.js";
import { connectDeepLink, prismaFlowStore, type FlowStore } from "./flow.js";
import { connectorTokens, type TokenManager } from "./tokens.js";
import { userMessage } from "../../util/userMessages.js";

/**
 * Google Picker for drive.file: Google only grants sparky the files the user
 * selects in Google's own picker. The app asks for a picker ticket, opens
 * GET /connect/google_drive/picker?ticket=… in a Custom Tab, the page runs the
 * Picker with the user's short-lived access token, posts the chosen file ids
 * to /picker/done and deep-links back (sparky://auth/connect?provider=google_drive&mode=picker&picked=N&state=…).
 *
 * Tickets reuse oauth_flows (mode 'picker'): state_hash = sha256(ticket), and
 * the app's state rides in code_verifier (not a secret, only matched by the app).
 */

export const PICKER_PATH = "/connect/google_drive/picker";
export const PICKER_TTL_MS = 10 * 60_000;
export const MAX_PICKED = 50;

/** The Cloud project number, the leading digits of the OAuth client id (Picker's appId). */
export function projectNumber(clientId: string | undefined): string | null {
  const m = clientId?.match(/^(\d{6,})-/);
  return m ? m[1] : null;
}

export type PickerDeps = {
  store: FlowStore;
  tokens: TokenManager;
  now: () => number;
  apiKey: () => string | undefined;
  clientId: () => string | undefined;
  baseUrl: () => string;
  /** Confirms sparky can see [id] now (the Picker granted it). */
  verify: (userId: string, id: string) => Promise<boolean>;
};

export type PickerView =
  | { ok: true; token: string; apiKey: string; appId: string | null; origin: string; ticket: string }
  | { ok: false; title: string; message: string; link: string | null };

export function createPicker(deps: PickerDeps) {
  async function start(userId: string): Promise<{ url: string; state: string; expiresIn: number }> {
    // Fails early (404/401) when Drive is not connected or needs Reconnect.
    await deps.tokens.accessToken(userId, "google_drive");
    const ticket = randomBytes(32).toString("base64url");
    const state = randomBytes(24).toString("base64url");
    await deps.store.create({
      provider: "google_drive",
      mode: "picker",
      stateHash: sha256(ticket),
      codeVerifier: state,
      userId,
      expiresAt: new Date(deps.now() + PICKER_TTL_MS),
    });
    return { url: `${deps.baseUrl()}${PICKER_PATH}?ticket=${encodeURIComponent(ticket)}`, state, expiresIn: PICKER_TTL_MS / 1000 };
  }

  /** What the picker page shows for [ticket]. */
  async function view(ticket: string): Promise<PickerView> {
    const row = ticket ? await deps.store.peek("google_drive", "picker", sha256(ticket), new Date(deps.now())).catch(() => null) : null;
    if (!row) return { ok: false, title: "This link expired", message: "Go back to sparky and tap Pick files again.", link: null };
    const back = connectDeepLink({ provider: "google_drive", mode: "picker", error: "picker_unavailable", state: row.codeVerifier });
    const apiKey = deps.apiKey();
    if (!apiKey) {
      return {
        ok: false,
        title: "Picker not set up",
        message:
          "The Google file picker needs an API key on this server (GOOGLE_PICKER_API_KEY). Files you save to Drive from sparky still show up in the app.",
        link: back,
      };
    }
    try {
      const token = await deps.tokens.accessToken(row.userId, "google_drive");
      return { ok: true, token, apiKey, appId: projectNumber(deps.clientId()), origin: deps.baseUrl(), ticket };
    } catch (e) {
      return { ok: false, title: "Reconnect Google Drive", message: userMessage("connector_reauth", (e as Error).message, "Reconnect Google Drive in sparky, then try again."), link: back };
    }
  }

  /** The page reports the picked ids (none = cancelled). Returns the deep link back. */
  async function done(ticket: string, ids: string[]): Promise<{ link: string; picked: number }> {
    const row = await deps.store.claim("google_drive", "picker", sha256(ticket), new Date(deps.now())).catch(() => null);
    if (!row) throw new AppError(400, "invalid_ticket", "This picker link expired. Start again from sparky.");
    const unique = [...new Set(ids.filter((id) => /^[A-Za-z0-9_-]{10,200}$/.test(id)))].slice(0, MAX_PICKED);
    let picked = 0;
    for (const id of unique) if (await deps.verify(row.userId, id).catch(() => false)) picked++;
    await deps.store.ready(row.id, sha256(randomBytes(16).toString("hex")), new Date(deps.now()), { login: "", picked }).catch(() => undefined);
    log.info("drive picker done", { picked, asked: unique.length });
    return { picked, link: connectDeepLink({ provider: "google_drive", mode: "picker", picked: String(picked), state: row.codeVerifier }) };
  }

  return { start, view, done };
}

export type Picker = ReturnType<typeof createPicker>;

// ---- the page ---------------------------------------------------------------

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
/** JSON safe inside a <script> element. */
const jsonForScript = (v: unknown) => JSON.stringify(v).replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026");

export function pickerCsp(nonce: string): string {
  return [
    "default-src 'none'",
    // gapi loads the Picker's own scripts: trusted through the nonce'd loader.
    `script-src 'nonce-${nonce}' 'strict-dynamic' https: 'unsafe-inline'`,
    "style-src 'unsafe-inline' https:",
    "img-src https: data:",
    "font-src https: data:",
    "connect-src 'self' https://*.googleapis.com https://apis.google.com",
    "frame-src https://docs.google.com https://drive.google.com https://accounts.google.com https://content.googleapis.com",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
}

const STYLE = `:root{--bg:#f5f5f2;--fg:#111;--muted:#6b6b6b;--line:#d6d6d0;--accent:#d71921}
@media (prefers-color-scheme:dark){:root{--bg:#000;--fg:#f2f2f2;--muted:#8d8d8d;--line:#2a2a2a}}
*{box-sizing:border-box}html,body{margin:0;height:100%}
body{background:var(--bg);color:var(--fg);font-family:"Space Grotesk",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;display:flex;align-items:center;justify-content:center;padding:24px 16px}
main{width:100%;max-width:420px;border:1px solid var(--line);border-radius:20px;padding:28px 22px}
.mark{font-family:"Space Mono",ui-monospace,Menlo,monospace;font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--muted)}
h1{font-size:24px;font-weight:600;margin:14px 0 8px}p{margin:0 0 22px;line-height:1.5;color:var(--muted);font-size:15px}
a.btn,button{display:block;width:100%;text-align:center;text-decoration:none;background:var(--fg);color:var(--bg);border:0;border-radius:999px;padding:15px 18px;font-family:"Space Mono",ui-monospace,Menlo,monospace;font-weight:700;font-size:13px;letter-spacing:.12em}`;

export function pickerPage(v: PickerView, nonce: string): string {
  const head = (title: string) =>
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><meta name="color-scheme" content="light dark"><title>${esc(title)}</title><style nonce="${nonce}">${STYLE}</style></head>`;
  if (!v.ok) {
    return `${head(v.title)}<body><main><div class="mark">● sparky · google drive</div><h1>${esc(v.title)}</h1><p>${esc(v.message)}</p>${
      v.link ? `<a class="btn" href="${esc(v.link)}">RETURN TO SPARKY</a>` : ""
    }</main></body></html>`;
  }
  const cfg = { token: v.token, key: v.apiKey, appId: v.appId, origin: v.origin, ticket: v.ticket, done: `${v.origin}${PICKER_PATH}/done` };
  return `${head("Pick files from Drive")}<body><main><div class="mark">● sparky · google drive</div><h1>Pick files for sparky</h1>
<p id="lead">Opening Google Drive… sparky will only see the files you choose here.</p>
<button id="again" type="button" hidden>OPEN DRIVE AGAIN</button></main>
<script nonce="${nonce}" type="application/json" id="cfg">${jsonForScript(cfg)}</script>
<script nonce="${nonce}">
(function(){
  var cfg=JSON.parse(document.getElementById("cfg").textContent);
  var lead=document.getElementById("lead"), again=document.getElementById("again"), sent=false;
  function finish(ids){
    if(sent)return; sent=true; lead.textContent=ids.length?"Saving your picks…":"Going back to sparky…";
    fetch(cfg.done,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({ticket:cfg.ticket,ids:ids})})
      .then(function(r){return r.json();})
      .then(function(j){ if(j&&j.link){location.replace(j.link);} else {lead.textContent=(j&&j.error&&j.error.message)||"Something went wrong. Go back to sparky and try again.";} })
      .catch(function(){lead.textContent="Could not reach sparky. Go back to the app and try again.";});
  }
  function open(){
    var view=new google.picker.DocsView(google.picker.ViewId.DOCS).setIncludeFolders(true).setSelectFolderEnabled(false);
    var b=new google.picker.PickerBuilder().setOAuthToken(cfg.token).setDeveloperKey(cfg.key).addView(view)
      .addView(new google.picker.DocsUploadView()).enableFeature(google.picker.Feature.MULTISELECT_ENABLED)
      .setOrigin(cfg.origin).setTitle("Pick files for sparky")
      .setCallback(function(d){
        if(d.action===google.picker.Action.PICKED){finish((d.docs||[]).map(function(x){return x.id;}));}
        else if(d.action===google.picker.Action.CANCEL){finish([]);}
      });
    if(cfg.appId)b.setAppId(cfg.appId);
    b.build().setVisible(true);
  }
  again.addEventListener("click",open);
  var s=document.createElement("script"); s.src="https://apis.google.com/js/api.js";
  s.onload=function(){gapi.load("picker",{callback:function(){again.hidden=false;open();}});};
  s.onerror=function(){lead.textContent="Could not load Google Drive. Check your connection and try again.";};
  document.head.appendChild(s);
})();
</script></body></html>`;
}

export const picker = createPicker({
  store: prismaFlowStore,
  tokens: connectorTokens,
  now: () => Date.now(),
  apiKey: () => config.googlePickerApiKey,
  clientId: () => config.google.webClientId,
  baseUrl: () => config.publicBaseUrl,
  verify: async (userId, id) => {
    const { drive } = await import("./drive.js");
    await drive.meta(userId, id);
    return true;
  },
});
