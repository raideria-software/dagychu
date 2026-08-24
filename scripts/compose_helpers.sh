# Shared helpers for install.sh / update.sh / update-dev.sh (source after compose_cmd is defined).
#
# Data safety: never call `compose down -v`, never remove named volumes, never rewrite .env.
# Upgrade only recreates containers onto existing volumes (postgres_data, runtime/, …).

resolve_worker_replicas() {
  local raw
  raw="$(env_get WORKER_REPLICAS)"
  if [[ -z "${raw}" ]]; then
    echo "1"
    return 0
  fi
  if ! [[ "${raw}" =~ ^[0-9]+$ ]] || [[ "${raw}" -lt 1 ]]; then
    echo "Invalid WORKER_REPLICAS='${raw}' in ${ENV_FILE}: must be an integer >= 1" >&2
    exit 1
  fi
  echo "${raw}"
}

resolve_worker_deadline_reserve() {
  local raw
  raw="$(env_get WORKER_DEADLINE_RESERVE)"
  if [[ -z "${raw}" ]]; then
    echo "1"
    return 0
  fi
  raw="$(echo "${raw}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${raw}" == "false" || "${raw}" == "no" || "${raw}" == "off" ]]; then
    echo "0"
    return 0
  fi
  if ! [[ "${raw}" =~ ^[0-9]+$ ]]; then
    echo "Invalid WORKER_DEADLINE_RESERVE='${raw}' in ${ENV_FILE}: must be an integer >= 0" >&2
    exit 1
  fi
  echo "${raw}"
}

compose_has_service() {
  local name="$1"
  compose_cmd config --services 2>/dev/null | grep -qx "${name}"
}

compose_up_scaled() {
  local replicas reserve_scale
  replicas="$(resolve_worker_replicas)"
  reserve_scale="$(resolve_worker_deadline_reserve)"
  echo "Scaling worker to ${replicas} replica(s) (WORKER_REPLICAS)..." >&2
  local scale_args=(--scale "worker=${replicas}")
  if compose_has_service "worker_deadline_reserve"; then
    echo "Scaling worker_deadline_reserve to ${reserve_scale} (WORKER_DEADLINE_RESERVE)..." >&2
    scale_args+=(--scale "worker_deadline_reserve=${reserve_scale}")
  fi
  compose_cmd up -d "${scale_args[@]}" "$@"
  local skip_recreate force_recreate
  skip_recreate="${WORKER_SKIP_FORCE_RECREATE:-$(env_get WORKER_SKIP_FORCE_RECREATE)}"
  skip_recreate="$(echo "${skip_recreate}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${skip_recreate}" == "1" || "${skip_recreate}" == "true" || "${skip_recreate}" == "yes" ]]; then
    return 0
  fi
  force_recreate="$(env_get WORKER_FORCE_RECREATE_ON_UPDATE)"
  if [[ -z "${force_recreate}" || "${force_recreate}" == "1" || "${force_recreate}" == "true" || "${force_recreate}" == "yes" ]]; then
    # Must pass --scale again: `up … worker` without --scale collapses replicas to 1
    # (compose file has no deploy.replicas; scale is CLI-only).
    echo "Recreating worker container(s) to pick up image/env changes..." >&2
    compose_cmd up -d --force-recreate --no-deps --scale "worker=${replicas}" worker
    if compose_has_service "worker_deadline_reserve"; then
      compose_cmd up -d --force-recreate --no-deps --scale "worker_deadline_reserve=${reserve_scale}" worker_deadline_reserve
    fi
  fi
}

# Stop app tier so API init_db can take table locks and release pooled DB connections.
stop_app_tier_for_migrate() {
  local stopped=0
  for svc in ui_backend worker worker_deadline_reserve scheduler api; do
    if compose_has_service "${svc}"; then
      echo "Stopping ${svc} (releases DB connections; data kept)..." >&2
      compose_cmd stop "${svc}" || true
      stopped=1
    fi
  done
  if [[ "${stopped}" -eq 1 ]]; then
    # Let Postgres drop sessions from stopped containers before migrations.
    sleep 5
  fi
}

# Backward-compatible alias.
stop_task_writers() {
  stop_app_tier_for_migrate
}

