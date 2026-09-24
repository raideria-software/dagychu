# DAGYCHU — User & operator guide

> Operator and user guide for Dagychu **Community**. Product version: see pack / repo **`VERSION`** and **Settings → Documentation → Releases** (current line **3.4.4**). Same document ships in the client pack and Community public repository.

This guide is for a **first-time operator**: install → open the UI → understand every menu item → run daily work safely. Deep troubleshooting and Kubernetes handoff live in **Settings → Documentation → Operations**.

---

## 1. What Dagychu is

**Dagychu** is an **execution control platform**. It separates:

| Layer | What it is |
|-------|------------|
| **Pipelines & jobs (YAML + code)** | *How* work is described — DAG of jobs, inputs, dependencies |
| **Tasks** | *One run instance* of a pipeline with concrete input JSON |
| **Worker + RabbitMQ** | Executes job steps and reports status |
| **PostgreSQL** | Full state: tasks, runs, definitions, users, audit |
| **Scheduler** | Creates tasks on cron / webhook / SLA / dependency plans |
| **Web UI** | Operator console (this app) |

The browser talks to **ui_backend** under `/api`. Ui_backend proxies to **Core API** and **Scheduler API**, and can read full job log files from disk (`JOB_LOG_DIR`).

### 1.1 New UI menu map

| Section | Menu item | Purpose |
|---------|-----------|---------|
| **Observability** | Monitoring | Platform health, concerns, incidents (decision Overview) |
| | My dashboards | Personal widget workspace |
| | System | Service health + workers fleet |
| **Registries** | Pipelines | YAML registry, validation, create task / schedule |
| | Tasks | Task registry + investigation (graph, jobs, freeze, debug) |
| | Scheduler | Plans (cron / SLA / webhook / manual / dependency), runs, events |
| | Logs | Operation timeline, audit, full job logs |
| **Management** | Administration | Users, tokens, roles, projects, maintenance |
| | Notifications | In-app event feed (+ Slack/Telegram if configured) |
| | Guide | This document |
| *(footer)* | Settings | Language, timezone, documentation, legal, account |

Create/edit task is a **modal**; Tasks is the registry plus investigation (graph, jobs, freeze, debug).

Header (New): a **console** streams notices; expand history and jump to a task / failing run when linked.

---

## 2. Install, update, and day-2 operations

### 2.1 First install (client package)

1. Unpack the client bundle next to Docker Engine + Compose v2.
2. Copy `.env.example` → `.env`. Set at least:
   - `POSTGRES_PASSWORD`
   - `UI_ADMIN_TOKEN` (bootstrap admin / API access when auth is on)
   - `WORKER_SERVICE_TOKEN` (must match between **api**, **worker**, **scheduler**)
3. Put automation under `runtime/` (see §3).
4. Review `dagychu-instance.yaml` (instance settings; secrets stay in `.env`).
5. Run `./install.sh`, then open `http://<host>:<FRONTEND_HOST_PORT>` (default **3000**).

Package: **`README.md`** (install), **`RELEASES.md`** / **`CHANGELOG.md`** (changelog), **`GUIDE.md`**, **`OPERATIONS.md`**, **`EDITION_COMPARISON.md`**. The same Guide / Operations / Releases / Edition comparison are also in **Settings → Documentation** for this image version.

### 2.2 Update

When you receive a new version package:

1. Read pack **`RELEASES.md`** (or the Community public repo copy) for versions newer than your install’s `VERSION` — decide whether to upgrade.
2. Replace `docker-compose.yml` (pinned image tag = **`VERSION`**) and refresh pack files including `RELEASES.md`.
3. Run **`./update.sh`** — pulls images, **does not** overwrite your `.env`, warns about missing keys, scales workers.
4. Diff `.env.example` against your `.env` for new variables.

**Do not** run `./install.sh` on an existing deployment (it resets `.env` from the example).

### 2.3 Dev / from git

```bash
./update-dev.sh
# or: docker compose -f docker-compose.dev.yml up --build
```

Typical ports: Core `8000`, Scheduler `9020`, Ui_backend `9010`, Vite `3000`, RabbitMQ UI `15672`.

### 2.4 Health checks after bring-up

1. **System** — all critical services OK; workers consuming.
2. **Pipelines** — your groups and YAML appear (wait ~30s for disk sync, or restart **api**).
3. **Administration → Projects** — groups connected if project gate is enabled.
4. Create a small task and confirm it reaches **SUCCEEDED** (or inspect Logs on failure).

---

## 3. Runtime: pipelines, jobs, projects

Job code and pipeline YAML live under **`RUNTIME_ROOT`** (Compose: host `runtime/` → `/srv/runtime`), not inside the Python package.

