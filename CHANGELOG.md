# Dagychu — releases

**Current version: 3.4.5**

Product release notes, **newest first**. Compare with your install’s `VERSION` file before `./update.sh`. The same text ships as pack **`RELEASES.md`** / **`CHANGELOG.md`** and in **Settings → Documentation → Releases**.

**Edition labels:** bullets marked **`(Enterprise)`** are Enterprise-only for that version. Unmarked bullets ship in **both** Community and Enterprise. Capability matrix: pack / UI **`EDITION_COMPARISON.md`** and **Settings → License**.

## Service matrix

| Service | Role |
|---------|------|
| **api** | Core FastAPI: tasks, jobs, pipelines, WebSocket, YAML disk sync on startup |
| **worker** | RabbitMQ consumer; jobs via subprocess (**`JOB_EXECUTOR=local`**) or Docker (**`JOB_EXECUTOR=docker`**); logs under `JOB_LOG_DIR` |
| **scheduler** | Scheduler HTTP API: cron/webhook plans; dispatches via Core `POST /tasks` |
| **ui_backend** | Proxies to Core + Scheduler; reads job logs from disk; serves built React UI |
| **postgres** | Tasks, runs, pipelines, users/sessions, audit |
| **rabbitmq** | Worker queue |

---

## 3.4.5

**Focus:** safer Docker executor for Compose; **(Enterprise)** table-report / output-view pack; global find by job name; entity notes; env without `dagychu_system`; ClickHouse report sync pool hardening **(Enterprise UI / BI pack)**; Admin **Config Snapshot + Restore**.

The repo **`VERSION`** file: **3.4.5** (previous line **3.4.4**).

**Highlights:**