wait_for_api_ready() {
  local timeout_sec="${1:-600}"
  local deadline=$((SECONDS + timeout_sec))
  local body=""
  echo "Waiting for Core API /ready (up to ${timeout_sec}s; migrations may take a few minutes)..." >&2
  while (( SECONDS < deadline )); do
    if ! compose_cmd ps --status running -q api 2>/dev/null | grep -q .; then
      sleep 2
      continue
    fi
    body="$(
      compose_cmd exec -T api python -c \
        "import urllib.request,urllib.error
try:
  print(urllib.request.urlopen('http://127.0.0.1:8000/ready', timeout=5).read().decode())
except urllib.error.HTTPError as e:
  print(e.read().decode(errors='replace')[:500])
except Exception as e:
  print(type(e).__name__ + ':' + str(e)[:200])
" 2>/dev/null || true
    )"
    if [[ "${body}" == *'"status":"ready"'* ]] || [[ "${body}" == *'"status": "ready"'* ]] \
      || [[ "${body}" == *'"status":"degraded_ready"'* ]] || [[ "${body}" == *'"status": "degraded_ready"'* ]]; then
      echo "Core API is ready." >&2
      return 0
    fi
    if [[ "${body}" == *'"startup":"failed"'* ]] || [[ "${body}" == *'migration lock unavailable'* ]]; then
      echo "ERROR: Core API startup failed: ${body}" >&2
      compose_cmd logs api --tail=100 >&2 || true
      return 1
    fi
    sleep 3
  done
  echo "ERROR: Core API did not become ready within ${timeout_sec}s." >&2
  echo "Last /ready body: ${body:-<empty>}" >&2
  compose_cmd logs api --tail=120 >&2 || true
  compose_cmd ps >&2 || true
  return 1
}

# Ordered production upgrade: writers down → infra → API recreate → /ready → workers/UI.
# Preserves named volumes, bind mounts, .env, dagychu-instance.yaml, runtime/.
compose_up_safe_upgrade() {
  local api_ready_timeout
  api_ready_timeout="$(env_get UPDATE_API_READY_TIMEOUT_SEC)"
  if [[ -z "${api_ready_timeout}" ]]; then
    api_ready_timeout="$(env_get INIT_DB_LOCK_TIMEOUT_SEC)"
  fi
  if [[ -z "${api_ready_timeout}" ]] || ! [[ "${api_ready_timeout}" =~ ^[0-9]+$ ]]; then
    api_ready_timeout="600"
  fi

  stop_app_tier_for_migrate

  local -a infra=()
  local s
  for s in postgres rabbitmq redis clickhouse; do
    if compose_has_service "${s}"; then
      infra+=("${s}")
    fi
  done
  if [[ "${#infra[@]}" -gt 0 ]]; then
    echo "Ensuring infrastructure is up (volumes reused, no data wipe): ${infra[*]}" >&2
    compose_cmd up -d "${infra[@]}"
  fi

  if compose_has_service api; then
    echo "Recreating Core API (force-recreate escapes stuck init_db; DB volume untouched)..." >&2
    compose_cmd up -d --force-recreate --no-deps api
    wait_for_api_ready "${api_ready_timeout}" || {
      echo "ERROR: Core API did not become ready. Stopping app tier to release DB connections." >&2
      compose_cmd stop api ui_backend worker scheduler 2>/dev/null || true
      return 1
    }
  fi

  echo "Starting remaining services (workers, scheduler, UI)..." >&2
  compose_up_scaled

  if compose_has_service scheduler; then
    compose_cmd up -d --no-deps scheduler || compose_cmd up -d scheduler
  fi
  if compose_has_service ui_backend; then
    compose_cmd up -d --force-recreate --no-deps ui_backend || true
  fi
}

