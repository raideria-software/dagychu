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

# Host directory mounted as container /srv/runtime (compose DAGYCHU_RUNTIME_HOST).
# Default: <pack>/runtime. Absolute override e.g. /srv/app keeps projects outside the pack.
# Relative paths resolve against the pack root (compose project directory).
resolve_runtime_host_abs() {
  local override bind_override default_abs
  default_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/runtime').resolve())")"
  override="$(env_get DAGYCHU_RUNTIME_HOST)"
  if [[ -n "${override}" ]]; then
    python3 -c "import pathlib; p=pathlib.Path('''${override}'''); print((p if p.is_absolute() else (pathlib.Path('''${ROOT_DIR}''')/p)).resolve())"
    return 0
  fi
  bind_override="$(env_get DAGYCHU_DOCKER_BIND_RUNTIME_HOST)"
  if [[ -n "${bind_override}" ]]; then
    python3 -c "import pathlib; print(pathlib.Path('''${bind_override}''').expanduser().resolve())"
    return 0
  fi
  printf '%s\n' "${default_abs}"
}

# When DAGYCHU_RUNTIME_HOST is set, keep DAGYCHU_DOCKER_BIND_RUNTIME_HOST on the same absolute path
# so JOB_EXECUTOR=docker job containers bind the same host tree compose mounts.
sync_docker_bind_runtime_host_if_needed() {
  local runtime_abs="$1"
  local override current
  override="$(env_get DAGYCHU_RUNTIME_HOST)"
  [[ -n "${override}" ]] || return 0
  current="$(env_get DAGYCHU_DOCKER_BIND_RUNTIME_HOST)"
  if [[ "${current}" == "${runtime_abs}" ]]; then
    return 0
  fi
  python3 - "$ENV_FILE" "DAGYCHU_DOCKER_BIND_RUNTIME_HOST" "${runtime_abs}" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
new_value = sys.argv[3]
lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.is_file() else []
updated = False
for idx, raw in enumerate(lines):
    stripped = raw.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw:
        continue
    k, _ = raw.split("=", 1)
    if k.strip() == key:
        lines[idx] = f"{key}={new_value}"
        updated = True
        break
if not updated:
    lines.append(f"{key}={new_value}")
env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Synced {key}={new_value} (matches DAGYCHU_RUNTIME_HOST)", file=sys.stderr)
PY
}

# Host directory for Config Snapshot archives (compose DAGYCHU_SNAPSHOT_HOST →
# container /var/lib/dagychu/snapshots on api). Default: <pack>/snapshots.
resolve_snapshot_host_abs() {
  local override default_abs
  default_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/snapshots').resolve())")"
  override="$(env_get DAGYCHU_SNAPSHOT_HOST)"
  if [[ -n "${override}" ]]; then
    python3 -c "import pathlib; p=pathlib.Path('''${override}'''); print((p if p.is_absolute() else (pathlib.Path('''${ROOT_DIR}''')/p)).resolve())"
    return 0
  fi
  printf '%s\n' "${default_abs}"
}

# Older packs documented DAGYCHU_SNAPSHOT_DIR as if it were a host path. Compose now
# always uses /var/lib/dagychu/snapshots in-container; migrate host paths to HOST.
migrate_legacy_snapshot_dir_to_host() {
  local legacy host
  host="$(env_get DAGYCHU_SNAPSHOT_HOST)"
  [[ -z "${host}" ]] || return 0
  legacy="$(env_get DAGYCHU_SNAPSHOT_DIR)"
  [[ -n "${legacy}" ]] || return 0
  if [[ "${legacy}" == "/var/lib/dagychu/snapshots" ]]; then
    return 0
  fi
  echo "Migrating DAGYCHU_SNAPSHOT_DIR=${legacy} → DAGYCHU_SNAPSHOT_HOST (api mounts host → /var/lib/dagychu/snapshots)." >&2
  python3 - "$ENV_FILE" "DAGYCHU_SNAPSHOT_HOST" "${legacy}" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
new_value = sys.argv[3]
lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.is_file() else []
updated = False
for idx, raw in enumerate(lines):
    stripped = raw.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw:
        continue
    k, _ = raw.split("=", 1)
    if k.strip() == key:
        lines[idx] = f"{key}={new_value}"
        updated = True
        break
if not updated:
    lines.append(f"{key}={new_value}")
env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Set {key}={new_value}", file=sys.stderr)
PY
}

