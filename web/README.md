# sparky web

Next.js (App Router, `src/`), TypeScript strict, Tailwind CSS v4, Radix UI, Hugeicons. Mirrors the Flutter app's look: Space Grotesk + Space Mono, dot grid, monochrome surfaces, red accent, light and dark.

## Scripts

`pnpm dev` · `build` · `start` · `lint` · `typecheck` · `format` · `test` · `tokens`

## Structure

- `src/app` routes (`/` placeholder, `/ui` component gallery)
- `src/components/ui` primitives, `brand` dot matrix / mascot, `theme` provider and toggle
- `src/lib` `cn`, theme helpers, dot-matrix engine
- `src/styles/tokens.css` generated, do not edit
- `scripts/gen-tokens.ts` token generator

## Tokens

`pnpm tokens` parses the Dart design constants in `frontend/lib/core` (`app_colors.dart`, `app_palette.dart`, `app_sizes.dart`, `settings_copy.dart`) and writes `src/styles/tokens.css`: palette variables for light and dark, plus the Tailwind `@theme` mapping (colors, spacing, radii, type scale, durations, easings). Re-run it after changing those Dart files.

Spacing names such as `sm`/`md`/`lg` are spacing tokens, so use arbitrary values (`max-w-[28rem]`) for container widths instead of `max-w-md`.

## Auth

Backend-for-frontend: tokens never reach browser JS.

- Sign-in (`/api/auth/login`, `register`, GitHub `github/start` then `github/return`) calls the Express API server-side and stores the access and refresh tokens in httpOnly, SameSite=Lax cookies (Secure in production). The access cookie lives as long as the token; the refresh cookie is scoped to `/api`.
- `src/server/api-fetch.ts` attaches the Bearer token and refreshes once on 401, single-flight per refresh token, rotating the cookies. `src/proxy.ts` sends signed-out visitors of any non-public route to `/api/auth/session`, which refreshes or redirects to `/login?next=…`; signed-in users are moved off `/login`.
- `/api/sparky/[...path]` proxies every method to the API, streaming request and response bodies (SSE, uploads) unbuffered. Endpoints that return tokens (`auth/login`, `refresh`, `github/*`, …) are blocked there. Unsafe methods need a same-origin `Sec-Fetch-Site` or `Origin`.
- Client: `src/lib/api` (zod schemas, typed `ApiError` client, TanStack Query, `useMe`); server components use `getSession()`.
- GitHub sign-in returns to the origin allow-listed by the backend's `WEB_APP_ORIGIN`. Google sign-in is not wired (it needs a Google web client for this origin).

Env: see `.env.example`.

## Theme

System, light or dark. A tiny inline script sets `data-theme` before paint; the choice is kept in `localStorage`.
