# auto-generate-dashboard

Auto-generates a Datadog APM dashboard for a given service.
Creates a ready-to-use board with throughput, error rate, p95 latency, and CPU usage widgets.

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
chmod +x auto_generate_dashboard.sh

# generate dashboard for a service
./auto_generate_dashboard.sh --service payments

# scoped to a specific environment
./auto_generate_dashboard.sh --service payments --env production

# custom dashboard title
./auto_generate_dashboard.sh --service checkout --env production --title "Checkout SLO Board"
```

## Output

```
Creating dashboard: payments (production) — APM Overview

Dashboard created successfully!
ID:  abc-123-def
URL: https://app.datadoghq.com/dashboard/abc-123-def
```

## Widgets included

| Widget | Metric |
|---|---|
| Throughput (req/s) | `trace.http.request.hits` |
| Error Rate (%) | `trace.http.request.errors / trace.http.request.hits` |
| p95 Latency (ms) | `p95:trace.http.request` |
| CPU Usage (%) | `system.cpu.user` |

## Options

| Flag | Default | Description |
|---|---|---|
| `--service` | *(required)* | Service name to generate the dashboard for |
| `--env` | *(all)* | Filter widgets by Datadog environment tag |
| `--title` | auto-generated | Custom dashboard title |

## API reference

- [Datadog Dashboards API v1](https://docs.datadoghq.com/api/latest/dashboards/#create-a-new-dashboard)
