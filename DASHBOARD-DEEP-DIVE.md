# AldoTel ClickStack Dashboards — Deep-Dive & Q&A Guide

A visual-by-visual reference for every dashboard in this pack. For each chart you will find **what data it reads**, **how it is calculated**, and a short **question-and-answer** that explains how to interpret it — including what healthy and unhealthy look like, and what to do next.

> **How this guide fits with the others**
> - **`DASHBOARD-CATALOG.md`** helps you decide *which* dashboards to import for your setup.
> - **This guide** helps you *understand and act on* each dashboard once it is showing data.
>
> New to the pack? Read the **[Core Concepts](#core-concepts)** section first — it explains the handful of ideas that every dashboard builds on.

---

## Contents

- [Core Concepts](#core-concepts)
- [1. Services — RED](#1-services--red)
- [2. Services — SLO / Error Budget](#2-services--slo--error-budget)
- [3. Logs — Overview](#3-logs--overview)
- [4. Kubernetes — Infrastructure](#4-kubernetes--infrastructure)
- [5. OpenTelemetry Collector — Pipeline Health](#5-opentelemetry-collector--pipeline-health)
- [6. ClickHouse — Cluster Health](#6-clickhouse--cluster-health)
- [7. ClickHouse — Query Performance & Errors](#7-clickhouse--query-performance--errors)
- [8. ClickHouse — Storage & MergeTree](#8-clickhouse--storage--mergetree)
- [9. ClickHouse — Keeper & Replication](#9-clickhouse--keeper--replication)
- [10. Executive Overview](#10-executive-overview)
- [Quick-Reference Playbook](#quick-reference-playbook)

---

## Core Concepts

A few ideas underpin every dashboard. Understanding them once makes all ten easy to read.

### The three data sources

Each chart reads from one of three data sources. A source is a table in ClickHouse together with the rules for interpreting it. The import script connects these automatically, so no manual configuration is required.

| Source | Contains | Produced by |
| --- | --- | --- |
| **Traces** | One record per *span* (a single timed operation within a request) | Application instrumentation sent over OTLP |
| **Logs** | One record per log line | Application logs (OTLP) and container output (filelog collector) |
| **Metrics** | One record per metric datapoint | OpenTelemetry collectors (Kubernetes, ClickHouse, and collector self-metrics) |

### How a chart queries its data

Charts use one of two query styles. You will see both throughout the pack.

- **Standard charts** aggregate a source with a function such as `count`, `average`, `quantile`, or `sum`, filtered by a simple expression (for example, *server spans that are errors*). These are fully portable and require only the data source.
- **SQL charts** run a purpose-built ClickHouse query. These are used when the data lives in a ClickHouse system table (such as `system.query_log` or `system.parts`) or when the calculation needs capabilities the standard builder does not provide, such as rolling baselines or custom time windows.

Both styles respect the dashboard filters described below.

### Units and conventions

- **Span durations are recorded in nanoseconds.** Latency charts convert this to seconds or milliseconds for display.
- **Server spans** represent the point at which a service received a request. Rate, error, and latency charts count only these, so a single request is not counted multiple times as it passes through the system.
- **Percentiles (p50 / p95 / p99)** describe the distribution of a value. A p95 latency of 500 ms means 95% of requests completed within 500 ms. Monitoring p95 and p99 reveals the slow "tail" of requests that a simple average would hide.
- **Metric types.** A *gauge* is a point-in-time reading (for example, queries running right now). A *sum* is a continuously increasing counter (for example, total queries ever run); its value is meaningful as a rate or as a change over a chosen window.
- **Dashboard filters.** The dropdown selectors at the top of a dashboard (such as *Service*, *Namespace*, or *Severity*) apply to every chart on that dashboard at once.

---

## 1. Services — RED

**Data source:** Traces  ·  **Filters:** Service
**Purpose:** The primary starting point for application performance. RED stands for **Rate**, **Errors**, and **Duration** — the three signals that best summarise the health of any service.

### Rate & errors

**Request rate by service** — request volume per service over time.
- **Q: What does this show?** The number of requests each service handles in each time interval.
- **Q: How should I read it?** This is the overall shape of your traffic. A line falling to zero indicates a service has stopped receiving requests. A sudden spike may indicate a surge in demand or a retry loop upstream.

**Error rate %** — the proportion of server requests that failed.
- **Q: Why a percentage rather than a count?** A percentage accounts for traffic volume. One hundred errors out of a million requests is negligible; one hundred out of two hundred is an outage.
- **Q: What is healthy?** For most services this is below 1%. A steadily rising line is often the earliest indication of a developing problem.

### Latency & error breakdown

**Latency p50 / p95 / p99** — response time at three percentiles.
- **Q: Why three lines?** The p50 line reflects the typical user experience, while p95 and p99 reflect the slowest requests. If p50 is stable but p99 climbs, a specific subset of requests is affected while most users are unaffected.

**Errors by status message** — a breakdown of failures by their reported reason.
- **Q: How should I use it?** A single dominant segment points to one primary failure mode to address first. Many small segments suggest broad instability.

### Slow routes & distribution

**Slowest routes (p95)** — a ranked table of the slowest endpoints. Selecting a row opens the underlying traces for that route.
- **Q: How should I use it?** Identify the endpoint with the worst p95 latency, then select it to inspect the individual slow traces and see where the time is being spent.

**Latency anomaly — p95 vs rolling baseline** — live p95 latency plotted against a self-calibrating expected range.
- **Q: What is the shaded band?** The chart calculates an expected baseline from roughly the previous 24 hours of data and surrounds it with a statistical range (three standard deviations). The band represents "normal" for this service.
- **Q: How should I read it?** When the live line rises above the upper edge of the band, latency is unusually high relative to its own recent history. Because the band adapts automatically, the same chart works for both fast and slow services without manual thresholds.

**Server latency distribution (heatmap)** — the full distribution of response times over time.
- **Q: What does this add?** It reveals the shape of latency. A single band indicates consistent performance. Two distinct bands indicate two populations of requests (for example, cached versus uncached responses) that an average would obscure.

---

## 2. Services — SLO / Error Budget

**Data source:** Traces  ·  **Filters:** Service
**Purpose:** Expresses reliability in business terms: whether you are meeting your service level objective (SLO) and how quickly you are consuming your error budget. The dashboard is configured for a **99.9%** objective, which allows a **0.1%** error budget.

### SLO — at a glance

**Availability (SLI)** — the measured proportion of successful requests, colour-coded against the objective.
- **Q: What is an SLI?** A Service Level Indicator is the measured "good request" ratio. The colours compare it to your target: amber below 99.9%, red below 99.5%.

**Error rate (1 − SLI)** and **Total server requests** — the failure proportion and the request count behind it.
- **Q: Why show the total?** The percentages are only meaningful with sufficient traffic. The request count confirms the sample is large enough to trust.

### Availability & traffic

**Availability over time (target 99.9%)** — the success ratio across the selected period.
- **Q: How should I read it?** Dips below the objective line are the moments that consume the error budget. Correlate them with deployments or known incidents.

**Good vs bad requests by service** — failed request counts attributed to each service.
- **Q: What is it for?** Identifying which services are contributing the failures.

### Burn rate

**Multi-window burn rate** — a table showing how fast the error budget is being spent over four periods: 1 hour, 6 hours, 24 hours, and 3 days.
- **Q: What does burn rate mean?** It is the rate at which you are consuming the error budget relative to a sustainable pace. A value of 1.0 means you are exactly on budget. A value of 14.4 means a full month's budget would be exhausted in about two days.
- **Q: Why several windows?** A high value over a short window indicates an acute problem happening now. A high value over a long window indicates a slower, ongoing issue. Comparing them distinguishes the two.

**Error-budget burn rate over time** — the burn rate plotted continuously.
- **Q: What should I watch for?** Sustained values above 1.0 indicate you are on course to miss the objective. Brief spikes are usually acceptable.

**Errors by service** — failed and total request counts per service. Selecting a row opens that service's error traces.

---

## 3. Logs — Overview

**Data source:** Logs  ·  **Filters:** Service, Severity
**Purpose:** Cluster-wide log triage — identifying what is failing, whether it is new, and providing a live view of errors as they occur.

> This source combines Kubernetes container output (captured from every pod) with structured application logs. It contains data even when applications are not instrumented for tracing.

### Volume & error rate

**Log volume by severity** — total log throughput, segmented by severity level.
- **Q: How should I read it?** The overall height reflects logging volume; the error and fatal segments are the focus. A sharp rise in total volume can indicate a log storm from a component stuck in a retry loop.

**Error / fatal rate by service** — the rate of error and fatal logs per service.
- **Q: What is it for?** Identifying which service began reporting errors, and when.

### Top errors & patterns

**Top error messages** — the most frequent error and fatal messages. Selecting a row opens those log entries.
- **Q: How should I use it?** A small number of messages usually accounts for most of the volume. Addressing those has the greatest impact.

**New log patterns in last 24h (vs prior 7d)** — error patterns that have appeared in the last day but not in the preceding week.
- **Q: How does it identify a "pattern"?** It normalises each message by replacing variable elements such as numbers and identifiers with placeholders, so that otherwise identical messages are grouped together. It then reports only those patterns that are genuinely new relative to the prior week.
- **Q: Why is this valuable?** New error signatures are a strong early indicator that a recent deployment or configuration change has introduced a problem. This chart highlights issues that have only just begun.

### Live stream

**Live error stream** — a continuously updating view of error and fatal logs, showing timestamp, severity, service, and message.
- **Q: What is it for?** Following errors in real time during an active investigation.

---

## 4. Kubernetes — Infrastructure

**Data source:** Metrics (Kubernetes)  ·  **Filters:** Namespace
**Purpose:** The health of the cluster that hosts your applications — its nodes, pods, and namespaces.

> This dashboard requires the Kubernetes infrastructure collectors (the `kubeletstats` and `k8s_cluster` receivers).

### Nodes

**Node CPU usage (cores)** and **Node memory usage** — resource consumption per node over time.
- **Q: How should I read it?** These indicate your physical headroom. Memory approaching a node's capacity risks pod eviction or termination.

**Nodes — status, CPU, memory, uptime** — a per-node summary table.
- **Q: What is it for?** A single-glance roster of node health. A status of *Not Ready* requires immediate attention.

**Nodes ready** — the count of nodes in a ready state.
- **Q: How should I read it?** This should equal your total node count. A lower number means a node has dropped out of the cluster.

**Node filesystem usage %** — disk utilisation per node.
- **Q: Why monitor it?** A full node disk disrupts image pulls, logging, and database writes. This should be addressed well before it reaches capacity.

### Pods

**Deployment availability (ready ÷ desired)** — the proportion of desired replicas that are running.
- **Q: How should I read it?** 100% means every replica is available. A lower value indicates a stalled rollout or crashing pods.

**Pods by phase** — the count of pods in each lifecycle phase, by namespace.
- **Q: How should I read it?** A predominance of *Running* is healthy. A growing *Pending* count indicates pods that cannot be scheduled; *Failed* indicates crashes.

**Pods — status & resources** — a detailed table including phase, CPU and memory usage against limits, age, and restart count, ordered by restarts.
- **Q: Which column matters most?** Restarts. A pod with a rising restart count is crash-looping. A memory usage near its limit predicts an imminent termination.

**Pod CPU vs limit %** and **Pod memory vs limit %** — resource usage as a percentage of each pod's configured limit.
- **Q: Why measure against the limit?** Kubernetes throttles CPU and terminates containers for memory at the limit. CPU near 100% of its limit indicates throttling (and slowness); memory near 100% indicates the pod is about to be terminated.

### Namespaces

**Namespace CPU usage** and **Namespace memory usage** — aggregate consumption per namespace.
- **Q: What is it for?** Understanding which application or team is consuming cluster resources — useful for capacity planning and identifying resource contention.

**Namespaces — phase, CPU, memory** — a per-namespace summary table.

---

## 5. OpenTelemetry Collector — Pipeline Health

**Data source:** Metrics (collector self-telemetry)  ·  **Filters:** Collector instance
**Purpose:** Confirms that the telemetry pipeline itself is healthy. If this dashboard shows problems, other dashboards may be missing data — check here first.

### Pipeline — at a glance

**Refused spans** and **Failed spans** — data the pipeline could not accept or could not deliver. Both are flagged red above zero.
- **Q: What is the difference?** *Refused* means the collector rejected incoming data, typically because it is overloaded. *Failed* means the collector accepted the data but could not deliver it to ClickHouse, typically due to a connectivity or authentication issue. Either represents lost telemetry.

**Exporter queue size** and **Exporter in-flight requests** — the backlog of data awaiting delivery.
- **Q: How should I read it?** A continuously growing queue means the collector is receiving data faster than it can deliver it. If unaddressed, the queue fills and the collector begins refusing data.

### Traces pipeline

**Spans: accepted vs refused vs failed** — accepted spans should dominate; refused and failed should remain near zero.
**Exporter sent spans** — should track the accepted volume, confirming data flows through.
**Exporter queue size vs capacity** — the gap between the two is your safety margin; a queue approaching capacity is a warning.
**Processor incoming vs outgoing items** — the two lines should overlap. A gap indicates data was dropped within the pipeline.

### Logs & metrics pipeline

**Accepted log records vs metric points** — the ingest rate for logs and metrics.
**Scraper: scraped vs errored metric points** — for metrics gathered by scraping. Errors above zero indicate the collector cannot reach a target it is configured to scrape.

### Collector resources

**Collector memory (RSS / heap)** and **Collector CPU seconds** — the collector's own resource usage.
- **Q: Why monitor this?** Memory approaching the collector's limit is a common root cause of the refusals described above. This is where to look when the pipeline is dropping data.

---

## 6. ClickHouse — Cluster Health

**Data source:** Metrics (ClickHouse)  ·  no filters
**Purpose:** The vital signs of the ClickHouse database that stores your observability data.

### Cluster health — at a glance

**Running queries**, **Max replication lag (s)**, **Readonly replicas**, and **Memory tracking**.
- **Q: What indicates a problem?** Rising replication lag means a replica is falling behind, which can produce stale reads. A replica becoming read-only usually indicates it has lost its coordination (Keeper) connection. Memory tracking approaching the server limit means queries will begin to fail.

### Query activity

**Query rate (vs previous week)** — current query volume overlaid with the same period a week earlier.
- **Q: What is it for?** Distinguishing normal variation from unusual load. Week-over-week comparison provides a reliable baseline.

**Failed queries**, **Inserted rows rate**, and **SELECT vs INSERT queries** — the read/write balance and confirmation that writes (your telemetry ingest) are flowing.

### Merges & mutations

**Merges in progress** and **Mutations in progress**.
- **Q: What are these?** ClickHouse continuously merges small data segments into larger ones in the background; this is normal and expected. A persistently high merge count can indicate the database is struggling to keep pace with the insert rate. Mutations are heavier operations, and many in progress can slow the system.

### I/O & cache

**Page-cache read bytes: cache vs source** — how much read traffic is served from cache versus re-read from storage. A higher proportion from cache indicates faster queries.
**Async insert bytes** — the throughput of batched asynchronous inserts.

---

## 7. ClickHouse — Query Performance & Errors

**Data source:** ClickHouse `system.query_log` (SQL) and ClickHouse metrics  ·  no filters
**Purpose:** The database administrator's view — which queries are slow, resource-intensive, or failing.

> Most charts read the `system.query_log` table, which requires the ClickHouse connection to permit reading it (the default in ClickStack).

### Query performance — at a glance

**Failed queries**, **Running queries (now)**, and **Memory tracking** — a summary of current query health.

### Query trends

**Query rate by kind** — query volume segmented into selects, inserts, and other operations.
**Query duration — p95 / p99** — the slow tail of query latency.
- **Q: How should I read it?** A rising p99 indicates some queries are becoming more expensive, often a sign of data growth or a query that would benefit from optimisation.

**Peak memory per query — p95 / max** — memory consumption per query.
- **Q: Why monitor it?** The maximum line approaching the server's per-query memory limit is what causes "memory limit exceeded" failures. This provides early warning.

**Query exceptions** — the count of queries that ended in an error.

### Slowest queries & errors

**Slowest queries (last 6h)** — a table of the slowest queries, including the user, duration, memory, rows read, and query text.
- **Q: How should I use it?** This is the most actionable chart for a slow database — it names the specific queries responsible so they can be optimised or rate-limited.

**Top ClickHouse error codes (last 24h)** — the most frequent categories of database error.
- **Q: How should I read it?** This shows the dominant classes of failure (such as memory or timeout errors), indicating the type of problem before you examine individual queries.

---

## 8. ClickHouse — Storage & MergeTree

**Data source:** ClickHouse `system.parts` and `system.part_log` (SQL)  ·  no filters
**Purpose:** Disk usage, compression, and the health of ClickHouse's background storage engine.

### Storage — at a glance

**Disk used (active parts)**, **Compression ratio**, **Active parts (total)**, and **Rows stored (active)**.
- **Q: What is a good compression ratio?** ClickHouse commonly achieves between 5× and 15×. A declining ratio can indicate high-entropy data or a schema whose ordering is not compressing well.

### Throughput & merges

**Part events / 5 min** — the rate of inserts, merges, and mutations.
- **Q: How should I read it?** Each insert creates a new data segment, and merges compact them. Healthy operation shows merges keeping pace with inserts.

**Merge duration — p95 / max** — how long merges take; increasing durations indicate merge pressure.
**Bytes written — inserted vs merged** and **Rows processed — inserted vs merged** — the additional work created by merging, which rewrites data. A large ratio of merged to inserted indicates significant rewrite activity.

### Tables & parts

**Largest tables by disk** — disk usage, row count, part count, and compression per table, answering where storage is being consumed.
**Active parts per table** — tables ordered by their number of data segments.
- **Q: Why does this matter?** ClickHouse rejects inserts with a "too many parts" error when a table accumulates too many unmerged segments, usually caused by very frequent small inserts. A table with a rapidly rising part count is the warning sign.

**Recent merges (last 6h)** — a table of individual merge operations and their outcomes.

---

## 9. ClickHouse — Keeper & Replication

**Data source:** ClickHouse Keeper metrics and replication system tables (SQL)  ·  no filters
**Purpose:** The coordination layer (ClickHouse Keeper) that enables replication and distributed operations.

> The replication tables at the bottom of this dashboard are empty on a single-node installation. This is expected and healthy — they populate only on replicated or clustered deployments.

### Keeper — at a glance

**Active sessions**, **Watches**, **Outstanding requests**, and **Alive connections**.
- **Q: How should I read it?** Sessions and connections should remain stable. A growing outstanding-requests backlog means Keeper cannot keep pace, which can stall merges and inserts across the cluster.

### Throughput & latency

**Keeper request rate by type**, **Commits vs failed commits**, **Packets received / sent**, **In-flight requests & watches**, and **Keeper commit-wait & process time**.
- **Q: What is the key warning sign?** Failed commits above zero, or a rising commit-wait time, indicates the consensus layer is unhealthy — typically due to slow disk or network issues between Keeper nodes.

**Keeper / ZooKeeper errors (last 24h)** — a table of coordination-related error counts.

### Replication (replicated deployments only)

**Replica status** — per-table replication state, including leader status, read-only status, and lag.
- **Q: How should I read it?** A read-only replica or a growing delay indicates a replica falling behind or disconnected from the coordination layer.

**Replication queue (stuck tasks)** — replication tasks ordered by retry count.
- **Q: How should I read it?** Tasks with a high retry count and a recorded exception are stuck in a retry loop, which is the direct cause of replicas diverging.

---

## 10. Executive Overview

**Data source:** Traces, Logs, and Metrics  ·  **Filters:** Service, Namespace
**Purpose:** A single-page summary of application health, platform health, the most affected services, and data ingest. Suitable for a status check or a shared status display. Charts degrade gracefully — any signal that is not configured simply appears empty while the rest continue to work.

### Service health — at a glance

**Span error rate (%)**, **Trace volume (spans)**, **Span latency p95**, and **Log error rate (%)**.
- **Q: What is this for?** Four figures that answer whether the applications are healthy right now. The colour rules present them as a simple status indicator.

### Platform — at a glance

**ClickHouse failed queries**, **ClickHouse running queries**, **K8s nodes ready**, and **Collector refused spans**.
- **Q: What is this for?** The equivalent view for the underlying infrastructure — the database, the cluster, and the pipeline. A non-zero refused-spans figure is a prompt to open the Collector Pipeline Health dashboard.

### Top services

**Services by error rate** and **Services by log errors** — each ranked worst-first, with rows that link directly to the underlying traces or logs.
- **Q: What is this for?** Identifying which services are affected and moving in a single step from "there is a problem" to the specific traces or logs behind it.

### Traffic & ingest

**Ingest throughput — spans accepted vs refused** — the rate of telemetry accepted versus rejected by the pipeline. Accepted should dominate and refused should remain at zero.
**Request rate & errors (traces)** — overall application request volume with the error count overlaid.

---

## Quick-Reference Playbook

| Situation | Start here | Then |
| --- | --- | --- |
| Is anything wrong right now? | Executive Overview | Follow the linked service tables |
| The application feels slow | Services — RED | Slowest routes → open the traces |
| Are we meeting our reliability target? | SLO / Error Budget | Review the multi-window burn rate |
| Errors started after a deployment | Logs — Overview | *New log patterns* chart |
| A pod or node looks unhealthy | Kubernetes — Infrastructure | Pods table (restarts, memory vs limit) |
| A dashboard is unexpectedly empty | Collector — Pipeline Health | Refused/failed spans, scraper errors |
| Queries or the database are slow | ClickHouse — Query Performance | Slowest queries table |
| Inserts are failing or disk is filling | ClickHouse — Storage | Active parts per table |

> **A useful rule of thumb:** if a chart is empty, first determine whether the dashboard is at fault or whether that data pipeline is simply not yet enabled. Running `preflight.ps1` answers this immediately.
