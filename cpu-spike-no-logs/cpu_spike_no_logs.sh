#!/usr/bin/env bash
# Detects CPU spikes that occurred without corresponding log activity.
# Correlates high CPU periods against log presence to surface silent failures.
# Uses the Datadog Metrics API (v1) and Logs Search API (v2).
#
# Usage:
#   ./cpu_spike_no_logs.sh --service <name> [--env <env>] [--window <minutes>] [--threshold <pct>]
#
# Examples:
#   ./cpu_spike_no_logs.sh --service payments
#   ./cpu_spike_no_logs.sh --service payments --env production --threshold 80
#   ./cpu_spike_no_logs.sh --service payments --env production --window 60 --threshold 70
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
SERVICE=""
ENV=""
WINDOW=60
THRESHOLD=85

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
    --service)   SERVICE="$2";   shift 2 ;;
    --env)       ENV="$2";       shift 2 ;;
    --window)    WINDOW="$2";    shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
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
[[ "$WINDOW"    =~ ^[0-9]+$ ]] || die "--window must be a positive integer."
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || die "--threshold must be a positive integer."

HEADERS=(-H "DD-API-KEY: ${DD_API_KEY}" -H "DD-APPLICATION-KEY: ${DD_APP_KEY}")

# ── build filter ──────────────────────────────────────────────────────────────
FILTER="service:${SERVICE}"
[[ -n "$ENV" ]] && FILTER="${FILTER},env:${ENV}"

TO=$(date +%s)
FROM=$(( TO - WINDOW * 60 ))
FROM_ISO=$(date -u -d "@${FROM}" +"%Y-%m-%dT%H:%M:%SZ")
TO_ISO=$(date -u -d "@${TO}"   +"%Y-%m-%dT%H:%M:%SZ")

echo "Service:    ${SERVICE}"
echo "Env:        ${ENV:-all}"
echo "Window:     last ${WINDOW} minute(s)"
echo "CPU thresh: ${THRESHOLD}%"
echo ""

# ── fetch CPU metrics ─────────────────────────────────────────────────────────
echo "Fetching CPU metrics..."

CPU_RESPONSE=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/query?query=$(jq -rn --arg q "avg:system.cpu.user{${FILTER}}" '$q | @uri')&from=${FROM}&to=${TO}") \
  || die "Metrics API request failed."

# extract spike intervals (consecutive points above threshold, grouped into 5-min buckets)
SPIKE_WINDOWS=$(echo "$CPU_RESPONSE" | jq -r \
  --argjson threshold "$THRESHOLD" '
  [.series[0].pointlist // [] |
    .[] | select(.[1] != null and .[1] >= $threshold) |
    (.[0] / 1000 | floor)          # epoch seconds
  ] |
  # group into 5-minute buckets
  group_by(. / 300 | floor) |
  map({ from: (min - 60), to: (max + 60) })[] |
  "\(.from) \(.to)"
')

if [[ -z "$SPIKE_WINDOWS" ]]; then
  echo "No CPU spikes above ${THRESHOLD}% found in the last ${WINDOW} minute(s)."
  exit 0
fi

SPIKE_COUNT=$(echo "$SPIKE_WINDOWS" | wc -l)
echo "CPU spikes detected: ${SPIKE_COUNT}"
echo ""

# ── check logs for each spike window ─────────────────────────────────────────
LOG_QUERY="service:${SERVICE}"
[[ -n "$ENV" ]] && LOG_QUERY="${LOG_QUERY} env:${ENV}"

SPIKES_WITHOUT_LOGS=0

echo "Spike                         Logs?"
echo "────────────────────────────  ─────"

while IFS=' ' read -r SPIKE_FROM SPIKE_TO; do
  SPIKE_FROM_ISO=$(date -u -d "@${SPIKE_FROM}" +"%Y-%m-%dT%H:%M:%SZ")
  SPIKE_TO_ISO=$(date -u -d "@${SPIKE_TO}"   +"%Y-%m-%dT%H:%M:%SZ")

  LOG_PAYLOAD=$(jq -n \
    --arg query "$LOG_QUERY" \
    --arg from  "$SPIKE_FROM_ISO" \
    --arg to    "$SPIKE_TO_ISO" \
    '{ filter: { query: $query, from: $from, to: $to }, page: { limit: 1 } }')

  LOG_RESP=$(curl -sf \
    -X POST "https://api.${DD_SITE}/api/v2/logs/events/search" \
    -H "Content-Type: application/json" \
    "${HEADERS[@]}" \
    -d "$LOG_PAYLOAD") || { echo "  WARNING: log API request failed for ${SPIKE_FROM_ISO}"; continue; }

  LOG_COUNT=$(echo "$LOG_RESP" | jq '.data | length')
  LABEL="${SPIKE_FROM_ISO} → ${SPIKE_TO_ISO}"

  if [[ "$LOG_COUNT" -eq 0 ]]; then
    printf "%-30s  NO LOGS -- possible silent crash or OOM\n" "${SPIKE_FROM_ISO}"
    SPIKES_WITHOUT_LOGS=$(( SPIKES_WITHOUT_LOGS + 1 ))
  else
    printf "%-30s  OK\n" "${SPIKE_FROM_ISO}"
  fi
done <<< "$SPIKE_WINDOWS"

echo ""
if [[ "$SPIKES_WITHOUT_LOGS" -gt 0 ]]; then
  echo "WARNING: ${SPIKES_WITHOUT_LOGS} spike(s) had no log activity — investigate for silent failures."
  exit 1
else
  echo "All CPU spikes had corresponding log activity."
fi