### 3.1 Layout & Code Placement (Git / CI/CD)

The project directories created by `install.sh` (`runtime/development` and `runtime/production`) are **starter recommendations**. You can configure automated CI/CD deployments or run `git pull` directly inside these folders, or create custom project directories under `runtime/`.

```text
runtime/                    # or each PIPELINE_YAML_DIRS group root
  development/              # e.g. cloned git repository
    dagychu-config.yaml     # [REQUIRED] Project runtime config (Python, dependencies, volumes)
    requirements.txt        # Python package dependencies
    pipelines/              # [REQUIRED] Pipeline YAML manifests (*.yaml)
    *.yaml
    jobs/                   # Python packages / scripts (referenced by YAML path)
```

**Key requirements for every project:**
1. **`dagychu-config.yaml`**: defines the Python stack, dependencies (`requirements.txt` or `pyproject.toml`), and mount volumes.
2. **`pipelines/` directory**: contains YAML pipeline definitions.
3. **Job code tree**: executable scripts/modules referenced in pipeline `path:` entries.
4. **`PIPELINE_YAML_DIRS` in `.env`**: list of `group=root` tokens (e.g. `myproj=myproj`).
5. **Connecting in UI**: open **Administration → Projects**, click **Refresh validation**, and click **Connect**.

- **`PIPELINE_YAML_DIRS`** — `group=root` tokens. Each root needs `pipelines/*.yaml`.
- Job `path:` in YAML is relative to the **group root**.
- **`JOB_APP_ROOT`** — optional; defaults to `RUNTIME_ROOT` (parent of `jobs/`).
- Platform Overview pipelines may use a **`repo:system/...`** group baked into the image.

Disk sync **upserts** definitions on API startup and every **`PIPELINE_DISK_SYNC_INTERVAL_SECONDS`** (default **30**; `0` = startup only). Deleting a YAML file does **not** delete the DB row.

### 3.2 First Project Walkthrough (Step-by-Step: Zero to Scheduled Pipeline)

Follow these 8 steps to connect your repository and run automated workflows:

1. **Create/choose project directory**: `mkdir -p runtime/my_project` (or use `runtime/development`).
2. **Sync your repository**: `git clone <repo-url> runtime/my_project` or configure CI/CD / `git pull`.
3. **Configure `dagychu-config.yaml`**: place `dagychu-config.yaml` in `runtime/my_project/` with `stack.python: "3.12"` and dependencies (`requirements.txt` or `pyproject.toml`).
4. **Create `pipelines/` & write pipeline YAML**: add `runtime/my_project/pipelines/my_pipeline.yaml` with job graph and dependencies (see `skills/dagychu/pipeline-yaml.md` or **Settings → Skills**).
5. **Register project in Dagychu**: add `my_project=my_project` to `PIPELINE_YAML_DIRS` in `.env` and run `./reload-projects.sh`.
6. **Validate and Connect in UI**: go to **Administration → Projects**, select `my_project`, click **Refresh validation** → **Connect**.
7. **Inspect Pipelines**: navigate to **Pipelines** — your newly connected pipelines and DAG graph will appear immediately.
8. **Create Task & Schedule**: click **Create task** to test run, then go to **Scheduler → New plan** to set up cron, webhook, SLA, or dependency triggers.

### 3.3 Project file `dagychu-config.yaml`

- Used by **Administration → Projects** to validate and **Connect** a group.
- If **`PROJECT_EXECUTION_GATE_ENABLED=true`**, only **connected** groups may run tasks.
- With **`JOB_EXECUTOR=docker`**, Core/worker build a per-group image from this config.

Copy from `examples/dagychu-config.yaml` in the client package, then **Refresh validation** → **Connect**.

### 3.4 Instance file `dagychu-instance.yaml`

One file per deployment (next to compose / `.env`). Non-secret instance settings (bootstrap, monitoring). Secrets stay in `.env`. See `dagychu-instance.template.yaml` next to the compose file.

### 3.5 Useful YAML controls

```yaml
_meta:
  launch_order_mode: declaration   # or auto_lpt
jobs:
  - job_name: notify_final
    deps: [build_report]
    run_on_upstream_failure: true  # cleanup / notify after failure
```

Per-job **`model.yaml`** next to job code can prefill create-task JSON and drive optional **news chat** highlights.

### 3.6 Job stdin / stdout (and what you see on failure)

Existing standalone Python or Bash scripts can run without source-code changes. Configure their executable path and runtime in the pipeline YAML. An exit code of 0 is success; empty stdout becomes `{}`, and non-JSON stdout is retained in `_dagychu_unparsed_stdout` and in the job log.