- **Config Snapshot + Restore (Admin → Snapshots):** export `dagychu-config-snapshot-v1.json` (RBAC, users, token *names*, projects/vars without secret values, pipelines, tasks, scheduler plans, notifications without tokens, maintenance, dashboards/reports/presets, entity notes nested with parents, creator subs, telemetry preference). Selective non-destructive merge; **never deletes** entities absent from the snapshot; **preserves public IDs** (`task_id` UUID, `scheduler_jobs.id` / webhook URL, `pipeline_group`+`name`, parallel parent links) so external integrations keep working after clone/restore. Preview returns `secrets_required[]` (webhook secrets, project secret vars, notification tokens, API tokens, ClickHouse env, instance `.env` checklist) — Apply is not blocked; operator re-enters secrets in Admin/Scheduler afterward. Archives land on the **host** via compose bind **`DAGYCHU_SNAPSHOT_HOST`** (default `./snapshots`) → container `/var/lib/dagychu/snapshots` on `api`; `install.sh` / `update.sh` create the host dir. Optional **`DAGYCHU_SNAPSHOT_SIGNING_KEY`**: export adds HMAC-SHA256 `integrity`; with key set, tampered/stripped signatures are rejected; **without** the key, restore remains allowed with an explicit “could not verify” warning (DR onto a new instance). Retention `DAGYCHU_SNAPSHOT_RETENTION` (default 14); optional `DAGYCHU_SNAPSHOT_REMOTE_PUT_URL`. Companion files (`dagychu-instance.yaml`, `runtime/**` job code, host `.env`) stay on disk — checklist only. Job-run history / audit / sessions are out of scope.
- **`docker_proxy` only mounts the Engine socket** (`docker-compose.docker-sock.yml`). api / worker / worker_deadline_reserve use `DOCKER_HOST=tcp://docker_proxy:2375` with an allowlisted Docker API (no raw sock in those containers).
- **`DAGYCHU_DOCKER_SOCK` auto-detect** in `install.sh` / `update.sh` / `update-dev.sh` via `scripts/detect_docker_sock.sh` (rootless `/run/user/$UID/docker.sock` vs rootful `/var/run/docker.sock`) — avoids Connect failures when the CLI context is rootless but compose mounted the system sock.
- Hardcoded `/var/run/docker.sock` mounts removed from community/dev base compose; Docker executor always goes through the overlay.
- **(Enterprise) Table report data export:** UI snippets use **`/api/ui/table-reports/{table_id}/{report_id}/data`** (ui_backend proxies Core). Fixes empty HTML from the SPA catch-all when calling the old `/table-reports/.../data` path on the UI origin. Community builds show an upgrade gate for full-page `view=table` reports.
- **(Enterprise) Report provenance:** BI / Expand Table chrome shows source (job output vs registry table), creator, API/CH flags, and links into Job Detail when scoped.
- **Global find:** `find:` indexes **pipeline job names**; Enter / click opens Job Detail (or Pipelines focus when no task exists yet).
- **(Enterprise) Output view designer:** Job Detail **actions rail** (Create output view); designer starts with **no** JSON paths selected; nested object tree; arrays **Keep JSON** vs **Explode to rows** (cartesian product when multiple); **min job run id** cutoff; Open/Edit honor `selectedJsonPaths` / explode modes / cutoff. Full-page Open uses the Enterprise report surface.
- **Entity notes:** polymorphic `entity_notes` (one note per task / scheduler plan / pipeline) with severity icon + Markdown modal (job-run notes unchanged). View mode shows rendered Markdown + severity border; edit via pencil. Author is the signed-in user (not editable). Attention = red, Debug = gray. Space key works in the note textarea (no longer stolen by table row activation).
- **Entity notes INSERT fix:** early `entity_notes` / `job_run_notes` DDL used `INTEGER PRIMARY KEY` without SERIAL on Postgres; creating a note returned Core 500 (UI **502**). Migrate now uses SERIAL + idempotent sequence repair; verify-mode detects the broken PK and falls back to migrate.
- **(Enterprise) Role project visibility:** Admin Roles matrix can set **visible projects** (`read_groups`) for `pipelines` read or full. Denied projects are filtered server-side across pipelines, tasks, job logs, audit/changelog, overview, monitoring, scheduler, notifications, and table reports.
- **Task Cloud RBAC:** `/analytics/tag-cloud` and news-summary honor `read_groups` (no more “all projects” leak for limited roles); project picker only promotes allowlisted groups.
- **New UI nav:** when **Tasks** is active, sidebar shows nested **Task Cloud** / **Registry**; when **Logs** is active, nested **Tasks log** / **Change log**. URL params `tasks_tab` / `logs_tab`.
- **Task Cloud default fit:** initial Fit View uses ~half previous zoom (`FIT_SCALE_FACTOR=0.5`).
- **Global find:** always loads a flat ACL task list (not cleared by group-by-pipeline); navigate denies with a clear message when the target screen is hidden for the role.
- **Settings split:** Settings nav is always available; personal sections (appearance, locale, account, …) for everyone; **License** / **Skills** still require the `settings` RBAC block.
- **Read-only UX:** write actions stay visible and explain **read-only mode** on click (Scheduler plan rail, Task registry edit, Investigation Run/Terminate, Job Detail rerun, entity note save).
- **Job Detail full log:** Copy + Download `.txt` for the complete on-disk log (not only the visible chunk).
- **Env generation:** `.env.example` / `generate_env` no longer append **`dagychu_system`** to `PIPELINE_YAML_DIRS` (builtin group remains in-image for old installs).
- **External projects root:** optional **`DAGYCHU_RUNTIME_HOST`** (default `./runtime`) for the compose bind into container `/srv/runtime` — e.g. host `/srv/app` beside the pack — without changing in-container paths. Unset keeps existing `./runtime` installs unchanged.
- **(Enterprise) ClickHouse report sync:** per-report DB sessions (no Session across `asyncio.to_thread`); pool timeout / backoff without crashing the loop. Sync is part of the saved BI report pack (Community has inline tables only).
- **Scheduler create plan 404:** after pipeline ACL, Core `GET /tasks/{id}` returned 404 for the service token (`pipelines: none`). Plan create validated task existence via that call and failed silently in production UI. Create now checks the shared `tasks` table; seed grants service role `pipelines: full` so engine reconcile / dispatch keep working. Create/save errors also surface in the plan modal + toast.
- **Config Snapshot HMAC 422 on Preview:** browser `JSON.stringify` collapses whole floats (`1.0`→`1`) and broke integrity after upload/archive load. Signing now canonicalizes numbers; verify accepts legacy signatures; **Load into preview / Apply** for Local archives run on the server (`…/archives/{name}/preview|apply`) so the JSON never round-trips through the browser. Error text includes a short key fingerprint to confirm the api container has the expected `DAGYCHU_SNAPSHOT_SIGNING_KEY`.
- **Config Snapshot UX:** quieter Snapshots tab (archives first, schedule collapsed); archive list shows contents summary + diff vs previous; **pin** (never purged by retention / blocked from delete) and **delete**; soft-deleted tasks show as **restore** (undelete) instead of a vague warning; Admin retention edits stick (saved `policy.json` wins over `DAGYCHU_SNAPSHOT_RETENTION` env).

**Compatibility:** existing installs with `JOB_EXECUTOR=docker` need pack files + `./update.sh` (pulls `tecnativa/docker-socket-proxy:0.3.0` and rewrites `DAGYCHU_DOCKER_SOCK` if the previous path is missing). Report export URLs in saved snippets should be updated to `/api/ui/table-reports/.../data` **(Enterprise)**. New `entity_notes` table is created on migrate. No other API/compose volume data migration.

*Upgrade note:* replace client pack compose/scripts/overlay; run `./update.sh` (creates `./snapshots` or `DAGYCHU_SNAPSHOT_HOST` and recreates `api` with the bind). Confirm Connect / project image build works. Optional: set `DAGYCHU_DOCKER_SOCK` explicitly for rootless. Re-copy API snippets for table reports if you saved the pre-3.4.5 URL **(Enterprise)**. After Config Snapshot restore: re-enter webhook secrets, project secret vars (`PROJECT_VARS_SECRET_KEY`), notification bot/webhook tokens, and new API tokens; ensure runtime pipeline/job code and `.env` match the source instance. If you previously set `DAGYCHU_SNAPSHOT_DIR` to a **host** path, `update.sh` migrates it to `DAGYCHU_SNAPSHOT_HOST`.

