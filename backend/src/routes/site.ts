import { Router } from "express";
import { homePage, privacyPage, termsPage } from "../site/pages.js";

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
