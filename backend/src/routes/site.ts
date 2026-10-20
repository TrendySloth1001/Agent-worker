import { Router } from "express";
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

siteRouter.get("/", send(homePage));
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
