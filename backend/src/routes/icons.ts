import { Router } from "express";
import { resolveIcon } from "../web/icons.js";

export const iconsRouter = Router();

// GET /icons/:set/:name.svg -> the icon, or the closest real one (X-Icon-Id says which).
iconsRouter.get("/:set/:file", async (req, res) => {
  const name = req.params.file.replace(/\.svg$/, "");
  const icon = await resolveIcon(req.params.set, name);
  if (!icon) {
    res.status(404).end();
    return;
  }
  res.setHeader("Content-Type", "image/svg+xml");
  res.setHeader("Cache-Control", "public, max-age=86400");
  res.setHeader("X-Icon-Id", icon.id);
  res.send(icon.svg);
});
