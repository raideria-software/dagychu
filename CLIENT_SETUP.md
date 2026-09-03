# Client install/update (pinned images, no latest)

This package deploys **Dagychu** using Docker Compose and **pinned** image tags (no `latest`).

In the **Enterprise** client artifact this file is copied to **`README.md`**. In the **Community** artifact the public product README is `README.md` and this file is shipped as **`CLIENT_SETUP.md`**. Operator Guide, Operations, Releases, and legal documents ship **inside the image** — after install, open **Settings → Documentation** (and **Settings → Legal**). Pipeline-author skills are in this package under `skills/` and also in the UI under **Settings → Skills**. Demo pipelines/jobs ship under `examples/`. Community packs also include `LICENSE.md`, `NOTICE.md`, `TRADEMARKS.md`, `SECURITY.md`, and `CONTRIBUTING.md`.

## Requirements
- Docker Engine
- Docker Compose v2 (`docker compose`)
- Outbound access to pull the pinned image from GHCR (Community: public `ghcr.io/raideria-software/dagychu` — no GitHub account, PAT, or `docker login` required)

## Files
- `docker-compose.yml` — production stack (pinned `ghcr.io/...:<version>` images; rendered at release from the repo template)
- `docker-compose.docker-sock.yml` — optional overlay when `JOB_EXECUTOR=docker`
- `dagychu-instance.yaml` — instance settings (monitoring tabs, bootstrap, `ui.legal`); edit next to `.env`. `update.sh` does not overwrite it
- `dagychu-instance.template.yaml` — commented reference template
- `.env.example` — full template (community and enterprise). `install.sh` copies it to `.env` and generates passwords/tokens
- `install.sh` — first-time install (generate `.env`, seed `runtime/`, pull images, start services)
- `update.sh` — update to the version pinned in `docker-compose.yml` (appends missing `.env` keys, does not rotate secrets)
- `reload-projects.sh` — create new `PIPELINE_YAML_DIRS` groups and recreate api/worker/scheduler/ui_backend only
- `scripts/compose_helpers.sh`, `scripts/recover_db_pressure.sh`, `scripts/generate_env.py`, `scripts/bootstrap_runtime.py`
- `examples/` — demo pipeline YAML, job seeds, project config template; Enterprise/Pro also include `examples/external_client/` for `/ext/tasks`
- `skills/` — Cursor-oriented skills for pipeline authors (`skills/README.md`)

## Runtime folder (jobs + pipelines) & Project Code Placement

`install.sh` creates `runtime/` next to `docker-compose.yml` with three initial projects:

- `runtime/demo/pipelines/` + `runtime/demo/jobs/` — seeded with demo jobs and pipeline YAML
- `runtime/development/pipelines/` + `runtime/development/jobs/` — starter development project
- `runtime/production/pipelines/` + `runtime/production/jobs/` — starter production project

Each project root also has `dagychu-config.yaml`. Compose mounts `runtime/` read-only at `/srv/runtime`.

---

## First project walkthrough (Step-by-step from zero to scheduled run)

Follow these 8 steps to deploy your custom repository and launch your first pipeline:

### Step 1: Create or choose a project directory under `runtime/`
You can use the starter `runtime/development` (or `runtime/production`) directory, or create a brand new folder:
```bash
mkdir -p runtime/my_analytics
```

### Step 2: Sync your repository (Git / CI/CD)
Clone your repository or set up your deployment runner to sync code directly into the project folder:
```bash
git clone git@github.com:my-org/my-analytics-repo.git runtime/my_analytics
# or inside CI/CD:
# rsync -av --exclude '.git' ./src/ /opt/dagychu/runtime/my_analytics/
```

### Step 3: Configure `dagychu-config.yaml` at project root
Create `runtime/my_analytics/dagychu-config.yaml` (copy from `examples/dagychu-config.yaml` as a base). This tells Dagychu which Python runtime and dependencies to prepare (`requirements.txt` or `pyproject.toml`):
```yaml
dagychu_config_version: 1
stack:
  python: "3.12"      # 3.10 | 3.11 | 3.12 | 3.13
  bash: false
dependencies:
  python:
    # Option A: Standard pip requirements.txt
    - type: requirements
      path: requirements.txt

    # Option B: Poetry pyproject.toml
    # - type: poetry
    #   path: pyproject.toml
volumes:
  external:
    scratch:
      host_path: /tmp/dagychu-my-analytics
      permission: read_write
```

