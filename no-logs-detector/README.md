# no-logs-detector

Detects services with no logs ingested in the last N minutes.
Useful for on-call checks, log pipeline health, and silent failure detection.

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
chmod +x no_logs_detector.sh

# basic check (last 5 minutes)
./no_logs_detector.sh --service payments

# specific env and window
./no_logs_detector.sh --service payments --env production --window 10
```

## Output

```
Service:  payments
Env:      production
Window:   last 5 minute(s)
From:     2024-11-14T18:00:00Z
To:       2024-11-14T18:05:00Z

STATUS: NO LOGS FOUND -- possible log pipeline issue or silent service.
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Logs found — service is healthy |
| `1` | No logs found — alert condition |
| `2` | Script or API error |

The exit codes make this script easy to integrate with monitoring tools, cron jobs, or CI pipelines:

```bash
./no_logs_detector.sh --service payments --env production || pagerduty-alert.sh
```

## API reference

- [Datadog Logs Search API v2](https://docs.datadoghq.com/api/latest/logs/#search-logs)
