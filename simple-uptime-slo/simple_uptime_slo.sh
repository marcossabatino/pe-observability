#!/usr/bin/env bash
# Calculates uptime SLO percentage for a Datadog monitor over a given period.
# Reports uptime %, downtime duration, and SLO breach status against a target.
# Uses the Datadog SLO History API (v1).
#
# Usage:
#   ./simple_uptime_slo.sh --monitor <id> [--days <n>] [--target <pct>]
#
# Examples:
#   ./simple_uptime_slo.sh --monitor 12345678
#   ./simple_uptime_slo.sh --monitor 12345678 --days 30 --target 99.9
#   ./simple_uptime_slo.sh --monitor 12345678 --days 7  --target 99.5
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
MONITOR_ID=""
DAYS=30
TARGET=99.9

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
    --monitor) MONITOR_ID="$2"; shift 2 ;;
    --days)    DAYS="$2";       shift 2 ;;
    --target)  TARGET="$2";     shift 2 ;;
    --help|-h) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
require curl
require jq

[[ -z "${DD_API_KEY:-}" ]] && die "DD_API_KEY is not set."
[[ -z "${DD_APP_KEY:-}" ]] && die "DD_APP_KEY is not set."
[[ -z "$MONITOR_ID" ]]     && die "--monitor is required."
[[ "$DAYS" =~ ^[0-9]+$ ]]  || die "--days must be a positive integer."

HEADERS=(-H "DD-API-KEY: ${DD_API_KEY}" -H "DD-APPLICATION-KEY: ${DD_APP_KEY}")

# ── fetch monitor details ─────────────────────────────────────────────────────
MONITOR=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/monitor/${MONITOR_ID}") \
  || die "Monitor API request failed. Check if monitor ID ${MONITOR_ID} exists."

MONITOR_NAME=$(echo "$MONITOR" | jq -r '.name')

# ── fetch monitor downtime history ────────────────────────────────────────────
TO=$(date +%s)
FROM=$(( TO - DAYS * 86400 ))

DOWNTIME_RESP=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/downtime?monitor_id=${MONITOR_ID}") \
  || die "Downtime API request failed."

# sum downtime seconds that fall within the window
DOWNTIME_SECS=$(echo "$DOWNTIME_RESP" | jq --argjson from "$FROM" --argjson to "$TO" '
  [.[] |
    select(.disabled == false or .disabled == null) |
    {
      start: ([.start, $from] | max),
      end:   (if .end != null then ([.end, $to] | min) else $to end)
    } |
    select(.end > .start) |
    (.end - .start)
  ] | add // 0
')

TOTAL_SECS=$(( DAYS * 86400 ))

# ── calculate uptime % ────────────────────────────────────────────────────────
UPTIME_PCT=$(jq -rn \
  --argjson total "$TOTAL_SECS" \
  --argjson down  "$DOWNTIME_SECS" \
  '(($total - $down) / $total * 100) | (. * 100 | round) / 100')

DOWNTIME_MIN=$(( DOWNTIME_SECS / 60 ))
DOWNTIME_HRS=$(jq -rn --argjson s "$DOWNTIME_SECS" '$s / 3600 | (. * 10 | round) / 10')

# ── determine SLO status ──────────────────────────────────────────────────────
SLO_STATUS=$(jq -rn \
  --argjson uptime "$UPTIME_PCT" \
  --argjson target "$TARGET" \
  'if $uptime >= $target then "PASS" else "BREACH" end')

# ── error budget ─────────────────────────────────────────────────────────────
BUDGET_SECS=$(jq -rn \
  --argjson total  "$TOTAL_SECS" \
  --argjson target "$TARGET" \
  --argjson down   "$DOWNTIME_SECS" \
  '(($total * (1 - $target / 100)) - $down) | floor')

BUDGET_MIN=$(jq -rn --argjson s "$BUDGET_SECS" '$s / 60 | floor')

# ── report ────────────────────────────────────────────────────────────────────
echo "Monitor:        ${MONITOR_NAME} (ID: ${MONITOR_ID})"
echo "Period:         last ${DAYS} day(s)"
echo "Target SLO:     ${TARGET}%"
echo ""
echo "Uptime:         ${UPTIME_PCT}%"
echo "Downtime:       ${DOWNTIME_HRS}h (${DOWNTIME_MIN} min)"
echo "Error budget:   ${BUDGET_MIN} min remaining"
echo ""

if [[ "$SLO_STATUS" == "PASS" ]]; then
  echo "STATUS: PASS -- SLO target met."
else
  echo "STATUS: BREACH -- SLO target NOT met."
  exit 1
fi
