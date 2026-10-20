# sparky backend: Express + Prisma, with ffmpeg for video/audio processing.

FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@11.28.5 --activate
# prisma generate reads the config but never connects at build time.
ENV DATABASE_URL=postgres://build:build@localhost:5432/build
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml prisma.config.ts ./
COPY prisma ./prisma
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src ./src
RUN pnpm build && pnpm prune --prod --ignore-scripts

FROM node:22-bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN chown node:node /app
ENV NODE_ENV=production PORT=3000
COPY --chown=node:node --from=build /app/package.json /app/prisma.config.ts ./
COPY --chown=node:node --from=build /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/prisma ./prisma
COPY --chown=node:node --from=build /app/dist ./dist
COPY --chown=node:node site-public ./site-public
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/health || exit 1
# Redeploys send SIGTERM; the server drains in-flight answer streams (SHUTDOWN_GRACE_MS, default 60 s)
# before exiting, so the stop timeout (compose stop_grace_period) must be longer than that.
STOPSIGNAL SIGTERM
# Applies pending migrations, then starts the server. `exec` makes node PID 1 so it receives SIGTERM
# (a plain `sh -c` would swallow it and the container would be SIGKILLed mid-stream).
CMD ["sh", "-c", "node_modules/.bin/prisma migrate deploy && exec node dist/index.js"]
