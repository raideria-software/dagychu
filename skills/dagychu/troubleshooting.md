# Troubleshooting

## Pipeline not visible in UI

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Name missing after adding YAML | Disk sync not run yet | Wait ~30s or restart `api`; check logs for `Pipeline disk sync` |
| Sync errors in logs | Invalid YAML, bad `path:`, missing `pipelines/` | Fix YAML; ensure `<group_root>/pipelines/` exists |
| Wrong group in Create Task | `PIPELINE_YAML_DIRS` mismatch | Match `pipeline_group` label to env token |
| Stale pipeline name | YAML deleted but DB row remains | Remove stale name in UI/admin; re-sync |

## Task blocked / gate notification

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Cannot create task | Gate on (`execution.project_execution_gate_enabled` / legacy `PROJECT_EXECUTION_GATE_ENABLED`) and project not connected | Admin → Projects → validate → **Connect** |
| Validation failed | Bad `dagychu-config.yaml` | Fix `stack.python`, `dependencies.python.path`, volumes |
| Docker build failed | Missing requirements, socket, bad path | Check api logs; verify Docker socket; paths inside project tree |

## Job fails at runtime

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `No such file` for script | `path:` wrong relative to **group root** | Correct path; verify file on mounted volume |
| `ModuleNotFoundError` | `JOB_APP_ROOT` / package layout | Align imports and `JOB_APP_ROOT` |
| Invalid JSON / empty stdout | Script prints logs before JSON or crashes | Only one JSON object on stdout; logs to **stderr** |
| U+FFFD / replacement character in stdout | `print(json.dumps)` / TextIOWrapper split, or `response.text` already poisoned | Use `examples/jobs/_lib/dagychu_stdio.py`; do not put HTTP `.text` into stdout JSON without a clean encode |
| Input key missing | Pipeline `inputs:` wiring | Match `outputs:` upstream; check merge `priority` |
| Wrong stdin shape | `initial_input_json` does not match `template` | Fix task JSON; for entrance jobs use `{"params": {...}}` |

## Validation errors

| Error | Fix |
|-------|-----|
| Cycle in deps | Remove circular `deps` |
| Unknown upstream job | Typo in `job:` reference |
| Duplicate job_name | Rename within file |
| Path not found | File missing under group root |

## Docker executor specifics

| Symptom | Fix |
|---------|-----|
| Cannot write output files | Use `volumes.external` with `read_write` or write under `/tmp` in container |
| Dependency install fails | Check `requirements.txt` path relative to group root |
| Old code running | Reconnect project to rebuild image after dep changes |

## UI / News summary

| Symptom | Fix |
|---------|-----|
| No highlight messages | Add `news_chat.output_keys`; paths must exist in `output_json` |
| Wrong badge color | Check `tag_color_field` resolves to `#RRGGBB` |
| Status-only messages | Keys missing in latest run output — inspect job log / stdout JSON |

## WebSocket / realtime errors

Browser console WebSocket failures with working HTTP: reverse proxy must forward `Upgrade` and `Connection` to ui_backend. See **Settings → Documentation → Operations**. UI falls back to polling.

## Platform Overview / dagychu_system

| Symptom | Fix |
|---------|-----|
| Overview empty | Connect `dagychu_system` project; ensure `PIPELINE_YAML_DIRS` includes `dagychu_system=repo:system/dagychu_system` |
| Builtin path wrong | Do not override `/srv/system` with empty host mount |

## External API (`/ext/tasks`)

Community builds **disable** `/ext/*` by edition even when YAML lists `external_api.enabled: true`. Enterprise applies `dagychu-instance.yaml` → `external_api`.

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| 404 / not available | Community edition | Use UI/API task create, or Enterprise with External API enabled |
| 401/403 | Bearer token; `external_api.allowed_users` | Check token user and instance YAML |
| 408 on sync run | Wait timeout | Increase timeout or use async submit + poll |
| Callback not received | URL, HMAC, firewall | Enterprise pack: `examples/external_client/`; Community has no External API |

## Debug workflow

1. **Pipelines → validate** YAML for the group.
2. **Task → Jobs** → open failed job → full log.
3. Compare stdout JSON to `model.yaml` / `outputs:` / `news_chat` paths.
4. API container logs: disk sync, project image build, gate blocks.
5. Worker logs: subprocess command, exit code, stderr.

See also **Settings → Documentation → Operations** on the instance.
