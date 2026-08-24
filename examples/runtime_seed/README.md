# Bundled runtime seed (committed)

Copied into the Docker image at **`/srv/runtime`** (`RUNTIME_ROOT`).

- `jobs/` — Python job packages (`jobs.*` on worker `PYTHONPATH`). Shared bytes helper: `jobs/_lib/dagychu_stdio.py`.
- `pipelines/` — `*.yaml` loaded into `pipeline_definitions` on startup (`pipeline_name` in YAML or filename stem).

Deploy layouts with nested dirs by setting **`PIPELINE_YAML_DIRS`** (`group=path` to the **group root** that contains `pipelines/`) and **`JOB_APP_ROOT`** if imports need a different directory on `PYTHONPATH`.
