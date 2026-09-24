# DAGYCHU — Operations, troubleshooting & platform handoff

> Dagychu **Community** operations notes for image tag **3.4.4** (see pack `VERSION`). Same file ships in the client pack, Community public repository, and **Settings → Documentation → Operations**.

This document complements pack **`README.md`** / **`GUIDE.md`**. Language: English (international deployments).

---

## 1. What is in the client package

The archive is **compose + env + instance yaml + install/update scripts + operator docs**.

| File | Purpose |
|------|---------|
| `README.md` | Install/update with Docker Compose, `runtime/` layout, security |
| `GUIDE.md` | Day-to-day operator guide (same as in-app Guide) |
| `OPERATIONS.md` | This document |
| `EDITION_COMPARISON.md` | Community vs Enterprise capabilities |
| `RELEASES.md` / `CHANGELOG.md` | Version changelog (newest first) |
| `docker-compose.yml` | Production stack; image tag = pinned version |
| `docker-compose.docker-sock.yml` | Optional overlay when `JOB_EXECUTOR=docker` |
| `.env.example` | Required environment variables |
| `dagychu-instance.yaml` | Instance settings; not overwritten on update |
| `install.sh` / `update.sh` | Pull images and start/update stack |
| `scripts/` | Helpers sourced by install/update |
| `examples/` / `skills/` | Demo pipelines/jobs and author skills |

After install: **Settings → Documentation** (Guide, Operations, Releases, Edition comparison) and **Settings → Legal**.

---

## 2. Install & startup checklist

1. **Host:** Docker Engine + Compose v2; outbound access to pull the pinned image from **GHCR** (Community public image needs no GitHub login).
2. **Secrets:** copy `.env.example` → `.env`; set **`POSTGRES_PASSWORD`**, **`UI_ADMIN_TOKEN`**, **`WORKER_SERVICE_TOKEN`** and any auth-related vars; never commit `.env`.
3. **Runtime:** populate **`./runtime`** next to compose with `pipelines/` and `jobs/` (see `README.md`). Mount is **read-only** in production compose for `api`/`worker`/`scheduler`. Install/update scripts auto-create missing runtime tree for all non-`repo:` groups from **`PIPELINE_YAML_DIRS`**.
4. **First start:** `./install.sh` → wait for healthchecks → browse `http://<host>:<FRONTEND_HOST_PORT>`.
5. **Smoke test:** UI loads → **Pipelines** lists your YAML-synced definitions → create a trivial task or use a demo pipeline if provided.

---

## 3. Best practice — own Git repo as source of truth

- Store **pipeline YAML** and **job code** in Git; deploy to the server with CI/CD (artifact, rsync, pull on boot).
- Keep **one clear mapping** from repo tree to **`PIPELINE_YAML_DIRS`** and **`JOB_APP_ROOT`** (document it in your internal wiki).
- **Tag** releases of automation separately from Dagychu image version if needed (`automation-v1.2` + `dagychu-2.0.2`).
- After deploying new YAML, Core API **re-syncs from disk on a timer** (default **30s**, `PIPELINE_DISK_SYNC_INTERVAL_SECONDS`; **0** = startup only). Restart **`api`** if you need an immediate refresh or disabled periodic sync.
- Prefer **`model.yaml`** per job so the UI and API agree on input shape.

---

## 4. When it does not start or the UI is empty

Work **top-down**; collect logs for support in §6.

### 4.1 Docker / Compose

- `docker compose ps` — all services `running` or `healthy`?
- `docker compose logs api worker ui_backend scheduler --tail 200` — errors on startup?

### 4.2 Database & queue

- Postgres healthcheck failing → wrong **`DATABASE_URL`** / password / volume permissions.
- RabbitMQ healthcheck failing → credentials; note prod compose sets **`RABBITMQ_DEFAULT_USER`** / **`PASS`** from env.

### 4.3 Authentication

- If **`AUTH_ENABLED=true`**, **`UI_ADMIN_TOKEN`** / user tokens must match what operators use; **`WORKER_SERVICE_TOKEN`** must match between **api**, **worker**, and **scheduler** where applicable.
- 401/403 on `/ui/*` → check token headers and env drift after `.env` edits (restart stack).
- Session lifetime policy (UI login sessions):
  - **`AUTH_SESSION_IDLE_TTL_HOURS`**: idle timeout window (session is extended while active).
  - **`AUTH_SESSION_MAX_TTL_HOURS`**: absolute max lifetime since session creation.
  - **`AUTH_SESSION_TOUCH_INTERVAL_MIN`**: DB write throttle for `last_seen_at` / expiry refresh.
  - Balanced recommendation: `24 / 720 / 5` (hours / hours / minutes).

### 4.4 Pipelines missing