Use the JSON contract only when jobs need structured task input, need to pass values to downstream jobs, or need fields available to Dagychu reports. Dagychu sends one JSON object on stdin. On success, emit a JSON object on stdout; the worker stores parsed keys in `output_json`, and YAML `inputs: { from: job, key: ... }` copies those keys.

Stdout may mix log lines with the JSON payload. The worker extracts the **last JSON object**, or the body after a `__JOB_OUTPUT_JSON__` marker (or a trailing JSON line). Jobs that print **only** one JSON object keep working. Prefer **`write_stdout_json`** for the payload; put noisy diagnostics on **stderr** when you want a clean separation.

On **failure** (non-zero exit, traceback, or stdout encoding guard), the job log file contains the exception **and** captured stdout/stderr (`=== STDOUT ===` / `=== STDERR ===`), same layout as a successful run. The job error box shows a tail of those streams so you do not lose prints that happened before the crash.

**Large UTF-8 JSON** (reviews, HTML, long text): prefer writing bytes once instead of `print(json.dumps(...))`. Copy **`examples/jobs/_lib/dagychu_stdio.py`** from the client package into your group as `jobs/_lib/dagychu_stdio.py` and use `read_stdin_json()` / `write_stdout_json()`. That avoids TextIOWrapper splitting a multibyte character across chunks, which the worker then rejects as U+FFFD.

Demo: `examples/jobs/demo_etl_pipeline/v1/main.py` (seeded into `runtime/demo/jobs/` on install).

---

## 4. Monitoring (Overview)

**Menu:** Observability → **Monitoring**.

New UI Overview is a **decision screen**: health score, what needs attention, then drill into detail — not a dump of every metric.

### What you see

- **Health / status** and short situation line.
- **Concerns** — platform-level signals (e.g. duration growth, queue depth, SLA variance). These are **not** the same as task incidents.
- **Incidents** — concrete task/job/scheduler problems (failures, missed SLA slots, etc.).
- **History** toggle — include resolved / manually resolved / **Expected** concerns and richer incident history.

### Concern dispositions

Open a concern:

| Action | Meaning |
|--------|---------|
| **Mark fixed** | Problem acknowledged fixed (`ManuallyResolved`). New material evidence may reopen later. |
| **Mark as expected** | Treat as **baseline** for this signal. While **Expected**, the same concern **will not auto-reopen**. |
| **Clear expected** | Resume monitoring for that signal. |

Detail always shows **first seen**, **last observed**, **observation ended**, summary, evidence, and a **History** timeline.

Filters: projects / pipelines where available. Deep-link drawers open the same concern/incident elsewhere (e.g. Pipelines → Concerns).

---

## 5. My dashboards

**Menu:** Observability → **My dashboards**.

Personal workspace of **widgets** (system health, workers fleet, and other catalog items). Arrange what you need for a shift without leaving the console. Widget availability depends on edition and permissions.

---

## 6. System

**Menu:** Observability → **System**.

Operator view of **whether the control plane can run work**:

- **System health** — Core API, scheduler, RabbitMQ / queue depth, stuck-task hints (signals may be folded into one expandable widget in New UI).
- **Workers fleet** — connected workers, consume status, replica hints. Scale via Compose `WORKER_REPLICAS` / your orchestrator, not from this table.
- Queue backlog here is the first place to look before blaming a pipeline YAML.

If health is red after install, check `WORKER_SERVICE_TOKEN` consistency across **api**, **worker**, and **scheduler**, then worker logs.

Nav badge (New): colored attention when health is degraded. If the queue backs up: check worker replicas, `WORKER_SERVICE_TOKEN`, worker logs, and **`JOB_TIMEOUT_SECONDS`**.

---

## 7. Pipelines

**Menu:** Registries → **Pipelines**.

This is a **registry of YAML definitions** (quality, registration, readiness) — not the live execution graph.

### Collection

- Summary facets (e.g. Needs attention, validation errors, not registered).
- Table with sort/filter/columns (prefs remembered per browser).
- **Pipeline** column shows optional `display_name` / title when set in YAML; otherwise the human alias of the **first created task** for that pipeline (when available). Technical `pipeline_name` appears as secondary text.
- **Description** column shows optional multi-line `description` from YAML.
- **Group by project** — presentation-only grouping (filters stay primary).
- Select a row → **Details** panel (can hide Details for full-width table).

### YAML labels (optional)

In the pipeline YAML (top-level or under `_meta`):

```yaml
display_name:
  - Sales report
description:
  - Marketplace sales report
  - from connected channel exports
```

After save / disk sync, the registry uses the title instead of the technical id.
### Details tabs