ensure_snapshot_host_dir() {
  migrate_legacy_snapshot_dir_to_host
  local abs
  abs="$(resolve_snapshot_host_abs)"
  mkdir -p "${abs}"
  echo "Config snapshots: ${abs} (host) → /var/lib/dagychu/snapshots (api)." >&2
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

resolve_api_ready_timeout() {
  # Prefer install-specific override, then update/shared keys, then 600s.
  local timeout_sec
  timeout_sec="$(env_get INSTALL_API_READY_TIMEOUT_SEC)"
  if [[ -z "${timeout_sec}" ]]; then
    timeout_sec="$(env_get UPDATE_API_READY_TIMEOUT_SEC)"
  fi
  if [[ -z "${timeout_sec}" ]]; then
    timeout_sec="$(env_get INIT_DB_LOCK_TIMEOUT_SEC)"
  fi
  if [[ -z "${timeout_sec}" ]] || ! [[ "${timeout_sec}" =~ ^[0-9]+$ ]]; then
    timeout_sec="600"
  fi
  echo "${timeout_sec}"
}

resolve_ui_ready_timeout() {
  local timeout_sec
  timeout_sec="$(env_get INSTALL_UI_READY_TIMEOUT_SEC)"
  if [[ -z "${timeout_sec}" ]] || ! [[ "${timeout_sec}" =~ ^[0-9]+$ ]]; then
    timeout_sec="180"
  fi
  echo "${timeout_sec}"
}

compose_retry() {
  # compose_retry <label> <max_attempts> <command...>
  local label="$1"
  local max_attempts="$2"
  shift 2
  local attempt=1
  local delay=5
  while (( attempt <= max_attempts )); do
    if "$@"; then
      return 0
    fi
    if (( attempt == max_attempts )); then
      echo "ERROR: ${label} failed after ${max_attempts} attempt(s)." >&2
      return 1
    fi
    echo "WARNING: ${label} failed (attempt ${attempt}/${max_attempts}); retrying in ${delay}s..." >&2
    sleep "${delay}"
    delay=$((delay * 2))
    if (( delay > 30 )); then
      delay=30
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

compose_pull_with_retry() {
  local attempts="${1:-3}"
  if ! [[ "${attempts}" =~ ^[0-9]+$ ]] || [[ "${attempts}" -lt 1 ]]; then
    attempts=3
  fi
  echo "Pulling images..." >&2
  compose_retry "docker compose pull" "${attempts}" compose_cmd pull
}

dump_install_failure_diagnostics() {
  echo "--------------------------------------------------------------------" >&2
  echo "Install failed — service status and recent logs:" >&2
  echo "--------------------------------------------------------------------" >&2
  compose_cmd ps >&2 || true
  for svc in api ui_backend postgres scheduler worker; do
    if compose_has_service "${svc}"; then
      echo "----- ${svc} (last 80 lines) -----" >&2
      compose_cmd logs "${svc}" --tail=80 >&2 || true
    fi
  done
  echo "--------------------------------------------------------------------" >&2
  echo "Fix the cause above, then resume without rewriting .env:" >&2
  echo "  DAGYCHU_INSTALL_RESUME=1 ./install.sh" >&2
  echo "Do not re-run a full ./install.sh once .env/volumes exist (it refuses and would risk secrets)." >&2
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

wait_for_ui_backend_healthy() {
  if ! compose_has_service ui_backend; then
    return 0
  fi
  local timeout_sec="${1:-}"
  if [[ -z "${timeout_sec}" ]]; then
    timeout_sec="$(resolve_ui_ready_timeout)"
  fi
  local deadline=$((SECONDS + timeout_sec))
  echo "Waiting for UI backend /health (up to ${timeout_sec}s)..." >&2
  while (( SECONDS < deadline )); do
    if ! compose_cmd ps --status running -q ui_backend 2>/dev/null | grep -q .; then
      sleep 2
      continue
    fi
    if compose_cmd exec -T ui_backend python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9010/health', timeout=5).read()" \
      2>/dev/null; then
      echo "UI backend is healthy." >&2
      return 0
    fi
    sleep 3
  done
  echo "ERROR: UI backend did not become healthy within ${timeout_sec}s." >&2
  compose_cmd logs ui_backend --tail=80 >&2 || true
  compose_cmd ps >&2 || true
  return 1
}

_compose_start_infra() {
  local -a infra=()
  local s
  for s in postgres rabbitmq redis clickhouse; do
    if compose_has_service "${s}"; then
      infra+=("${s}")
    fi
  done
  if [[ "${#infra[@]}" -eq 0 ]]; then
    return 0
  fi
  echo "Starting infrastructure: ${infra[*]}" >&2
  compose_retry "infrastructure up (${infra[*]})" 3 compose_cmd up -d "${infra[@]}"
}

_compose_start_api_with_ready_retries() {
  local api_ready_timeout="$1"
  local force_first="${2:-0}"
  local api_max=3
  local api_attempt=1
  while (( api_attempt <= api_max )); do
    if (( api_attempt == 1 && force_first == 0 )); then
      echo "Starting Core API (attempt ${api_attempt}/${api_max})..." >&2
      compose_cmd up -d --no-deps api
    else
      echo "Recreating Core API (attempt ${api_attempt}/${api_max}; escapes stuck init_db)..." >&2
      compose_cmd up -d --force-recreate --no-deps api
    fi
    if wait_for_api_ready "${api_ready_timeout}"; then
      return 0
    fi
    if (( api_attempt == api_max )); then
      echo "ERROR: Core API did not become ready after ${api_max} attempts." >&2
      return 1
    fi
    echo "WARNING: API not ready; will recreate and retry..." >&2
    sleep 5
    api_attempt=$((api_attempt + 1))
  done
  return 1
}

_compose_start_app_tier() {
  # workers (+ optional deadline reserve) then scheduler + ui_backend
  local force_ui="${1:-0}"
  echo "Starting remaining services (workers, scheduler, UI)..." >&2
  compose_retry "app services up" 3 compose_up_scaled
  if compose_has_service scheduler; then
    compose_cmd up -d --no-deps scheduler || compose_cmd up -d scheduler
  fi
  if compose_has_service ui_backend; then
    if [[ "${force_ui}" == "1" ]]; then
      compose_cmd up -d --force-recreate --no-deps ui_backend || compose_cmd up -d ui_backend || true
    else
      compose_cmd up -d --no-deps ui_backend || compose_cmd up -d ui_backend
    fi
  fi
}

# Fresh install: infra → API (+ recreate retries) → /ready → workers/UI → UI /health.
# Does not wipe volumes; safe if infra already partially started.
compose_up_safe_install() {
  local api_ready_timeout ui_ready_timeout
  api_ready_timeout="$(resolve_api_ready_timeout)"
  ui_ready_timeout="$(resolve_ui_ready_timeout)"

  _compose_start_infra || return 1

  if compose_has_service api; then
    _compose_start_api_with_ready_retries "${api_ready_timeout}" 0 || return 1
  fi

  _compose_start_app_tier 0 || return 1
  wait_for_ui_backend_healthy "${ui_ready_timeout}" || return 1
}

# Ordered production upgrade: writers down → infra → API recreate → /ready → workers/UI.
# Preserves named volumes, bind mounts, .env, dagychu-instance.yaml, runtime/.
compose_up_safe_upgrade() {
  local api_ready_timeout
  api_ready_timeout="$(resolve_api_ready_timeout)"

  stop_app_tier_for_migrate

  _compose_start_infra || return 1

  if compose_has_service api; then
    echo "Recreating Core API (force-recreate escapes stuck init_db; DB volume untouched)..." >&2
    compose_cmd up -d --force-recreate --no-deps api
    wait_for_api_ready "${api_ready_timeout}" || {
      echo "ERROR: Core API did not become ready. Stopping app tier to release DB connections." >&2
      compose_cmd stop api ui_backend worker scheduler 2>/dev/null || true
      return 1
    }
  fi

  _compose_start_app_tier 1
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

# Detect Engine socket (rootless-aware) and keep DAGYCHU_DOCKER_SOCK in .env for the
# docker-compose.docker-sock.yml overlay (only docker_proxy mounts the sock).
ensure_dagychu_docker_sock() {
  local je detected current detect_script
  je="$(env_get JOB_EXECUTOR 2>/dev/null || true)"
  je="$(printf '%s' "${je:-local}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "${je}" != "docker" ]]; then
    return 0
  fi
  detect_script="${ROOT_DIR}/scripts/detect_docker_sock.sh"
  if [[ ! -f "${detect_script}" ]]; then
    echo "WARNING: missing ${detect_script}; defaulting DAGYCHU_DOCKER_SOCK=/var/run/docker.sock" >&2
    detected="/var/run/docker.sock"
  else
    # shellcheck source=scripts/detect_docker_sock.sh
    # shellcheck disable=SC1090
    source "${detect_script}"
    if ! detected="$(detect_docker_sock)"; then
      echo "ERROR: JOB_EXECUTOR=docker but no Docker socket is reachable." >&2
      echo "Start Docker (rootful or rootless), or set DAGYCHU_DOCKER_SOCK in ${ENV_FILE}." >&2
      exit 1
    fi
  fi
  current="$(env_get DAGYCHU_DOCKER_SOCK 2>/dev/null || true)"
  if [[ -n "${current}" && -S "${current}" ]]; then
    echo "JOB_EXECUTOR=docker → Docker socket ${current} (DAGYCHU_DOCKER_SOCK; proxy-only mount)." >&2
    return 0
  fi
  if [[ -n "${current}" && ! -S "${current}" ]]; then
    echo "WARNING: DAGYCHU_DOCKER_SOCK=${current} is missing; replacing with ${detected}" >&2
  fi
  if command -v env_set_value >/dev/null 2>&1; then
    env_set_value "DAGYCHU_DOCKER_SOCK" "${detected}"
  else
    # update.sh may not define env_set_value — write via python
    python3 - "$ENV_FILE" "DAGYCHU_DOCKER_SOCK" "${detected}" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
new_value = sys.argv[3]
lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.is_file() else []
updated = False
for idx, raw in enumerate(lines):
    stripped = raw.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw:
        continue
    k, _ = raw.split("=", 1)
    if k.strip() == key:
        lines[idx] = f"{key}={new_value}"
        updated = True
        break
if not updated:
    lines.append(f"{key}={new_value}")
env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
  fi
  echo "JOB_EXECUTOR=docker → Docker socket ${detected} (written to DAGYCHU_DOCKER_SOCK; only docker_proxy mounts it)." >&2
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
