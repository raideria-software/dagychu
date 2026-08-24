# Demo pipeline documentation (CTO-facing)

Every **demo pipeline** in this repository must ship with **English documentation** that a CTO (or engineering lead) can read without opening Python or YAML. The goal: explain **what it is**, **why it exists**, and **how to adopt it inside their company**.

## When this applies

- **Required** for each new pipeline under `pipelines/*.yaml` in the **dagychu demo** repo and any customer-facing demo catalogue.
- **Optional** for internal-only or throwaway experiments (mark as `draft` in doc frontmatter).

## File layout

One doc set per pipeline, keyed by `pipeline_name`:

```text
docs/pipelines/
  <pipeline_name>/
    README.md          # required — CTO-facing main doc
```

Example:

```text
pipelines/ingest_orders_v1.yaml
docs/pipelines/ingest_orders_v1/README.md
```

Keep `pipeline_name` in the YAML and the docs folder **identical**.

Optional later (do not create until needed):

- `docs/pipelines/<pipeline_name>/architecture.md` — deeper technical appendix
- `docs/pipelines/<pipeline_name>/runbook.md` — operator-only detail

## Writing rules

| Rule | Detail |
|------|--------|
| **Audience** | CTO, VP Engineering, head of data/platform — not Dagychu contributors |
| **Language** | English only |
| **Tone** | Clear, confident, no marketing fluff; assume the reader knows their stack |
| **Length** | README ~1–2 screens; prefer tables and bullets over prose walls |
| **No code-first** | Lead with business outcome; link to YAML/jobs only in an appendix |
| **Honest scope** | Say what is demo vs production-ready; list external dependencies explicitly |
| **Actionable** | Reader must know who does what, what to configure, and how to run the first task |

Avoid: internal ticket IDs, Russian text, Dagychu implementation jargon without a one-line explanation.

## README template

Copy for each new pipeline:

```markdown
# <Human title> (`<pipeline_name>`)

> **Status:** demo | production-pattern | draft
> **Dagychu group:** `demo`
> **Last updated:** YYYY-MM-DD

## What this is

One short paragraph: what automation this pipeline represents in plain language.

## Why it matters

- Business outcome 1 (e.g. faster reconciliation, fewer manual exports)
- Business outcome 2
- What breaks or wastes time without it

## What it does (high level)

| Stage | Purpose |
|-------|---------|
| Job A | … |
| Job B | … |

Optional one-line DAG: `entrance → load → transform → notify`

## How to use it in your company

### Prerequisites

- Systems / credentials / data the customer must have (e.g. PostgreSQL mart, API key, SFTP folder)
- Dagychu: project **connected**, group `demo`, `JOB_EXECUTOR` note if docker

### Roles

| Role | Responsibility |
|------|----------------|
| Platform / DevOps | Mount runtime, Connect project, secrets in `.env` or vault |
| Data / Analytics | Owns input parameters and downstream consumers |
| Operations | Monitors tasks, reruns, alerts |

### Run manually (first time)

1. Open Dagychu → **Create task** → group **demo** → pipeline **`<pipeline_name>`**
2. Review prefilled JSON from job `model.yaml` templates
3. Adjust `initial_input_json` (document each field below)
4. Start task → **Task / Jobs** → verify each step

### Schedule (optional)

How to wire cron / scheduler webhook in their environment (high level; no secrets).

### Task input (`initial_input_json`)

| Field | Required | Example | Meaning |
|-------|----------|---------|---------|
| `params.period` | yes | `"2026-03"` | Reporting month |

### Outputs and consumers

Where results land (table, file, notification) and who uses them.

## Operational notes

- Typical runtime and failure modes
- What to check in Dagychu UI (News summary, logs)
- When to rerun vs fix upstream data

## Limitations (demo honesty)

- What is simplified, mocked, or not included in this demo
- What they must build for production (auth, DQ, monitoring, SLAs)

## Technical reference (optional appendix)

- Pipeline file: `pipelines/<pipeline_name>.yaml`
- Jobs: `jobs/...`
- Related operator docs: **Settings → Documentation** (Guide and Operations)
```

## Agent workflow when adding a demo pipeline

```
- [ ] Implement jobs + model.yaml + pipeline YAML
- [ ] Validate pipeline in Dagychu UI
- [ ] Create docs/pipelines/<pipeline_name>/README.md from template above
- [ ] Fill every section; remove placeholder rows
- [ ] Set Status honestly (demo vs production-pattern)
- [ ] Cross-check pipeline_name matches YAML and doc path
- [ ] Add one-line pointer in docs/pipelines/README.md index table
```

## Quality checklist (CTO-readable)

- [ ] **What this is** — understandable in 30 seconds without Dagychu context
- [ ] **Why it matters** — ties to cost, risk, or speed for the business
- [ ] **How to use in your company** — roles, prerequisites, first manual run
- [ ] **Inputs documented** — every `initial_input_json` field explained
- [ ] **Outputs documented** — who consumes results and where
- [ ] **Limitations** — demo scope stated explicitly
- [ ] No untranslated non-English text

## Index (maintain in `docs/pipelines/README.md`)

When the catalogue grows, keep a table:

| Pipeline | Doc | One-line value |
|----------|-----|----------------|
| `ingest_orders_v1` | [README](ingest_orders_v1/README.md) | Daily order ingest from API to warehouse |