*Rollback:* pin pack/image `3.4.4` (or restore previous `docker-compose.docker-sock.yml` that mounted sock into api/worker). Keep volumes. Entity notes table can remain unused. Snapshot archives on disk are inert JSON and can be kept or deleted.

*Known limitations:* proxy allowlist still permits container create/build (required for jobs); prefer dedicated nodes and strong Dagychu auth. Fully isolated remote Docker remains the strongest model (see enterprise DOCKER_EXECUTOR_MODES). Entity notes are single-note-per-object (no threads) in this line. Community operators looking for full-page reports / BI export / output-view Open should see **Settings → License** / **`EDITION_COMPARISON.md`**, not a missing community feature. Config Snapshot does not copy plaintext secrets, pg_dump history, or `runtime/**/jobs` code (Phase 1).

---

## 3.4.4

**Focus:** Community-public operator documentation with anti-drift bake into UI + pack + public repo, and Job Detail input fixes for failed / first mid-pipeline runs.

The repo **`VERSION`** file: **3.4.4** (previous line **3.4.3**).

**Highlights:**

- **Community docs canon:** `docs/community-public/` (`GUIDE.md`, `OPERATIONS.md`, `EDITION_COMPARISON.md`) plus this `RELEASES.md` bake to Settings → Documentation and ship in every client pack / Community public repository (`CHANGELOG.md` aliases `RELEASES.md`). CI lint + sync gates prevent UI/pack drift and block internal references or overstated delivery claims.
- **Trust contracts** in Guide/Operations: unchanged Python/Bash jobs; JSON for structured I/O only; PostgreSQL primary state; ClickHouse optional reports; no exactly-once for external side effects.
- **Job Detail — FAILED input:** stripped task lists no longer treat `error_text` as full IO; the UI fetches `getJobRun` so Input shows the stdin that was used.
- **Job Detail — new mid-pipeline job:** empty / `{}` “Rerun with JSON” omits override so the worker infers stdin from upstream SUCCEEDED outputs and task initial input (same as Run last inputs).

**Compatibility:** no breaking API or compose contract changes.

*Upgrade note:* replace pack files including docs; run `./update.sh`. Confirm **Settings → About** shows **Dagychu 3.4.4**.

*Rollback:* pin the previous image tag / client pack (`3.4.3`), run `./update.sh` (or `docker compose up -d`). Keep Postgres/RabbitMQ volumes. See Operations → Day-2.

*Known limitations:* external actions are not exactly-once under retry; Community does not expose `/ext/*` (see Edition comparison).

---

## 3.4.3

**Focus:** scheduler tick reliability (hung drain no longer drops overdue cron slots), explicit skip incidents with manual-trigger guidance, and UX/docs polish from operator feedback.

The repo **`VERSION`** file: **3.4.3** (previous line **3.4.2**).

**Highlights:**

- **Scheduler tick stability:** Drain/reconcile under the leader lock now respects a wall-clock budget (`SCHEDULER_DRAIN_BUDGET_SEC`, default ~25s) and no longer blocks the dispatch phase on long Core HTTP. `due_before` is recomputed immediately before the due-jobs query so slots that become due during a slow tick are still seen.
- **Catch-up before overdue sweep:** When cron catch-up is enabled, the engine prefers dispatching an overdue cursor instead of silently abandoning it. Sweep that still skips writes a `SKIPPED` event / skipped run with `reason=overdue_cursor_sweep` (parity with `cron_missed_slot`). Example: a hung tick no longer drops a twice-daily DWH slot without a record.
- **Incidents:** Skipped schedule slots surface as **Schedule slot skipped** (not a false “started late” late-start). Recommendations tell operators to open run history, use **Trigger** if the business run is still needed, and check engine diagnostics when many plans skip in the same minute.
- **Scheduler plan edit / webhooks:** Edit form pre-fills non-secret fields (including public GET rate). Token shows as already set; leaving it empty on save keeps the existing secret (API never returns the secret).
- **Pipelines & Tasks UX:** Edit task / edit schedule plan from Pipeline details; task kebab opens the Scheduler bottom panel; CREATED status chip is slate/gray (RUNNING stays yellow); task Owner (`created_by`) on investigation metadata.
- **Job stdout docs:** Skills and operator guide match the worker: stdin JSON in; stdout may mix log lines and a JSON payload (last object / `__JOB_OUTPUT_JSON__`); `write_stdout_json` remains the safe emit path. JSON-only jobs stay compatible.
- **Changelog in the client pack:** `RELEASES.md` ships in Community and Enterprise packs (and the Community public repo) so you can review what changed versus your current `VERSION` before `./update.sh`. Guide/Operations remain image-only under **Settings → Documentation**.

*Upgrade note:* optional new env `SCHEDULER_DRAIN_BUDGET_SEC` (default is fine for most installs). After upgrade, confirm the sidebar footer / **Settings → About** shows **Dagychu 3.4.3**. Run `./update.sh` on existing installations.

