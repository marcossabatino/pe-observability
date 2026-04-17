# pe-observability

A collection of small, self-contained Bash scripts for Datadog observability tasks — built for SRE and DevOps day-to-day operations.

## Requirements

- `curl`
- `jq`

## Configuration

```bash
export DD_API_KEY="..."
export DD_APP_KEY="..."
export DD_SITE="datadoghq.com"
```

Or copy `.env.example` to `.env` and source it:

```bash
cp .env.example .env
source .env
```

## Scripts

| Script | Description |
|---|---|
| [metrics-to-csv](./metrics-to-csv/) | Export metric query results to CSV for offline analysis |
| no-logs-detector | Detect services with no logs in the last N minutes |
| top-5xx-services | List top 10 services by 5xx error count |
| top-endpoints-p95 | List top endpoints by p95 latency |
| duplicate-alerts-detector | Find monitors with duplicate alert conditions |
| services-without-monitor | List services with no active monitor |
| services-without-tracing | List services with no active tracing |
| simple-uptime-slo | Calculate simple uptime SLO from metrics |
| auto-generate-dashboard | Auto-generate a Datadog dashboard via API |
| cpu-spike-no-logs | Detect CPU spikes with no corresponding logs (anti-pattern) |
