#!/usr/bin/env bash
# Detects duplicate Datadog monitors sharing the same query or name.
# Helps reduce alert fatigue and monitor sprawl in large environments.
# Uses the Datadog Monitors API (v1).
#
# Usage:
#   ./duplicate_alerts_detector.sh [--tags <tag1,tag2>] [--type <monitor_type>]
#
# Examples:
#   ./duplicate_alerts_detector.sh
#   ./duplicate_alerts_detector.sh --tags team:payments,env:production
#   ./duplicate_alerts_detector.sh --type metric alert
#
# Monitor types: metric alert, service check, event alert, query alert,
#                composite, log alert, apm alert, synthetics alert
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
TAGS=""
TYPE=""

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
    --tags) TAGS="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
require curl
require jq

[[ -z "${DD_API_KEY:-}" ]] && die "DD_API_KEY is not set."
[[ -z "${DD_APP_KEY:-}" ]] && die "DD_APP_KEY is not set."

# ── build query string ────────────────────────────────────────────────────────
PARAMS=""
[[ -n "$TAGS" ]] && PARAMS="${PARAMS}&monitor_tags=$(jq -rn --arg t "$TAGS" '$t | @uri')"
[[ -n "$TYPE" ]] && PARAMS="${PARAMS}&type=$(jq -rn --arg t "$TYPE" '$t | @uri')"

# ── fetch monitors (paginated) ────────────────────────────────────────────────
BASE_URL="https://api.${DD_SITE}/api/v1/monitors"
PAGE=0
PAGE_SIZE=200
ALL_MONITORS="[]"

echo "Fetching monitors..."

while true; do
  RESPONSE=$(curl -sf \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
    "${BASE_URL}?page=${PAGE}&page_size=${PAGE_SIZE}${PARAMS}") \
    || die "API request failed."

  COUNT=$(echo "$RESPONSE" | jq 'length')
  [[ "$COUNT" -eq 0 ]] && break

  ALL_MONITORS=$(echo "$ALL_MONITORS $RESPONSE" | jq -s 'add')
  [[ "$COUNT" -lt "$PAGE_SIZE" ]] && break
  PAGE=$(( PAGE + 1 ))
done

TOTAL=$(echo "$ALL_MONITORS" | jq 'length')
echo "Total monitors fetched: ${TOTAL}"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  echo "No monitors found."
  exit 0
fi

# ── detect duplicates by query ────────────────────────────────────────────────
DUP_QUERY=$(echo "$ALL_MONITORS" | jq -r '
  group_by(.query) |
  map(select(length > 1)) |
  .[] |
  "  Query: \(.[0].query)\n" +
  (map("    [" + (.id | tostring) + "] " + .name) | join("\n"))
')

# ── detect duplicates by name ─────────────────────────────────────────────────
DUP_NAME=$(echo "$ALL_MONITORS" | jq -r '
  group_by(.name) |
  map(select(length > 1)) |
  .[] |
  "  Name: \(.[0].name)\n" +
  (map("    [" + (.id | tostring) + "] query: " + .query) | join("\n"))
')

# ── report ────────────────────────────────────────────────────────────────────
FOUND=0

if [[ -n "$DUP_QUERY" ]]; then
  FOUND=1
  echo "=== Duplicate queries (same query, different monitors) ==="
  echo "$DUP_QUERY"
  echo ""
fi

if [[ -n "$DUP_NAME" ]]; then
  FOUND=1
  echo "=== Duplicate names (same name, different monitor IDs) ==="
  echo "$DUP_NAME"
  echo ""
fi

if [[ "$FOUND" -eq 0 ]]; then
  echo "No duplicate monitors found."
fi