---

## 3.4.2

**Focus:** scheduler precision & SLA dispatch deduplication, accurate product telemetry activity aggregation, fullscreen chart portals, universal UI search, and a modern autonomous demo jobs package.

The repo **`VERSION`** file: **3.4.2** (previous line **3.4.1**).

**Highlights:**

- **Scheduler SLA precision & zero duplicate dispatches:** Fixed cursor advancement for SLA deadline plans to prevent multiple dispatches of the same scheduled slot. Suppressed false-positive `SKIPPED` log records when an in-flight run is already covering the target slot.
- **Accurate Product Telemetry aggregation:** Telemetry heartbeat metrics (`runs_24h` and `active_pipelines_24h`) now dynamically count real job and pipeline runs executed within the last 24 hours (`JobRun.started_at` with cascading fallback to `PipelineOperationEvent` and `Task`), resolving reporting of zero runs on active clusters.
- **Operations Dashboard fullscreen charts:** Fixed chart fullscreen mode in `ChartTemplate` and `ChartCard` using React Portals directly into `document.body` (bypassing `react-grid-layout` CSS transform containment), and added `Escape` key shortcut for quick closing.
- **Universal Global Search in UI:** Terminal `find:` command and dedicated search buttons on section headers (Pipelines, Tasks, Scheduler) with instant preloaded global indexing, fuzzy matching, and direct navigation.
- **Modern autonomous demo jobs package:** Replaced legacy math jobs with 8 realistic, in-memory, zero-dependency demo jobs (`demo_etl_pipeline`, `demo_batch_processing`, `demo_data_quality_check`, `demo_retry_recovery`, `demo_unstable_service`, `demo_long_running_job`, `demo_validation_failure`, `demo_daily_report`), 4 advanced scenarios (`demo_api_sync`, `demo_parallel_workers`, `demo_resource_processing`, `demo_timeout`), and a complete guided `demo_orders_workflow`.
- **Exit code diagnostics in UI:** Human-readable explanations and hints for common job exit codes (e.g. `rc=137` SIGKILL / OOM Killer, `rc=1`, `rc=2`) directly in the job execution details view.
- **Branding & Visuals:** Transparent background for in-app splash and sidebar logos, GitHub Social Preview card (`.github/preview.png`), and cleaned up UI footer.

*Upgrade note:* no mandatory `.env` changes. After upgrade, confirm the sidebar footer / **Settings → About** shows **Dagychu 3.4.2**. Run `./update.sh` on existing installations.

---

## 3.4.1

**Focus:** monitoring charts on the dashboard, task-level parallel runs, clearer errors in the UI, and a sharper Community vs Enterprise experience.

The repo **`VERSION`** file: **3.4.1** (previous line **3.4.0**).

**Highlights:**

- **Parallel executions on a Task:** How many copies of the same Task may run at once is a Task setting (**Max parallel executions**, default 1), not a scheduler plan cap. Scheduler, UI rerun, webhook, manual, and Ext API all share that limit. Extra in-flight runs reuse hidden slots; the registry still shows one Task, and job history is merged. If the cap is full, a new start is refused (409) rather than queued. Existing plan field `max_concurrent_runs` is still accepted but ignored for execution; on upgrade the Task cap is set to the highest plan cap that already pointed at that Task.
- **Monitoring charts:** Dashboard charts for failed job executions (last 24h) and worker busy / idle over time. Expand a chart, inspect data sources, and open linked objects when available.
- **One chart template everywhere:** Every monitoring block — KPIs, execution health, queue pressure, duration, workers, hotspots, Enterprise analytics — renders through the chart template, so titles, toolbars, expand, data sources, freshness, loading and empty states look and behave the same regardless of chart type. Timestamps follow **Settings → Timezone** in axes, tooltips and tables.
- **One instance profile per install, not per edition:** Community and Enterprise ship the same `dagychu-instance.yaml`; the running edition decides which capabilities are served. Upgrading Community → Enterprise unlocks Overview, Execution map, API Security and monitoring V2 without editing configuration files. New file version is `dagychu_instance_version: 2`; version 1 files keep working, and their monitoring flags no longer pin an upgraded deployment to Community defaults. Enterprise-only surfaces stay closed on Community even when the file asks for them — the external `/ext/*` API, for example, remains disabled there.
- **Workers by worker:** On the workers timeline, switch from fleet totals to a per-worker view (idle vs busy; a gap means the worker was offline or restarted).
- **Clearer errors:** API and form failures show a short human-readable message instead of raw protocol dumps.
- **Long-running admin actions:** Connecting or refreshing a project can take several minutes; the UI waits for the server to finish instead of aborting early.
- **Community edition:** Locked Enterprise areas show a clear upgrade path (what is included vs what needs Enterprise), without dead ends in navigation.
- **Tables & dashboards:** Table toolkit preferences and My Dashboards chart widgets work with the new chart blocks; deep links into a job or run from a chart open the right screen.