| Tab | Use |
|-----|-----|
| **Overview** | Registry / validation / task count / last execution |
| **YAML** | View / edit / save (when you have write access to the group) |
| **Validation** | Error tree from disk/API validation |
| **Tasks** | Current tasks for this pipeline; expand for triggers; **Create schedule**; open task |
| **Concerns** | Overview concerns + related incidents for this pipeline (history toggle) |
| **History** | Provenance snapshot (not a full YAML git log) |

**Create task** (toolbar / Details) opens a modal with project + pipeline prefilled (requires Tasks write; pipeline must be registered).

If a pipeline is missing: check `pipelines/` path, API logs (`Pipeline disk sync`), `python_executable` inside the API environment, and wait for sync / restart **api**.

---

## 8. Tasks

**Menu:** Registries → **Tasks**.

### 8.1 Registry (overview)

Tabs: **Registry** (table) and **Cloud** (graph / news) when analytics edition features are on.

Registry columns include status, alias, project, pipeline, tags, owner, last/next run, triggers.

**Row actions** (when permitted):

| Icon | Action |
|------|--------|
| Pencil | Edit task (modal; usually while `CREATED`) |
| Lock / unlock | **Freeze / unfreeze external triggers** — blocks scheduler, ext API, and full pipeline rerun; Investigation debug still works |
| Calendar+ | Create scheduler plan for this task (opens Scheduler with type picker: cron / SLA / webhook / manual / dependency) |
| Trash | Delete (archive) task |

Click a row → **Investigation**.

### 8.2 Investigation

Focus: one task’s graph, job detail, runs, logs jump, freeze banner, terminate, export.

**External freeze** — same as registry lock: confirms + optional audit reason.

**Investigation / Dev mode** (graph):

- Enter Investigation for an isolated debug lane (live automation outputs unchanged).
- **Reset / To here / Debug run / Step** — mark nodes to re-run; frozen nodes reuse live outputs.
- Prefer **Terminate** over hammering Rerun while active.

URL deep links (`task_id`, `job_name`, `job_run_id`) share exact context; New UI uses `screen=TASKS`.

---

## 9. Scheduler

**Menu:** Registries → **Scheduler**.

The scheduler does **not** publish to RabbitMQ itself. Each dispatch asks Core to start (or clone) a task (`POST /tasks/{id}/rerun`). The linked task is the **template**: same pipeline YAML and input JSON.

### 9.1 Plan types

Every plan has exactly one type. Choose it when you **Create plan**, or change it later in **Plan settings** (gear on the row). The compact table shows **Type** plus a **Schedule** summary (cron expression, SLA deadline, webhook URL, “Trigger only”, or dependency watchers).

| Type | When it fires | What you configure |
|------|----------------|-------------------|
| **Cron** | When `next_run_at` is due (five-field cron in the plan timezone). Catch-up after downtime is **on** by default. | Cron expression. No SLA buffer. |
| **Deadline (SLA)** | The cron tick (or optional daily **HH:MM UTC**) is the **finish-by** time. Start = deadline − (expected duration + buffer). | Cron and/or HH:MM, duration, buffer, optional late dispatch. |
| **Webhook** | HTTP call to this plan’s URL. **No cron.** `buffer_sec` is **not** a debounce window. | Webhook token; optional public GET rate. |
| **Manual** | Only **Trigger** in the UI (or `POST /scheduler/jobs/{id}/trigger`). **No cron.** | Task + max parallel. Schedule column shows “Trigger only”. |
| **Dependency** | When a watched **plan**, **task**, or **pipeline** reaches **SUCCEEDED** (or **FAILED** if policy allows). **CANCELLED** never fires. **No cron.** | Watchers (OR), success-only vs always, optional legacy named event. |

Edition notes: the Scheduler **screen** exists in Community. Public webhook HTTP path and dependency emit routes are gated (Community typically 404 on public webhook; dependency emit is Enterprise). UI still lets you describe plans; a blocked path will fail at call time.

### 9.2 Plans table (New UI)

Columns are compact: plan id, type, schedule summary, task, enabled, next run. Next to the time: **recompute** (nearest slot from now) and **skip next run** (cron/SLA only — jump to the following slot; recompute brings back the nearest). Full column set remains on the **table report** export.

Row clicks do not start editing. Use the **action icons on the right** (same pattern as Tasks):

| Icon | Action |
|------|--------|
| Filter | Toggle: scope **Recent runs** and **Events** to this plan; press again (or Clear) to remove the filter |
| Gear | **Plan settings** modal — type-specific fields (cron, SLA timing, webhook token/GET, dependency watchers), enabled, max parallel |
| Play | **Trigger** now (counts as a scheduler run of this plan) |
| Trash | Archive the plan |

Click the **task name** to open Tasks / investigation. Plan id is not a filter link.

**Enabled** (in settings): pause without deleting. Inactive / historical rows cannot be edited until restored.

