# cpu-spike-no-logs

Detects CPU spikes that occurred without corresponding log activity.
Correlates high CPU periods against log presence to surface silent failures, OOM kills, or zombie processes.

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
chmod +x cpu_spike_no_logs.sh

# check last 60 minutes with default 85% CPU threshold
./cpu_spike_no_logs.sh --service payments

# custom threshold and window
./cpu_spike_no_logs.sh --service payments --env production --threshold 80 --window 120

# staging check
./cpu_spike_no_logs.sh --service checkout --env staging --threshold 70
```

## Output

```
Service:    payments
Env:        production
Window:     last 60 minute(s)
CPU thresh: 85%

Fetching CPU metrics...
CPU spikes detected: 2

Spike                         Logs?
────────────────────────────  ─────
2024-11-14T18:02:00Z          NO LOGS -- possible silent crash or OOM
2024-11-14T18:45:00Z          OK

WARNING: 1 spike(s) had no log activity — investigate for silent failures.
```

## How it works

1. Queries `avg:system.cpu.user` for the service over the window
2. Identifies time buckets where CPU exceeded the threshold
3. For each spike bucket, queries the Logs API for any activity
4. Reports spikes with no corresponding logs as potential silent failures

## Options

| Flag | Default | Description |
|---|---|---|
| `--service` | *(required)* | Service name to investigate |
| `--env` | *(all)* | Filter by Datadog environment tag |
| `--window` | `60` | Time window in minutes |
| `--threshold` | `85` | CPU percentage to consider a spike |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All spikes had log activity (or no spikes found) |
| `1` | At least one spike had no log activity |

## API reference

- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points)
- [Datadog Logs Search API v2](https://docs.datadoghq.com/api/latest/logs/#search-logs)
