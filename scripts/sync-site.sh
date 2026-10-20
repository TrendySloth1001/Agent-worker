#!/usr/bin/env bash
# Copy the public landing site (github.com/TrendySloth1001/sparky-site) into the
# backend, which serves it at https://sparky.cloudnsofts.com/. Run before a deploy
# whenever the site changes. Usage: scripts/sync-site.sh [path-to-sparky-site]
set -euo pipefail
src="${1:-$(cd "$(dirname "$0")/../.." && pwd)/sparky-site}"
dst="$(cd "$(dirname "$0")/.." && pwd)/backend/site-public"
[ -f "$src/index.html" ] || { echo "error: $src/index.html not found" >&2; exit 1; }
rm -rf "$dst" && mkdir -p "$dst"
cp "$src/index.html" "$dst/"
cp -R "$src/css" "$src/js" "$src/assets" "$dst/"
echo "synced $(cd "$src" && git rev-parse --short HEAD 2>/dev/null || echo '?') -> backend/site-public ($(du -sh "$dst" | cut -f1))"
