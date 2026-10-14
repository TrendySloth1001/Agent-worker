#!/usr/bin/env bash
# Symbolize an obfuscated sparky crash trace on this machine.
#
#   scripts/symbolize.sh <fingerprint> [--symbols <dir|file>] [--sample N] [--mapping <mapping.txt>]
#
# Fetches the stored trace of an error group (GET /admin/errors/<fingerprint>, owner-only) and runs
# `flutter symbolize` on it with the split-debug-info symbols of the build that produced it.
#
#   --symbols  a symbols file, or a directory holding app.android-arm64.symbols (also looked up in
#              <dir>/<build>/). Default: frontend/build/symbols/<build>/. Uploading and downloading
#              symbols for released builds arrives with the release script phase; until then pass the
#              directory the release was built with (--split-debug-info=<dir>).
#   --sample   which stored sample to use, 1 = newest (default 1).
#   --mapping  R8 mapping.txt: Kotlin/Java traces are passed through `retrace` when it is installed.
#
# API_TOKEN and PUBLIC_BASE_URL (default https://sparky.cloudnsofts.com) are read from the
# environment or backend/.env. The token is never printed or placed on a command line.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

fp="" symbols="" sample=1 mapping=""
while [ $# -gt 0 ]; do
  case "$1" in
    --symbols) symbols="${2:-}"; shift 2 ;;
    --sample)  sample="${2:-}"; shift 2 ;;
    --mapping) mapping="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*)        echo "unknown option: $1" >&2; usage ;;
    *)         if [ -z "$fp" ]; then fp="$1"; shift; else echo "unexpected argument: $1" >&2; usage; fi ;;
  esac
done
[[ "$fp" =~ ^[0-9a-f]{40}$ ]] || { echo "error: give the 40-character fingerprint of an error group" >&2; usage; }
[[ "$sample" =~ ^[0-9]+$ ]] && [ "$sample" -ge 1 ] || { echo "error: --sample must be 1 or more" >&2; exit 2; }

envval() {
  local k="$1" v="${!1:-}"
  if [ -z "$v" ] && [ -f "$root/backend/.env" ]; then
    v="$(grep -E "^${k}=" "$root/backend/.env" | tail -n1 | cut -d= -f2- || true)"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  fi
  printf '%s' "$v"
}
token="$(envval API_TOKEN)"
base="$(envval PUBLIC_BASE_URL)"
base="${base:-https://sparky.cloudnsofts.com}"; base="${base%/}"
[ -n "$token" ] || { echo "error: API_TOKEN is not set (environment or backend/.env)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The token goes to curl through a stdin config, never argv.
body="$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
  curl -sS --max-time 30 -K - -w '\n%{http_code}' "$base/admin/errors/$fp")" || { echo "error: request failed" >&2; exit 1; }
code="${body##*$'\n'}"; body="${body%$'\n'*}"
[ "$code" = 200 ] || { echo "error: server answered $code (unknown fingerprint, or not the owner)" >&2; exit 1; }

printf '%s' "$body" > "$work/group.json"
# Writes the trace to $work/trace.txt and prints "<build> <kind>".
info="$(python3 -I - "$work" "$sample" <<'PY'
import json, sys
work, n = sys.argv[1], int(sys.argv[2])
d = json.load(open(work + "/group.json"))
samples = [s for s in d.get("samples", []) if s.get("stack")]
if not samples:
    sys.exit("no stored sample with a stack for this group")
if n > len(samples):
    sys.exit("only %d sample(s) with a stack" % len(samples))
s = samples[n - 1]
open(work + "/trace.txt", "w").write(s["stack"] + "\n")
print(s["build"], s["kind"])
PY
)"
build="${info%% *}"; kind="${info##* }"
echo "Group ${fp:0:8}: build $build, kind $kind, sample $sample" >&2

if [ "$kind" = kotlin ]; then
  if [ -n "$mapping" ] && command -v retrace >/dev/null 2>&1; then
    retrace "$mapping" "$work/trace.txt"
  else
    cat "$work/trace.txt"
    [ -z "$mapping" ] || echo "(retrace not installed: showing the raw trace)" >&2
  fi
  exit 0
fi

# A readable (non-obfuscated) trace needs no symbols.
if ! grep -qE 'virt [0-9a-f]+' "$work/trace.txt"; then
  echo "(trace is not obfuscated: showing it as stored)" >&2
  cat "$work/trace.txt"
  exit 0
fi
# Find the Dart symbols file.
file=""
if [ -z "$symbols" ]; then symbols="$root/frontend/build/symbols"; fi
if [ -f "$symbols" ]; then
  file="$symbols"
else
  for c in "$symbols/app.android-arm64.symbols" "$symbols/$build/app.android-arm64.symbols"; do
    if [ -f "$c" ]; then file="$c"; break; fi
  done
fi
[ -n "$file" ] || { echo "error: no app.android-arm64.symbols for build $build under $symbols (use --symbols <dir|file>)" >&2; exit 1; }

exec flutter symbolize -d "$file" -i "$work/trace.txt"
