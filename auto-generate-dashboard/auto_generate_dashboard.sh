#!/usr/bin/env bash
# Auto-generates a Datadog APM dashboard for a given service.
# Creates widgets for: throughput, error rate, p95 latency, and CPU usage.
# Uses the Datadog Dashboards API (v1).
#
# Usage:
#   ./auto_generate_dashboard.sh --service <name> [--env <env>] [--title <title>]
#
# Examples:
#   ./auto_generate_dashboard.sh --service payments
#   ./auto_generate_dashboard.sh --service payments --env production
#   ./auto_generate_dashboard.sh --service checkout --env production --title "Checkout SLO Board"
#
# Dependencies: curl, jq
# Env vars: DD_API_KEY, DD_APP_KEY, DD_SITE (default: datadoghq.com)

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
DD_SITE="${DD_SITE:-datadoghq.com}"
SERVICE=""
ENV=""
TITLE=""

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
    --service) SERVICE="$2"; shift 2 ;;
    --env)     ENV="$2";     shift 2 ;;
    --title)   TITLE="$2";   shift 2 ;;
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

# ── build filters ─────────────────────────────────────────────────────────────
FILTER="service:${SERVICE}"
[[ -n "$ENV" ]] && FILTER="${FILTER},env:${ENV}"

[[ -z "$TITLE" ]] && TITLE="${SERVICE}${ENV:+ (${ENV})} — APM Overview"

# ── build dashboard payload ───────────────────────────────────────────────────
PAYLOAD=$(jq -n \
  --arg title   "$TITLE" \
  --arg service "$SERVICE" \
  --arg filter  "$FILTER" \
'{
  title:        $title,
  description:  ("Auto-generated APM dashboard for " + $service),
  layout_type:  "ordered",
  reflow_type:  "fixed",
  widgets: [
    {
      definition: {
        type:  "timeseries",
        title: "Throughput (req/s)",
        requests: [{
          q:           ("sum:trace.http.request.hits{" + $filter + "}.as_rate()"),
          display_type: "line"
        }]
      }
    },
    {
      definition: {
        type:  "timeseries",
        title: "Error Rate (%)",
        requests: [{
          q:           ("100 * sum:trace.http.request.errors{" + $filter + "}.as_rate() / sum:trace.http.request.hits{" + $filter + "}.as_rate()"),
          display_type: "line"
        }]
      }
    },
    {
      definition: {
        type:  "timeseries",
        title: "p95 Latency (ms)",
        requests: [{
          q:           ("p95:trace.http.request{" + $filter + "} * 1000"),
          display_type: "line"
        }]
      }
    },
    {
      definition: {
        type:  "timeseries",
        title: "CPU Usage (%)",
        requests: [{
          q:           ("avg:system.cpu.user{" + $filter + "}"),
          display_type: "line"
        }]
      }
    }
  ]
}')

# ── create dashboard ──────────────────────────────────────────────────────────
echo "Creating dashboard: ${TITLE}"

RESPONSE=$(curl -sf \
  -X POST "https://api.${DD_SITE}/api/v1/dashboard" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
  -d "$PAYLOAD") \
  || die "Dashboard API request failed."

DASH_ID=$(echo "$RESPONSE" | jq -r '.id')
DASH_URL=$(echo "$RESPONSE" | jq -r '.url')

echo ""
echo "Dashboard created successfully!"
echo "ID:  ${DASH_ID}"
echo "URL: https://app.${DD_SITE}${DASH_URL}"
