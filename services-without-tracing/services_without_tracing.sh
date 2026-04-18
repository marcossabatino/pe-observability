#!/usr/bin/env bash
# Detects services that are running but not sending APM traces to Datadog.
# Compares infrastructure services (via host tags) against active APM services.
# Uses the Datadog Metrics API (v1) and Infrastructure API (v1).
#
# Usage:
#   ./services_without_tracing.sh [--env <env>] [--window <minutes>]
#
# Examples:
#   ./services_without_tracing.sh
#   ./services_without_tracing.sh --env production
#   ./services_without_tracing.sh --env production --window 30
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

# ── fetch services from infrastructure host tags ──────────────────────────────
echo "Fetching infrastructure services from host tags..."

HOST_FILTER="*"
[[ -n "$ENV" ]] && HOST_FILTER="env:${ENV}"

HOSTS_RESPONSE=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/hosts?filter=${HOST_FILTER}&count=1000") \
  || die "Hosts API request failed."

INFRA_SERVICES=$(echo "$HOSTS_RESPONSE" | jq -r '
  [.host_list[].tags_by_source // {} |
    to_entries[].value[] |
    select(startswith("service:")) |
    ltrimstr("service:")
  ] | unique | sort | .[]
')

if [[ -z "$INFRA_SERVICES" ]]; then
  echo "No services found in infrastructure host tags."
  echo "Tip: ensure hosts are tagged with service:<name>."
  exit 0
fi

INFRA_COUNT=$(echo "$INFRA_SERVICES" | wc -l)
echo "Infrastructure services found: ${INFRA_COUNT}"

# ── fetch active APM services ─────────────────────────────────────────────────
echo "Fetching active APM services (last ${WINDOW} min)..."

APM_FILTER="*"
[[ -n "$ENV" ]] && APM_FILTER="env:${ENV}"

TO=$(date +%s)
FROM=$(( TO - WINDOW * 60 ))

METRICS_RESPONSE=$(curl -sf \
  "${HEADERS[@]}" \
  "https://api.${DD_SITE}/api/v1/query?query=$(jq -rn --arg q "sum:trace.http.request.hits{${APM_FILTER}} by {service}" '$q | @uri')&from=${FROM}&to=${TO}") \
  || die "Metrics API request failed."

APM_SERVICES=$(echo "$METRICS_RESPONSE" | jq -r '
  [.series[].tags_by_name.service // empty] | unique | sort | .[]
')

APM_COUNT=$(echo "$APM_SERVICES" | grep -c . || true)
echo "Active APM services found:      ${APM_COUNT}"
echo ""

# ── compare ───────────────────────────────────────────────────────────────────
WITHOUT_TRACING=$(comm -23 \
  <(echo "$INFRA_SERVICES") \
  <(echo "$APM_SERVICES" | sort))

if [[ -z "$WITHOUT_TRACING" ]]; then
  echo "All infrastructure services are sending APM traces. Good instrumentation!"
  exit 0
fi

COUNT=$(echo "$WITHOUT_TRACING" | wc -l)
echo "Services WITHOUT APM tracing (${COUNT}):"
echo "──────────────────────────────────────"
echo "$WITHOUT_TRACING" | while read -r svc; do
  echo "  - ${svc}"
done
echo ""
echo "Tip: instrument these services with a Datadog APM tracer."
echo "     https://docs.datadoghq.com/tracing/setup_overview/"
