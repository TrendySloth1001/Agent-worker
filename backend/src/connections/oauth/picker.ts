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
/** Files imported from picked folders (all folders together). */
export const MAX_IMPORT = 50;
export const FOLDER_MIME = "application/vnd.google-apps.folder";

/** A Drive item as the picker sees it. */
export type PickedItem = { id: string; name: string; folder: boolean; supported: boolean };
/** What the picked set came to. [fallback] are folders sparky cannot list: the user picks inside them. */
export type Expansion = { picked: number; imported: number; skipped: number; folders: number; fallback: Array<{ id: string; name: string }> };

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
  /** The item behind [id] when sparky can see it now (the Picker granted it), else null. */
  inspect: (userId: string, id: string) => Promise<PickedItem | null>;
  /** Lists a folder's direct children the token can see. Under drive.file this is usually denied or empty. */
  children: (userId: string, folderId: string) => Promise<{ ok: boolean; status: number; items: PickedItem[] }>;
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

  const cleanIds = (ids: string[]) => [...new Set(ids.filter((id) => /^[A-Za-z0-9_-]{10,200}$/.test(id)))].slice(0, MAX_PICKED);

  /**
   * Turns the picked ids into counts: files sparky can see, folders listed (files inside imported up to
   * MAX_IMPORT, unsupported types skipped) and folders it cannot list (the fallback). [handled] folders had
   * their files picked inside them already. Logs only whether listing worked, never names or ids.
   */
  async function expand(userId: string, ids: string[], handled: string[] = []): Promise<Expansion> {
    const items = (await Promise.all(cleanIds(ids).map((id) => deps.inspect(userId, id).catch(() => null)))).filter((i): i is PickedItem => !!i);
    const seen = new Set(items.filter((i) => !i.folder).map((i) => i.id));
    const folders = items.filter((i) => i.folder);
    const out: Expansion = { picked: seen.size, imported: 0, skipped: 0, folders: folders.length, fallback: [] };
    for (const f of folders) {
      if (handled.includes(f.id)) continue;
      const r = await deps.children(userId, f.id).catch(() => ({ ok: false, status: 0, items: [] as PickedItem[] }));
      const kids = r.items.filter((i) => !i.folder);
      log.info("drive folder listing", { ok: r.ok, status: r.status, children: kids.length });
      if (!r.ok || kids.length === 0) {
        out.fallback.push({ id: f.id, name: f.name });
        continue;
      }
      for (const k of kids) {
        if (seen.has(k.id)) continue;
        if (!k.supported || out.imported >= MAX_IMPORT) {
          out.skipped++;
          continue;
        }
        seen.add(k.id);
        out.imported++;
      }
    }
    return out;
  }

  /** The folders still to open in the picker, without ending the session (the ticket stays valid). */
  async function resolve(ticket: string, ids: string[]): Promise<Expansion> {
    const row = await deps.store.peek("google_drive", "picker", sha256(ticket), new Date(deps.now())).catch(() => null);
    if (!row) throw new AppError(400, "invalid_ticket", "This picker link expired. Start again from sparky.");
    return expand(row.userId, ids);
  }

  /** The page reports the picked ids (none = cancelled). Returns the deep link back. */
  async function done(ticket: string, ids: string[], handled: string[] = []): Promise<Expansion & { link: string }> {
    const row = await deps.store.claim("google_drive", "picker", sha256(ticket), new Date(deps.now())).catch(() => null);
    if (!row) throw new AppError(400, "invalid_ticket", "This picker link expired. Start again from sparky.");
    const e = await expand(row.userId, ids, handled);
    await deps.store.ready(row.id, sha256(randomBytes(16).toString("hex")), new Date(deps.now()), { login: "", picked: e.picked + e.imported }).catch(() => undefined);
    log.info("drive picker done", { picked: e.picked, imported: e.imported, skipped: e.skipped, folders: e.folders, limited: e.fallback.length, asked: cleanIds(ids).length });
    const n = (v: number) => (v > 0 ? String(v) : null);
    return {
      ...e,
      link: connectDeepLink({
        provider: "google_drive",
        mode: "picker",
        picked: String(e.picked),
        imported: n(e.imported),
        skipped: n(e.skipped),
        folders: n(e.folders),
        limited: n(e.fallback.length),
        state: row.codeVerifier,
      }),
    };
  }

  return { start, view, resolve, done };
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
a.btn,button{display:block;width:100%;text-align:center;text-decoration:none;background:var(--fg);color:var(--bg);border:0;border-radius:999px;padding:15px 18px;font-family:"Space Mono",ui-monospace,Menlo,monospace;font-weight:700;font-size:13px;letter-spacing:.12em}
.spin{width:22px;height:22px;border:2px solid var(--line);border-top-color:var(--accent);border-radius:50%;animation:s .8s linear infinite;margin:0 0 22px}
@keyframes s{to{transform:rotate(360deg)}}@media (prefers-reduced-motion:reduce){.spin{animation:none}}
body.picking main{visibility:hidden}
/* Google's picker wrapper lives in our page (its contents are Google's iframe): full screen on phones, our backdrop. */
.picker-dialog-bg{background:var(--bg)!important;opacity:1!important}
.picker-dialog{border:0!important;border-radius:0!important;box-shadow:none!important;top:0!important;left:0!important;width:100vw!important;height:100vh!important;height:100dvh!important}
.picker-dialog-content,.picker-dialog-content iframe{width:100vw!important;height:100vh!important;height:100dvh!important}
@media (min-width:900px){.picker-dialog{top:50%!important;left:50%!important;transform:translate(-50%,-50%);width:860px!important;height:600px!important;border-radius:20px!important;overflow:hidden}.picker-dialog-content,.picker-dialog-content iframe{width:860px!important;height:600px!important}}`;

export function pickerPage(v: PickerView, nonce: string): string {
  const head = (title: string) =>
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin"><meta name="color-scheme" content="light dark"><title>${esc(title)}</title><style nonce="${nonce}">${STYLE}</style></head>`;
  if (!v.ok) {
    return `${head(v.title)}<body><main><div class="mark">● sparky · google drive</div><h1>${esc(v.title)}</h1><p>${esc(v.message)}</p>${
      v.link ? `<a class="btn" href="${esc(v.link)}">RETURN TO SPARKY</a>` : ""
    }</main></body></html>`;
  }
  const cfg = { token: v.token, key: v.apiKey, appId: v.appId, origin: v.origin, ticket: v.ticket, base: `${v.origin}${PICKER_PATH}` };
  return `${head("Pick files from Drive")}<body><main><div class="mark">● sparky · google drive</div><h1>Pick files for sparky</h1>
<div class="spin" id="spin" aria-hidden="true"></div><p id="lead">Opening Google Drive… sparky will only see the files you choose here.</p>
<button id="again" type="button" hidden>OPEN DRIVE AGAIN</button></main>
<script nonce="${nonce}" type="application/json" id="cfg">${jsonForScript(cfg)}</script>
<script nonce="${nonce}">
(function(){
  var cfg=JSON.parse(document.getElementById("cfg").textContent);
  var lead=document.getElementById("lead"), again=document.getElementById("again"), spin=document.getElementById("spin"), sent=false;
  var FOLDER="application/vnd.google-apps.folder", all=[], handled=[];
  function post(path,body){
    return fetch(cfg.base+path,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)}).then(function(r){return r.json();});
  }
  function finish(ids){
    if(sent)return; sent=true; lead.textContent=ids.length?"Saving your picks…":"Going back to sparky…";
    post("/done",{ticket:cfg.ticket,ids:ids,handled:handled})
      .then(function(j){ if(j&&j.link){location.replace(j.link);} else {lead.textContent=(j&&j.error&&j.error.message)||"Something went wrong. Go back to sparky and try again.";} })
      .catch(function(){lead.textContent="Could not reach sparky. Go back to the app and try again.";});
  }
  function busy(text){document.body.classList.remove("picking");spin.hidden=false;lead.textContent=text;}
  // Google lets sparky open only what is picked: for a folder it cannot list, open the picker inside it.
  function pickInFolders(queue){
    if(!queue.length){finish(all);return;}
    var f=queue.shift(), P=google.picker;
    var view=new P.DocsView(P.ViewId.DOCS).setMode(P.DocsViewMode.LIST).setParent(f.id).setIncludeFolders(false);
    new P.PickerBuilder().setOAuthToken(cfg.token).setDeveloperKey(cfg.key).addView(view)
      .enableFeature(P.Feature.MULTISELECT_ENABLED).enableFeature(P.Feature.SUPPORT_DRIVES)
      .setOrigin(cfg.origin).setTitle("Pick files in "+f.name)
      .setSize(Math.max(320,window.innerWidth),Math.max(400,window.innerHeight))
      .setCallback(function(d){
        if(d.action===P.Action.LOADED){document.body.classList.add("picking");}
        else if(d.action===P.Action.PICKED){
          busy("Next…");
          var got=(d.docs||[]).map(function(x){return x.id;});
          if(got.length){all=all.concat(got);handled.push(f.id);}
          pickInFolders(queue);
        }
        else if(d.action===P.Action.CANCEL){busy("Next…");pickInFolders(queue);}
      }).build().setVisible(true);
  }
  function picked(docs){
    var ids=docs.map(function(x){return x.id;});
    all=ids;
    if(!docs.some(function(x){return x.mimeType===FOLDER;})){finish(ids);return;}
    busy("Looking inside your folders…");
    post("/resolve",{ticket:cfg.ticket,ids:ids})
      .then(function(j){pickInFolders(((j&&j.fallback)||[]).slice());})
      .catch(function(){finish(ids);});
  }
  function open(){
    var P=google.picker, list=P.DocsViewMode.LIST;
    // Files first (newest on top, list rows read well on a phone), then folders (selectable: sparky lists what Google allows, else asks for the files inside), then upload.
    var files=new P.DocsView(P.ViewId.DOCS).setMode(list).setIncludeFolders(false).setLabel("Files");
    var folders=new P.DocsView(P.ViewId.FOLDERS).setMode(list).setIncludeFolders(true).setSelectFolderEnabled(true).setLabel("Folders");
    var shared=new P.DocsView(P.ViewId.DOCS).setMode(list).setOwnedByMe(false).setLabel("Shared with me");
    var b=new P.PickerBuilder().setOAuthToken(cfg.token).setDeveloperKey(cfg.key)
      .addView(files).addView(folders).addView(shared).addView(new P.DocsUploadView())
      .enableFeature(P.Feature.MULTISELECT_ENABLED).enableFeature(P.Feature.SUPPORT_DRIVES)
      .setOrigin(cfg.origin).setTitle("Pick files for sparky")
      .setSize(Math.max(320,window.innerWidth),Math.max(400,window.innerHeight))
      .setCallback(function(d){
        if(d.action===P.Action.LOADED){document.body.classList.add("picking");}
        if(d.action===P.Action.PICKED){busy("Saving your picks…");picked(d.docs||[]);}
        else if(d.action===P.Action.CANCEL){busy("Going back to sparky…");finish([]);}
      });
    if(cfg.appId)b.setAppId(cfg.appId);
    b.build().setVisible(true);
  }
  again.addEventListener("click",open);
  var s=document.createElement("script"); s.src="https://apis.google.com/js/api.js";
  s.onload=function(){gapi.load("picker",{callback:function(){again.hidden=false;spin.hidden=true;open();}});};
  s.onerror=function(){spin.hidden=true;lead.textContent="Could not load Google Drive. Check your connection and try again.";};
  document.head.appendChild(s);
})();
</script></body></html>`;
}

/** A Drive file as the picker counts it: folders apart, and only readable kinds or images/media are worth importing. */
export function pickedItem(f: { id: string; name: string; mimeType: string; kind: string }): PickedItem {
  return {
    id: f.id,
    name: f.name,
    folder: f.mimeType === FOLDER_MIME,
    supported: f.kind !== "none" || /^(image|video|audio)\//.test(f.mimeType),
  };
}

export const picker = createPicker({
  store: prismaFlowStore,
  tokens: connectorTokens,
  now: () => Date.now(),
  apiKey: () => config.googlePickerApiKey,
  clientId: () => config.google.webClientId,
  baseUrl: () => config.publicBaseUrl,
  inspect: async (userId, id) => {
    const { drive } = await import("./drive.js");
    return pickedItem(await drive.meta(userId, id));
  },
  children: async (userId, folderId) => {
    const { drive } = await import("./drive.js");
    const r = await drive.children(userId, folderId, MAX_IMPORT * 2);
    return { ok: r.ok, status: r.status, items: r.files.map(pickedItem) };
  },
});
