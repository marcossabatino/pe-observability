#!/usr/bin/env bash
# Detects APM services that have no Datadog monitor associated with them.
# Compares active services (via APM metrics) against monitor query coverage.
# Uses the Datadog Metrics API (v1) and Monitors API (v1).
#
# Usage:
#   ./services_without_monitor.sh [--env <env>] [--window <minutes>]
#
# Examples:
#   ./services_without_monitor.sh
#   ./services_without_monitor.sh --env production
#   ./services_without_monitor.sh --env production --window 30
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
ENV=""
WINDOW=60

# ── helpers ───────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
  exit 0
}

die()     { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" &>/dev/null || die "'$1' is required but not installed."; }

# ── parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)    ENV="$2";    shift 2 ;;
    --window) WINDOW="$2"; shift 2 ;;
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

HEADERS=(-H "DD-API-KEY: ${DD_API_KEY}" -H "DD-APPLICATION-KEY: ${DD_APP_KEY}")

# ── fetch active APM services via metrics ─────────────────────────────────────
FILTER="*"
[[ -n "$ENV" ]] && FILTER="env:${ENV}"

TO=$(date +%s)
FROM=$(( TO - WINDOW * 60 ))

echo "Fetching active APM services (last ${WINDOW} min)..."

METRICS_RESPONSE=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/query?query=$(jq -rn --arg q "sum:trace.http.request.hits{${FILTER}} by {service}" '$q | @uri')&from=${FROM}&to=${TO}") \
  || die "Metrics API request failed."

APM_SERVICES=$(echo "$METRICS_RESPONSE" | jq -r '
  [.series[].tags_by_name.service // empty] | unique | sort | .[]
')

if [[ -z "$APM_SERVICES" ]]; then
  echo "No active APM services found for the given window/env."
  exit 0
fi

SERVICE_COUNT=$(echo "$APM_SERVICES" | wc -l)
echo "Active APM services found: ${SERVICE_COUNT}"

# ── fetch all monitors ────────────────────────────────────────────────────────
echo "Fetching monitors..."

PAGE=0
PAGE_SIZE=200
ALL_MONITORS="[]"

while true; do
  RESP=$(curl -sf \
    "${HEADERS[@]}" \
    "https://api.${DD_SITE}/api/v1/monitors?page=${PAGE}&page_size=${PAGE_SIZE}") \
    || die "Monitors API request failed."
  COUNT=$(echo "$RESP" | jq 'length')
  [[ "$COUNT" -eq 0 ]] && break
  ALL_MONITORS=$(echo "$ALL_MONITORS $RESP" | jq -s 'add')
  [[ "$COUNT" -lt "$PAGE_SIZE" ]] && break
  PAGE=$(( PAGE + 1 ))
done

echo "Total monitors: $(echo "$ALL_MONITORS" | jq 'length')"
echo ""

# ── extract services referenced in monitors ───────────────────────────────────
# looks for service:<name> in query, tags, and message fields
MONITORED_SERVICES=$(echo "$ALL_MONITORS" | jq -r '
  [.[] |
    ((.query // "") + " " + ((.tags // []) | join(" ")) + " " + (.message // "")) |
    scan("service:([a-zA-Z0-9_-]+)") | .[0]
  ] | unique | sort | .[]
')

# ── compare ───────────────────────────────────────────────────────────────────
UNMONITORED=$(comm -23 \
  <(echo "$APM_SERVICES") \
  <(echo "$MONITORED_SERVICES" | sort))

if [[ -z "$UNMONITORED" ]]; then
  echo "All active APM services have at least one monitor. Good coverage!"
  exit 0
fi

UNMONITORED_COUNT=$(echo "$UNMONITORED" | wc -l)
echo "Services WITHOUT a monitor (${UNMONITORED_COUNT}):"
echo "──────────────────────────────────────"
echo "$UNMONITORED" | while read -r svc; do
  echo "  - ${svc}"
done