# Refuse install.sh on an existing deployment (protects .env, DB volumes, runtime/).
deployment_data_exists() {
  if [[ -f "${ENV_FILE}" ]]; then
    if compose_cmd ps -q 2>/dev/null | grep -q .; then
      return 0
    fi
  fi
  local project
  project="$(env_get COMPOSE_PROJECT_NAME)"
  if [[ -z "${project}" ]]; then
    project="$(basename "${ROOT_DIR}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
  fi
  if docker volume ls --filter "label=com.docker.compose.project=${project}" --format '{{.Name}}' 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

# Missing keys: show .env.example defaults, do not modify .env; prompt to continue (English).
confirm_env_missing_keys_or_abort() {
  local missing_lines
  missing_lines="$(python3 - "${ENV_EXAMPLE_FILE}" "${ENV_FILE}" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

example = Path(sys.argv[1])
env = Path(sys.argv[2])

def assignments(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        key, value = s.split("=", 1)
        key = key.strip()
        if key:
            out[key] = value
    return out

example_vals = assignments(example)
env_keys = set(assignments(env).keys())
for key in sorted(k for k in example_vals if k not in env_keys):
    print(f"{key}={example_vals[key]}")
PY
)"
  if [[ -z "${missing_lines}" ]]; then
    return 0
  fi

  echo "" >&2
  echo "WARNING: ${ENV_FILE} is missing variables from ${ENV_EXAMPLE_FILE}." >&2
  echo "Your .env file will NOT be modified." >&2
  echo "If you continue, the upgrade uses script/compose fallbacks where defined" >&2
  echo "(e.g. WORKER_REPLICAS defaults to 1 when absent). Reference values from ${ENV_EXAMPLE_FILE}:" >&2
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    echo "  ${line}" >&2
  done <<< "${missing_lines}"
  echo "" >&2
  echo "Add these keys to ${ENV_FILE} manually before upgrading to use custom values." >&2
  echo "" >&2

  if [[ -n "${DAGYCHU_UPDATE_ASSUME_DEFAULTS:-}" ]]; then
    echo "DAGYCHU_UPDATE_ASSUME_DEFAULTS is set; continuing without changing .env." >&2
    return 0
  fi

  if [[ ! -t 0 ]] && [[ ! -t /dev/tty ]]; then
    echo "Non-interactive session: upgrade aborted. Add missing keys to .env or set DAGYCHU_UPDATE_ASSUME_DEFAULTS=1." >&2
    exit 1
  fi

  local ans=""
  read -r -p "Continue upgrade? [y/N] " ans </dev/tty 2>/dev/null || read -r -p "Continue upgrade? [y/N] " ans
  if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
    echo "Upgrade aborted." >&2
    exit 1
  fi
}

pack_edition() {
  if [[ -f "${ROOT_DIR}/EDITION" ]]; then
    tr -d '[:space:]' < "${ROOT_DIR}/EDITION"
  else
    echo "enterprise"
  fi
}

warn_if_community_env_incompatible() {
  local edition pipeline_dirs
  edition="$(pack_edition)"
  [[ "${edition}" == "community" ]] || return 0
  pipeline_dirs="$(env_get PIPELINE_YAML_DIRS)"
  if [[ "${pipeline_dirs}" == *"dagychu_system"* ]]; then
    echo "WARNING: Community package does not ship system/dagychu_system." >&2
    echo "  Update ${ENV_FILE}: PIPELINE_YAML_DIRS=demo=demo,development=development,production=production" >&2
  fi
}

warn_compose_env_dollar_interpolation() {
  # docker compose interpolates $VAR / ${VAR} from .env into compose YAML.
  # A password like ...$B... or ...$tx0n... triggers: The "B" variable is not set.
  local hits
  hits="$(python3 - "$ENV_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
known = {
    "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "DATABASE_URL",
    "RABBITMQ_USER", "RABBITMQ_PASSWORD", "RABBITMQ_URL", "REDIS_URL",
    "QUEUE_NAME", "JOB_EXECUTOR", "JOB_CONCURRENCY", "WORKER_REPLICAS",
    "WORKER_DEADLINE_RESERVE", "SLA_DEADLINE_RESERVE_QUEUE_NAME",
    "UI_ADMIN_TOKEN", "WORKER_SERVICE_TOKEN", "EXTERNAL_AGENT_TOKEN",
    "DAGYCHU_BUILD_ROOT", "PIPELINE_YAML_DIRS", "COMPOSE_PROJECT_NAME",
}
pat = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    s = raw.strip()
    if not s or s.startswith("#") or "=" not in s:
        continue
    k, v = s.split("=", 1)
    key = k.strip()
    for m in pat.finditer(v):
        name = m.group(1) or m.group(2)
        if name and name not in known and name != key:
            out.append(f"{key} contains ${name}")
for line in out[:12]:
    print(line)
PY
)"
  if [[ -z "${hits}" ]]; then
    return 0
  fi
  echo "" >&2
  echo "WARNING: docker compose will interpolate bare \$VAR in ${ENV_FILE} values." >&2
  echo "  If you see 'The \"B\" variable is not set', a secret likely contains \$B / \$tx0n / etc." >&2
  echo "  Escape literal dollars as \$\$ (e.g. pass=ab\$\$Bcd). Hits:" >&2
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    echo "    - ${line}" >&2
  done <<< "${hits}"
  echo "" >&2
}
