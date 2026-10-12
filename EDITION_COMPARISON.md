# Dagychu — Community vs Enterprise

> Documentation for image / pack tag **3.4.5** (see `VERSION`). Ships in the Community client pack, public repository, and **Settings → Documentation → Edition comparison**.

Shared core for a given release tag is the same in both editions: pipelines, jobs, scheduler (cron / SLA / webhook / manual / dependency watchers), workers, logs, and the operator UI shell. The **former Pro SKU is removed**; its capabilities live in **Enterprise** only.

**How to read releases:** in pack / UI **`RELEASES.md`**, bullets marked **`(Enterprise)`** are Enterprise-only for that version. Unmarked bullets ship in both editions. This comparison table is the durable capability matrix.

## At a glance

| Area | Community | Enterprise |
|------|-----------|------------|
| Pipelines, tasks, job runs, logs | Yes | Yes |
| Scheduler plans & Trigger | Yes | Yes |
| Global find (`find:` pipelines, tasks, **jobs**, scheduler plans) | Yes | Yes |
| Entity notes (task / plan / pipeline sticky notes) | Yes | Yes |
| Inline TableToolkit (sort, filter, column prefs, presets) | Yes | Yes |
| Operational charts (monitoring charts tab) | Yes | Yes |
| Full-page expanded table / report (`view=table`), shareable report URL, CSV/JSON/XLSX/SQL export | No (upgrade gate) | Yes |
| Saved BI report configs, API export (`/api/ui/table-reports/.../data`), ClickHouse report sync | No (upgrade gate) | Yes |
| Job output view designer + Open expanded report | No (Open uses Enterprise report surface) | Yes |
| Decision Overview / Monitoring V2 | No | Yes |
| Execution map | No | Yes |
| API Security surface | No | Yes |
| Workspace / My dashboards (workspace edition features) | Limited / gated | Yes |
| Onboarding tour | No | Yes |
| Multi-user admin (create users, custom roles, token issuance UX) | Built-in admin/service only | Yes |
| Slack / Telegram notification endpoints | No | Yes |
| External HTTP API `/ext/*` | No (404) | Yes (when enabled) |
| Client pack `examples/external_client/` | Not included | Included |

## Runtime notes

- **PostgreSQL** is the primary state store in both editions.
- **ClickHouse** remains optional **Enterprise** report synchronization when `CLICKHOUSE_URL` is configured (not required for core runs; not a Community BI surface).
- Community images are composition-checked so Enterprise-only modules are not served; upgrading the image to Enterprise unlocks gated surfaces without rewriting `dagychu-instance.yaml` (edition decides what is effective).
- On Community, opening a full-page report or BI URL shows an in-app **Enterprise** upgrade explanation (not a broken empty page).

## Where to read more

- Pack / UI **`GUIDE.md`** — day-to-day operations (Community-safe).
- Pack / UI **`OPERATIONS.md`** — backup, update, rollback, health.
- Pack / UI **`RELEASES.md`** — per-version changes (with **`(Enterprise)`** labels where needed).
- In-app **Settings → License** — edition of the running image.
