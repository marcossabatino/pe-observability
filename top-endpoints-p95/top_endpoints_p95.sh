#!/usr/bin/env bash
# Lists the top N endpoints by p95 latency over a given time window.
# Uses the Datadog Metrics Query API (v1) with APM trace duration metrics.
#
# Usage:
#   ./top_endpoints_p95.sh [--service <name>] [--env <env>] [--window <minutes>] [--top <n>]
#
# Examples:
#   ./top_endpoints_p95.sh
#   ./top_endpoints_p95.sh --env production --top 10
#   ./top_endpoints_p95.sh --service payments --env production --window 30
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
SERVICE=""
ENV=""
WINDOW=60
TOP=5

# ── helpers ───────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

die() { echo "ERROR: $*" >&2; exit 1; }

require() {
  command -v "$1" &>/dev/null || die "'$1' is required but not installed."
}

# ── parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --env)     ENV="$2";     shift 2 ;;
    --window)  WINDOW="$2";  shift 2 ;;
    --top)     TOP="$2";     shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
require curl
require jq

[[ -z "${DD_API_KEY:-}" ]] && die "DD_API_KEY is not set."
[[ -z "${DD_APP_KEY:-}" ]] && die "DD_APP_KEY is not set."
[[ "$WINDOW" =~ ^[0-9]+$ ]] || die "--window must be a positive integer."
[[ "$TOP"    =~ ^[0-9]+$ ]] || die "--top must be a positive integer."

# ── build query ───────────────────────────────────────────────────────────────
FILTER="*"
[[ -n "$ENV" ]]     && FILTER="env:${ENV}"
[[ -n "$SERVICE" ]] && FILTER="${FILTER},service:${SERVICE}"

QUERY="p95:trace.http.request{${FILTER}} by {resource_name,service}"

TO=$(date +%s)
FROM=$(( TO - WINDOW * 60 ))

# ── call Datadog Metrics API ──────────────────────────────────────────────────
BASE_URL="https://api.${DD_SITE}/api/v1/query"

echo "Window:   last ${WINDOW} minute(s)"
echo "Env:      ${ENV:-all}"
echo "Service:  ${SERVICE:-all}"
echo "Top:      ${TOP}"
echo ""

RESPONSE=$(curl -sf \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  "${BASE_URL}?query=$(jq -rn --arg q "$QUERY" '$q | @uri')&from=${FROM}&to=${TO}") \
  || die "API request failed."

STATUS=$(echo "$RESPONSE" | jq -r '.status // "ok"')
[[ "$STATUS" == "error" ]] && die "Datadog API error: $(echo "$RESPONSE" | jq -r '.error')"

SERIES_COUNT=$(echo "$RESPONSE" | jq '.series | length')

if [[ "$SERIES_COUNT" -eq 0 ]]; then
  echo "No APM data found for the given window and filters."
  exit 0
fi

# ── aggregate and rank ────────────────────────────────────────────────────────
# p95 is a gauge — take the max value across the window per series
echo "Rank  Service              Endpoint                         p95 (ms)"
echo "────  ───────────────────  ───────────────────────────────  ────────"

echo "$RESPONSE" | jq -r '
  [ .series[] |
    {
      service:  (.tags_by_name.service  // "unknown"),
      endpoint: (.tags_by_name.resource_name // .scope),
      p95_ms:   ([ .pointlist[][1] | select(. != null) ] | max // 0) * 1000
    }
  ] | sort_by(-.p95_ms) | to_entries[] |
  [ (.key + 1), .value.service, .value.endpoint, (.value.p95_ms | round) ] |
  @tsv
' | head -n "$TOP" | awk -F'\t' '{
  printf "%-5s %-20s %-32s %s\n", $1, substr($2,1,20), substr($3,1,32), $4
}'
