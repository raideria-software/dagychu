# Project setup: groups, config files, connection

## Two config layers

| File | Location | Purpose |
|------|----------|---------|
| `dagychu-instance.yaml` | Deployment root (next to `.env`, compose file) | Instance: bootstrap cron, monitoring tabs, `external_api`, onboarding — **no secrets** |
| `dagychu-config.yaml` | **Each pipeline group root** | Project runtime: Python version, deps, volumes — **per group** |

**Never** place `dagychu-instance.yaml` inside a pipeline group root.

## PIPELINE_YAML_DIRS

Comma-separated `group=root` tokens in `.env`:

```bash
PIPELINE_YAML_DIRS=default=.,dagychu_system=repo:system/dagychu_system
```

| Token | Meaning |
|-------|---------|
| `default=.` | Group `default`, root = `RUNTIME_ROOT` (`/srv/runtime` in compose) |
| `myproj=app` | Group `myproj`, root = `RUNTIME_ROOT/app` → YAML in `app/pipelines/` |
| `demo=repo:examples` | Group `demo`, root = bundled examples in the image |

Each group root **must** contain `pipelines/*.yaml`. Job `path:` is relative to **group root**, not `pipelines/`.

`repo:` prefix = path from the application image root.

### JOB_APP_ROOT

Directory on `PYTHONPATH` for `import jobs....`. Defaults to `RUNTIME_ROOT`. Set explicitly when jobs live in a subfolder:

```bash
JOB_APP_ROOT=/srv/runtime/app
PIPELINE_YAML_DIRS=default=app
```

Align `path:` in YAML with this layout.

## Directory template (typical client install)

```text
runtime/                          # mounted → /srv/runtime
  dagychu-config.yaml
  requirements.txt
  pipelines/
    my_pipeline_v1.yaml
  jobs/
    my_domain/
      my_job/
        latest/
          main.py
          model.yaml
```

Copy `examples/dagychu-config.yaml` → `runtime/dagychu-config.yaml` and adjust.

## dagychu-config.yaml

```yaml
dagychu_config_version: 1
stack:
  python: "3.12"    # 3.10 | 3.11 | 3.12 | 3.13 — exactly one
  bash: false
dependencies:
  python:
    - type: requirements
      path: requirements.txt
volumes:
  external:
    scratch:
      host_path: /tmp/dagychu-myproject
      permission: read_write
```

When `JOB_EXECUTOR=docker`:

- Core builds a **per-group image** from this file on Connect.
- Project dir mounted **read-only** at `/workspace` — writes via `volumes.external` (`read_write`) or `/tmp` inside container.
- Docker socket must be available on api/worker (see **Settings → Documentation → Operations**).

## Connect project (Admin → Projects)

1. Ensure `dagychu-config.yaml` exists at group root.
2. Fix validation errors shown in UI (Python version, requirements path, unsafe volume paths).
3. **Refresh validation**.
4. **Connect** — triggers runtime image build when using docker executor.
5. If `execution.project_execution_gate_enabled: true` in `dagychu-instance.yaml` (legacy env `PROJECT_EXECUTION_GATE_ENABLED`), disconnected/invalid groups **cannot run tasks**.

Platform group `dagychu_system` ships in the image; connect once after install. Do not bind-mount empty `./system` over `/srv/system`.

## Disk sync

API upserts pipeline YAML from disk on startup and every `PIPELINE_DISK_SYNC_INTERVAL_SECONDS` (default 30; `0` = disabled).

- **Adding/editing YAML** → wait for sync or restart `api`.
- **Deleting YAML** does **not** remove DB row — clean stale names in UI if needed.
- **Python job code** → picked up on next run from volume; no DB sync.

## Deploying changes

1. Keep pipelines/jobs in **version control**.
2. Deploy snapshot to server `runtime/` (rsync, CI, git pull).
3. Validate + connect project after config changes.
4. Create/rerun task to test.

## Instance bootstrap (optional)

`dagychu-instance.yaml` → `bootstrap:` ensures Overview monitoring pipeline + scheduler exist. Template: `dagychu-instance.template.yaml` in the client package.
