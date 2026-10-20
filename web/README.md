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

## Theme

System, light or dark. A tiny inline script sets `data-theme` before paint; the choice is kept in `localStorage`.
