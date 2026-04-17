#!/usr/bin/env bash
# Detects services with no logs ingested in the last N minutes.
# Useful for on-call checks and log pipeline health monitoring.
# Uses the Datadog Logs Search API (v2).
#
# Usage:
#   ./no_logs_detector.sh --service <name> [--env <env>] [--window <minutes>]
#
# Examples:
#   ./no_logs_detector.sh --service payments
#   ./no_logs_detector.sh --service payments --env production --window 10
#   ./no_logs_detector.sh --service payments --env production --window 5
#
# Exit codes:
#   0 - logs found (healthy)
#   1 - no logs found (alert)
#   2 - script/API error
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
WINDOW=5
SERVICE=""
ENV=""

# ── helpers ───────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

die() { echo "ERROR: $*" >&2; exit 2; }

require() {
  command -v "$1" &>/dev/null || die "'$1' is required but not installed."
}

# ── parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --env)     ENV="$2";     shift 2 ;;
    --window)  WINDOW="$2";  shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
require curl
require jq

[[ -z "${DD_API_KEY:-}" ]] && die "DD_API_KEY is not set."
[[ -z "${DD_APP_KEY:-}" ]] && die "DD_APP_KEY is not set."
[[ -z "$SERVICE" ]]        && die "--service is required."

# ── build time range (ISO 8601) ───────────────────────────────────────────────
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FROM=$(date -u -d "${WINDOW} minutes ago" +"%Y-%m-%dT%H:%M:%SZ")

# ── build query filter ────────────────────────────────────────────────────────
QUERY="service:${SERVICE}"
[[ -n "$ENV" ]] && QUERY="${QUERY} env:${ENV}"

# ── call Datadog Logs Search API ──────────────────────────────────────────────
BASE_URL="https://api.${DD_SITE}/api/v2/logs/events/search"

PAYLOAD=$(jq -n \
  --arg query "$QUERY" \
  --arg from   "$FROM" \
  --arg to     "$NOW" \
  '{
    filter: { query: $query, from: $from, to: $to },
    page: { limit: 1 }
  }')

RESPONSE=$(curl -sf \
  -X POST "${BASE_URL}" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  -d "$PAYLOAD") || die "API request failed."

# ── evaluate result ───────────────────────────────────────────────────────────
COUNT=$(echo "$RESPONSE" | jq '.data | length')

echo "Service:  ${SERVICE}"
echo "Env:      ${ENV:-all}"
echo "Window:   last ${WINDOW} minute(s)"
echo "From:     ${FROM}"
echo "To:       ${NOW}"
echo ""

if [[ "$COUNT" -eq 0 ]]; then
  echo "STATUS: NO LOGS FOUND -- possible log pipeline issue or silent service."
  exit 1
else
  echo "STATUS: OK -- logs found in the last ${WINDOW} minute(s)."
  exit 0
fi
