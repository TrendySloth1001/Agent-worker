# Brand and file-type logos (`logos/`)

Official logos, fetched once from the Iconify API
(`https://api.iconify.design/<set>/<name>.svg`) and bundled so they draw
offline and before sign-in. Only the root `width`/`height` (`1em`, which
flutter_svg cannot resolve) were removed; two monochrome marks got their
official brand color baked in (noted below). Nothing else was redrawn or
recolored. All names and logos are trademarks of their respective owners
and are used only to identify those products.

Use: `BrandLogos` in `lib/core/constants/brand_logos.dart`.

| File | Iconify id | Set license |
| --- | --- | --- |
| github.svg | simple-icons:github | CC0 1.0 (Simple Icons) |
| google_drive.svg | logos:google-drive | CC0 (SVG Logos, gilbarbara/logos) |
| google_drive_mono.svg | simple-icons:googledrive | CC0 1.0 (Simple Icons) |
| google_photos.svg | logos:google-photos | CC0 (SVG Logos) |
| gmail.svg | logos:google-gmail | CC0 (SVG Logos) |
| google_calendar.svg | logos:google-calendar | CC0 (SVG Logos) |
| notion.svg | logos:notion-icon | CC0 (SVG Logos) |
| notion_mono.svg | simple-icons:notion | CC0 1.0 (Simple Icons) |
| slack.svg | logos:slack-icon | CC0 (SVG Logos) |
| groq.svg | thesvg-color:groq | MIT (theSVG, glincker/thesvg) |
| groq_mono.svg | bxl:groq-ai | MIT (BoxIcons) |
| groq_wordmark.svg | logos:groq | CC0 (SVG Logos) |
| nvidia.svg | simple-icons:nvidia, filled with NVIDIA green #76B900 | CC0 1.0 (Simple Icons) |
| nvidia_wordmark.svg | logos:nvidia | CC0 (SVG Logos) |
| ollama.svg | simple-icons:ollama | CC0 1.0 (Simple Icons) |
| openrouter.svg | simple-icons:openrouter | CC0 1.0 (Simple Icons) |
| openrouter_color.svg | logos:openrouter-icon | CC0 (SVG Logos) |
| reddit.svg | logos:reddit-icon | CC0 (SVG Logos) |
| reddit_mono.svg | simple-icons:reddit | CC0 1.0 (Simple Icons) |
| stackoverflow.svg | logos:stackoverflow-icon | CC0 (SVG Logos) |
| hackernews.svg | simple-icons:ycombinator, filled with Hacker News orange #FF6600 | CC0 1.0 (Simple Icons) |
| google_docs_2026.svg | thesvg-color:google-docs-2026 | MIT (theSVG) |
| google_sheets_2026.svg | thesvg-color:google-sheets-2026 | MIT (theSVG) |
| google_slides_2026.svg | thesvg-color:google-slides-2026 | MIT (theSVG) |
| google_docs.svg | thesvg-color:google-docs | MIT (theSVG) |
| google_sheets.svg | thesvg-color:google-sheets | MIT (theSVG) |
| google_slides.svg | thesvg-color:google-slides | MIT (theSVG) |
| google_docs_selfhst.svg | selfhst:google-docs | CC BY 4.0 (selfh.st/icons) |
| google_sheets_selfhst.svg | selfhst:google-sheets | CC BY 4.0 (selfh.st/icons) |
| google_slides_selfhst.svg | selfhst:google-slides | CC BY 4.0 (selfh.st/icons) |
| pdf.svg | vscode-icons:file-type-pdf2 | MIT (VSCode Icons) |
| word.svg | vscode-icons:file-type-word | MIT (VSCode Icons) |
| excel.svg | vscode-icons:file-type-excel | MIT (VSCode Icons) |
| powerpoint.svg | vscode-icons:file-type-powerpoint | MIT (VSCode Icons) |
| text_file.svg | vscode-icons:file-type-text | MIT (VSCode Icons) |
| markdown_file.svg | vscode-icons:file-type-markdown | MIT (VSCode Icons) |
| markdown.svg | simple-icons:markdown | CC0 1.0 (Simple Icons) |
| flutter.svg | logos:flutter-icon | CC0 (SVG Logos) |

## Model family logos (`logos/models/`)

The maker of each model family, shown next to a model wherever the app
names one (`ModelLogos.forModelId` in `lib/core/constants/model_logos.dart`).
Fetched once from LobeHub Icons, pinned
(`https://unpkg.com/@lobehub/icons-static-svg@1.95.1/icons/<name>.svg`,
MIT, <https://github.com/lobehub/lobe-icons>), except Microsoft (Iconify, as
above). Only the root `width`/`height` (`1em`) and inline `style` were
removed. NVIDIA Nemotron uses `nvidia.svg` above.

| File | Source | License | Families |
| --- | --- | --- | --- |
| openai.svg | lobehub openai (mono) | MIT (LobeHub Icons) | gpt-oss, GPT, o-series |
| gemma.svg | lobehub gemma (mono) | MIT (LobeHub Icons) | Google Gemma |
| meta.svg | lobehub meta-color | MIT (LobeHub Icons) | Meta Llama |
| qwen.svg | lobehub qwen-color | MIT (LobeHub Icons) | Alibaba Qwen, QwQ |
| glm.svg | lobehub chatglm-color | MIT (LobeHub Icons) | Z.ai / Zhipu GLM |
| deepseek.svg | lobehub deepseek-color | MIT (LobeHub Icons) | DeepSeek |
| kimi.svg | lobehub kimi (mono) | MIT (LobeHub Icons) | Moonshot Kimi |
| mistral.svg | lobehub mistral-color | MIT (LobeHub Icons) | Mistral, Mixtral, Codestral… |
| microsoft.svg | Iconify logos:microsoft-icon | CC0 (SVG Logos) | Microsoft Phi |

Attribution for the CC BY 4.0 files: icons by selfh.st
(https://github.com/selfhst/icons), licensed CC BY 4.0. The About screen
credits these sets too.

The 2026 Google Docs/Sheets/Slides icons use SVG masks and blur filters
that flutter_svg cannot draw faithfully, so the app shows the file-shaped
`google_*.svg` ones and keeps the 2026 files bundled for later.

Google Drive file rows prefer the type icon Google itself serves for each
file (Drive API `iconLink`); the bundled Google/Office/PDF logos show while
it loads or when it cannot.