### 9.3 Max parallel

**Max parallel** (`max_concurrent_runs`): how many in-flight scheduler runs this plan may have at once.

- **`1` (default)** — if the linked task is still `RUNNING` / `QUEUED` / `PENDING`, the next tick is **skipped** (`job_concurrency_limit` / `task_running`) and the slot is held.
- **`> 1`** — overlapping starts are allowed. When the template task is still busy, scheduler **clones** a fresh task (same pipeline + input) for the new slot. You will see a second task id in Runs / Tasks (alias like `…-j{planId}-{timestamp}`). Global active-run caps still apply.

**Dispatch retry** (Scheduler) is Core API delivery. **Job retry** is per-job `retry_policy` in pipeline YAML (failed job execution). They are different.

### 9.4 Deadline (SLA) buffer and lead time

For **Deadline (SLA)** plans, the scheduler starts the run **before** the finish-by deadline:

```
lead = expected_duration_sec + buffer_sec
next_run_at = deadline − lead
```

- **Expected duration** — how long the pipeline usually takes (if `0`, auto-estimate from recent successful runs).
- **Buffer** — padding **added to** duration (not a window *after* the deadline, and **not** used as webhook debounce). Raising buffer from 60s to 500s moves the start ~7 minutes earlier for a ~2-minute task.
- Example: duration 120s + buffer 60s → start **3 minutes** before the deadline.

Optional **Allow late dispatch** (`sla_late_dispatch_policy=best_effort`): if the deadline already passed before the scheduler could start the run, still dispatch (SLA will be marked missed, but the task runs). Default is **strict** — skip with `sla_deadline_missed_before_dispatch`.

**Deadline reserve worker** (`WORKER_DEADLINE_RESERVE`, default `1`): an extra worker process that listens only to `sla_deadline_reserve_queue`. When all normal workers are busy and an SLA task is still `QUEUED`, the scheduler publishes a copy there (shortest expected duration first). Set `WORKER_DEADLINE_RESERVE=0` to disable.

### 9.5 Webhook plans

- URL is `/api/ui/scheduler/webhook/{plan_id}` (stable while the plan exists; deleted ids are **not** reused).
- Auth is the plan **webhook secret**, header `x-scheduler-token` — **not** the UI Bearer login.
- Scripts: **POST** JSON. Browser bookmark: optional **GET** `?token=` (secret may appear in history and logs).
- **Public GET limit** (req/h): empty = unlimited GET, `0` = GET off (POST still works).
- Overlap is controlled by **Max parallel**, not by a buffer/debounce field.

### 9.6 Typical work

1. **Create plan** (modal) — pick **task** and **type**. You can also start from Pipelines → Details → **Create schedule** or Tasks → calendar icon (task preselected).
2. Use row **gear** to change type-specific settings; **Play** to run now; **Filter** to inspect Runs / Events for that plan.
3. If dispatch fails, read **Reason / note** on Runs / Events (Core down, validation, limits, frozen task, maintenance, project not runnable). See §10.1.

Tables use shared TableToolkit (Plan ID sorts newest-first by default).

### 9.7 Dependency plans

A **dependency** plan has no cron. It starts its task when a watched source reaches **SUCCEEDED** (or **FAILED**, if policy is “on success or failure”). **CANCELLED** never fires dependents. Investigation Reset/Run of a single job does **not** fire dependents.

Watchers are **OR** — any matching source is enough. Create at least one watcher **or** a legacy `dependency_event`.

| Watcher | Fires when | Covers | Does not cover |
|---------|------------|--------|----------------|
| **Scheduler plan** | That plan’s run finishes (any trigger of the plan: cron / SLA / webhook / Trigger) | Scheduler-dispatched runs of that plan | UI Trigger of the task with no scheduler run |
| **Task** | That exact `task_id` becomes SUCCEEDED/FAILED | UI Trigger, scheduler rerun of the template | Other task ids |
| **Pipeline** | Any task of `pipeline_group` / `pipeline_name` finishes | Tasks of that YAML | Other pipelines |

Each dependent dispatch writes **why it fired** on the scheduler run (`reason`) and on a `SCHEDULE_TRIGGERED` event. In the UI that is the **Reason / note** column of **Recent scheduler runs** and **Recent scheduler events** (for example `Triggered by task "nightly" SUCCEEDED (scheduler)`). Jobs on that run also get reserved stdin JSON `dagychu_trigger` (no YAML change): `kind` (`scheduler_dependency` or `scheduler_cron` / `scheduler_webhook` / `scheduler_manual` / `scheduler_sla` for ordinary plans), `source_task_id`, alias, status, `matched_watcher`, and plan ids when a plan was watched.

Named `dependency_event` emit over HTTP is an **Enterprise** path; Community uses watchers in the UI.

