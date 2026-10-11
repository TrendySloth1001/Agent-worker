#!/usr/bin/env python3
"""Renders the sparky brand mark (SVG sources + PNGs) from one geometry.

The mark is a dot-matrix lowercase "s" followed by a red period: "s." -- the
launcher-sized echo of the "sparky." wordmark on the login screen.

    python3 assets/brand/render_brand.py      # from frontend/

Outputs land next to this script. Needs Pillow only (no SVG rasterizer).
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent

INK = "#0A0A0A"  # icon background / light-theme ink
PAPER = "#FFFFFF"  # dots on dark
RED = "#D71921"  # the period
UNLIT_DARK = "#1C1C1C"  # dim "off" pixels on the black tile (app dotGrid)
SPLASH_LIGHT = "#F4F4F2"  # AppColors.lightBackground
SPLASH_DARK = "#000000"  # AppColors.darkBackground

# 6 columns x 5 rows. "#" = lit white dot, "r" = red period, "." = unlit.
GLYPH = [
    ".####.",
    "#.....",
    ".###..",
    "....#.",
    "####.r",
]
COLS, ROWS = len(GLYPH[0]), len(GLYPH)

# Geometry in the 108-unit adaptive-icon frame. The whole mark (diagonal
# ~60.5) sits inside the 66-unit safe-zone circle.
FRAME = 108.0
PITCH = 8.0
DOT = 6.6


def dots(frame=FRAME, pitch=PITCH, dot=DOT, unlit=False):
    """Yields (cx, cy, r, kind) in frame units, mark centered."""
    w = (COLS - 1) * pitch + dot
    h = (ROWS - 1) * pitch + dot
    x0 = (frame - w) / 2 + dot / 2
    y0 = (frame - h) / 2 + dot / 2
    for j, row in enumerate(GLYPH):
        for i, c in enumerate(row):
            if c == "." and not unlit:
                continue
            yield x0 + i * pitch, y0 + j * pitch, dot / 2, c


def color_for(kind, ink, unlit_color):
    return {"#": ink, "r": RED, ".": unlit_color}[kind]


# ---------------------------------------------------------------- SVG


def svg(frame, background, ink, unlit_color=None, scale=1.0, radius=0.0):
    k = scale
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {frame:g} {frame:g}" '
        f'width="1024" height="1024">'
    ]
    if background:
        parts.append(
            f'  <rect width="{frame:g}" height="{frame:g}" rx="{radius:g}" fill="{background}"/>'
        )
    for cx, cy, r, kind in dots(
        frame, PITCH * k, DOT * k, unlit=unlit_color is not None
    ):
        fill = color_for(kind, ink, unlit_color)
        parts.append(f'  <circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{fill}"/>')
    parts.append("</svg>\n")
    return "\n".join(parts)


# ---------------------------------------------------------------- PNG

SS = 4  # supersampling


def png(
    path,
    px,
    frame,
    background,
    ink,
    unlit_color=None,
    scale=1.0,
    radius=0.0,
    mono=False,
):
    big = px * SS
    u = big / frame
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        d.rounded_rectangle(
            [0, 0, big - 1, big - 1], radius=radius * u, fill=background
        )
    for cx, cy, r, kind in dots(
        frame, PITCH * scale, DOT * scale, unlit=unlit_color is not None
    ):
        fill = "#FFFFFF" if mono else color_for(kind, ink, unlit_color)
        d.ellipse([(cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u], fill=fill)
    img = img.resize((px, px), Image.LANCZOS)
    img.save(OUT / path)


def main():
    # Sources (vector).
    (OUT / "sparky_icon.svg").write_text(
        svg(FRAME, INK, PAPER, UNLIT_DARK, scale=1.25, radius=FRAME * 0.22)
    )
    (OUT / "sparky_foreground.svg").write_text(svg(FRAME, None, PAPER, UNLIT_DARK))
    (OUT / "sparky_monochrome.svg").write_text(svg(FRAME, None, "#FFFFFF"))
    (OUT / "sparky_mark_dark.svg").write_text(svg(FRAME, None, PAPER))
    (OUT / "sparky_mark_light.svg").write_text(svg(FRAME, None, INK))

    # Legacy launcher icon: rounded black tile, mark larger (no mask crops it).
    png("icon_legacy.png", 1024, FRAME, INK, PAPER, UNLIT_DARK, 1.25, FRAME * 0.22)
    # Play-store style full-bleed square (also a handy preview).
    png("icon_square.png", 1024, FRAME, INK, PAPER, UNLIT_DARK, 1.25)
    # Adaptive layers (108-unit frame, safe zone respected).
    png("icon_foreground.png", 1024, FRAME, None, PAPER, UNLIT_DARK)
    png("icon_monochrome.png", 1024, FRAME, None, PAPER, mono=True)

    # Splash marks. Pre-12 splash: drawn at 1x = 288 px for a ~96dp mark at
    # xxxhdpi it's scaled by the plugin, so give it a tight-ish canvas.
    png("splash_dark.png", 768, FRAME, None, PAPER, scale=1.4)
    png("splash_light.png", 768, FRAME, None, INK, scale=1.4)
    # Android 12+: 1152 px canvas, content must stay inside the inner
    # 768 px circle (2/3) -- the mark diagonal at scale 1.0 is ~56% of frame.
    png("splash12_dark.png", 1152, FRAME, None, PAPER)
    png("splash12_light.png", 1152, FRAME, None, INK)

    # Previews of the adaptive icon as a launcher would mask it.
    preview_adaptive()


def preview_adaptive():
    size = 1024
    fg = Image.open(OUT / "icon_foreground.png")
    bg = Image.new("RGBA", (size, size), INK)
    full = Image.alpha_composite(bg, fg)
    # Launchers show the inner 72/108 of the layer, masked.
    crop = int(size * 18 / 108)
    shown = full.crop((crop, crop, size - crop, size - crop)).resize((512, 512), Image.LANCZOS)
    sheet = Image.new("RGBA", (512 * 3 + 64 * 4, 512 + 128), "#F4F4F2")
    masks = []
    for kind in ("circle", "squircle", "mono"):
        m = Image.new("L", (512 * SS, 512 * SS), 0)
        dm = ImageDraw.Draw(m)
        if kind == "squircle":
            dm.rounded_rectangle([0, 0, 512 * SS - 1, 512 * SS - 1], radius=512 * SS * 0.3, fill=255)
        else:
            dm.ellipse([0, 0, 512 * SS - 1, 512 * SS - 1], fill=255)
        masks.append((kind, m.resize((512, 512), Image.LANCZOS)))
    mono_fg = Image.open(OUT / "icon_monochrome.png")
    # Themed icon look: tinted background + tinted glyph.
    tinted_bg = Image.new("RGBA", (size, size), "#DCE3F5")
    alpha = mono_fg.split()[3]
    glyph = Image.new("RGBA", (size, size), "#1E2A44")
    glyph.putalpha(alpha)
    themed = Image.alpha_composite(tinted_bg, glyph)
    themed = themed.crop((crop, crop, size - crop, size - crop)).resize((512, 512), Image.LANCZOS)
    for n, (kind, m) in enumerate(masks):
        src = themed if kind == "mono" else shown
        x = 64 + n * (512 + 64)
        sheet.paste(src, (x, 64), m)
    sheet.save(OUT / "preview_adaptive.png")


if __name__ == "__main__":
    main()