*Upgrade note:* no mandatory `.env` changes. After upgrade, confirm the sidebar footer / **Settings → About** shows **Dagychu 3.4.1**. Replace `docker-compose.yml` then `./update.sh`; docs come with the image. `update.sh` keeps your `dagychu-instance.yaml`; new Community installs now ship the shared profile, where `execution.project_execution_gate_enabled: true` requires a connected project in **Administration → Projects** before the first run.

---

## 3.4.0

**Focus:** canvas and scheduler UX, real dependency plans (watch other plans / tasks / pipelines), product version in the UI, and a Settings hub with legal documents.

The repo **`VERSION`** file: **3.4.0** (previous line **3.3.2**).

**Highlights:**

- **Canvas:** dragging a job node no longer opens JobDetail (click still does). Opening a task, a histogram wave, or a scheduler run without `job_name` leaves the overlay closed; explicit `job_name` links still open that job.
- **Investigation layout:** node height no longer grows in investigation mode; Reset/Run stay on one row as icons. Optional **Duration** toggle draws a relative sky bar inside the card (longest job in the wave = 100%).
- **Task header:** shows **wave** status (live jobs / selected histogram wave), not a stuck stored `FAILED`. Investigation restore will not write FAILED back over a live success, and will not restore FAILED while a job is still RUNNING.
- **Scheduler create plan:** the modal is one-shot (sidebar **Scheduler** no longer reopens it). Overview scheduler onboarding banner only appears on tour step `scheduler_*`.
- **Dependency plans:** `schedule_type=dependency` watches **scheduler plan**, **task id**, and/or **pipeline** (OR). Fires when the source task reaches SUCCEEDED (or FAILED if policy is `always`); CANCELLED never fires. Covers UI Trigger, Ext rerun by id, scheduler rerun of the template, and new Ext `POST /ext/tasks` instances (pipeline watcher). Investigation Reset/Run does not wake dependents. Legacy `POST /scheduler/dependencies/emit` is unchanged.
- **Stdin `dagychu_trigger`:** reserved JSON on every job of a dependent (and ordinary cron/SLA/webhook/manual) run — `kind`, source task/plan ids, status, `matched_watcher`. No YAML change; job reads stdin.
- **PIPELINE RUNS histogram:** axis labels sit under tick marks (`hour12: false`; same-day in the display timezone).
- **Overview incident:** What / Where / When / Why story; one **Open task**; scheduler/pipeline under **Open in…**.
- **Product version** from the `VERSION` file on `/ui/auth/config` (`product_version`), New UI sidebar footer (`Dagychu 3.4.0`), and **Settings → About** (version, edition, instance).
- **Settings hub:** inner nav + URL `settings_section=` (Appearance, Locale, Account, Notifications, About, License, Documentation, Legal). All items stay visible in every edition; locked packs show a stub. Admin users/roles stay a separate nav item.
- **Legal documents** under `frontend/public/customization/legal/`: Terms, Privacy, Notices in English. **Settings → Legal** shows them from the image. Optional `ui.legal` in `dagychu-instance.yaml` substitutes `{{LEGAL_ENTITY}}` and similar tokens if they appear in the markdown.
- **Guide:** scheduler section documents the three watcher kinds and `dagychu_trigger`.
- **Thin client pack:** archive is compose, env, instance yaml, and install/update scripts. Operations and Releases are baked into `/customization/docs/` in the image; **Settings → Documentation** opens them. Prod compose no longer bind-mounts `onboarding-tour.yaml` (image `/srv/onboarding-tour.yaml` is the default).

*Upgrade note:* no mandatory `.env` changes. Scheduler schema (`dependency_watchers`, `dependency_run_policy`, `scheduler_dependency_firings`) is applied by `init_db` on startup. After upgrade, confirm sidebar shows **Dagychu 3.4.0**. Replace `docker-compose.yml` then `./update.sh`; docs come with the image. Dependency plans need at least one watcher (or a legacy `dependency_event`).

---

## 3.3.2

**Focus:** Postgres connection exhaustion and stuck upgrades after 3.3.0/3.3.1 (`too many clients`, Core `/ready` 503 for hours).

- **`update.sh`:** stops full app tier (`ui_backend`, `worker`, `scheduler`, `api`) before API recreate — releases pooled DB sessions.
- **`scripts/recover_db_pressure.sh`:** emergency stop app tier when Postgres returns `too many clients` (no data loss).
- **`init_db`:** `lock_timeout` / `statement_timeout` on migration connections — DDL fails in minutes, not hours.
- **Auth middleware:** `AUTH_RESOLVE_TIMEOUT_SEC` (default 8s) → 503 instead of wedging thread pool on DB lock storms.
- **Worker orphan reconcile:** after restart grace (`WORKER_ORPHAN_RUNNING_GRACE_SEC`), stale `job_runs.status=RUNNING` with no online task owner are auto-cancelled (`ORPHAN_RUNNING_JOB_MAX_AGE_MIN`) so stuck `RUNNING` tasks unblock scheduler. Batch reconcile also runs from scheduler tick and **`POST /system/tasks/reconcile-stuck`**; `force_release`/`release_stuck` close orphan RUNNING jobs when no online fleet owner (post-outage unblock).
- **Core `/health`:** returns **503** until `startup=ready` (Docker healthcheck stops lying green).
- **System → Services:** Core check uses `/ready`, not `/health`.
- **Prod compose:** Postgres `max_connections=200`; capped API/UI DB pools + `DB_STATEMENT_TIMEOUT_MS` on ui_backend.
- **Connection budget (`db_connection_budget.py`):** fixed per-role pool caps; **decoupled from `MAX_PARALLEL_COMPUTATIONS`**; API startup logs cluster worst-case and can enforce `DAGYCHU_DB_ENFORCE_CLUSTER_BUDGET=1`.

