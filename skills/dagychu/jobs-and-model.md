# Jobs: script contract, inputs, outputs, model.yaml

## Script layout

Preferred tree under group root:

```text
<group_root>/
  jobs/<domain>/<job_name>/latest/main.py
  jobs/<domain>/<job_name>/latest/model.yaml
  jobs/<domain>/<job_name>/v1/main.py          # optional versioned impl
```

`latest/main.py` may re-export `v1` (see `examples/jobs/job1_square/` in the client package).

Pipeline YAML `path:` example: `runtime_seed/jobs/job1_square/latest/main.py` when group root points at a tree that includes `runtime_seed/`.

## Runtime contract

1. Read **stdin** as JSON (empty → `{}`).
2. Validate required fields; **`raise`** or exit non-zero on invalid input.
3. On success: write **one JSON object** to **stdout** — no extra stdout noise.
4. Put `print` / `logging` on **stderr** so diagnostics are not mixed into the JSON contract.
5. Deterministic for same input; no hidden side effects unless the job is explicitly designed for DB/API.

Small ASCII payloads can use `print(json.dumps(result))`. For **large UTF-8 JSON**, copy `examples/jobs/_lib/dagychu_stdio.py` (repo: `examples/runtime_seed/jobs/_lib/dagychu_stdio.py`) and write bytes once:

```python
from jobs._lib.dagychu_stdio import read_stdin_json, write_stdout_json

def main() -> None:
    payload = read_stdin_json()
    n = int(payload["number"])
    write_stdout_json({"result": n * n})

if __name__ == "__main__":
    main()
```

`print(json.dumps(..., ensure_ascii=False))` goes through TextIOWrapper and can split a multibyte character; the worker then fails the job with U+FFFD. `write_stdout_json` avoids that. Downstream jobs still read **keys from `output_json`**, not the stdout stream.

On failure the worker stores the exception **and** captured stdout/stderr in the job log (`=== STDOUT ===` / `=== STDERR ===`). The UI error box shows a tail of those streams.

Worker maps pipeline `inputs:` into the stdin payload. Keys in `outputs:` must exist at the **top level** of the printed JSON (or nested keys referenced downstream via `key:`).

## model.yaml fields

| Field | Role |
|-------|------|
| `template` | Default JSON for Create Task / rerun when no prior run |
| `input_schema` | JSON Schema for UI hints and validation |
| `output_schema` | Documents stdout shape; optional strict validation |
| `news_chat` | UI News summary paths (preferred v1 block) |
| `news` | Legacy alias: `keys` + `color` instead of `output_keys` + `tag_color_field` |

Minimal example (`examples/jobs/job1_square/latest/model.yaml`):

```yaml
template:
  number: 4
input_schema:
  type: object
  required: [number]
  properties:
    number:
      type: integer
      minimum: 1
      maximum: 10
output_schema:
  type: object
  required: [result]
  properties:
    result:
      type: integer
```

Without `model.yaml`, execution still works if YAML wiring is correct; UI may not pre-fill inputs.

## news_chat (stdout → UI)

```yaml
news_chat:
  output_keys:
    - path: summary.title
      label: Summary
    - path: summary.message
      label: Message
    - path: result.status
      label: Status
  tag_color_field: summary.color
```

Rules:

- **`path`** — dot-path from root of stdout JSON (`items[0].id` supported).
- **`label`** — caption in Task/JOBS and Monitoring stream.
- **`tag_color_field`** — optional `#RRGGBB` for badge; omit field in JSON when default status color is enough.

### When to set `summary.color`

| Situation | Action |
|-----------|--------|
| Normal success | **Do not** set color — UI uses run status color |
| `raise` / failed run | **Do not** set color — error styling from runner |
| Success but **bad data** (DQ, validation) | Set `summary.color: "#000000"` + clear `summary.message` |

### Empty data

- **Preferred**: `raise ValueError("no rows for period")` — explicit failure in UI.
- Alternative (only if agreed): `print(json.dumps({...}))` then `sys.exit(1)` for controlled failure without traceback.

### Two-step ETL example fields

**Load job** summary: rows read, duration human-readable.

**Transform job** summary: rows after cleanup, before/after grouping counts, min/max metrics, `result.status`, upsert count.

Every displayed field needs a matching `news_chat.output_keys` entry with a clear `label`.

## Changing inputs or outputs

1. Update Python to read new stdin keys.
2. Update `input_schema` / `template` in `model.yaml`.
3. Update pipeline YAML `inputs:` wiring (`initial`, `job`, `const`, or `merge`).
4. Update `outputs:` list on the job node.
5. Update downstream jobs' `inputs` that reference `key:` from this job.
6. Re-validate pipeline YAML in the UI.
