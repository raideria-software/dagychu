---
name: dagychu
description: >-
  Guides Dagychu pipeline and job development on a deployed instance: job scripts
  with model.yaml, pipeline YAML, dagychu-config.yaml, project setup, and
  debugging. Use when creating or changing jobs, pipelines, or project config.
  Optional best-practice add-ons: demo CTO docs and data-platform (DQ/SQL) patterns.
---

# Dagychu — jobs, pipelines, projects

Skill for **operators and pipeline authors** extending a Dagychu deployment. Canonical layout: **group root** → `dagychu-config.yaml` + `pipelines/` + `jobs/`.

## Before you code — ask the user

| Topic | Questions |
|-------|-----------|
| **Scope** | New job, new pipeline, or change existing? Which **pipeline group** (`default`, custom label from `PIPELINE_YAML_DIRS`)? |
| **Layout** | Where is the group root on disk (`runtime/`, bundled examples, separate git repo)? How are `path:` entries written relative to that root? |
| **Execution** | `JOB_EXECUTOR=process` or `docker`? Python version and `requirements.txt` path for `dagychu-config.yaml`? |
| **Inputs** | What goes in task `initial_input_json`? Per-job constants? Upstream job outputs? Need `merge` + `priority`? |
| **Outputs** | Which keys does each job expose in `outputs:`? What should appear in UI **News summary** (`news_chat`)? |
| **Failure** | Empty data → `raise` or controlled `sys.exit(1)`? Any job must run after upstream failure (`run_on_upstream_failure`)? |
| **Gate** | Is `execution.project_execution_gate_enabled` true in `dagychu-instance.yaml` (legacy env `PROJECT_EXECUTION_GATE_ENABLED` still works)? Has the group been **Connected** in Admin → Projects? |
| **DQ / SQL** (best practice, data projects) | Source tables, target mart, Jinja params (`month_offset` etc.), pre/post DQ files? Skip unless the user has an analytics/ETL layout. |
| **Demo doc** (best practice, demo catalogue) | Only when publishing a customer-facing demo pipeline: business outcome, prerequisites, who runs it, demo vs production scope. |

If unclear, read the user's `PIPELINE_YAML_DIRS`, `runtime/` tree, and `.env` before proposing paths.

---

## Non-negotiable rules

1. **YAML on disk is the source of truth** for pipeline DAGs — not UI-only edits. The database syncs from disk.
2. **Job `path:`** resolves relative to the **pipeline group root**, not `pipelines/`.
3. **Worker contract**: job reads JSON from **stdin**, writes **one JSON object** to **stdout** on success; non-zero exit on failure. Logs go to **stderr**. Large UTF-8 JSON: `jobs/_lib/dagychu_stdio.py` (`write_stdout_json`).
4. **`model.yaml`** sits next to the job script; drives UI templates, schemas, and News summary paths.
5. **`dagychu-config.yaml`** at **group root** (same level as `pipelines/`) — required to validate/connect when the execution gate is on or `JOB_EXECUTOR=docker`.
6. **Do not** put `dagychu-instance.yaml` inside a group root — it lives at deployment root (next to `.env`).

---

## Workflows

### A) Connect a new project (group)

```
- [ ] Define group in PIPELINE_YAML_DIRS (e.g. default=.)
- [ ] Create <group_root>/pipelines/ and jobs tree
- [ ] Copy examples/dagychu-config.yaml → <group_root>/dagychu-config.yaml
- [ ] Set stack.python + dependencies.python (requirements path)
- [ ] Admin → Projects → Refresh validation → Connect
- [ ] Place at least one valid pipeline YAML; wait for disk sync (~30s) or restart api
```

Details: [project-setup.md](project-setup.md)

### B) Create or change a job

```
- [ ] Script: stdin JSON → validate → work → one JSON object on stdout (`write_stdout_json` or `print(json.dumps(...))`)
- [ ] model.yaml: template, input_schema, output_schema; optional news_chat
- [ ] Ensure path in pipeline YAML matches layout under group root
- [ ] Python-only edits: no DB sync needed; rerun task to pick up code
```

Details: [jobs-and-model.md](jobs-and-model.md)

### C) Create or change a pipeline

```
- [ ] Add/edit <group_root>/pipelines/<name>.yaml
- [ ] Unique job_name per file; acyclic deps; outputs list matches stdout keys
- [ ] Wire inputs: initial | job | const | merge
- [ ] Validate in UI (Pipelines) before relying on the pipeline
- [ ] Confirm pipeline appears after disk sync
```

Details: [pipeline-yaml.md](pipeline-yaml.md)

