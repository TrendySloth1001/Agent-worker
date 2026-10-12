# Mascots

Decision: sparky's mascot is a **custom dot-matrix character drawn in code**
(`CustomPainter` + one `AnimationController`). No third-party animation files
are bundled, so there is no licence or attribution risk and no bundle growth.

## Candidates reviewed

Verified on 2026-10-12 from the sources linked. "Fit" is the Nothing aesthetic
(monochrome ink plus one red accent, dot-matrix).

| Candidate | URL | Licence (as found) | Attribution | Format / size | Fits | Nothing fit |
|---|---|---|---|---|---|---|
| **Sparky (custom, chosen)** | `lib/core/widgets/mascot.dart` | Own work, no third-party code or art | None | Code only, 0 KB assets | All states, all screens | Perfect: ink dots plus red accent, follows light and dark |
| Google Noto Animated Emoji | https://googlefonts.github.io/noto-emoji-animation/ | CC BY 4.0 per the project (the repo LICENSE could not be fetched in this session, so confirm before use) | Required (credit the author, link the licence) | Lottie JSON (also WebP/GIF), roughly 20-150 KB each | Generic reactions (robot, thinking, party) | Poor: full-colour emoji, a Lottie colour filter would flatten them, not a consistent character |
| Microsoft Fluent Emoji | https://github.com/microsoft/fluentui-emoji | MIT (LICENSE read: "MIT License, Copyright (c) Microsoft Corporation") | Keep the copyright notice | Static SVG/PNG (3D, Color, Flat, High Contrast); no animated variants found in the repo | Static icons only | High Contrast set is monochrome but static |
| LottieFiles free animations | https://lottiefiles.com/page/license | Lottie Simple License: commercial use allowed, attribution "strongly encouraged" not required, modified files stay under the same licence, no re-compiling into a competing service. Each file has its own page, some are marked otherwise | Optional | Lottie JSON, 10-300 KB | Anything, but each file must be checked individually | Mixed styles, would need recolouring per file, no single consistent character |
| Rive Community | https://rive.app/docs/community/community-overview | CC BY (Rive docs: community files are shared under CC BY) | Required | `.riv`, small, but needs the `rive` runtime package (native lib, bigger APK) | Rich mascots exist | Colours are baked in, mixed authors, extra runtime |
| Open Peeps (already used) | https://www.openpeeps.com/ | CC0 | None | SVG, static | Login, hello, empty screens | Line art, already tinted; static only |
| unDraw | https://undraw.co/license | Own licence: free for commercial use, no attribution, but cannot be bundled or redistributed as packs and is discouraged where illustrations are central to an app | None | SVG, static | Spot illustrations | Colourful, static; the restriction is a risk for an app |
| Dot-matrix / pixel-art animated characters | searched, none found with a clear permissive licence and a code/dev theme | n/a | n/a | n/a | n/a | n/a |
| GitHub Octocat | https://github.com/logos | Trademarked, not open source | n/a | n/a | n/a | Not used. Replaced by a branch-antenna sparky |

## Recommended set: one character, nine states

One consistent character beats a mix of emoji. Sparky is a 17 x 15 dot grid:
ink dots (theme text colour), unlit dots in the border colour, and a red
accent dot on the antenna. It loops over 4 seconds.

| State | Look | Used for |
|---|---|---|
| idle | blinks, glances sideways, smiles | empty chat (HELLO), empty history, docs outline ready |
| thinking | eyes up, three dots light in turn | Round Table seating/checking/reviewing, doc planning, empty memory |
| writing | eyes down, red text line grows | Round Table drafting/synthesizing, doc writing, empty docs list |
| searching | eyes scan left and right | Round Table researching, doc researching, empty knowledge base, no search matches |
| celebrating | ^ ^ eyes, hops, confetti | doc finishing |
| sleeping | closed eyes, breathing, Z | empty storage, empty telemetry, archived list, doc paused/partial |
| error | red X eyes, blinking spark and "!" | load failures (history, KB, memory, storage, docs), failed doc |
| offline | dim eyes, wavy mouth, flickering signal bars | reserved for offline banners |
| github | `<` `>` eyes, forked antenna with a travelling red node | GitHub connect card, future GitHub screen |

`Mascot(state:, size:)` lives in `lib/core/widgets/mascot.dart`; frames are
built by the pure function `buildMascotFrame` in `mascot_frame.dart`.
Reduced motion (`MediaQuery.disableAnimations`) shows frame 0 and the
controller never runs; the ticker also stops when its route is hidden
(`TickerMode`). Stage mapping: `MascotState.forTablePhase` and
`MascotState.forDocPhase`.

## Optional licensed accents

If richer motion is wanted later, Noto Animated Emoji (CC BY 4.0) or a
LottieFiles file can be added with the `lottie` package. Add the attribution
to `AboutStrings.creditList` and `assets/mascots/LICENSES.md` at that point.
Currently no such asset is bundled.