*Upgrade note:* if Postgres already shows `too many clients`, run `./scripts/recover_db_pressure.sh` then `./update.sh`. Client data volumes are never deleted. After outage with stuck RUNNING + idle runners, call `POST /system/tasks/reconcile-stuck` or wait for scheduler/worker reconcile.

---

## 3.3.1

**Focus:** production upgrade safety after 3.3.0 — `update.sh` must bring a client from a stuck/partial 3.3.0 boot back to healthy **without manual compose commands** and **without touching customer data**.

- **`update.sh` ordered rollout:** stop `worker`/`scheduler` → ensure infra → `--force-recreate` Core API → wait for `/ready` → scale workers (+ auto `docker-compose.docker-sock.yml` when `JOB_EXECUTOR=docker`). Named volumes, `.env`, `runtime/`, and instance YAML are never deleted.
- **API init_db + uvicorn `--workers 2`:** peers wait for the migration advisory lock instead of failing with `migration lock unavailable`.
- **API healthcheck `start_period`:** 600s so long `init_db` is not marked unhealthy mid-migrate.

*Upgrade note:* ship a new client pack (image tag **3.3.1** + updated `update.sh` / `scripts/compose_helpers.sh`). On a site already stuck after 3.3.0, operators only need to unpack and run `./update.sh` again — no ad-hoc `docker compose` steps. Data stays on existing volumes.

---

## 3.3.0

**Focus:** fintech-scale read-path stability and enterprise sales gate foundations (SSO/crypto/Helm/DR) — UI must stay usable under large `job_runs` history without deleting customer metadata by default.

**Track A — scale / history (Airflow-like browse):**

- **`GET /job_runs`:** default `include_total=false` (no lifetime `COUNT(*)`); page size capped at **500**; browse via `after_id` / page fullness.
- **List read cache** (L1 + Redis L2) with single-flight stampede guard; invalidate on realtime `task.*`.
- **Auth:** DB resolve off the asyncio event loop (`to_thread`) + short session micro-cache; prod **api/ui_backend `--workers 2`**.
- **Dashboard report:** longer TTL (default **60s**), single-flight rebuild, tighter row caps; aggregates remain **time-windowed**.
- **History contract:** metadata keep-by-default; optional batched retention (ops, like `airflow db clean`, still **off** by default).
- **`job_runs` growth path:** BRIN(`started_at`) on heap installs; partition ensure for already-partitioned tables; migrate runbook for live heaps.
- **Approx totals** via `pg_class.reltuples` when exact count is skipped; optional `DB_STATEMENT_TIMEOUT_MS`.
- **New UI load caps:** toolkit / Tasks / Pipelines mount fetches ≤**200** (was 1000–2000).

**Track B — enterprise gate (foundations):**

- **AES-GCM (v2)** project runtime secrets; legacy XOR (v1) still decrypts; enterprise/prod **fail-closed** without `PROJECT_VARS_SECRET_KEY`.
- **OIDC SSO** (Authorization Code + PKCE): `/auth/oidc/start|callback` + UI proxy; group→role map via env.
- **Scheduler sticky advisory lease** (no try-lock-then-immediate-unlock).
- **Helm chart** under `deploy/helm/dagychu/` (BYO managed Postgres/Rabbit/Redis recommended).
- **docker.sock** not mounted by default in prod compose; opt-in overlay `docker-compose.docker-sock.yml`.
- **Ext API:** `ext.public_outputs` allowlist + default deny for broad job IO.
- **OTel bootstrap** (optional extras), **audit webhook** export, enterprise CORS defaults.
- **Docs:** `PERFORMANCE_RUNBOOK` history contract; `JOB_RUNS_PARTITION_MIGRATE`, `DISASTER_RECOVERY`, `docs/enterprise/*` (security, compliance pack, docker modes).
- **Operator Guide:** status/reason glossary (Logs + Scheduler skip reasons, reconcile messages) and **Max parallel > 1** overlapping cron starts (clone task when template still RUNNING).
- **`install.sh` / `update.sh`:** when `JOB_EXECUTOR=docker`, auto-attach `docker-compose.docker-sock.yml` (3.3.0 prod compose no longer mounts sock by default).
- **Worker:** `pipeline_failed` ops events include exception type/message.

