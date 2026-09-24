# Dagychu — Community vs Enterprise

> Documentation for image / pack tag **3.4.4** (see `VERSION`). Ships in the Community client pack, public repository, and **Settings → Documentation → Edition comparison**.

Shared core for a given release tag is the same in both editions: pipelines, jobs, scheduler (cron / SLA / webhook / manual / dependency watchers), workers, logs, and the operator UI shell. The **former Pro SKU is removed**; its capabilities live in **Enterprise** only.

## At a glance

| Area | Community | Enterprise |
|------|-----------|------------|
| Pipelines, tasks, job runs, logs | Yes | Yes |
| Scheduler plans & Trigger | Yes | Yes |
| Operational charts (monitoring charts tab) | Yes | Yes |
| Decision Overview / Monitoring V2 | No | Yes |
| Execution map | No | Yes |
| API Security surface | No | Yes |
| Workspace / My dashboards (workspace edition features) | Limited / gated | Yes |
| Onboarding tour | No | Yes |
| Multi-user admin (create users, custom roles, token issuance UX) | Built-in admin/service only | Yes |
| Slack / Telegram notification endpoints | No | Yes |
| External HTTP API `/ext/*` | No (404) | Yes (when enabled) |
| Table report full-page / BI export / ClickHouse report sync extras | Inline tables yes; full enterprise report pack no | Yes |
| Client pack `examples/external_client/` | Not included | Included |

## Runtime notes

- **PostgreSQL** is the primary state store in both editions.
- **ClickHouse** remains optional report synchronization when configured.
- Community images are composition-checked so Enterprise-only modules are not served; upgrading the image to Enterprise unlocks gated surfaces without rewriting `dagychu-instance.yaml` (edition decides what is effective).

## Where to read more

- Pack / UI **`GUIDE.md`** — day-to-day operations (Community-safe).
- Pack / UI **`OPERATIONS.md`** — backup, update, rollback, health.
- Pack / UI **`RELEASES.md`** — per-version changes.
- In-app **Settings → License** — edition of the running image.
