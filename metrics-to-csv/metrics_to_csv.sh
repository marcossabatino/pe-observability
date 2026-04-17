#!/usr/bin/env bash
# Exports Datadog metric query results to a CSV file for offline analysis.
# Uses the Datadog Metrics Query API (v1).
#
# Usage:
#   ./metrics_to_csv.sh --query <dql> --from <epoch> --to <epoch> [--output <file.csv>]
#
# Examples:
#   ./metrics_to_csv.sh --query "avg:system.cpu.user{*}" --from 1700000000 --to 1700003600
#   ./metrics_to_csv.sh --query "avg:system.cpu.user{host:web-01}" --from 1700000000 --to 1700003600 --output cpu.csv
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
OUTPUT="output.csv"
QUERY=""
FROM=""
TO=""

# ── helpers ──────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

die() { echo "ERROR: $*" >&2; exit 1; }

require() {
  command -v "$1" &>/dev/null || die "'$1' is required but not installed."
}

# ── parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)  QUERY="$2";  shift 2 ;;
    --from)   FROM="$2";   shift 2 ;;
    --to)     TO="$2";     shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
require curl
require jq

[[ -z "${DD_API_KEY:-}" ]] && die "DD_API_KEY is not set."
[[ -z "${DD_APP_KEY:-}" ]] && die "DD_APP_KEY is not set."
[[ -z "$QUERY" ]]          && die "--query is required."
[[ -z "$FROM" ]]           && die "--from is required (Unix epoch)."
[[ -z "$TO" ]]             && die "--to is required (Unix epoch)."

# ── query Datadog Metrics API ─────────────────────────────────────────────────
BASE_URL="https://api.${DD_SITE}/api/v1/query"

echo "Querying: $QUERY"
echo "Window:   $(date -d @"$FROM" '+%Y-%m-%d %H:%M:%S') → $(date -d @"$TO" '+%Y-%m-%d %H:%M:%S')"
echo ""

RESPONSE=$(curl -sf \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  "${BASE_URL}?query=$(jq -rn --arg q "$QUERY" '$q | @uri')&from=${FROM}&to=${TO}")

# ── check for errors ──────────────────────────────────────────────────────────
STATUS=$(echo "$RESPONSE" | jq -r '.status // "ok"')
[[ "$STATUS" == "error" ]] && die "Datadog API error: $(echo "$RESPONSE" | jq -r '.error')"

SERIES_COUNT=$(echo "$RESPONSE" | jq '.series | length')
[[ "$SERIES_COUNT" -eq 0 ]] && { echo "No data returned for the given query and time range."; exit 0; }

# ── write CSV ─────────────────────────────────────────────────────────────────
echo "timestamp,value,metric,scope" > "$OUTPUT"

echo "$RESPONSE" | jq -r '
  .series[] |
  . as $serie |
  ($serie.metric) as $metric |
  ($serie.scope) as $scope |
  $serie.pointlist[] |
  [ (.[0] / 1000 | todate), .[1], $metric, $scope ] |
  @csv
' >> "$OUTPUT"

ROWS=$(( $(wc -l < "$OUTPUT") - 1 ))
echo "Exported ${ROWS} data points to: ${OUTPUT}"
