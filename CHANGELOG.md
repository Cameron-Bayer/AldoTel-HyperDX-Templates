# Changelog

All notable changes to the ClickStack dashboard templates are documented here.
Tested against **HyperDX 2.27.0** (OSS ClickStack) on minikube.

## [Unreleased]

### Added

- **Grafana deliverable (`grafana/`)** — four dashboards (Executive Summary, Service Health /
  golden signals, Kubernetes Cluster Overview, Logs & Errors Overview) over the same ClickHouse
  data, plus a **provisioned alerting pack** (`grafana/alerting/`) of six unified-alerting rules
  (generic webhook by default) shipped as YAML **and** Terraform. Portable via a datasource variable,
  with a durable ConfigMap installer for ClickStack-on-Kubernetes (`grafana/kubernetes/`).
- **Customer-facing docs** — each section README embeds an architecture diagram (Mermaid),
  live screenshots, and a glossary, so leadership and engineers share one document per product.
- **Alerts pack (`hyperdx/alerts/`)** — importable HyperDX alerts bound to dashboard tiles, one per
  high-level signal: services error rate (> 2%), SLO fast burn (14.4× of a 99.9% SLO), collector
  dropping telemetry (refused spans > 0), ClickHouse too-many-parts (> 5000 active parts), and
  replication lag (> 60s). `import-alerts.ps1` / `import-alerts.sh` upsert idempotently and notify a
  generic **webhook** you point at your own on-call channel. Thresholds are tunable per install.
  See `alerts/README.md`.
- **Screenshots of all 10 dashboards** in the README (`docs/images/*.png`), captured against a live
  open-source ClickStack (HyperDX 2.27) with the OpenTelemetry demo flowing — a visual preview of
  what customers get after `import`.
- **Preview image embedded at the top of every per-dashboard reference** (`docs/<slug>.md`), wired
  into `gen-docs.js` so the screenshot is included automatically when `docs/images/<slug>.png` exists.
- **Section headers on every dashboard** — each board is split into labelled sections (e.g. *At a
  glance*, *Throughput & latency*) with KPI number rows pulled to the top, so dashboards read
  top-to-bottom instead of as one dense grid.
- **Kubernetes dashboard — namespace views & richer tables:** per-namespace CPU and memory charts;
  Namespaces, Nodes, and consolidated Pods (status/resources) tables rendered with human-readable
  status text, sizes, and uptimes.

### Changed

- **Alerting is now channel-agnostic — Microsoft Teams removed as the default.** Both packs ship a
  **generic webhook** placeholder you point at your own on-call channel (Slack incoming webhook, a
  Teams Workflow URL, PagerDuty, Discord, or any HTTP endpoint). Grafana's contact point is a
  `webhook` type named **ClickStack Alerts** (Terraform var `teams_webhook_url` →
  `alert_webhook_url`); the HyperDX webhook default name is **ClickStack Alerts**. All
  Teams-specific setup instructions were removed from the READMEs and importer help.
- **Repository reorganized into two clear sections.** All HyperDX assets moved under
  [`hyperdx/`](hyperdx/) (dashboards, alerts, docs, `import`/`preflight` scripts, `gen-docs.js`,
  `requirements.json`, catalog & deep-dive docs) and the Grafana deliverable stays under
  [`grafana/`](grafana/). The root [`README.md`](README.md) is now a **hub** linking to both
  sections. Script relative paths are preserved, so `cd hyperdx` then run the importer as before.
  History preserved via `git mv`.
- **Removed** the unused `exports/logs-overview.json` (a stale duplicate not referenced anywhere).
- **`clickhouse-queryperf` metric labels & units clarified** to reduce customer confusion: the
  `Failed queries` tile now reports a count over the window (not a per-second rate), matching the
  Executive Overview; query-duration tiles gained a proper **duration** axis (e.g. `24s / 12s`) and
  the peak-memory tile a **byte** axis (e.g. `172 MiB`).
