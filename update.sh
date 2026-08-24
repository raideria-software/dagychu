#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
COMPOSE_FILE=""
ENV_FILE=".env"
ENV_EXAMPLE_FILE=""

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose (v2) is required" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

if [[ -f "docker-compose.yml" ]]; then
  COMPOSE_FILE="docker-compose.yml"
elif [[ -f "docker-compose.prod.yml" ]]; then
  COMPOSE_FILE="docker-compose.prod.yml"
else
  echo "Missing docker-compose.yml (or docker-compose.prod.yml)" >&2
  exit 1
fi

echo "Using compose file: ${COMPOSE_FILE}" >&2

if [[ ! -f ".env" ]]; then
  echo "Missing .env. Run install.sh first (or create .env from .env.example)." >&2
  exit 1
fi

if [[ -f ".env.example" ]]; then
  ENV_EXAMPLE_FILE=".env.example"
elif [[ -f "env.example" ]]; then
  ENV_EXAMPLE_FILE="env.example"
else
  echo "Missing .env.example (or env.example)" >&2
  exit 1
fi

check_env_has_all_example_keys() {
  echo "Merging any missing keys from ${ENV_EXAMPLE_FILE} into ${ENV_FILE} (existing values kept)..." >&2
  python3 "${ROOT_DIR}/scripts/generate_env.py" \
    --env "${ROOT_DIR}/${ENV_FILE}" \
    --root "${ROOT_DIR}" \
    --example "${ROOT_DIR}/${ENV_EXAMPLE_FILE}" \
    --edition "$(pack_edition)" \
    --merge-missing
}

env_get() {
  local key="$1"
  python3 - "$ENV_FILE" "$key" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
value = ""
for raw in env_path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    if k.strip() == key:
        value = v.strip()
print(value)
PY
}

compose_cmd() {
  # When JOB_EXECUTOR=docker, attach docker-compose.docker-sock.yml so workers can
  # reach the host Docker API (3.3.0+ prod compose does not mount sock by default).
  local -a files=("-f" "${COMPOSE_FILE}")
  local sock_overlay="${ROOT_DIR}/docker-compose.docker-sock.yml"
  local je
  je="$(env_get JOB_EXECUTOR 2>/dev/null || true)"
  je="$(printf '%s' "${je:-local}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "${je}" == "docker" ]]; then
    if [[ -f "${sock_overlay}" ]]; then
      files+=("-f" "${sock_overlay}")
    else
      echo "WARNING: JOB_EXECUTOR=docker but ${sock_overlay} is missing; Docker jobs will fail." >&2
    fi
  fi
  docker compose "${files[@]}" --env-file "${ENV_FILE}" "$@"
}

if [[ ! -f "${ROOT_DIR}/scripts/compose_helpers.sh" ]]; then
  echo "Missing scripts/compose_helpers.sh. Re-copy the scripts/ folder from the client package." >&2
  exit 1
fi
# shellcheck source=scripts/compose_helpers.sh
source "${ROOT_DIR}/scripts/compose_helpers.sh"

ensure_runtime_layout() {
  local runtime_host="$1"
  local pipeline_dirs="$2"
  python3 "${ROOT_DIR}/scripts/bootstrap_runtime.py" \
    --root "${ROOT_DIR}" \
    --runtime "${runtime_host}" \
    --pipeline-dirs "${pipeline_dirs}"
}

preflight_bind_paths() {
  local runtime_bind="$1"
  local _build_bind_unused="$2"
  local executor="$3"
  local repo_bind="$4"
  local pipeline_dirs="$5"
  local pack_edition_name
  pack_edition_name="$(pack_edition)"

  if [[ -z "${runtime_bind}" || ! -d "${runtime_bind}" ]]; then
    echo "Bind preflight failed: DAGYCHU_DOCKER_BIND_RUNTIME_HOST='${runtime_bind}' is missing. Set override in ${ENV_FILE} or rerun update.sh." >&2
    exit 1
  fi
  # DAGYCHU_DOCKER_BIND_BUILD_HOST is optional — workers auto-map dagychu_build via docker.sock.
  if [[ "${executor}" == "docker" && "${pipeline_dirs}" == *"repo:"* ]]; then
    if [[ -z "${repo_bind}" || ! -d "${repo_bind}" ]]; then
      echo "Bind preflight failed: DAGYCHU_DOCKER_BIND_REPO_HOST='${repo_bind}' is missing (PIPELINE_YAML_DIRS uses repo: paths)." >&2
      exit 1
    fi
    if [[ ! -d "${repo_bind}/system/dagychu_system/pipelines" ]]; then
      if [[ "${pack_edition_name}" == "community" ]]; then
        echo "WARNING: ${repo_bind}/system/dagychu_system/pipelines is absent (expected for Community)." >&2
        echo "Remove dagychu_system=repo:system/dagychu_system from PIPELINE_YAML_DIRS in ${ENV_FILE}." >&2
      else
        echo "Bind preflight failed: expected ${repo_bind}/system/dagychu_system/pipelines (ship system/dagychu_system in the client package)." >&2
        exit 1
      fi
    fi
  fi
}