### Step 4: Create `pipelines/` directory and author your pipeline YAML
Create a `pipelines/` subdirectory and add your pipeline manifest (e.g. `runtime/my_analytics/pipelines/daily_etl.yaml`).
*(For pipeline YAML syntax, input wiring, and schema contracts, see the `skills/dagychu/pipeline-yaml.md` skill or UI documentation)*:
```yaml
pipeline_name: daily_etl
pipeline_tags: [analytics, daily]
jobs:
  - job_name: extract_data
    ui_name: 1. Extract Data
    path: jobs/extract/main.py
    deps: []
    outputs: [raw_records, count]
    inputs:
      date: initial

  - job_name: transform_and_load
    ui_name: 2. Transform & Load
    path: jobs/transform/main.py
    deps: [extract_data]
    outputs: [status, loaded_rows]
    inputs:
      records:
        job: extract_data
        key: raw_records
```

### Step 5: Inform Dagychu about the new project (`reload-projects.sh`)
If you created a new project directory (e.g. `my_analytics`), add it to `PIPELINE_YAML_DIRS` in `.env`:
```bash
# In .env:
PIPELINE_YAML_DIRS=demo=demo,development=development,production=production,my_analytics=my_analytics
```
Then run the reload script to register the project without taking down databases:
```bash
./reload-projects.sh
```

### Step 6: Validate & Connect in Dagychu UI
1. Open the Dagychu UI in your browser (`http://<host>:3000`).
2. Go to **Administration → Projects**.
3. Select your new project group (`my_analytics`).
4. Click **Refresh validation** to check syntax and requirements.
5. Click **Connect** (triggers runtime image build when using Docker executor).

### Step 7: View your pipelines in the Pipelines registry
Go to the **Pipelines** tab in the main navigation. Your `daily_etl` pipeline and its interactive DAG graph will be visible and ready for execution.

### Step 8: Create a Task and configure a Scheduler plan
1. Click **Create task** on your pipeline, supply test input JSON (e.g. `{"date": "2026-08-31"}`), and click **Run now**.
2. To automate runs: go to **Scheduler → New plan**, select your project group and pipeline, and configure a **cron**, **webhook**, **SLA**, or **dependency** trigger.

---

### Where and how to place your code (Summary)

The `development` and `production` folders are **recommended conventions**, not hard requirements. You can deploy your own codebase in several convenient ways:

1. **Direct Git clone / CI/CD into `runtime/development` or `runtime/production`:**
   Configure your deployment pipeline or run `git pull` directly inside `runtime/development` (or `runtime/production`).
2. **Dedicated custom project folders:**
   Clone your repo into `runtime/<my_project_name>`. Add `<my_project_name>=<my_project_name>` to `PIPELINE_YAML_DIRS` in `.env` and run `./reload-projects.sh`.

#### Core requirements for any Dagychu project:

1. **`dagychu-config.yaml`** at the project group root: defines the Python runtime stack (`stack.python`), dependencies (`dependencies.python` pointing to `requirements.txt` or `pyproject.toml`), and external mount volumes.
2. **`pipelines/` directory**: contains YAML pipeline manifests (`*.yaml`) that describe the execution DAG and job dependencies.
3. **Job code**: Python scripts or modules (by default under `jobs/`, or any relative path referenced in your pipeline YAML `path:` fields).

#### Connecting the project:
After placing your project files, open **Administration → Projects** in the UI, click **Refresh validation**, and click **Connect**. If `execution.project_execution_gate_enabled: true` is set, tasks will only execute once the project group is connected.

`.env` after install:

