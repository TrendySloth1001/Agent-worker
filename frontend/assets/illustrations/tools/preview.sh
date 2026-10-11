#!/bin/bash
# preview.sh <svg_dir> <out_dir>
SRC=$1; OUT=$2; mkdir -p "$OUT"; T=$(mktemp -d)
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for f in "$SRC"/*.svg; do
  n=$(basename "$f" .svg)
  for mode in light dark; do
    if [ $mode = light ]; then ink='#0A0A0A'; paper='#F4F4F2'; dot='#E2E2DE'; else ink='#FFFFFF'; paper='#000000'; dot='#1C1C1C'; fi
    sed -e "s/#000000/@INK@/g" -e "s/#FFFFFF/$paper/g" -e "s/@INK@/$ink/g" "$f" > "$T/$n-$mode.svg"
    cat > "$T/$n-$mode.html" <<H
<html><body style="margin:0;width:560px;height:560px;display:flex;align-items:center;justify-content:center;background:$paper;background-image:radial-gradient($dot 1.6px,transparent 1.7px);background-size:16px 16px">
<img src="$n-$mode.svg" style="max-width:480px;max-height:480px"></body></html>
H
    "$CH" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --screenshot="$OUT/${n}_$mode.png" --window-size=560,560 "file://$T/$n-$mode.html" 2>/dev/null >/dev/null
  done
done
rm -rf "$T"
