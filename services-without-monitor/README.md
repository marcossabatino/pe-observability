# services-without-monitor

Detects APM services that have no Datadog monitor associated with them.
Compares active services (via APM metrics) against monitor query coverage to find gaps in alerting.

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
chmod +x services_without_monitor.sh

# check all environments
./services_without_monitor.sh

# filter by environment
./services_without_monitor.sh --env production

# custom window for APM activity detection
./services_without_monitor.sh --env production --window 30
```

## Output

```
Fetching active APM services (last 60 min)...
Active APM services found: 12
Fetching monitors...
Total monitors: 47

Services WITHOUT a monitor (3):
──────────────────────────────────────
  - billing
  - notification-worker
  - data-exporter
```

## How it works

1. Queries `trace.http.request.hits` grouped by `service` to list active APM services
2. Fetches all monitors and scans their queries, tags, and messages for `service:<name>` references
3. Reports services present in APM but absent from any monitor

## Options

| Flag | Default | Description |
|---|---|---|
| `--env` | *(all)* | Filter by Datadog environment tag |
| `--window` | `60` | Time window in minutes for APM service detection |

## API reference

- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points)
- [Datadog Monitors API v1](https://docs.datadoghq.com/api/latest/monitors/#get-all-monitor-details)
