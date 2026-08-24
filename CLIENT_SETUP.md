# Client install/update (pinned images, no latest)

This package deploys **Dagychu** using Docker Compose and **pinned** image tags (no `latest`).

In the **Enterprise** client artifact this file is copied to **`README.md`**. In the **Community** artifact the public product README is `README.md` and this file is shipped as **`CLIENT_SETUP.md`**. Operator Guide, Operations, Releases, and legal documents ship **inside the image** — after install, open **Settings → Documentation** (and **Settings → Legal**). Pipeline-author skills are in this package under `skills/` and also in the UI under **Settings → Skills**. Demo pipelines/jobs ship under `examples/`. Community packs also include `LICENSE.md`, `NOTICE.md`, `TRADEMARKS.md`, `SECURITY.md`, and `CONTRIBUTING.md`.

## Requirements
- Docker Engine
- Docker Compose v2 (`docker compose`)
- A GitHub Personal Access Token (PAT) with **read:packages** to pull from GHCR.

## Files
- `docker-compose.yml` — production stack (pinned `ghcr.io/...:<version>` images; rendered at release from the repo template)
- `docker-compose.docker-sock.yml` — optional overlay when `JOB_EXECUTOR=docker`
- `dagychu-instance.yaml` — instance settings (monitoring tabs, bootstrap, `ui.legal`); edit next to `.env`. `update.sh` does not overwrite it
- `dagychu-instance.template.yaml` — commented reference template
- `.env.example` — full template (community and enterprise). `install.sh` copies it to `.env` and generates passwords/tokens
- `install.sh` — first-time install (GHCR login, generate `.env`, seed `runtime/`, pull images, start services)
- `update.sh` — update to the version pinned in `docker-compose.yml` (appends missing `.env` keys, does not rotate secrets)
- `reload-projects.sh` — create new `PIPELINE_YAML_DIRS` groups and recreate api/worker/scheduler/ui_backend only
- `scripts/compose_helpers.sh`, `scripts/recover_db_pressure.sh`, `scripts/generate_env.py`, `scripts/bootstrap_runtime.py`
- `examples/` — demo pipeline YAML, job seeds, project config template; Enterprise/Pro also include `examples/external_client/` for `/ext/tasks`
- `skills/` — Cursor-oriented skills for pipeline authors (`skills/README.md`)

## Runtime folder (jobs + pipelines)

`install.sh` creates `runtime/` next to `docker-compose.yml` with three projects:

- `runtime/demo/pipelines/` + `runtime/demo/jobs/` — seeded with demo jobs and pipeline YAML
- `runtime/development/pipelines/` + `runtime/development/jobs/` — empty project
- `runtime/production/pipelines/` + `runtime/production/jobs/` — empty project

Each project root also has `dagychu-config.yaml`. Compose mounts `runtime/` read-only at `/srv/runtime`.

`.env` after install:

- `PIPELINE_YAML_DIRS=demo=demo,development=development,production=production` (enterprise also appends `dagychu_system=repo:system/dagychu_system`)
- `JOB_APP_ROOT=/srv/runtime` (parent of each project's `jobs/` folder is the project root; job `path:` in YAML is relative to the group root)
- `JOB_EXECUTOR=docker` for both Community and Enterprise (`install.sh` attaches `docker-compose.docker-sock.yml`). Set `JOB_EXECUTOR=local` only if you cannot mount the host Docker socket. ClickHouse and other enterprise keys are already present so an upgrade does not require rewriting `.env`.

### Add another project

1. Create `runtime/<name>/pipelines` and `runtime/<name>/jobs` (or let the reload script do it).
2. Add `<name>=<name>` to `PIPELINE_YAML_DIRS` in `.env`.
3. Run `./reload-projects.sh` — recreates **api**, **worker**, **scheduler**, **ui_backend** only. Postgres, RabbitMQ, and Redis stay up.

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
- Do not save the GHCR token to disk. `install.sh` reads it from stdin and does `docker login`.
- Keep `.env` private (it contains secrets).
- Public scheduler launch links are token-based (`/ui/scheduler/webhook/{job_id}`) by design. Treat webhook tokens as secrets: generate per integration, rotate regularly, and revoke (change token / disable job) on suspicion.
- Keep public exposure on the UI entrypoint only. Core WebSocket paths (for example `/ws/tasks/{task_id}`) are not intended as public scheduler trigger channels.

## After install

Open the UI and use **Settings → Documentation** for Guide, Operations, and Releases of this image version, **Settings → Skills** for pipeline-author skill markdown, and **Settings → Legal** for Terms, Privacy, and Notices.

Copy useful extra demos from **`examples/`** into `runtime/<project>/` if needed. Demo pipelines are already seeded under **`runtime/demo/`**.

Ext API policy lives under **`dagychu-instance.yaml` → `external_api:`**. Compose mounts this file into **`ui_backend`** at `/srv/dagychu-instance.yaml` — after edits, `docker compose up -d ui_backend` (no image rebuild required).
