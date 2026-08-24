#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
COMPOSE_FILE=""
ENV_FILE=".env"
ENV_EXAMPLE_FILE=""
ENV_CHANGED=0

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

if [[ -f ".env.example" ]]; then
  ENV_EXAMPLE_FILE=".env.example"
elif [[ -f "env.example" ]]; then
  ENV_EXAMPLE_FILE="env.example"
else
  echo "Missing .env.example (or env.example)" >&2
  exit 1
fi

env_get() {
  local key="$1"
  [[ -f "${ENV_FILE}" ]] || return 0
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

print_login_banner() {
  local frontend_port admin_token ui_url
  frontend_port="$(env_get FRONTEND_HOST_PORT)"
  [[ -z "${frontend_port}" ]] && frontend_port="3000"
  ui_url="$(env_get DAGYCHU_PUBLIC_BASE_URL)"
  ui_url="${ui_url%/}"
  local extra_url=""
  if [[ -z "${ui_url}" ]]; then
    ui_url="http://127.0.0.1:${frontend_port}"
    extra_url="$(hostname -I 2>/dev/null | awk '{print $1}')"
    if [[ -n "${extra_url}" && "${extra_url}" != "127.0.0.1" ]]; then
      extra_url="http://${extra_url}:${frontend_port}"
    else
      extra_url=""
    fi
  fi
  admin_token="$(env_get UI_ADMIN_TOKEN)"
  admin_token="${admin_token%\"}"
  admin_token="${admin_token#\"}"
  admin_token="${admin_token%\'}"
  admin_token="${admin_token#\'}"

  local reset="" bold="" title="" url_c="" token_c="" dim=""
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    reset=$'\033[0m'
    bold=$'\033[1m'
    title=$'\033[1;97;44m'
    url_c=$'\033[1;96m'
    token_c=$'\033[1;30;103m'
    dim=$'\033[2m'
  fi

  echo "" >&2
  echo "${title}  Dagychu is ready — open the UI and sign in  ${reset}" >&2
  echo "" >&2
  echo "${bold}  Open:${reset}  ${url_c}${ui_url}${reset}" >&2
  if [[ -n "${extra_url}" ]]; then
    echo "${bold}  Or:${reset}    ${url_c}${extra_url}${reset}" >&2
  fi
  echo "${dim}  (sign-in screen; paste the admin token below)${reset}" >&2
  echo "" >&2
  if [[ -n "${admin_token}" ]]; then
    echo "${bold}  UI admin token:${reset}" >&2
    echo "${token_c}  ${admin_token}  ${reset}" >&2
  else
    echo "${bold}  UI admin token:${reset} missing — check UI_ADMIN_TOKEN in ${ENV_FILE}" >&2
  fi
  echo "${dim}  Also stored as UI_ADMIN_TOKEN in ${ENV_FILE} (do not share that file).${reset}" >&2
  echo "" >&2
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

if deployment_data_exists; then
  echo "ERROR: An existing Dagychu deployment was detected (running containers or compose volumes)." >&2
  echo "Use ./update.sh to upgrade — install.sh replaces ${ENV_FILE} from ${ENV_EXAMPLE_FILE} and is for first-time setup only." >&2
  echo "Your ${ENV_FILE}, dagychu-instance.yaml, runtime/, and database volumes are preserved by update.sh." >&2
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  ts="$(date +"%Y%m%d_%H%M%S")"
  backup_path=".env.backup.${ts}"
  if [[ -e "${backup_path}" ]]; then
    backup_path=".env.backup.${ts}.$RANDOM"
  fi
  mv "${ENV_FILE}" "${backup_path}"
  echo "Backed up existing ${ENV_FILE} to ${backup_path}" >&2
fi
cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
echo "Created fresh ${ENV_FILE} from ${ENV_EXAMPLE_FILE}." >&2
python3 "${ROOT_DIR}/scripts/generate_env.py" --env "${ROOT_DIR}/${ENV_FILE}" --root "${ROOT_DIR}" --edition "$(pack_edition)"
echo "Generated passwords, tokens, and default projects in ${ENV_FILE}." >&2

env_set_if_empty() {
  local key="$1"
  local value="$2"
  local result
  result="$(python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
new_value = sys.argv[3]

lines = env_path.read_text(encoding="utf-8").splitlines()
updated = False
changed = False
for idx, raw in enumerate(lines):
    stripped = raw.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw:
        continue
    k, v = raw.split("=", 1)
    if k.strip() != key:
        continue
    updated = True
    if v.strip():
        print("kept")
        sys.exit(0)
    lines[idx] = f"{key}={new_value}"
    changed = True
    break

if not updated:
    lines.append(f"{key}={new_value}")
    changed = True

env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("changed" if changed else "kept")
PY
)"
  if [[ "${result}" == "changed" ]]; then
    ENV_CHANGED=1
    echo "Auto-configured ${key} in ${ENV_FILE}" >&2
  fi
}

ensure_runtime_layout() {
  local runtime_host="$1"
  local pipeline_dirs="$2"
  python3 "${ROOT_DIR}/scripts/bootstrap_runtime.py" \
    --root "${ROOT_DIR}" \
    --runtime "${runtime_host}" \
    --pipeline-dirs "${pipeline_dirs}" \
    --seed-demo
}

discover_build_mountpoint() {
  local compose_project volume_name mountpoint
  compose_project="$(
    compose_cmd ps --format json 2>/dev/null \
      | python3 -c "import json,sys; raw=sys.stdin.read().strip(); rows=json.loads(raw) if raw else []; print(rows[0].get('Project','') if rows else '')" \
      || true
  )"
  if [[ -z "${compose_project}" ]]; then
    compose_project="$(env_get COMPOSE_PROJECT_NAME)"
  fi
  if [[ -z "${compose_project}" ]]; then
    compose_project="$(basename "${ROOT_DIR}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
  fi

  volume_name="$(
    docker volume ls \
      --filter "label=com.docker.compose.project=${compose_project}" \
      --filter "label=com.docker.compose.volume=dagychu_build" \
      --format '{{.Name}}' \
      | python3 -c "import sys; lines=[l.strip() for l in sys.stdin if l.strip()]; print(lines[0] if lines else '')"
  )"
  if [[ -z "${volume_name}" ]]; then
    return 1
  fi
  mountpoint="$(docker volume inspect "${volume_name}" --format '{{.Mountpoint}}' 2>/dev/null || true)"
  [[ -n "${mountpoint}" ]] || return 1
  printf '%s\n' "${mountpoint}"
}