- **`runtime/`** empty or wrong path relative to compose file.
- **`PIPELINE_YAML_DIRS`** does not point at a directory that contains **`pipelines/*.yaml`**.
- YAML **validation** failed — see **api** logs (`Pipeline disk sync`).
- **`python_executable`** in YAML points to a binary **not present inside the API container** (common with Windows-only venv paths).

### 4.5 UI loads but tasks never run

- **Worker** not consuming → check RabbitMQ management (if exposed in dev only) or **System** screen; worker logs.
- **JOB_CONCURRENCY** = 0 or worker crash loop.
- Tasks stuck **queued** — Core not publishing or wrong queue name (**`QUEUE_NAME`**).

### 4.6 Scheduler diagnostics (runs missing overnight)

If a scheduler plan appears to run only when operators open the UI, verify the scheduler loop directly:

- Check scheduler health snapshot:
  - `curl -s http://127.0.0.1:9020/health | jq`
  - Confirm `engine.running=true` and `engine.last_tick_ok_at` updates over time.
- Check leader state:
  - `engine.is_leader` should be `true` on the instance expected to dispatch jobs.
  - In multi-instance setups, non-leaders intentionally do not dispatch.
- Check one scheduler job in depth:
  - `curl -s "http://127.0.0.1:9010/ui/scheduler/jobs/<job_id>/diagnostics" -H "Authorization: Bearer <UI_ADMIN_TOKEN>" | jq`
  - Inspect `job.next_run_at`, `due_in_seconds`, `skip_reason_counts`, `recent_events`, `recent_runs`.
- Typical reasons in `skip_reason_counts`:
  - `project_not_runnable` (project gate / dagychu-config validation)
  - `global_limit` or `job_concurrency_limit` (active run limits)
- Cron reminder:
  - `0 * * * *` means top of each hour (UTC in current scheduler trigger implementation).

### 4.7 Frontend blank or API errors

- Wrong **`FRONTEND_HOST_PORT`** or reverse proxy stripping `/api` prefix.
- Browser console: CORS only applies in split dev setups; prod serves UI from **ui_backend** in the same image.
- Console errors referencing **`bootstrap-autofill-overlay.js`** / **`AutofillOverlayContentService`**: a **password-manager browser extension** (Bitwarden, 1Password, etc.), not Dagychu. Disable the extension for your UI origin or ignore the error.

### 4.8 Docker job runtime and notifications

