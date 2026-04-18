# services-without-tracing

Detects services that are running (present in infrastructure host tags) but not sending APM traces to Datadog.
Useful for finding uninstrumented services before incidents reveal the blind spot.

## Dependencies

- `curl`
- `jq`

## Environment variables

```bash
export DD_API_KEY="..."
export DD_APP_KEY="..."
export DD_SITE="datadoghq.com"   # optional, default: datadoghq.com
```

## Usage

```bash
chmod +x services_without_tracing.sh

# check all environments
./services_without_tracing.sh

# filter by environment
./services_without_tracing.sh --env production

# custom activity window
./services_without_tracing.sh --env production --window 30
```

## Output

```
Fetching infrastructure services from host tags...
Infrastructure services found: 15
Fetching active APM services (last 60 min)...
Active APM services found:      11

Services WITHOUT APM tracing (4):
──────────────────────────────────────
  - legacy-importer
  - cron-worker
  - pdf-generator
  - smtp-relay

Tip: instrument these services with a Datadog APM tracer.
     https://docs.datadoghq.com/tracing/setup_overview/
```

## How it works

1. Fetches all active hosts and extracts `service:<name>` tags
2. Queries `trace.http.request.hits` to list services actively sending APM traces
3. Reports services found in infrastructure but absent from APM

## Options

| Flag | Default | Description |
|---|---|---|
| `--env` | *(all)* | Filter by Datadog environment tag |
| `--window` | `60` | Time window in minutes for APM trace detection |

> **Note:** requires hosts to be tagged with `service:<name>`. Untagged hosts are not included in the comparison.

## API reference

- [Datadog Hosts API v1](https://docs.datadoghq.com/api/latest/hosts/#get-all-hosts-for-your-organization)
- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points)