### D) Demo pipeline — CTO documentation (best practice)

**Optional.** Use when publishing a **customer-facing demo** pipeline catalogue (not required for every internal job).

```
- [ ] Create docs/pipelines/<pipeline_name>/README.md (English, CTO audience)
- [ ] Cover: what it is, why it matters, how to use in the customer's company
- [ ] Document prerequisites, roles, initial_input_json fields, outputs/consumers
- [ ] State demo limitations and production gaps honestly
- [ ] Add row to docs/pipelines/README.md index table
```

Details: [demo-pipeline-docs.md](demo-pipeline-docs.md)

### E) Data-platform pipeline — entrance + DQ + SQL (best practice)

**Optional.** Pattern for analytics/ETL projects that already use `utils/`, `dq/`, and `data_transformation/` job trees. Skip for ordinary Python/Bash automation.

1. `pipeline_params_entrance` — normalize `initial_input_json.params` once.
2. Pre-DQ per source table (`utils/dq_runner`).
3. Optional `noop` barrier with `run_on_upstream_failure: true`.
4. `run_sql_scenario` on `data_transformation/...sql` with `params` from entrance.
5. Post-DQ on target mart; `pipeline_tags` include `dq`.

Details: [pipeline-yaml.md](pipeline-yaml.md#production-orchestration-entrance-dq-sql)

---

## Quick reference

### Minimal linear pipeline

```yaml
pipeline_name: my_pipeline_v1
pipeline_tags: [my_domain]
jobs:
  - job_name: step_a
    ui_name: Step A
    path: jobs/my_job/latest/main.py
    deps: []
    outputs: [result]
    inputs:
      field: initial

  - job_name: step_b
    path: jobs/my_other/latest/main.py
    deps: [step_a]
    outputs: [summary]
    inputs:
      value:
        job: step_a
        key: result
```

Runnable demos in the client package: `examples/pipelines/demo_math_linear_v1.yaml`, `examples/pipelines/demo_shared_job_payload_merge.yaml`.

### model.yaml + stdout (UI highlights)

```yaml
news_chat:
  output_keys:
    - path: summary.title
      label: Summary
    - path: result.status
      label: Status
  tag_color_field: summary.color
```

- Do **not** set `summary.color` for routine success — UI colors by run status.
- Use `#000000` only to flag **data-critical** situations (job succeeded but data bad).
- On empty/invalid data prefer **`raise`** — runner shows error styling.

### dagychu-config.yaml (minimal)

```yaml
dagychu_config_version: 1
stack:
  python: "3.12"
dependencies:
  python:
    - type: requirements
      path: requirements.txt
```

Template: `examples/dagychu-config.yaml` in the client package (source repos may also have `examples/dagychu-config.template.yaml`).

---

## Related docs in this package

| Resource | Purpose |
|----------|---------|
| [jobs-and-model.md](jobs-and-model.md) | stdin/stdout, schemas, news_chat, empty data |
| [pipeline-yaml.md](pipeline-yaml.md) | merge, retry, launch_order, orchestration |
| [project-setup.md](project-setup.md) | PIPELINE_YAML_DIRS, instance vs project config |
| [troubleshooting.md](troubleshooting.md) | frequent failures and fixes |
| [demo-pipeline-docs.md](demo-pipeline-docs.md) | **Best practice** — CTO-facing doc template per demo pipeline |
| `docs/pipelines/README.md` | demo catalogue index (in demo repos) |
| `examples/pipelines/README.md` | demo patterns (in this package) |
| Settings → Documentation → Guide | operator guide (in the image) |
| Settings → Documentation → Operations | maintenance and Docker executor |

## Out of scope for this skill

Platform/product development (API, UI, workers, edition gating) is **not** covered here — that lives in the product source tree under `.cursor/skills/`. For operators: scheduling UI, Monitoring, and External API usage — see **Settings → Documentation** and `examples/external_client/` in the client package.

---

## Agent checklist (done = all checked)

- [ ] Confirmed group root and `PIPELINE_YAML_DIRS` label with user
- [ ] `dagychu-config.yaml` valid and project connected (if gate/docker)
- [ ] Job script + `model.yaml` aligned with stdout keys and `outputs:`
- [ ] Pipeline YAML validated in UI; deps acyclic; paths exist under group root
- [ ] `initial_input_json` shape documented (YAML header comment or task template)
- [ ] **Best practice — demo catalogue only:** `docs/pipelines/<pipeline_name>/README.md` complete and indexed
- [ ] User told how to deploy (`runtime/` rsync/git pull) and refresh disk sync
