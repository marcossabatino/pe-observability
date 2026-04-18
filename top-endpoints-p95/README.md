# top-endpoints-p95

Lists the top N endpoints by p95 latency over a given time window.
Useful for performance triage, SLO reviews, and identifying slow outliers before they become incidents.

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
chmod +x top_endpoints_p95.sh

# top 5 slowest endpoints across all services (last 60 minutes)
./top_endpoints_p95.sh

# production only, last 30 minutes, top 10
./top_endpoints_p95.sh --env production --window 30 --top 10

# scoped to a single service
./top_endpoints_p95.sh --service payments --env production
```

## Output

```
Window:   last 60 minute(s)
Env:      production
Service:  all
Top:      5

Rank  Service              Endpoint                         p95 (ms)
────  ───────────────────  ───────────────────────────────  ────────
1     checkout             POST /v1/orders                  4312
2     payments             POST /v1/charge                  1893
3     user-api             GET /v1/profile/{id}             741
4     cart                 PUT /v1/cart/items               228
5     inventory            GET /v1/stock                    95
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--service` | *(all)* | Filter by service name |
| `--env` | *(all)* | Filter by Datadog environment tag |
| `--window` | `60` | Time window in minutes |
| `--top` | `5` | Number of endpoints to display |

## API reference

- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-points)
- Metric used: `p95:trace.http.request` grouped by `resource_name` and `service`
