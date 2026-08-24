# Dagychu AI skills (pipeline authors)

Skills in this folder help **operators and pipeline authors** extend their Dagychu deployment: jobs, pipeline YAML, project config, and troubleshooting. They ship in the **client install package** as `skills/` and are also available in the UI under **Settings → Skills** (baked into the image).

They are **not** for Dagychu platform development (that lives in the product source repo under `.cursor/skills/`).

## Contents

| Path | Purpose |
|------|---------|
| `dagychu/SKILL.md` | Main skill — start here |
| `dagychu/jobs-and-model.md` | Job scripts, `model.yaml`, stdout contract |
| `dagychu/pipeline-yaml.md` | Pipeline YAML, inputs merge, orchestration patterns |
| `dagychu/project-setup.md` | `dagychu-config.yaml`, groups, Connect project |
| `dagychu/troubleshooting.md` | Common issues and fixes |
| `dagychu/demo-pipeline-docs.md` | CTO-facing English doc template per demo pipeline |

## Cursor

1. Copy `dagychu/` to your project (or a folder you use for automation docs):

   ```text
   your-project/.cursor/skills/dagychu/
   ```

2. In chat, reference the skill:

   ```text
   @.cursor/skills/dagychu/SKILL.md
   ```

   Or mention "dagychu skill" when asking to add jobs, pipelines, or connect a project.

3. Point the assistant at your **`runtime/`** tree (pipelines, jobs, `dagychu-config.yaml`) and `.env` / `PIPELINE_YAML_DIRS`.

## Other assistants

Attach `dagychu/SKILL.md` and linked markdown files as context, or paste the skill path if your tool supports file references.

## Related docs

- **Settings → Documentation → Guide** — operator guide (in the image)
- **Settings → Documentation → Operations** — troubleshooting and platform handoff
- `examples/pipelines/README.md` — runnable demo YAML patterns (in this package)
- `examples/dagychu-config.yaml` — project config template (in this package)