---

## 10. Logs

**Menu:** Registries → **Logs**.

Three layers for one incident:

- **Change journal** — audited UI/API changes (who changed what).
- **Pipeline operations** — task/job lifecycle events for a selected task (optional job-name focus sorts those rows first).
- **Job runs** — per-job start/finish plus **full captured log** for a `job_run_id` (file from `JOB_LOG_DIR` via ui_backend).

Jump to Tasks / Scheduler from context chips when available. Use after a failed node: error text + output JSON in investigation, then Logs for the same run.

---

## 10.1 Status & reason glossary

Use this when a table cell, event, or operation message looks “internal”. For each term: **what it means**, **where you see it**, **normal or anomaly**, **what to do**.

### Task statuses (Tasks / Monitoring / Scheduler runs)

| Status | Meaning | Where | Normal? | Operator action |
|--------|---------|-------|---------|-----------------|
| **CREATED** | Task row exists; not started yet (often an overlap clone awaiting `/rerun`) | Tasks | Yes (brief) | Wait for dispatch; if stuck minutes → Logs / System |
| **PENDING** | Accepted, waiting to enter the queue | Tasks | Yes (brief) | Wait; if long → check workers / queue |
| **QUEUED** | Published to RabbitMQ; waiting for a worker | Tasks, Monitoring | Yes under load | Scale workers if backlog grows |
| **RUNNING** | Worker is executing the pipeline | Tasks, Monitoring, Scheduler | Yes | Wait; use Investigation / Terminate only if wrong |
| **SUCCEEDED** | Pipeline finished successfully | Tasks, Logs | Yes | None |
| **FAILED** | Pipeline finished with error | Tasks, Logs, Monitoring | Anomaly for the business run | Open task → failed job → Logs; fix & rerun |
| **CANCEL_REQUESTED** | Terminate in progress | Tasks | Transient | Wait for **CANCELLED**; do not spam Rerun |
| **CANCELLED** | Stopped by terminate / force-release | Tasks, Logs | Expected after terminate | Rerun when ready |

**Job run** statuses (`PENDING` / `RUNNING` / `SUCCEEDED` / `FAILED` / …) are per-node inside a task — same intuition at job grain (Logs + Investigation graph).

### Operation event messages (Logs → operations)

| Message / pattern | Meaning | Where | Normal? | Operator action |
|-------------------|---------|-------|---------|-----------------|
| **Republished by … reconcile** (e.g. `worker`, `api`) | Platform found a QUEUED/orphan message gap and re-published the pipeline to the queue | Logs | Often **self-heal** after worker restart / brief outage | If rare → ignore. If frequent → System (workers/Rabbit) + OPERATIONS |
| **Pipeline finalized by status reconcile** | Background reconcile closed a stuck RUNNING/QUEUED task using job outcomes | Logs | Self-heal | Confirm final status matches jobs; escalate if wrong |
| **Pipeline force-released** | Stuck task was force-moved to a terminal state (often after terminate could not reach a worker) | Logs | Anomaly / recovery | Verify no zombie worker; safe to create a new run |
| **`{old} -> {new} (reconcile)`** / **`(sync from pipeline event)`** | Status sync from reconcile or pipeline events | Logs | Usually normal | Ignore unless final state is wrong |
| **Rerun pipeline published to queue** | Scheduler/UI successfully asked Core to enqueue a rerun | Logs | Yes | Watch task become RUNNING |

### Scheduler skip / event reasons (Scheduler → Events / Runs)

