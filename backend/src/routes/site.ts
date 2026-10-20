import { existsSync } from "node:fs";
import { join } from "node:path";
import express, { Router } from "express";
import { homePage, privacyPage, termsPage } from "../site/pages.js";
import { latestApkUrl } from "../ota/service.js";
import { rateLimit } from "../util/rateLimit.js";

/** Public pages: home, privacy policy, terms (linked from Google's and Notion's consent screens and the app). */
export const siteRouter = Router();

const send = (html: () => string) => (_req: unknown, res: import("express").Response) => {
  res
    .set("Cache-Control", "public, max-age=300")
    .set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'")
    .type("html")
    .send(html());
};

/** The landing site (synced from the sparky-site repo by scripts/sync-site.sh). Falls back to the plain home page. */
const SITE_DIR = join(process.cwd(), "site-public");
const SITE_CSP =
  "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; " +
  "connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

if (existsSync(join(SITE_DIR, "index.html"))) {
  siteRouter.get(["/", "/index.html"], (_req, res) => {
    res.set("Cache-Control", "public, max-age=300").set("Content-Security-Policy", SITE_CSP).sendFile(join(SITE_DIR, "index.html"));
  });
  const assets = express.static(SITE_DIR, {
    index: false,
    fallthrough: true,
    setHeaders: (res, path) => {
      // Fonts and images are fingerprint-free but rarely change: a day, then revalidate; CSS/JS an hour.
      res.setHeader("Cache-Control", /\.(css|js)$/.test(path) ? "public, max-age=3600" : "public, max-age=86400");
    },
  });
  siteRouter.use((req, res, next) => (/^\/(css|js|assets)\//.test(req.path) ? assets(req, res, next) : next()));
} else {
  siteRouter.get("/", send(homePage));
}
siteRouter.get(["/privacy", "/privacy-policy"], send(privacyPage));
siteRouter.get(["/terms", "/terms-of-service"], send(termsPage));

/** Public: "Download for Android" on the website — a redirect to a short-lived link to the newest live APK. */
siteRouter.get(["/download", "/download/android"], rateLimit(30, 60_000, "ip"), async (_req, res, next) => {
  try {
    const latest = await latestApkUrl();
    res.set("Cache-Control", "no-store");
    if (!latest) {
      res.redirect(302, "/");
      return;
    }
    res.set("X-Sparky-Version", `${latest.version}+${latest.build}`).redirect(302, latest.url);
  } catch (e) {
    next(e);
  }
});
