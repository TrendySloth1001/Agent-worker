# Mascots

Decision (2026-10-12): sparky is rendered from **Google's Animated Noto Emoji**
(Lottie JSON, CC BY 4.0), one emoji per state, on a tonal disc with a dot-ring
halo. This replaces the earlier code-drawn dot-matrix character, which looked
unfinished.

## Licence (verified 2026-10-12)

Official Noto Emoji page, https://googlefonts.github.io/noto-emoji-files/ :

> Animated Noto Emoji is licensed under CC BY 4.0. See the full license for all details.

Full text: https://creativecommons.org/licenses/by/4.0/ . Commercial use is
allowed, attribution required. Note: the `noto-emoji` repo's own `LICENSE` is
the SIL OFL 1.1 (fonts) and its README says tools and most images are Apache
2.0; those cover the fonts and static images, not the animated set. The
animation repo has no LICENSE file of its own, so the CC BY 4.0 statement above
is the authoritative one. Credit: "Animated emoji: Noto Emoji by Google, CC BY
4.0" (About screen, `AboutStrings.creditList`) and
`frontend/assets/mascots/LICENSE.md`. Files are bundled unmodified.

## Cast

URL pattern (verified by fetching): `https://fonts.gstatic.com/s/e/notoemoji/latest/<codepoint>/lottie.json`.
Not every emoji exists (the magnifier 1f50d and satellite 1f4e1 return 404).

| State | Emoji | File | Size |
|---|---|---|---|
| idle | robot 1f916 | idle.json | 187 KB |
| thinking | thinking face 1f914 | thinking.json | 68 KB |
| writing | writing hand 270d_fe0f | writing.json | 81 KB |
| searching | magnifier tilted right 1f50e | searching.json | 29 KB |
| celebrating | party popper 1f389 | celebrating.json | 68 KB |
| sleeping | sleeping face 1f634 | sleeping.json | 24 KB |
| error | crossed-out eyes 1f635 | error.json | 28 KB |
| offline | electric plug 1f50c | offline.json | 16 KB |
| code host (the `github` state) | laptop 1f4bb (an octopus would be Octocat-adjacent) | code.json | 83 KB |

Total about 584 KB.

## Implementation

`Mascot(state:, size:)` (`lib/core/widgets/mascot.dart`) draws a halo
(`CustomPainter`: tonal disc plus 28 dots from the theme palette), then a
`Lottie.asset` for the state inside an `AnimatedSwitcher` (320 ms cross-fade).
The lottie package caches parsed compositions, so each file loads once. The
Lottie controller uses the widget tree's tickers, so it stops under
`TickerMode(enabled: false)` (hidden routes). Reduced motion
(`MediaQuery.disableAnimations`) renders the first frame only. If a file fails
to load, only the halo shows. Only one mascot is shown per screen; do not put it
in list rows beyond the small empty/error states. Stage mapping:
`MascotState.forTablePhase` and `MascotState.forDocPhase`.

## Other candidates reviewed

| Candidate | Licence | Why not |
|---|---|---|
| Microsoft Fluent Emoji | MIT | Static only |
| LottieFiles free animations | Lottie Simple License, per-file | Mixed styles, no single character |
| Rive Community | CC BY | Needs the rive runtime, baked colours |
| Open Peeps (used for illustrations) | CC0 | Static line art |
| unDraw | Own licence | Cannot be bundled as packs |
| Octocat | Trademarked | Not used |