| Reason | Meaning | Where | Normal? | Operator action |
|--------|---------|-------|---------|-----------------|
| **global_limit** | Too many active scheduler runs platform-wide | Scheduler Events | Capacity guard | Wait or raise scheduler global cap / finish running plans |
| **job_concurrency_limit** | This plan already has `max_concurrent_runs` in flight (note may be `scheduler_run_in_flight` or `pipeline_task_active`) | Scheduler Events | Expected when Max parallel = 1 and previous still running | Wait for finish, or set Max parallel > 1 if overlap is intended |
| **task_running** | Preflight: linked task still RUNNING (Max parallel = 1) | Scheduler Events | Expected for long jobs vs short cron | Same as concurrency limit; consider Max parallel > 1 for intentional overlap |
| **task_already_queued** | Linked task is QUEUED/PENDING (Max parallel = 1) | Scheduler Events | Expected | Wait; check queue if stuck |
| **task_cancel_requested** | Linked task is terminating | Scheduler Events | Transient | Wait for CANCELLED |
| **task_busy** | Core returned HTTP 409 (task already running) on `/rerun` | Scheduler Events | Should be rare after gates | Check Max parallel / race; inspect task |
| **external_triggers_frozen** | Task freeze blocks scheduler / external starts | Scheduler, Tasks | Expected while investigating | Unfreeze when ready |
| **cron_missed_slot** | Overdue cron slot abandoned (no catch-up) | Scheduler Events | Expected after long outage | Check next_run; trigger manually if needed |
| **overdue_cursor_sweep** | Overdue cursor abandoned after hold window (often after a stuck tick); catch-up preferred when enabled | Scheduler Events / skipped Runs | Anomaly if catch-up was expected | Open plan run history; **Trigger** if the business run is still needed; check engine diagnostics (`overdue_jobs_count`, `tick_body_stale`) |
| **cron_slot_expired** | Slot too old to dispatch meaningfully | Scheduler Events | Expected after long downtime | Same as missed slot |
| **cron_hold_slot_released** | Held concurrency slot released after max age | Scheduler Events | Recovery | Confirm next schedule |
| **sla_deadline_missed_before_dispatch** | SLA deadline passed before start (strict policy) | Scheduler Events | Anomaly for SLA plans | Capacity / duration / buffer; or enable late dispatch on the plan |
| **sla_late_dispatch** | Dispatched after deadline because plan allows best-effort | Scheduler Events | Expected when late policy is on | SLA will likely miss; confirm run completes |
| **api_deduplicated** | Core coalesced a duplicate rerun | Scheduler Runs | Harmless | Ignore |
| **maintenance_window** | Launches blocked by active maintenance | Scheduler Events | Expected during maintenance | Wait or adjust window |
| **project_not_runnable** | Project/runtime policy blocks launch | Scheduler Events | Config | Fix project validation / runtime |
| **overlap_task_spawned** (note on SCHEDULE_TRIGGERED) | Max parallel > 1 and template busy → new task cloned for this slot | Scheduler Events | Expected for overlap | Track the **dispatch_task_id** in Tasks/Runs |

### Playbooks (if I see X → do Y)

1. **See `Republished by worker reconcile` once after a deploy** → ignore; confirm task proceeds to RUNNING/SUCCEEDED.
2. **See `job_concurrency_limit` / `task_running` every tick on a 30‑minute cron whose job lasts ~31 minutes** → either accept skipped slots, or set **Max parallel ≥ 2** so the next tick overlaps (platform clones a task).
3. **See `Pipeline force-released` / unexpected CANCELLED** → check Terminate history and worker health; do not assume business success.
4. **See `external_triggers_frozen` skips** → someone froze the task; unfreeze when investigation ends.
5. **See `global_limit` across many plans** → platform saturated; finish runs or raise global active-run setting with care.

---

## 11. Administration


**Menu:** Management → **Administration** (needs Admin permission).

| Tab | Purpose |
|-----|---------|
| **Users** | Interactive accounts; create users; per-user **API tokens** |
| **Roles & access** | Permission blocks (dashboard, tasks, scheduler, admin, …); pipeline write policies / writable groups |
| **Projects** | Validate & **Connect** pipeline groups (`dagychu-config.yaml`); project activity |
| **Maintenance** | Operator maintenance slots / windows (edition-dependent) |
| **Notifications** | Admin-side notification endpoint settings (when enabled) |

### 11.1 Interactive login vs service tokens

| Kind | How | Use |
|------|-----|-----|
| **User session** | UI login when `AUTH_ENABLED=true` | Humans in the browser |
| **User API token** | Administration → Users → API tokens | Scripts acting as that user (`Authorization: Bearer …`) |
| **`UI_ADMIN_TOKEN`** | Env secret | Bootstrap / admin-style access to UI/API paths that accept it |
| **`WORKER_SERVICE_TOKEN`** | Shared env on api / worker / scheduler | Service-to-service only — **not** for browsers or agents |

Never commit tokens. Rotate by updating `.env` / regenerating user tokens and recreating affected containers.

Community edition uses built-in admin and service accounts only; multi-user administration requires Enterprise — see Settings → License and **`EDITION_COMPARISON.md`**.

---

## 12. Notifications

**Menu:** Management → **Notifications**.

In-app feed of platform events (failures, gates, operational notices). Optional **Slack / Telegram** delivery via user endpoints.

- Notices stream into the **header console**.
- Actions: open origin task, failing run, Logs, Scheduler when metadata is present.

Requires appropriate **Tasks** / notification permissions.

---

## 13. Settings

**Menu:** footer → **Settings**.

