# top-5xx-services

Lists the top N services by 5xx error count over a given time window.
Useful for incident triage, SLO breach investigation, and release health checks.

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
chmod +x top_5xx_services.sh

# top 5 services with 5xx errors in the last 60 minutes (all envs)
./top_5xx_services.sh

# production only, last 30 minutes, top 10
./top_5xx_services.sh --env production --window 30 --top 10

# staging, last 15 minutes
./top_5xx_services.sh --env staging --window 15
```

## Output

```
Window:   last 60 minute(s)
Env:      production
Top:      5

Rank  Service                              5xx Errors
────  ───────────────────────────────────  ──────────
1     checkout                             4312
2     payments                             1893
3     user-api                             741
4     cart                                 228
5     inventory                            95
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--env` | *(all)* | Filter by Datadog environment tag |
| `--window` | `60` | Time window in minutes |
| `--top` | `5` | Number of services to display |

## API reference

- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points)
- Metric used: `trace.http.request.errors` filtered by `http.status_class:5xx`
