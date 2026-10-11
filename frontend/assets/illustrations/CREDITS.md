# Illustrations — credits & license

The people in these illustrations come from **Open Peeps** by **Pablo Stanley**
(https://www.openpeeps.com/), released under **CC0 1.0 Universal** (public
domain dedication, https://creativecommons.org/publicdomain/zero/1.0/).
Attribution is not required under CC0; we give it anyway with thanks.

The props (spark, speech bubble, puzzle pieces, box, clock) were hand-drawn
for sparky and are dedicated to the public domain under the same CC0 terms.

| File                  | Open Peeps source parts                                   | Added props                    |
|-----------------------|-----------------------------------------------------------|--------------------------------|
| `login.svg`           | bust: body "Macbook" (peep-46), head "Short-5", face "Smiling" (peep-13) | red spark on the laptop lid, ink spark |
| `hello.svg`           | peep-standing-16                                          | speech bubble, red typing dot  |
| `github.svg`          | bust: body "Whatever" (peep-44), head "Twists-2" (peep-91), face "Smiling" | two puzzle pieces, red spark |
| `empty_knowledge.svg` | peep-sitting-9                                            | empty open box, red spark      |
| `empty_history.svg`   | peep-sitting-12                                           | clock with red hand            |

## Color contract

Each SVG uses exactly three colors, swapped at runtime by
`lib/core/widgets/illustration.dart`:

- `#000000` ink → `palette.textPrimary`
- `#FFFFFF` paper (fills that hide overlapping lines) → the host background
- `#D71921` accent → kept as-is

## Regenerating

`tools/compose.py` rebuilds the SVGs from the official Open Peeps SVGs
(downloaded from openpeeps.com); `tools/preview.sh` renders the light/dark PNGs
in `previews/` with headless Chrome. Neither the tools nor the previews are
bundled into the app.

```sh
python3 -I tools/compose.py <open-peeps-svg-dir> .
tools/preview.sh . previews
```