- **Appearance** — mobile bottom-nav pins.
- **Locale** — language and display timezone (`ui.timezone` used in tables).
- **Account** — identity shown in the sidebar.
- **Documentation** — this image’s **Guide**, **Operations**, and **Releases**. Pack **`RELEASES.md`** is the same changelog for review before `./update.sh`; Guide/Operations stay image-only. Demo `examples/` and author `skills/` also ship in the pack.
- **Skills** — the same pipeline-author skill markdown as `skills/` in the client pack (read in UI or copy to `.cursor/skills/`).
- **Legal** — Terms / Privacy / Notices baked into the image (English).
- Mobile: pin primary bottom-nav items.

---

## 14. Tables, reports, and shared UX

Many screens share **TableToolkit**:

- Sort / filter / visible columns / page size (often persisted per table id).
- Date/ID columns may sort **newest first** first; second click = ascending; third = clear.
- Export / shareable **table report** URLs where enabled (Scheduler plans report keeps the **full** column set; the Scheduler screen uses a compact set).
- Saved reports can expose selected task, job-run, scheduler, operation, and incident fields as CSV or JSON.
- Optional ClickHouse synchronization publishes report rows to a dedicated `dagychu_reports` database when `CLICKHOUSE_URL` is configured. This is report synchronization for BI access, not Dagychu's primary state store; PostgreSQL remains authoritative. Job `input_json` and `output_json` are available in applicable job-run reports.
- Saved views / presets when offered.
- **Row actions** (Tasks, Scheduler) live in a trailing icon rail — not on the id cell.

---

## 15. External API (agents & integrations)

**Community** does **not** expose `/ext/*`. Create and monitor tasks from the UI (or the Core API behind the UI when auth allows).

The HTTP External API (`/ext/tasks`, …) is an **Enterprise** capability. See pack **`EDITION_COMPARISON.md`** and **Settings → License**. Do not expect Ext helpers in the Community client pack.

---

## 15a. Runtime contracts (trust)

- **Unchanged Python/Bash:** Point pipeline `path:` at your scripts. Jobs read structured JSON from **stdin** and emit a JSON object on **stdout** (logs may mix; prefer `write_stdout_json` / `__JOB_OUTPUT_JSON__`). You do not rewrite scripts into a proprietary SDK.
- **JSON for structured I/O only:** stdin/stdout JSON wires pipeline keys. This is **not** a promise of business-level idempotency or exactly-once side effects.
- **PostgreSQL** is the primary orchestration and state store (tasks, runs, definitions, users, audit).
- **ClickHouse** is optional report synchronization for BI when configured — not required for core pipeline execution.
- **No exactly-once for external actions:** retries and reruns may call external systems more than once. Design jobs and downstream systems accordingly (idempotent keys, safe upserts, or compensating actions).

---

## 16. Playbooks

### 16.1 First day after install

1. Log in (or open UI if auth off).
2. **Settings** → switch to **New** UI if you want the layouts in this guide.
3. **System** — green health.
4. **Administration → Projects** — connect your groups.
5. **Pipelines** — confirm YAML; fix validation.
6. **Create task** from Pipelines → watch **Tasks** investigation → **Logs** if needed.
7. Optional: **Scheduler** — pick a plan type (cron / SLA / webhook / manual / dependency); **Monitoring** for ongoing health.

### 16.2 Incident: failed job

1. **Tasks** → open task → failed node.
2. Read error (includes a tail of stdout/stderr) and open **Logs** for the full captured streams.
3. Fix input (`model.yaml` / Edit) or job code under `runtime/jobs/`.
4. Rerun job or pipeline; use Investigation for partial re-runs.
5. Mark related Overview **concern** Fixed or Expected if it was a known baseline.

### 16.3 Incident: queue backlog

1. **System** → queue / workers.
2. Scale `WORKER_REPLICAS` / check worker logs.
3. Confirm `WORKER_SERVICE_TOKEN` consistency.
4. Review stuck tasks and timeouts.

### 16.4 Freeze during delicate investigation

1. On the task: **Freeze external** (registry lock or Investigation menu).
2. Debug with Investigation without scheduler/ext API interference.
3. **Unfreeze** when ready for production triggers again.

### 16.5 Share context with a teammate

Copy the browser URL with `screen`, `task_id`, and optional `job_name` / `job_run_id`.

---

## 17. Where else to look

| Document | When |
|----------|------|
| **`README.md`** (client pack) | Install & update |
| **`GUIDE.md`** / **Settings → Documentation → Guide** | Day-to-day operator path |
| **`OPERATIONS.md`** / **Settings → Documentation → Operations** | Failures, maintenance, K8s handoff |
| **`RELEASES.md`** / **Settings → Documentation → Releases** | What changed per version |
| **`EDITION_COMPARISON.md`** | Community vs Enterprise |
| **Guide** (this screen) | Same content as pack `GUIDE.md` |

---

*If this text disagrees with your build, trust the behaviour of image tag **`VERSION`** and **Settings → Documentation → Releases**.*
