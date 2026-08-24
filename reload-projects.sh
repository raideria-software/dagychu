#!/usr/bin/env bash
# Recreate pipeline groups from PIPELINE_YAML_DIRS without restarting data services.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
COMPOSE_FILE=""
ENV_FILE=".env"

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

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Run ./install.sh first." >&2
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
  local -a files=("-f" "${COMPOSE_FILE}")
  local sock_overlay="${ROOT_DIR}/docker-compose.docker-sock.yml"
  local je
  je="$(env_get JOB_EXECUTOR 2>/dev/null || true)"
  je="$(printf '%s' "${je:-local}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "${je}" == "docker" && -f "${sock_overlay}" ]]; then
    files+=("-f" "${sock_overlay}")
  fi
  docker compose "${files[@]}" --env-file "${ENV_FILE}" "$@"
}

if [[ ! -f "${ROOT_DIR}/scripts/bootstrap_runtime.py" ]]; then
  echo "Missing scripts/bootstrap_runtime.py." >&2
  exit 1
fi

runtime_host_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/runtime').resolve())")"
pipeline_yaml_dirs="$(env_get PIPELINE_YAML_DIRS)"

echo "Ensuring runtime groups from PIPELINE_YAML_DIRS..." >&2
python3 "${ROOT_DIR}/scripts/bootstrap_runtime.py" \
  --root "${ROOT_DIR}" \
  --runtime "${runtime_host_abs}" \
  --pipeline-dirs "${pipeline_yaml_dirs}"

echo "Recreating api, worker, scheduler, and ui_backend (postgres/rabbitmq/redis stay up)..." >&2
compose_cmd up -d --no-deps --force-recreate api worker scheduler ui_backend

if compose_cmd config --services 2>/dev/null | grep -qx 'worker_deadline_reserve'; then
  compose_cmd up -d --no-deps --force-recreate worker_deadline_reserve || true
fi

echo "Done. New PIPELINE_YAML_DIRS groups are loaded. YAML files in existing groups still sync on PIPELINE_DISK_SYNC_INTERVAL_SECONDS." >&2