runtime_host_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/runtime').resolve())")"
repo_host_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}').resolve())")"
pipeline_yaml_dirs="$(env_get PIPELINE_YAML_DIRS)"
ensure_runtime_layout "${runtime_host_abs}" "${pipeline_yaml_dirs}"

echo "Upgrade preserves ${ENV_FILE} (not modified), dagychu-instance.yaml, runtime/, and Docker volumes (postgres, rabbitmq, redis, job_logs, …)." >&2
check_env_has_all_example_keys

job_executor="$(env_get JOB_EXECUTOR)"
if [[ -z "${job_executor}" ]]; then
  job_executor="local"
fi
if [[ "${job_executor}" == "docker" ]]; then
  if [[ -f "${ROOT_DIR}/docker-compose.docker-sock.yml" ]]; then
    echo "JOB_EXECUTOR=docker → including docker-compose.docker-sock.yml (host docker.sock)." >&2
  else
    echo "ERROR: JOB_EXECUTOR=docker requires docker-compose.docker-sock.yml next to the compose file." >&2
    echo "Copy it from the client package, or set JOB_EXECUTOR=local." >&2
    exit 1
  fi
fi
runtime_bind="$(env_get DAGYCHU_DOCKER_BIND_RUNTIME_HOST)"
if [[ -z "${runtime_bind}" ]]; then
  runtime_bind="${runtime_host_abs}"
fi
build_bind="$(env_get DAGYCHU_DOCKER_BIND_BUILD_HOST)"
repo_bind="$(env_get DAGYCHU_DOCKER_BIND_REPO_HOST)"
if [[ -z "${repo_bind}" ]]; then
  repo_bind="${repo_host_abs}"
fi
warn_if_community_env_incompatible
preflight_bind_paths "${runtime_bind}" "${build_bind}" "${job_executor}" "${repo_bind}" "${pipeline_yaml_dirs}"

if [[ "${UPDATE_SKIP_MAINTENANCE_CHECK:-}" != "1" ]]; then
  api_port="$(env_get API_PORT)"
  [[ -z "${api_port}" ]] && api_port="8000"
  maint_status="$(curl -fsS "http://127.0.0.1:${api_port}/admin/maintenance-windows/active" 2>/dev/null || true)"
  if [[ -n "${maint_status}" ]] && [[ "${maint_status}" != *'"active":null'* ]] && [[ "${maint_status}" != *'"active": null'* ]]; then
    echo "WARNING: An active maintenance window is configured. Prefer draining tasks and ack-deployment before update." >&2
    echo "Set UPDATE_SKIP_MAINTENANCE_CHECK=1 to hide this warning." >&2
  fi
fi

echo "Pulling images defined in ${COMPOSE_FILE}..." >&2
compose_cmd pull

echo "Applying safe upgrade (stop writers → recreate API → wait /ready → start workers)..." >&2
echo "Client data is preserved: Docker volumes, ${ENV_FILE}, runtime/, dagychu-instance.yaml. Tour and operator docs come from the image." >&2
compose_up_safe_upgrade

echo "Waiting for services to become healthy..." >&2
deadline=$((SECONDS + 300))
unhealthy="1"
while (( SECONDS < deadline )); do
  unhealthy="$(compose_cmd ps --format json | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
rows = json.loads(raw) if raw else []
# Ignore one-shot / exited bootstrap; require running services with health to be healthy.
bad = 0
for r in rows:
    name = (r.get('Service') or r.get('Name') or '')
    if 'platform_bootstrap' in name:
        continue
    state = (r.get('State') or '').lower()
    health = r.get('Health') or ''
    if state in ('exited', 'dead') and 'bootstrap' not in name.lower():
        # stopped optional services are fine; writers should be running after upgrade
        svc = (r.get('Service') or '')
        if svc in ('worker', 'scheduler', 'api', 'ui_backend', 'postgres', 'rabbitmq', 'redis'):
            bad += 1
        continue
    if health and health not in ('healthy',):
        bad += 1
print(bad)
" 2>/dev/null || echo 1)"
  if [[ "${unhealthy}" == "0" ]]; then
    break
  fi
  sleep 3
done
if [[ "${unhealthy}" != "0" ]]; then
  echo "Some services are not healthy after timeout." >&2
  compose_cmd ps >&2
  exit 1
fi

if compose_cmd config --services 2>/dev/null | grep -qx 'platform_bootstrap'; then
  if [[ -f "${ROOT_DIR}/dagychu-instance.yaml" ]]; then
    echo "Ensuring platform bootstrap (overview task + scheduler)…" >&2
    compose_cmd run --rm platform_bootstrap >&2 || true
  else
    echo "Skip platform_bootstrap: ${ROOT_DIR}/dagychu-instance.yaml not found (using image defaults)." >&2
  fi
fi

echo "Done. Current status:" >&2
compose_cmd ps