*Upgrade note:* merge new `.env` keys from `.env.example` (cache/OIDC/secrets/timeouts). Set **`PROJECT_VARS_SECRET_KEY`** before enabling enterprise edition secrets. For **`JOB_EXECUTOR=docker`**, ensure `docker-compose.docker-sock.yml` is present and use updated `update.sh` (or pass `-f docker-compose.docker-sock.yml` manually). Partition migrate of existing `job_runs` heaps is **optional maintenance** — see `docs/operations/JOB_RUNS_PARTITION_MIGRATE.md`. Follow-ups: [`docs/ROADMAP.md`](ROADMAP.md) (3.3.x / 3.4+ / 4.0.0).

---

## 3.2.1

**Focus:** New UI operational depth — Tasks/Pipelines registry workflows, Overview concern dispositions, quieter background loads, and documentation for first-time operators.

**Highlights:**

- **Create Task modal** no longer clears operator input when parent screens poll (notifications / pipelines).
- **Quiet timeouts:** background refresh paths retry briefly and keep cached data instead of sticky red API banners; user-initiated saves still surface errors.
- **Pipelines (New):** project **group-by** in the collection; **Concerns** tab on pipeline details (active + history, shared concern drawer).
- **Overview concerns:** dispositions **Fixed** (manual resolve) and **Expected** (baseline mute — no auto-reopen while Expected); clearer first-seen / last-observed / ended history; multi-week duration creep detection stays as a **concern** (not an incident).
- **Tasks (New) registry actions:** create schedule, edit, freeze/unfreeze external triggers, delete (archive) from the table row.
- **TableToolkit:** columns with `sortDescFirst` (e.g. Scheduler Plan ID) cycle **desc → asc → clear** correctly.
- **Guide / releases:** in-app operator guide and **`RELEASES.md`** updated for **3.2.1** menu layout and day-to-day workflows.

*Upgrade note:* no mandatory `.env` changes. Prefer **New** UI under **Settings → UI version** to use Tasks registry actions, Pipelines Concerns, and the refreshed Guide. After upgrade, open **Guide** once to confirm your package ships this text as **`USER_GUIDE.md`**.

---

## 3.2.0

**Focus:** dual UI shell (Classic / New) for parallel layout work without changing data contracts.

**Highlights:**

- **UI version** preference in **Settings** (`ui.shellVariant`: `classic` | `new`), stored in this browser. Default remains **Classic**.
- **Classic** — current control-plane UI (baseline; left unchanged while iterating layout).
- **New** — parallel shell; layout-only changes land here. Shared host (API clients, WebSocket, query-param routing, prefs) stays common; request/response and connection formats are **not** changed by shell work.
- Frontend module: `frontend/src/uiShell/` (`UiShellVariantProvider`, `resolveUiObject`, `classic/` / `new/` tracks).

**New UI — sidebar (initial track):**

- **Boot** (every New shell mount / after authorization): center logo + DAGYCHU (accent **Y**) → fade → sidebar logo hold → brand typewriter → menu letter type-in (50 ms item stagger) → main work area unlocks.
- **Nav sections:** Observability (Monitoring, My dashboards, System) / Registries / Management; Settings pinned at bottom. Classic sidebar unchanged.
- **Nav icons (New only):** Gauge, PanelsTopLeft, Archive, SquarePen (create/edit task), Cpu (Task/Jobs engine), Play (Scheduler), Activity, Lock, Settings; TL→BR cyan→slate gradients.
- **Collapse:** letter erase (brand + nav) → collapse chevron flies **straight** into the Dagychu logo (external aura / vortex; logo bitmap stays undimmed) → icon-only rail.
- **Expand:** widen rail first → chevron extracts logo→dock at the far right → then brand + nav type back in. Idle logo aura is a quiet static glow (no pulse “click me”).

*Upgrade note:* no mandatory `.env` changes for this feature. Operators and users can switch UI version under **Settings → UI version**.

---

## 2.2.0

**Focus:** Docker-backed job execution without Kubernetes, project config polling, and operator notifications.

**Highlights:**

- **`JOB_EXECUTOR`**: **`local`** (default) or **`docker`** — per-pipeline-group images built from validated `dagychu-config` (MVP: **`requirements`**-style Python deps only).
- **DB**: `DagychuProject.runtime_image_built_at`; notification rows may carry **`user_id`**; migrations for existing deployments.
- **Worker**: optional **`DAGYCHU_PROJECT_CONFIG_POLL_SECONDS`** loop for connected projects; Docker executor with mounts and external volumes from config.
- **Notifications**: in-app **`DagychuNotification`** feed, Slack/Telegram delivery via **`UserNotificationEndpoint`**, API + UI (**Notifications** nav, gated by **Tasks** block).
- **Compose / `.env.example`**: document **`JOB_EXECUTOR`**, polling interval, and Docker socket mount on **api** + **worker** when using Docker jobs.

*Upgrade note:* merge new `.env` keys; if using **`JOB_EXECUTOR=docker`**, ensure **api** and **worker** can reach Docker (see **OPERATIONS** §4.7).

