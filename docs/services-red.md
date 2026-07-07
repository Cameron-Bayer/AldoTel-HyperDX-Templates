# AldoTel · Services — RED (Rate / Errors / Duration)

> Auto-generated reference (do not edit by hand — run `node gen-docs.js`).

This page lists the ClickHouse tables and columns behind every visual on the dashboard.

- **Template:** `dashboards/services-red.json` · tag `tmpl:services-red`
- **Data required:** Application traces (OTLP)

## Dashboard filters

These apply to every compatible tile on the dashboard.

| Filter | Column / expression | Source |
|---|---|---|
| Service | `ServiceName` | Traces (`default.otel_traces`) |

## Rate & errors

### Request rate by service — line

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** count(*) as `requests`  — where `SpanKind:Server` (lucene)
- **Group by:** `ServiceName`
- **Columns used:** `ServiceName`, `SpanKind`

### Error rate % — line

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** count(*) as `errors`  — where `SpanKind:Server AND StatusCode:Error` (lucene); count(*) as `total`  — where `SpanKind:Server` (lucene)
- **Columns used:** `StatusCode`, `SpanKind`

## Latency & error breakdown

### Latency p50 / p95 / p99 — line

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** quantile(`Duration`) as `p50`  — where `SpanKind:Server` (lucene); quantile(`Duration`) as `p95`  — where `SpanKind:Server` (lucene); quantile(`Duration`) as `p99`  — where `SpanKind:Server` (lucene)
- **Columns used:** `Duration`, `SpanKind`

### Errors by status message — pie

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** count(*) as `errors`  — where `StatusCode:Error` (lucene)
- **Group by:** `StatusMessage`
- **Columns used:** `StatusCode`, `StatusMessage`

## Slow routes & distribution

### Slowest routes (p95) — table

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** quantile(`Duration`) as `p95`  — where `SpanKind:Server` (lucene); count(*) as `requests`  — where `SpanKind:Server` (lucene)
- **Group by:** `SpanAttributes['http.route']`
- **Order by:** `p95 DESC`
- **Drill-down:** click a row → opens search
- **Columns used:** `SpanAttributes['http.route']`, `Duration`, `SpanKind`

### Latency anomaly — p95 vs 7-day baseline (z-score) — line · Raw SQL

- **Tables:** `default.otel_traces`

<details><summary>SQL query</summary>

```sql
WITH points AS (
  SELECT toStartOfInterval(Timestamp, INTERVAL 5 MINUTE) AS t,
         quantile(0.95)(Duration)/1e6 AS p95_ms
  FROM default.otel_traces
  WHERE SpanKind = 'Server' AND Timestamp > now() - INTERVAL 7 DAY AND $__filters
  GROUP BY t
)
SELECT t,
       p95_ms,
       (p95_ms - avg(p95_ms) OVER ()) / nullIf(stddevPop(p95_ms) OVER (), 0) AS z_score
FROM points
ORDER BY t
```

</details>

### Server latency distribution (heatmap) — heatmap

- **Source / table:** Traces → `default.otel_traces`
- **Measure(s):** `Duration` bucketed, count `count()`
- **Filter:** `SpanKind:Server` (lucene)
- **Columns used:** `Duration`, `SpanKind`