- **`services-red` latency anomaly reworked into a causal rolling control chart.** It now plots p95
  against a trailing baseline and ±3σ control band computed over a causal ~24h window (ending 1h
  before each point), so an in-progress spike can't poison its own baseline. Honors the `Service`
  filter; degrades gracefully until enough history exists.
- **Roomier, taller tiles** across all 10 dashboards for readability, with positions reflowed so
  nothing overlaps.
- **Consistent number formatting** — ratio "rates" render as true percentages with 3 decimal
  places; throughput counts (req/s, query/s, rows/s) left as counts.

### Fixed

- **Latency/duration tiles read ~1000× too high.** Several tiles fed raw nanosecond/millisecond
  values into a duration format whose base unit is seconds (p95 showed `44.08s` for an actual
  ~44 ms; merge durations showed hours). All affected tiles in `executive-overview`, `services-red`,
  and `clickhouse-storage-mergetree` now convert to seconds and format correctly.
- **Dashboard filters no longer blank unrelated tiles.** HyperDX applies dashboard filters
  globally, so a filter on a column some tiles lack silently emptied them. Audited all 10
  dashboards: removed the non-working ClickHouse `Instance`/`Node` filters, kept infrastructure
  tiles as constant context on the Executive Overview, made the Services RED / SLO analytics tiles
  honor the `Service` filter, and fixed the Logs "new patterns" tile (severity is stored lowercase).
- **Dashboards can now be saved in the HyperDX UI after import.** Markdown section headers are
  authored as config tiles and every panel now carries the fields the UI's save validation requires,
  so imported dashboards edit and save cleanly. (Header text is edit-via-template-and-reimport when
  imported through the API.)

### Known

- The HyperDX v2 dashboards API **strips `colorRules`** from number tiles on import
  (confirmed across all number tiles, including untouched ones). Color thresholds are kept in
  the template JSON for UI use / future API support but do not currently persist via import.

## [1.0.0-rc1] — 2026-06-23

Release candidate for the first customer-downloadable pack. 10 dashboards, verified live
(all PASS `preflight` with 0 missing checks; importer upserts round-trip).

### Dashboards
- ClickHouse — Cluster Health (`clickhouse-health`)
- ClickHouse — Query Performance & Errors (`clickhouse-queryperf`)
- ClickHouse — Storage & MergeTree (`clickhouse-storage-mergetree`)
- ClickHouse — Keeper & Replication (`clickhouse-keeper-replication`)
- Kubernetes — Infrastructure (`kubernetes-infrastructure`)
- Services — RED (`services-red`)
- Services — SLO / Error Budget (`slo-errorbudget`)
- Logs — Overview (`logs-overview`)
- OTel Collector — Pipeline Health (`collector-health`)
- Executive Overview (`executive-overview`)

### Cross-cutting (applied to every dashboard)
- **Filters/variables** on all 10 dashboards (service / namespace / node / instance / severity).
- **Drill-downs** (`onClick`) on every builder table over a Logs/Traces source
  (executive-overview ×2, services-red, slo-errorbudget, logs-overview).
- **Units & formatting** — bytes (`bytes_iec`), percent, and duration; `services-red` latency now
  formats as `duration` (auto-scales via the traces source `durationPrecision`).
- **Naming/tagging** — stable `tmpl:<slug>` tag on every dashboard for idempotent upserts.
- **Branding** — every dashboard name is prefixed `ClickStack · …` (shows in the HyperDX title bar/tab; no grid space used).

### Tooling
- `preflight.ps1` / `preflight.sh` — compatibility check driven by `requirements.json`.
- `import.ps1` / `import.sh` — upsert importer with `-DryRun` / `-Only` / `-Delete` / `-Duplicate`.

### Known / to confirm before GA (`1.0.0`)
- UI click-through of the `services-red` "Slowest routes" drill-down
  (`{{SpanAttributes['http.route']}}` row variable).
- Visual render of `clickhouse-storage-mergetree` "Merge duration (ms)" Raw-SQL `output:"duration"` formatting.
- RUM / Frontend Sessions dashboard deferred — `hyperdx_sessions` has no data without a browser SDK.