---

## 2.1.0

**Focus:** external execution API for agents, scheduler reliability, and mobile-first UX.

**Highlights:**

- New **external async API** in `ui_backend` for agent/app integrations:
  - `POST /ext/tasks` returns `202 Accepted` with `task_id`;
  - `GET /ext/tasks/{task_id}` for status;
  - `GET /ext/tasks/{task_id}/result` for terminal payloads.
- External delivery model supports both **polling** and **webhook callback**:
  - callback retries with backoff;
  - callback delivery state is persisted and auditable;
  - optional callback HMAC signature headers for receiver-side verification.
- Added **idempotency** and guardrails for external submit:
  - `Idempotency-Key` deduplication;
  - per-actor rate limiting;
  - optional allowlist via environment config for external entrypoint users.
- Introduced external integration persistence model (`external_task_requests`) and seed defaults:
  - dedicated `agent_client` role/user profile (tasks-only access pattern);
  - optional bootstrap token env for external clients.
- Scheduler/task flow hardening:
  - fixed task enabling/disabling persistence from table editing;
  - trigger paths now correctly propagate dispatch state and task linkage;
  - webhook path stability preserved across plan edits (no ID churn on minor updates).
- Task UX upgraded with **alias-first display**:
  - canonical label format: `pipeline_name (alias)`;
  - alias editable from create/edit flow and task-centric screens;
  - backend identity remains stable `task_id` UUID.
- Table and navigation UX improvements:
  - collapsible filter row with dedicated toggle;
  - scheduler task cells provide direct navigation to Task/Jobs;
  - fixed invalid nested-button DOM rendering in table cells.
- Mobile web UX improvements:
  - bottom icon navigation for mobile;
  - mobile menu customization in Settings (pin primary items, overflow under `More`);
  - responsive form/control widths for operational use on phones.
- Added release-support assets:
  - external client example script in `examples/external_client/`;
  - smoke checklist for external integrations in [`EXTERNAL_AGENT_SMOKE.md`](./EXTERNAL_AGENT_SMOKE.md).

*Upgrade note:* review and merge new external integration variables in `.env.example` (`EXT_*`, `UI_BACKEND_SERVICE_TOKEN`, optional `EXTERNAL_AGENT_TOKEN`) before deploying 2.1.0.

---

## 2.0.3

**Focus:** unified tables, events/export, execution flexibility.

**Highlights:**

- Shared **table** UX (filters, sort, columns, presets, export, shareable state where enabled).
- **Events / runs** presentation (e.g. chart ↔ table selection for job runs).
- **Executor router** for pluggable job execution paths.

*Note:* if your shipped **`VERSION`** is still 2.0.2, treat 2.0.3 items as the next tag line; update this section with date and release commit when 2.0.3 is published.

---

## 2.0.2

**Focus:** operations, SLA, infrastructure, runtime correctness.

The repo **`VERSION`** file at documentation time: **2.0.2**.

**Highlights:**

- **SLA / scheduler** tuning (poll, tolerances, dispatch).
- **Docker** and build/runtime fixes.
- **Pipeline path** behaviour and **multiple groups** (`PIPELINE_YAML_DIRS`).
- Example jobs and YAML validator alignment.

---

## 2.0.1

**Focus:** release pipeline hardening and security tightening.

**Highlights:**

- **Client artifact** and release process fixes (`fix release files`).
- **Security / auth** parameter updates between UI and Core (`security update`, refined security params).

*Upgrade note:* diff new `.env.example` against your `.env` when moving from 2.0.0.

---

## 2.0.0

**Focus:** start of the 2.x line, production-oriented delivery and mature control plane.

**Highlights:**

- Client bundle with **pinned image tags** (no `latest`), `install.sh` / `update.sh`, deployment docs.
- **Scheduler** as a separate HTTP service (jobs, pause/resume, webhook, runs/events).
- **Admin panel and roles**, pipeline/group policy hooks.
- UI customization: branding, locales, theme.
- Task and pipeline editors; runtime **pipeline groups** via **`PIPELINE_YAML_DIRS`**.

---

## Operator upgrade checklist

1. Obtain new **`client-<version>`** or updated `docker-compose.yml` with the target image tag.
2. Follow **`README.md`** / **`CLIENT_SETUP.md`**: run `./update.sh` after replacing compose.
3. Reconcile **`.env`** and **`runtime/`** (`pipelines/`, `jobs/`).
4. If external agent integrations are enabled, run smoke:
   - submit `POST /ext/tasks` with Bearer token and `Idempotency-Key`,
   - poll `GET /ext/tasks/{task_id}` until terminal,
   - verify `GET /ext/tasks/{task_id}/result`,
   - verify callback delivery (or retry trail) in audit log.
   - full checklist: [EXTERNAL_AGENT_SMOKE.md](./EXTERNAL_AGENT_SMOKE.md)

## Python package version

[`pyproject.toml`](../pyproject.toml) **`version`** may differ from product **`VERSION`**: images and client packages use **`VERSION`**.
