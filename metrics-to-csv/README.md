# metrics-to-csv

Exports a Datadog metric query result to a CSV file for offline analysis (Excel, pandas, etc).

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
chmod +x metrics_to_csv.sh

./metrics_to_csv.sh \
  --query "avg:system.cpu.user{*}" \
  --from 1700000000 \
  --to   1700003600 \
  --output cpu.csv
```

### Get epoch timestamps quickly

```bash
# last 1 hour
FROM=$(date -d '1 hour ago' +%s)
TO=$(date +%s)

./metrics_to_csv.sh --query "avg:system.cpu.user{*}" --from $FROM --to $TO
```

## Output

```
timestamp,value,metric,scope
2024-11-14T18:00:00Z,42.3,system.cpu.user,host:web-01
2024-11-14T18:01:00Z,43.1,system.cpu.user,host:web-01
...
```

## API reference

- [Datadog Metrics Query API v1](https://docs.datadoghq.com/api/latest/metrics/#query-timeseries-data-across-multiple-products)
