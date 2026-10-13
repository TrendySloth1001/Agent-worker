#!/usr/bin/env bash
# Upload a release APK to the sparky OTA endpoint (POST /app/releases).
#
#   scripts/publish-apk.sh <apk> --kind feature [--live] [--min N]
#                          [--title "..."] [--note "..."]... [--version x.y.z] [--build N]
#
# version/build come from frontend/pubspec.yaml (`version: x.y.z+N`) unless overridden.
# RELEASE_TOKEN and PUBLIC_BASE_URL (default https://sparky.cloudnsofts.com) are read from the
# environment or backend/.env. The token is never printed or placed on a command line.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

apk="" kind="" live=0 min="" title="" version="" build=""
notes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --kind)    kind="${2:-}"; shift 2 ;;
    --live)    live=1; shift ;;
    --min)     min="${2:-}"; shift 2 ;;
    --title)   title="${2:-}"; shift 2 ;;
    --note)    notes+=("${2:-}"); shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --build)   build="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*)        echo "unknown option: $1" >&2; usage ;;
    *)         if [ -z "$apk" ]; then apk="$1"; shift; else echo "unexpected argument: $1" >&2; usage; fi ;;
  esac
done

[ -n "$apk" ] && [ -f "$apk" ] || { echo "error: APK file not found" >&2; usage; }
case "$kind" in patch|feature|major|critical) ;; *) echo "error: --kind must be patch|feature|major|critical" >&2; exit 2 ;; esac
if [ -n "$min" ] && ! [[ "$min" =~ ^[0-9]+$ ]]; then echo "error: --min must be a number" >&2; exit 2; fi

if [ -z "$version" ] || [ -z "$build" ]; then
  line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+' "$root/frontend/pubspec.yaml" | head -n1 || true)"
  [ -n "$line" ] || { echo "error: no 'version: x.y.z+N' in frontend/pubspec.yaml" >&2; exit 1; }
  spec="$(printf '%s' "$line" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]].*$//')"
  [ -n "$version" ] || version="${spec%%+*}"
  [ -n "$build" ] || build="${spec##*+}"
fi

# Read KEY from the environment, else from backend/.env (no sourcing; value is not echoed).
envval() {
  local k="$1" v="${!1:-}"
  if [ -z "$v" ] && [ -f "$root/backend/.env" ]; then
    v="$(grep -E "^${k}=" "$root/backend/.env" | tail -n1 | cut -d= -f2- || true)"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  fi
  printf '%s' "$v"
}
token="$(envval RELEASE_TOKEN)"
base="$(envval PUBLIC_BASE_URL)"
base="${base:-https://sparky.cloudnsofts.com}"; base="${base%/}"
[ -n "$token" ] || { echo "error: RELEASE_TOKEN is not set (environment or backend/.env)" >&2; exit 1; }

# notes -> JSON array of strings
json_notes="["
sep=""
for n in ${notes[@]+"${notes[@]}"}; do
  esc="${n//\\/\\\\}"; esc="${esc//\"/\\\"}"; esc="${esc//$'\n'/\\n}"; esc="${esc//$'\t'/\\t}"
  json_notes+="${sep}\"${esc}\""; sep=","
done
json_notes+="]"

status=draft; [ "$live" = 1 ] && status=live
echo "Uploading $(basename "$apk") as v$version (build $build, $kind, $status) to $base ..."

args=(-sS -o - -w '\n%{http_code}' --max-time 900 -X POST "$base/app/releases"
  -F "apk=@${apk};type=application/vnd.android.package-archive"
  -F "version=$version" -F "build=$build" -F "kind=$kind" -F "title=$title"
  -F "notes=$json_notes" -F "status=$status")
[ -n "$min" ] && args+=(-F "minSupportedBuild=$min")

# The auth header goes through a curl config on stdin so the token never appears in argv.
resp="$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -K - "${args[@]}")" || { echo "error: request failed" >&2; exit 1; }
code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
if [ "$code" = 200 ] || [ "$code" = 201 ]; then
  echo "Published: HTTP $code"; echo "$body"
else
  echo "error: HTTP $code" >&2; echo "$body" >&2; exit 1
fi
