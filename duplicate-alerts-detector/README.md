# duplicate-alerts-detector

Detects duplicate Datadog monitors sharing the same query or the same name.
Helps reduce alert fatigue and monitor sprawl in large environments.

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
chmod +x duplicate_alerts_detector.sh

# check all monitors
./duplicate_alerts_detector.sh

# filter by tags
./duplicate_alerts_detector.sh --tags team:payments,env:production

# filter by monitor type
./duplicate_alerts_detector.sh --type "metric alert"
```

## Output

```
Fetching monitors...
Total monitors fetched: 142

=== Duplicate queries (same query, different monitors) ===
  Query: avg(last_5m):avg:system.cpu.user{env:production} > 90
    [12345] CPU High - Production (Legacy)
    [67890] CPU High - Production

=== Duplicate names (same name, different monitor IDs) ===
  Name: High Error Rate - payments
    [11111] query: sum(last_5m):sum:trace.http.request.errors{service:payments}.as_count() > 100
    [22222] query: sum(last_5m):sum:trace.http.request.errors{service:payments}.as_count() > 50
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--tags` | *(all)* | Filter monitors by tags (comma-separated) |
| `--type` | *(all)* | Filter by monitor type (e.g. `metric alert`, `log alert`) |

## Monitor types

`metric alert`, `service check`, `event alert`, `query alert`, `composite`, `log alert`, `apm alert`, `synthetics alert`

## API reference

- [Datadog Monitors API v1](https://docs.datadoghq.com/api/latest/monitors/#get-all-monitor-details)
