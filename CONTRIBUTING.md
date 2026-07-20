# Maintainer guide

Customer-facing docs live in the section READMEs. This file collects the
**maintainer-only** workflows — regenerating templates, validating them against a
live backend, and the local authoring harness. Customers do **not** need any of this
to import and use the dashboards.

## Source of truth: the generators

Never hand-edit generated output. Edit the generator, then regenerate.

| Product | Edit | Regenerate with | Output |
|---------|------|-----------------|--------|
| Grafana | `grafana/gen-dashboards.js` | `node grafana/gen-dashboards.js` | `grafana/dashboards/*.json` |
| HyperDX docs | dashboard JSON in `hyperdx/dashboards/` | `node hyperdx/gen-docs.js` | `hyperdx/docs/*.md` (+ index) |

The HyperDX per-dashboard reference pages (`hyperdx/docs/<slug>.md`) are generated from
each dashboard template — edit the template and re-run `gen-docs.js`, don't edit the docs.

## Grafana: local authoring & validation harness

`grafana/` ships a throwaway Grafana wired to a ClickStack ClickHouse for authoring and
validating the dashboards.

```powershell
# 1. Expose ClickHouse from your cluster
kubectl port-forward -n clickstack svc/clickstack-clickhouse-clickhouse-headless 9000:9000

# 2. Start the dev Grafana (http://localhost:3005, admin/admin)
#    Set CH_PASSWORD first — it feeds the dev ClickHouse datasource (no default is baked in).
$env:CH_PASSWORD = "<your ClickHouse password>"
docker compose -f grafana/docker-compose.yml up -d

# 3. Regenerate dashboards after editing the generator
node grafana/gen-dashboards.js

# 4. Validate every panel query against real data
node grafana/validate.js
```

- `grafana/docker-compose.yml` — dev Grafana with the ClickHouse plugin pre-installed.
- `grafana/provisioning/` — dev data source + dashboard provider (points at `host.docker.internal:9000`).
- `grafana/validate.js` — runs each panel's SQL through Grafana's query API and reports row
  counts. It substitutes the dashboard template variables (`${database}` → `default`, and the
  `${service}` / `${namespace}` filter placeholders) the way Grafana's frontend would.

## HyperDX: implementation notes

- Dashboards are built against the HyperDX **v2** dashboard API (`packages/api/openapi.json`
  in the hyperdx repo).
- The importer **upserts** by the stable `tmpl:<slug>` tag, so re-running updates dashboards
  in place instead of duplicating them.
- Dashboard **display titles** carry a `ClickStack · …` prefix; the `tmpl:<slug>` tag is the
  stable identity used for upserts and is intentionally independent of the title/filename.
