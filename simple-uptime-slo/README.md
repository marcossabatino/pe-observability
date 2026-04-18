# simple-uptime-slo

Calculates uptime SLO percentage for a Datadog monitor over a given period.
Reports uptime %, downtime duration, remaining error budget, and whether the SLO target was met.

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
chmod +x simple_uptime_slo.sh

# 30-day uptime with 99.9% target (defaults)
./simple_uptime_slo.sh --monitor 12345678

# 7-day window with custom target
./simple_uptime_slo.sh --monitor 12345678 --days 7 --target 99.5

# 90-day SLO review
./simple_uptime_slo.sh --monitor 12345678 --days 90 --target 99.9
```

## Output

```
Monitor:        Payments API - Health Check (ID: 12345678)
Period:         last 30 day(s)
Target SLO:     99.9%

Uptime:         99.94%
Downtime:       0.3h (18 min)
Error budget:   25 min remaining

STATUS: PASS -- SLO target met.
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--monitor` | *(required)* | Datadog monitor ID |
| `--days` | `30` | Lookback period in days |
| `--target` | `99.9` | SLO target percentage |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | SLO target met |
| `1` | SLO target breached |

## API reference

- [Datadog Monitors API v1](https://docs.datadoghq.com/api/latest/monitors/)
- [Datadog Downtimes API v1](https://docs.datadoghq.com/api/latest/downtimes/)