preflight_bind_paths() {
  local runtime_bind="$1"
  local build_bind="$2"
  local executor="$3"
  local repo_bind="$4"
  local pipeline_dirs="$5"
  local pack_edition_name
  pack_edition_name="$(pack_edition)"

  if [[ -z "${runtime_bind}" || ! -d "${runtime_bind}" ]]; then
    echo "Bind preflight failed: DAGYCHU_DOCKER_BIND_RUNTIME_HOST='${runtime_bind}' is missing. Set override in ${ENV_FILE} or rerun install.sh." >&2
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
env_set_if_empty "DAGYCHU_DOCKER_BIND_RUNTIME_HOST" "${runtime_host_abs}"
env_set_if_empty "DAGYCHU_DOCKER_BIND_REPO_HOST" "${repo_host_abs}"
# First install: empty Postgres needs DDL. Compose defaults INIT_DB_STARTUP_MODE=verify
# (read-only); without migrate (or API verify→migrate fallback) /ready never succeeds.
env_set_if_empty "INIT_DB_STARTUP_MODE" "migrate"

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
build_bind="$(env_get DAGYCHU_DOCKER_BIND_BUILD_HOST)"
repo_bind="$(env_get DAGYCHU_DOCKER_BIND_REPO_HOST)"
warn_if_community_env_incompatible
if [[ "${job_executor}" != "docker" ]]; then
  preflight_bind_paths "${runtime_bind}" "${build_bind}" "${job_executor}" "${repo_bind}" "${pipeline_yaml_dirs}"
fi

frontend_port="$(env_get FRONTEND_HOST_PORT)"
[[ -z "${frontend_port}" ]] && frontend_port="3000"
edition_name="$(pack_edition)"

echo "" >&2
echo "--------------------------------------------------------------------" >&2
echo "Dagychu files are ready. Docker has not been started yet." >&2
echo "--------------------------------------------------------------------" >&2
echo "Edition:              ${edition_name}" >&2
echo "Compose file:         ${COMPOSE_FILE}" >&2
echo "Environment:          ${ENV_FILE}  (passwords and tokens generated)" >&2
echo "Job executor:         ${job_executor}" >&2
echo "Projects (.env):      ${pipeline_yaml_dirs}" >&2
echo "Runtime projects:" >&2
echo "  ${runtime_host_abs}/demo          (demo jobs + pipeline YAML)" >&2
echo "  ${runtime_host_abs}/development   (empty pipelines/jobs)" >&2
echo "  ${runtime_host_abs}/production    (empty pipelines/jobs)" >&2
echo "Each project has dagychu-config.yaml." >&2
echo "" >&2
echo "Review before start (optional):" >&2
echo "  - ${ENV_FILE}  — ports, JOB_EXECUTOR, PIPELINE_YAML_DIRS, secrets" >&2
echo "  - dagychu-instance.yaml  — instance UI / monitoring" >&2
echo "  - runtime/<project>/dagychu-config.yaml" >&2
echo "  - runtime/demo/pipelines/  — demo pipelines" >&2
echo "" >&2
echo "You can inspect or edit those files now (another terminal), then confirm below." >&2
echo "--------------------------------------------------------------------" >&2

confirm_start() {
  if [[ -n "${DAGYCHU_INSTALL_ASSUME_YES:-}" ]]; then
    echo "DAGYCHU_INSTALL_ASSUME_YES is set; starting without prompt." >&2
    return 0
  fi
  if [[ ! -t 0 ]] && [[ ! -t /dev/tty ]]; then
    echo "Non-interactive session: start aborted." >&2
    echo "Re-run from a terminal, or set DAGYCHU_INSTALL_ASSUME_YES=1 to start immediately." >&2
    exit 1
  fi
  local ans=""
  if [[ -t /dev/tty ]]; then
    read -r -p "Start Dagychu now? [y/N] " ans </dev/tty
  else
    read -r -p "Start Dagychu now? [y/N] " ans
  fi
  if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
    echo "Start cancelled. Generated ${ENV_FILE} and runtime/ were kept; Docker was not started." >&2
    echo "When ready, run ./install.sh again (it will recreate ${ENV_FILE} unless a deployment already exists)." >&2
    exit 0
  fi
}

confirm_start

echo "Pulling images..." >&2
compose_cmd pull

echo "Starting services..." >&2
# Fresh containers already pick up image/env; force-recreate would mint new
# worker_ids and leave the previous rows as offline ghosts in the UI.
WORKER_SKIP_FORCE_RECREATE=1
export WORKER_SKIP_FORCE_RECREATE
compose_up_scaled

if [[ "${job_executor}" == "docker" ]]; then
  # Optional: persist discovered build volume mount for operators who want an explicit override.
  build_bind_before="$(env_get DAGYCHU_DOCKER_BIND_BUILD_HOST)"
  if [[ -z "${build_bind}" ]]; then
    if discovered_mount="$(discover_build_mountpoint 2>/dev/null || true)" && [[ -n "${discovered_mount}" ]]; then
      env_set_if_empty "DAGYCHU_DOCKER_BIND_BUILD_HOST" "${discovered_mount}"
      build_bind="$(env_get DAGYCHU_DOCKER_BIND_BUILD_HOST)"
    fi
  fi
  runtime_bind="$(env_get DAGYCHU_DOCKER_BIND_RUNTIME_HOST)"
  repo_bind="$(env_get DAGYCHU_DOCKER_BIND_REPO_HOST)"
  preflight_bind_paths "${runtime_bind}" "${build_bind}" "${job_executor}" "${repo_bind}" "${pipeline_yaml_dirs}"
  if [[ -z "${build_bind_before}" && -n "${build_bind}" ]]; then
    echo "Recreating services to apply discovered build bind path..." >&2
    compose_up_scaled
  fi
fi

count_unhealthy_services() {
  compose_cmd ps --format json | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    print(1)
    raise SystemExit
rows = []
try:
    parsed = json.loads(raw)
    rows = parsed if isinstance(parsed, list) else [parsed]
except json.JSONDecodeError:
    for line in raw.splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
n = 0
for r in rows:
    health = str(r.get("Health") or "")
    state = str(r.get("State") or r.get("Status") or "").lower()
    # One-shot jobs (no healthcheck, already exited 0) are not "unhealthy".
    if health in ("unhealthy", "starting"):
        n += 1
    elif health == "" and "running" in state:
        pass
    elif health == "" and ("exit" in state or "exited" in state):
        pass
    elif health not in ("healthy", ""):
        n += 1
print(n)
' 2>/dev/null || echo 1
}

echo "Waiting for services to become healthy..." >&2
deadline=$((SECONDS + 180))
unhealthy="1"
while (( SECONDS < deadline )); do
  unhealthy="$(count_unhealthy_services)"
  if [[ "${unhealthy}" == "0" ]]; then
    break
  fi
  sleep 3
done
if [[ "${unhealthy}" != "0" ]]; then
  echo "WARNING: health wait timed out (one-shot bootstrap or JSON parse). Continuing — check status below." >&2
  compose_cmd ps >&2
fi

echo "Done. Current status:" >&2
compose_cmd ps
print_login_banner
echo "Projects: runtime/demo (seeded), runtime/development, runtime/production." >&2
echo "After adding a group to PIPELINE_YAML_DIRS, run ./reload-projects.sh (does not restart Postgres/RabbitMQ/Redis)." >&2