- `PIPELINE_YAML_DIRS=demo=demo,development=development,production=production` (enterprise also appends `dagychu_system=repo:system/dagychu_system`)
- `JOB_APP_ROOT=/srv/runtime` (parent of each project's `jobs/` folder is the project root; job `path:` in YAML is relative to the group root)
- `JOB_EXECUTOR=docker` for both Community and Enterprise (`install.sh` attaches `docker-compose.docker-sock.yml`). Set `JOB_EXECUTOR=local` only if you cannot mount the host Docker socket. ClickHouse and other enterprise keys are already present so an upgrade does not require rewriting `.env`.

### Add another project

1. Create `runtime/<name>/pipelines` and `runtime/<name>/jobs` (or let the reload script do it, or `git clone` your repo into `runtime/<name>`).
2. Ensure `runtime/<name>/dagychu-config.yaml` exists and is configured.
3. Add `<name>=<name>` to `PIPELINE_YAML_DIRS` in `.env`.
4. Run `./reload-projects.sh` — recreates **api**, **worker**, **scheduler**, **ui_backend** only. Postgres, RabbitMQ, and Redis stay up.
5. In UI **Administration → Projects**, click **Refresh validation** → **Connect**.

YAML files in existing groups also sync on `PIPELINE_DISK_SYNC_INTERVAL_SECONDS` without a reload. A **new group** in `.env` needs `reload-projects.sh`.

## Quick start
1. Unpack the provided archive/folder.
2. Platform Overview is baked into the image at `/srv/_builtin/dagychu_system`. Do **not** use `docker-compose.override.yml` with empty `./system:/srv/system`.
3. Run:
   - `./install.sh`

   That copies `.env.example` → `.env`, generates all passwords and tokens, and creates `runtime/demo|development|production`. The script then lists what was created and waits for **`y`** before pulling images and starting containers. Review `.env` / `dagychu-instance.yaml` first if you want. Non-interactive: `DAGYCHU_INSTALL_ASSUME_YES=1 ./install.sh`.
4. Open the UI (install.sh prints the URL and admin token in color). Default: `http://<host>:3000` (or `FRONTEND_HOST_PORT`). Sign in by pasting the UI admin token.

Public exposed port in `.env`:
- `FRONTEND_HOST_PORT`

`ui_backend` serves the built frontend UI from inside the same image.
All other services (`api`, `scheduler`, `postgres`, `rabbitmq`) communicate only inside Docker network and are not exposed externally in production compose.

## Updating
When you receive a **new client package** (new version), replace `docker-compose.yml` (and `install.sh` / `update.sh` / `scripts/` if they changed) and run:
- `./update.sh`

**Do not run `./install.sh` on an existing deployment** — it resets `.env` from `.env.example` and generates new secrets. `update.sh` pulls new images, **appends missing keys** from `.env.example` without changing existing secrets, enables `dagychu_system` on enterprise, reapplies `WORKER_REPLICAS` scale, and leaves `dagychu-instance.yaml`, `runtime/`, and database volumes intact. Documentation and the onboarding tour come from the new image.

## Scaling workers

Parallel **pipelines (tasks)** require multiple worker **processes**, not only a higher `JOB_CONCURRENCY`:

| Variable | Meaning |
|----------|---------|
| `WORKER_REPLICAS` | Number of worker containers (RabbitMQ consumers). Default `1`. |
| `JOB_CONCURRENCY` | Parallel job steps **inside** one pipeline on one process. |

1. Set `WORKER_REPLICAS` in `.env` if you want more than the default. `update.sh` appends the key from `.env.example` when it is missing (existing values are kept).
2. Run `./update.sh` (applies `docker compose up --scale worker=N` automatically).
3. Confirm **System → Queue → consumers** equals `WORKER_REPLICAS`.

For jobs that run 30–50 minutes, also raise `JOB_TIMEOUT_SECONDS` (e.g. `3600`). Plan host CPU/RAM for `WORKER_REPLICAS × JOB_CONCURRENCY` when using Docker job executor.

## Security notes
- Keep `.env` private (it contains secrets).
- Public scheduler launch links are token-based (`/ui/scheduler/webhook/{job_id}`) by design. Treat webhook tokens as secrets: generate per integration, rotate regularly, and revoke (change token / disable job) on suspicion.
- Keep public exposure on the UI entrypoint only. Core WebSocket paths (for example `/ws/tasks/{task_id}`) are not intended as public scheduler trigger channels.

## Product telemetry

Dagychu contains an optional product telemetry module.

The default is:

- **Community:** enabled;
- **Enterprise:** disabled.

Administrators can review or change the setting under **Administration → Product Telemetry**.

When enabled, Dagychu sends a small telemetry report to:

```text
https://telemetry.raideria.com
```

approximately once every 24 hours.

The report contains only:

- a random installation ID generated by Dagychu;
- Dagychu version;
- Dagychu edition;
- the aggregate number of runs during the previous 24 hours;
- the aggregate number of pipelines that were active during the previous 24 hours.

The telemetry service may derive an approximate country from the network address used to receive the request. The source IP address is not stored as part of the product telemetry dataset.

Dagychu does not send workflow or job names, workflow code, YAML definitions, logs, execution parameters, runtime variables, secrets, usernames, organization names, hostnames, database names, filesystem paths, or hardware identifiers.

Telemetry can be configured in `dagychu-instance.yaml`:

```yaml
telemetry:
  enabled: true
```

and may be overridden with:

```text
DAGYCHU_TELEMETRY_ENABLED=true|false
```

When the environment variable is set, it takes precedence over the instance configuration and the Administration toggle.

Disabling telemetry prevents Dagychu from sending product telemetry requests. Telemetry availability or delivery failures never affect workflow execution or normal Dagychu operation.

## After install

Open the UI and use **Settings → Documentation** for Guide, Operations, and Releases of this image version, **Settings → Skills** for pipeline-author skill markdown, and **Settings → Legal** for Terms, Privacy, and Notices.

Copy useful extra demos from **`examples/`** into `runtime/<project>/` if needed. Demo pipelines are already seeded under **`runtime/demo/`**.

Ext API policy lives under **`dagychu-instance.yaml` → `external_api:`**. Compose mounts this file into **`ui_backend`** at `/srv/dagychu-instance.yaml` — after edits, `docker compose up -d ui_backend` (no image rebuild required).
