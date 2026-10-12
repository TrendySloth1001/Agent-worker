import { AppError } from "../../util/errors.js";
import type { Connector } from "../types.js";
import { googleDrive, notion } from "./apps.js";
import { doc } from "./doc.js";
import { file } from "./file.js";
import { github } from "./github.js";
import { hackernews } from "./hackernews.js";
import { note } from "./note.js";
import { reddit } from "./reddit.js";
import { stackoverflow } from "./stackoverflow.js";
import { web } from "./web.js";

export type SourceType = "web" | "github" | "stackoverflow" | "reddit" | "hackernews" | "note" | "file" | "doc" | "google_drive" | "notion";
/** Types a user can add by URL/handle; notes, files, docs and connected-app items are created by the server. */
export type AddableType = Exclude<SourceType, "note" | "file" | "doc" | "google_drive" | "notion">;
export const SOURCE_TYPES: AddableType[] = ["web", "github", "stackoverflow", "reddit", "hackernews"];

export const connectors: Record<SourceType, Connector> = { web, github, stackoverflow, reddit, hackernews, note, file, doc, google_drive: googleDrive, notion };

export function detectType(input: string): AddableType {
  const s = input.trim();
  if (/^https?:\/\//i.test(s)) {
    let host = "";
    try {
      host = new URL(s).hostname.toLowerCase().replace(/^www\./, "");
    } catch {
      throw new AppError(400, "bad_request", "Invalid URL");
    }
    if (host === "github.com") return "github";
    if (host === "stackoverflow.com" || host.endsWith(".stackoverflow.com")) return "stackoverflow";
    if (host === "reddit.com" || host.endsWith(".reddit.com") || host === "redd.it") return "reddit";
    if (host === "news.ycombinator.com") return "hackernews";
    return "web";
  }
  if (/^[\w-]+\/[\w.-]+$/.test(s) && !/^r\//i.test(s)) return "github";
  if (/^\/?r\/\w+$/i.test(s)) return "reddit";
  if (/^[\w-]+(\.[\w-]+)+(\/\S*)?$/i.test(s)) return "web";
  throw new AppError(400, "bad_request", "Could not detect the source type. Pick one explicitly.");
}
