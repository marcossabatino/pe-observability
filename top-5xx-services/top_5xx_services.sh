#!/usr/bin/env bash
# Lists the top N services by 5xx error count over a given time window.
# Uses the Datadog Metrics Query API (v1) with APM trace error metrics.
#
# Usage:
#   ./top_5xx_services.sh [--env <env>] [--window <minutes>] [--top <n>]
#
# Examples:
#   ./top_5xx_services.sh
#   ./top_5xx_services.sh --env production --window 60 --top 10
#   ./top_5xx_services.sh --env staging --window 30
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
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
    --env)    ENV="$2";    shift 2 ;;
    --window) WINDOW="$2"; shift 2 ;;
    --top)    TOP="$2";    shift 2 ;;
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
[[ -n "$ENV" ]] && FILTER="env:${ENV}"

QUERY="sum:trace.http.request.errors{${FILTER},http.status_class:5xx} by {service}.rollup(sum, $((WINDOW * 60)))"

TO=$(date +%s)
FROM=$(( TO - WINDOW * 60 ))

# ── call Datadog Metrics API ──────────────────────────────────────────────────
BASE_URL="https://api.${DD_SITE}/api/v1/query"

echo "Window:   last ${WINDOW} minute(s)"
echo "Env:      ${ENV:-all}"
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
  echo "No 5xx errors found for the given window and environment."
  exit 0
fi

# ── aggregate and rank ────────────────────────────────────────────────────────
echo "Rank  Service                              5xx Errors"
echo "────  ───────────────────────────────────  ──────────"

echo "$RESPONSE" | jq -r '
  [ .series[] |
    {
      service: (.tags_by_name.service // .scope),
      total:   ([ .pointlist[][1] | select(. != null) ] | add // 0)
    }
  ] | sort_by(-.total) | to_entries[] |
  "\(.key + 1)     \(.value.service)                                    \(.value.total | floor)"
' | head -n "$TOP" | awk '{
  rank    = $1
  errors  = $NF
  service = ""
  for (i = 2; i < NF; i++) service = service (i > 2 ? " " : "") $i
  printf "%-5s %-36s %s\n", rank, service, errors
}'