- **`JOB_EXECUTOR=docker`**: **api** and **worker** need access to a Docker Engine API. The shipped Compose files mount **`/var/run/docker.sock`** into those services; alternatively set **`DOCKER_HOST`** to a TCP endpoint your platform provides. Without this, image builds (admin **Projects**) and containerized job steps will fail.
- **Admin → Projects → Connect** with **`JOB_EXECUTOR=docker`**: Core builds or reuses the project image **before** setting **connected**. If the image build fails (e.g. **`pip install`**), the API returns **503** and **`detail`** includes a **tail of the Docker build log**; the project is **not** left in a false “connected” state. **Refresh validation** still returns **200** after updating validation; check **`docker_build_ok`** / **`docker_build_message`** in the JSON if the image step fails. **ui_backend** proxies those calls with a long read timeout (**`CORE_HTTP_LONG_TIMEOUT_SEC`**, default **1800**); raise it if builds exceed that. If a reverse proxy sits in front of **ui_backend**, increase its read timeout for **`/api/ui/admin/projects/*/connect`** and **`.../validate-and-refresh`** as well.
- **`JOB_EXECUTOR=local`** (default): jobs run as subprocesses on the worker host; no Docker socket required. If you never use **`docker`**, you may remove the **`/var/run/docker.sock`** bind mounts from **api** and **worker** in Compose for tighter isolation.
- **Lifecycle:** When an operator connects a project (admin **Projects**), Core validates **`dagychu-config.yaml`** and builds a **per-project Docker image** (tag derived from config/deps hashes). **Each job step** runs in a **new short-lived container** from that image, then the container is removed. There is **no** long-lived container per project.
- **Mounts inside the job container:** The pipeline group root is bind-mounted at **`/workspace` read-only**. The orchestrator does not write into the project tree (which may be replaced by git pulls on the host). **Write outputs** to **`volumes.external`** paths marked **`read_write`** in **`dagychu-config.yaml`**, or to **`/tmp`** inside the container (ephemeral, discarded when the container exits).
- **Build context:** Image builds copy the project tree into a writable staging directory under **`DAGYCHU_BUILD_ROOT`** (named volume in shipped Compose), not into **`./runtime`** on the host — production **`./runtime`** stays read-only for **api**/**worker**.
- **Step payload bind:** Each Docker job step receives JSON input via a file bind-mounted from **`DAGYCHU_BUILD_ROOT/payloads/`** (not under the read-only project tree). By default, install/update scripts auto-discover the mountpoint for compose volume `dagychu_build` and write it into **`DAGYCHU_DOCKER_BIND_BUILD_HOST`** when missing. Manual override is still supported for custom platforms.
- **Runtime bind for multi-project:** one **`DAGYCHU_DOCKER_BIND_RUNTIME_HOST`** points to shared runtime root (usually `./runtime`). Multiple project groups from **`PIPELINE_YAML_DIRS`** live inside that root; no per-group bind env is required.
- **Dev helper for missing host paths:** if external volume `host_path` is missing and jobs fail with Docker bind errors, you can set:
  - `DAGYCHU_DOCKER_AUTO_CREATE_MISSING_HOST_PATHS=true`
  - worker/admin preflight first attempt `mkdir -p` for missing `read_write` external volume paths.
  - if the original host path is still not visible to Docker daemon (common in local dev), Dagychu remaps bind source to deterministic fallback under:
    - `DAGYCHU_BUILD_ROOT/external-fallback/<pipeline_group>/<original-host-path-components>`
  - container `mount_path` stays unchanged; only bind `source` is remapped for local/dev compatibility.
  - keep it **false in production** unless your platform policy explicitly allows auto-provisioned bind directories.
- **Cancel / terminate:** The UI can call **Cancel** (SIGTERM for local subprocess) or **Terminate pipeline** (SIGKILL / Docker kill). The worker reconnects to RabbitMQ automatically after connection drops; scaling **multiple worker replicas** is supported for throughput.
- **Worker scale:** set **`WORKER_REPLICAS`** in `.env` (default `1`). `./install.sh` and `./update.sh` run `docker compose up --scale worker=N`. This is **not** the same as `JOB_CONCURRENCY` (parallel jobs inside one pipeline). For production with concurrent or long-running tasks, raise `WORKER_REPLICAS` and verify **System → Queue → consumers** matches. See [PERFORMANCE_RUNBOOK.md](../operations/PERFORMANCE_RUNBOOK.md) (Worker throughput model).
- **Project image MVP** builds from **`dependencies.python`** entries of type **`requirements`** only (plain `pip install -r`); Poetry/Pipenv-style locks are not generated inside the Dockerfile yet. The generated image layer installs **`libpq-dev`** (with **`build-essential`**) so **`psycopg2`** can compile when no matching wheel exists (e.g. some **aarch64** builds). You can use **`psycopg2-binary`** or **`psycopg`** wheels instead to avoid compiling.
- **`DAGYCHU_PROJECT_CONFIG_POLL_SECONDS`**: when **> 0**, the worker periodically re-validates connected projects; set **0** to disable polling.
- **Notifications**: in-app feed under **Notifications** (requires **Tasks** access). Optional **Slack** webhooks and **Telegram** `sendMessage` use per-user endpoints configured in that screen; webhook URLs and bot tokens are masked in API responses.
- **News summary stream** (Monitoring and Task/JOBS): built from latest-per-job runs. If operators report missing highlights, verify job `model.yaml` includes `news_chat.output_keys` and that paths match actual `output_json` structure.

### 4.9 First install: `/ready` fails with `runtime schema is not ready`

Symptom on a **new** empty Postgres volume (existing installs with schema are fine):

- `update.sh` / health wait: `init_db verify failed: runtime schema is not ready; run init_db migrate`
- API logs: `UndefinedTable` for `job_runs` / `table_reports`

Cause: prod compose defaults **`INIT_DB_STARTUP_MODE=verify`** (read-only). On an empty DB verify fails and API never becomes ready.

**Immediate workaround (any 3.3.x image):**

```bash
# in .env
INIT_DB_STARTUP_MODE=migrate
docker compose up -d --force-recreate api
# wait until curl -sf http://127.0.0.1:8000/ready
```

Then start the rest of the stack / re-run `./update.sh`. After the schema exists you may set `INIT_DB_STARTUP_MODE=verify` again (optional; migrate stays idempotent).

**Fixed in source:** API `verify` auto-falls back to `migrate` when the schema is missing; `install.sh` seeds `INIT_DB_STARTUP_MODE=migrate` on first install when the key is unset.

---

## 5. Day-2 maintenance

- **Upgrades:** read pack **`RELEASES.md`** first; replace `docker-compose.yml` from a newer client package, run `./update.sh` (does not edit `.env`; prompts if new keys are missing, then pulls images and recreates containers; volumes preserved). **Do not** use `./install.sh` on a live deployment — it replaces `.env` from example.
- **Rollback:** pin `docker-compose.yml` (and pack files) to the previous image tag / client pack version, run `./update.sh` (or `docker compose up -d`). Postgres/RabbitMQ volumes are kept; do not run destructive volume deletes. Schema migrations are generally forward-compatible — if a release notes a hard migration, follow that release’s rollback note.
- **Backups:** persist **`postgres_data`** volume (or external managed DB); document restore procedure. PostgreSQL is the primary state store.
- **ClickHouse (optional):** report sync only when configured; not required for core runs.
- **Logs:** job logs on worker volume **`JOB_LOG_DIR`** — plan retention (**`JOB_LOG_TOTAL_MAX_MB`**).
- **Secrets rotation:** update `.env`, recreate containers; ensure scheduler/worker pick up new service token.
- **Disk space:** Postgres + RabbitMQ volumes + job logs.
- **Retries / external side effects:** Dagychu does **not** provide exactly-once delivery to external systems; design jobs for safe retry.

---

## 6. Information to hand off to **Kubernetes** / platform engineering

The Compose file is the **reference topology**. A typical mapping:

| Compose service | Kubernetes direction |
|-----------------|----------------------|
| `api` | Deployment + Service (ClusterIP); expose only via ingress if needed internally |
| `worker` | Deployment; scale replicas **with care** — multiple workers consume the same queue by design |
| `scheduler` | Single-replica Deployment or leader-elected workload if you run multiple instances |
| `ui_backend` | Deployment; ingress for operator UI; same image tag as api/worker/scheduler |
| `postgres` | StatefulSet or **managed RDS/Cloud SQL** (recommended for prod) |
| `rabbitmq` | StatefulSet or **managed AMQP** |

**Carry over these env groups:**

- **Core:** `DATABASE_URL`, `RABBITMQ_URL`, `QUEUE_NAME`, `RUNTIME_ROOT`, `PIPELINE_YAML_DIRS`, `JOB_APP_ROOT`, `AUTH_ENABLED`, `UI_ADMIN_TOKEN`, `WORKER_SERVICE_TOKEN`, `APP_ENV`
- **Worker:** same DB/queue/runtime + `WORKER_REPLICAS`, `JOB_CONCURRENCY`, `JOB_TIMEOUT_SECONDS`, `JOB_LOG_*`
- **Scheduler:** DB, `TASK_API_URL` → Core service URL, scheduler tuning vars, `WORKER_SERVICE_TOKEN`
- **Ui_backend:** `CORE_API_URL`, `SCHEDULER_API_URL`, `JOB_LOG_DIR`, RabbitMQ HTTP for diagnostics, CORS if split front/back

**Health endpoints:** Core `/health`, Scheduler `/health`, Ui_backend `/health` — use for **liveness/readiness**.

**Config & runtime:**

- Mount **`runtime/`** as ConfigMap/CSI **read-only** or sync from Git; size limits apply for ConfigMaps — large job trees often use **PVC** or init container sync.
- **Job logs:** shared **ReadWriteMany** PVC or object storage adapter (product today expects filesystem paths).

**Images:** same GHCR tag for all app containers (**`VERSION`**).

---

## 7. Planned / follow-up work (indicative TODO)

Enterprise packaging starter artifacts live under **`deploy/helm/dagychu/`** (Chart `0.1.0`); for backup/restore targets and drill checklist see **`docs/operations/DISASTER_RECOVERY.md`** (RTO 4h / RPO 24h as planning targets).

Not a commitment; tracks common product gaps for enterprise and K8s:

- **Helm chart** or official **Kubernetes manifests** with sane defaults for HA Postgres/RabbitMQ.
- **External secrets** integration (Vault, cloud secret manager) instead of flat `.env`.
- **Observability:** OpenTelemetry traces/metrics across api/worker/scheduler; structured log schema.
- **Runtime sync:** optional file watcher or Git-driven operator for **sub-second** reloads (today: periodic API sync + job code read at run time).
- **High-availability scheduler** documented leader election story when running >1 replica.
- **Log shipping** from `JOB_LOG_DIR` to centralized logging (agent pattern).
- **Ext API SSE:** stream intermediate job outputs to automation clients (`GET /ext/tasks/{id}/stream`); pipeline YAML flag for public outputs (success-only); richer `/result` on `FAILED` (`failed_job`, `error_text`).

---

## 8. Support escalation template

When opening a ticket internally or to the vendor, attach:

1. **Dagychu version** (`VERSION` from package / image tag).
2. `docker compose ps` (or k8s `kubectl get pods`) output.
3. Last **200 lines** of logs: `api`, `worker`, `scheduler`, `ui_backend`.
4. **Redacted** `.env` keys (names only) and confirmation `PIPELINE_YAML_DIRS` / `JOB_APP_ROOT`.
5. One **failing task id** and **job_run_id** if applicable.
6. Whether issue is **install**, **sync**, **run**, or **UI**.
