# Demo pipeline YAML (repo group root = `examples/`)

Platform Overview monitoring lives under **`system/dagychu_system/`** (not here). See `system/README.md`.

Pipeline definitions for the **`demo_examples=repo:examples`** style of `PIPELINE_YAML_DIRS`: group root is the `examples/` directory in the repository, YAML files live here under **`pipelines/`**, and each `path:` in a job is relative to that group root (e.g. `runtime_seed/jobs/...`).

## Inputs merge (shared job across different pipelines)

`inputs.<field>` supports three source types:

- `from: job` - value from upstream job output (`job` + `key`)
- `from: const` - fixed per-job value from YAML
- `from: initial` - value from task `initial_input_json` (`key` optional)

You can combine them with:

- `merge: [ ...sources ]`
- `priority: [job, const, initial]` (higher wins on key conflicts)
- `deep_merge: true|false` (recursive merge for objects)

If source objects have different keys, they are merged additively.
`priority` only affects overlapping keys.
For `from: initial` inside `merge`, a missing key in task input is treated as "source not provided" (not a hard error), so lower-priority sources like `const` can still be used.

### Variant A: only `initial`

```yaml
inputs:
  payload: initial
```

### Variant B: `job + const`

```yaml
inputs:
  payload:
    merge:
      - from: job
        job: prepare
        key: payload
      - from: const
        value: { profile: email }
    priority: [job, const, initial]
```

### Variant C: `job + const + initial`

```yaml
inputs:
  payload:
    merge:
      - from: job
        job: prepare
        key: payload
      - from: const
        value: { profile: sms, template: notify_v2 }
      - from: initial
        key: payload
    priority: [job, const, initial]
    deep_merge: true
```

See full runnable example:

- `examples/pipelines/demo_shared_job_payload_merge.yaml`

## Retry policy on job level

`retry_policy` is configured per job in pipeline YAML:

```yaml
retry_policy:
  mode: fixed            # fixed | exponential
  max_attempts: 3
  delay_sec: 60
  max_delay_sec: 300     # optional, used for exponential backoff cap
```

Runnable example:

- `examples/pipelines/demo_retry_policy_even_odd.yaml`

## Parallel launch order mode (`_meta.launch_order_mode`)

When several jobs are ready at the same time and worker concurrency is limited, you can control
which ready jobs are started first:

```yaml
_meta:
  launch_order_mode: declaration   # declaration | auto_lpt
```

- `declaration` - starts ready jobs in YAML declaration order (default).
- `auto_lpt` - starts ready jobs by longest predicted duration first (LPT), based on historical successful runs.

If value is missing or invalid, Dagychu normalizes it to `declaration`.

## Standard notification job (`notify_channel`)

The standard job can be inserted from constructor marketplace and configured via regular inputs.
It supports delivery modes and can be forced to run even if upstream jobs failed.

```yaml
jobs:
  - job_name: notify_final
    path: runtime_seed/jobs/notify_channel/latest/main.py
    deps: [prepare, validate]
    run_on_upstream_failure: true
    inputs:
      payload:
        merge:
          - from: const
            value:
              mode: on_any_failure
              channel: telegram
              message_prefix: "[accounts-check]"
              strict_delivery: false
          - from: initial
            key: notify
        priority: [initial, const, job]
```

Runnable example:

- `examples/pipelines/demo_notify_channel_modes.yaml`

## News summary keys in `model.yaml` (TASK/JOBS + Monitoring chat)

You can define which output fields should be highlighted in the UI chat-like "News summary".

```yaml
news_chat:
  output_keys:
    - path: decision.summary
      label: Decision
    - path: metrics.score
      label: Score
    - path: followup.next_action
      label: Next action
  tag_color_field: style.tag_color
```

Rules for v1:

- `output_keys` is a list of key paths searched in `output_json` of the latest run.
- Each item can be a string path or object with `path` + optional `label`.
- `tag_color_field` is optional and must resolve to `#RRGGBB`; it colors only the message badge.
- If no keys are configured/found, UI still shows a status message (always colored by run status).

### Valid highlight examples (including compatibility aliases)

```yaml
# Preferred format
news_chat:
  output_keys:
    - path: summary.title
      label: Summary
    - path: summary.wb_message
      label: WB Message
    - path: result.status
      label: Status
  tag_color_field: summary.color
```

```yaml
# Compact format with string keys
news_chat:
  output_keys:
    - summary.title
    - summary.wb_message
    - result.status
  tag_color_field: summary.color
```

```yaml
# Compatibility format (also supported)
news:
  keys:
    - path: summary.title
      label: Summary
    - path: summary.wb_message
      label: WB Message
    - path: result.status
      label: Status
  color: summary.color
```

Notes:

- Paths are read from `output_json` of the latest run per job.
- Nested fields and list indexes are supported, e.g. `items[0].title`.
- Color must resolve to `#RRGGBB` (example: `#22C55E`).
