#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
COMPOSE_FILE=""
ENV_FILE=".env"
ENV_EXAMPLE_FILE=""
ENV_CHANGED=0
INSTALL_WORKER_REPLICAS=""
INSTALL_RUNTIME_HOST=""

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

example_env_get() {
  local key="$1"
  python3 - "$ENV_EXAMPLE_FILE" "$key" <<'PY'
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

INSTALL_RESUME=0
resume_raw="$(echo "${DAGYCHU_INSTALL_RESUME:-}" | tr '[:upper:]' '[:lower:]')"
if [[ "${resume_raw}" == "1" || "${resume_raw}" == "true" || "${resume_raw}" == "yes" ]]; then
  INSTALL_RESUME=1
fi

if [[ "${INSTALL_RESUME}" -eq 1 ]]; then
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: DAGYCHU_INSTALL_RESUME=1 requires an existing ${ENV_FILE}." >&2
    exit 1
  fi
  echo "Resume mode: keeping ${ENV_FILE} and runtime/; retrying pull/start until API and UI are ready." >&2
elif deployment_data_exists; then
  echo "ERROR: An existing Dagychu deployment was detected (running containers or compose volumes)." >&2
  echo "Use ./update.sh to upgrade — install.sh replaces ${ENV_FILE} from ${ENV_EXAMPLE_FILE} and is for first-time setup only." >&2
  echo "To retry a failed first start without rewriting secrets: DAGYCHU_INSTALL_RESUME=1 ./install.sh" >&2
  echo "Your ${ENV_FILE}, dagychu-instance.yaml, runtime/, and database volumes are preserved by update.sh." >&2
  exit 1
fi

env_set_value() {
  local key="$1"
  local value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
new_value = sys.argv[3]

lines = env_path.read_text(encoding="utf-8").splitlines()
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
}

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

install_is_interactive() {
  [[ -t 0 ]] || [[ -t /dev/tty ]]
}

install_read_reply() {
  local prompt="$1"
  local ans=""
  if [[ -t /dev/tty ]]; then
    read -r -p "${prompt}" ans </dev/tty
  else
    read -r -p "${prompt}" ans
  fi
  printf '%s' "${ans}"
}

print_install_plan() {
  local edition version image_line job_executor default_runtime
  edition="$(pack_edition)"
  version=""
  if [[ -f "${ROOT_DIR}/VERSION" ]]; then
    version="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
  fi
  image_line="$(
    grep -E '^\s*image:\s*.*dagychu' "${COMPOSE_FILE}" 2>/dev/null | head -1 | sed 's/^[[:space:]]*image:[[:space:]]*//' || true
  )"
  if [[ -z "${image_line}" && -f "${ROOT_DIR}/IMAGE" ]]; then
    image_line="$(tr -d '[:space:]' < "${ROOT_DIR}/IMAGE")"
  fi
  job_executor="$(example_env_get JOB_EXECUTOR)"
  job_executor="$(printf '%s' "${job_executor:-docker}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  default_runtime="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/runtime').resolve())")"

  echo "" >&2
  echo "====================================================================" >&2
  echo "Dagychu installation plan" >&2
  echo "====================================================================" >&2
  echo "Edition:       ${edition}" >&2
  if [[ -n "${version}" ]]; then
    echo "Version:       ${version}" >&2
  fi
  echo "Compose file:  ${COMPOSE_FILE}" >&2
  if [[ -n "${image_line}" ]]; then
    echo "App image:     ${image_line}" >&2
  fi
  echo "Job executor:  ${job_executor} (from ${ENV_EXAMPLE_FILE}; written into ${ENV_FILE} on continue)" >&2
  echo "" >&2
  echo "Docker services that will be started:" >&2
  echo "  postgres                 — task/run metadata, users, sessions, audit" >&2
  echo "  rabbitmq                 — work queue between Core and workers" >&2
  echo "  redis                    — short-lived coordination / caches" >&2
  if [[ "${edition}" != "community" ]]; then
    echo "  clickhouse               — report / BI analytics store (Enterprise)" >&2
  fi
  echo "  api                      — Core FastAPI (tasks, pipelines, WebSocket)" >&2
  echo "  worker                   — executes pipeline tasks from the queue (scaled by WORKER_REPLICAS)" >&2
  echo "  worker_deadline_reserve  — extra consumer for SLA / deadline reliability" >&2
  echo "  scheduler                — cron / webhook / dependency plan dispatcher" >&2
  echo "  ui_backend               — web UI + API proxy (host port FRONTEND_HOST_PORT)" >&2
  echo "  platform_bootstrap       — one-shot seed of platform overview task/plan (exits when done)" >&2
  if [[ "${job_executor}" == "docker" ]]; then
    echo "  docker_proxy             — filtered Docker socket proxy for JOB_EXECUTOR=docker" >&2
  fi
  echo "" >&2
  echo "Also during install (before containers start):" >&2
  echo "  - Generate ${ENV_FILE} from ${ENV_EXAMPLE_FILE} (secrets, tokens, defaults)" >&2
  if [[ -f "${ENV_FILE}" ]]; then
    echo "  - Back up the existing ${ENV_FILE} first" >&2
  fi
  echo "  - Create/check host project tree under runtime (default: ${default_runtime})" >&2
  echo "  - Pull container images and run docker compose up" >&2
  echo "" >&2
  echo "You will answer 4 questions (1/4 … 4/4) before Docker starts." >&2
  echo "====================================================================" >&2
}

# Normalize y/n answers. Empty + default_no → n. Returns 0=yes, 1=no, 2=invalid.
install_parse_yn() {
  local ans="$1"
  local default_no="${2:-1}"
  ans="$(printf '%s' "${ans}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ -z "${ans}" ]]; then
    if [[ "${default_no}" == "1" ]]; then
      return 1
    fi
    return 2
  fi
  case "${ans}" in
    y|yes) return 0 ;;
    n|no) return 1 ;;
    *) return 2 ;;
  esac
}

prompt_begin_install() {
  if [[ -n "${DAGYCHU_INSTALL_ASSUME_YES:-}" ]]; then
    echo "DAGYCHU_INSTALL_ASSUME_YES is set; skipping prompts 1/4–4/4." >&2
    return 0
  fi
  if ! install_is_interactive; then
    echo "Non-interactive session: installation aborted before writing ${ENV_FILE}." >&2
    echo "Re-run from a terminal, or set DAGYCHU_INSTALL_ASSUME_YES=1 for unattended install." >&2
    exit 1
  fi
  echo "" >&2
  local ans yn
  while true; do
    ans="$(install_read_reply "[1/4] Begin Dagychu installation? [y/N] ")"
    install_parse_yn "${ans}" 1
    yn=$?
    if [[ "${yn}" -eq 0 ]]; then
      return 0
    fi
    if [[ "${yn}" -eq 1 ]]; then
      echo "Installation cancelled. No files were changed; Docker was not started." >&2
      exit 0
    fi
    echo "Please answer y or n." >&2
  done
}

prompt_worker_replicas() {
  local current_replicas="1"
  current_replicas="$(example_env_get WORKER_REPLICAS)"
  [[ -z "${current_replicas}" ]] && current_replicas="1"

  if [[ -n "${DAGYCHU_INSTALL_ASSUME_YES:-}" ]]; then
    INSTALL_WORKER_REPLICAS="${current_replicas}"
    return 0
  fi
  if ! install_is_interactive; then
    INSTALL_WORKER_REPLICAS="${current_replicas}"
    return 0
  fi

  echo "" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "[2/4] Worker processes (WORKER_REPLICAS)" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Each worker runs one task (pipeline run) at a time from RabbitMQ." >&2
  echo "Set this to your estimated maximum number of parallel independent" >&2
  echo "pipeline runs (not individual job steps inside a pipeline)." >&2
  echo "Example: if you expect about 5 concurrent tasks, choose 5." >&2
  echo "A practical heuristic is to size toward reserved CPU capacity" >&2
  echo "(roughly one busy run per worker), leaving headroom for api," >&2
  echo "postgres, and the UI." >&2
  echo "Default: ${current_replicas}." >&2
  echo "Note: a dedicated worker_deadline_reserve container is always" >&2
  echo "created in addition to this number (SLA / deadline reliability)." >&2
  echo "--------------------------------------------------------------------" >&2

  local input_replicas
  while true; do
    input_replicas="$(install_read_reply "How many worker processes (WORKER_REPLICAS)? [${current_replicas}]: ")"
    input_replicas="$(echo "${input_replicas}" | tr -d '[:space:]')"
    if [[ -z "${input_replicas}" ]]; then
      input_replicas="${current_replicas}"
    fi
    if [[ "${input_replicas}" =~ ^[0-9]+$ ]] && [[ "${input_replicas}" -ge 1 ]]; then
      INSTALL_WORKER_REPLICAS="${input_replicas}"
      echo "Will set WORKER_REPLICAS=${INSTALL_WORKER_REPLICAS}." >&2
      return 0
    fi
    echo "Invalid value '${input_replicas}'. Enter an integer >= 1 (or press Enter for ${current_replicas})." >&2
  done
}

prompt_runtime_path() {
  local default_runtime
  default_runtime="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}/runtime').resolve())")"

  if [[ -n "${DAGYCHU_INSTALL_ASSUME_YES:-}" ]]; then
    INSTALL_RUNTIME_HOST="${default_runtime}"
    return 0
  fi
  if ! install_is_interactive; then
    INSTALL_RUNTIME_HOST="${default_runtime}"
    return 0
  fi

  echo "" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "[3/4] Project / job scripts path (DAGYCHU_RUNTIME_HOST)" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Dagychu mounts this host directory into containers as /srv/runtime." >&2
  echo "Put pipeline YAML and executable job code under project folders here" >&2
  echo "(demo, development, production, or your own groups)." >&2
  echo "Default (press Enter): ${default_runtime}" >&2
  echo "--------------------------------------------------------------------" >&2

  local input_path candidate
  while true; do
    input_path="$(install_read_reply "Runtime path [${default_runtime}]: ")"
    input_path="$(echo "${input_path}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "${input_path}" ]]; then
      input_path="${default_runtime}"
    fi
    if ! candidate="$(
      python3 -c "import pathlib; p=pathlib.Path('''${input_path}''').expanduser(); print((p if p.is_absolute() else (pathlib.Path('''${ROOT_DIR}''')/p)).resolve())" 2>/dev/null
    )"; then
      echo "Could not resolve path '${input_path}'. Try again." >&2
      continue
    fi

    if [[ -d "${candidate}" ]]; then
      if [[ -w "${candidate}" ]]; then
        INSTALL_RUNTIME_HOST="${candidate}"
        echo "Using existing directory: ${INSTALL_RUNTIME_HOST}" >&2
        return 0
      fi
      echo "Directory exists but is not writable: ${candidate}. Choose another path." >&2
      continue
    fi

    echo "Directory does not exist; creating: ${candidate}" >&2
    if mkdir -p "${candidate}" 2>/dev/null && [[ -d "${candidate}" ]] && [[ -w "${candidate}" ]]; then
      INSTALL_RUNTIME_HOST="${candidate}"
      return 0
    fi
    echo "Could not create a writable directory at ${candidate} (check permissions). Try another path." >&2
  done
}

generate_env_and_apply_answers() {
  if [[ -f "${ENV_FILE}" ]]; then
    local ts backup_path
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

  if [[ -n "${INSTALL_WORKER_REPLICAS}" ]]; then
    env_set_value "WORKER_REPLICAS" "${INSTALL_WORKER_REPLICAS}"
    echo "Configured WORKER_REPLICAS=${INSTALL_WORKER_REPLICAS} in ${ENV_FILE}." >&2
  fi

  if [[ -n "${INSTALL_RUNTIME_HOST}" ]]; then
    env_set_value "DAGYCHU_RUNTIME_HOST" "${INSTALL_RUNTIME_HOST}"
    env_set_value "DAGYCHU_DOCKER_BIND_RUNTIME_HOST" "${INSTALL_RUNTIME_HOST}"
    echo "Configured DAGYCHU_RUNTIME_HOST=${INSTALL_RUNTIME_HOST} in ${ENV_FILE}." >&2
  fi
}

print_important_env() {
  local edition frontend_port ui_url admin_token workers runtime_path job_executor pipeline_dirs
  edition="$(pack_edition)"
  frontend_port="$(env_get FRONTEND_HOST_PORT)"
  [[ -z "${frontend_port}" ]] && frontend_port="3000"
  ui_url="$(env_get DAGYCHU_PUBLIC_BASE_URL)"
  ui_url="${ui_url%/}"
  if [[ -z "${ui_url}" ]]; then
    ui_url="http://127.0.0.1:${frontend_port}"
  fi
  admin_token="$(env_get UI_ADMIN_TOKEN)"
  admin_token="${admin_token%\"}"
  admin_token="${admin_token#\"}"
  admin_token="${admin_token%\'}"
  admin_token="${admin_token#\'}"
  workers="$(env_get WORKER_REPLICAS)"
  [[ -z "${workers}" ]] && workers="1"
  runtime_path="$(resolve_runtime_host_abs)"
  job_executor="$(env_get JOB_EXECUTOR)"
  [[ -z "${job_executor}" ]] && job_executor="local"
  pipeline_dirs="$(env_get PIPELINE_YAML_DIRS)"

  echo "" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Environment file ready: ${ENV_FILE}" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Important values (review or edit ${ENV_FILE} before the final step):" >&2
  echo "  Edition:            ${edition}" >&2
  echo "  UI URL / port:      ${ui_url}  (FRONTEND_HOST_PORT=${frontend_port})" >&2
  echo "  UI_ADMIN_TOKEN:     ${admin_token}" >&2
  echo "  WORKER_REPLICAS:    ${workers}" >&2
  echo "  Runtime path:       ${runtime_path}" >&2
  echo "  JOB_EXECUTOR:       ${job_executor}" >&2
  echo "  PIPELINE_YAML_DIRS: ${pipeline_dirs}" >&2
  if [[ "${edition}" != "community" ]]; then
    echo "  ClickHouse:         credentials are in ${ENV_FILE} (CLICKHOUSE_*)" >&2
  fi
  echo "" >&2
  echo "Other secrets (Postgres, service tokens, …) were also generated in ${ENV_FILE}." >&2
  echo "You can open that file in another terminal now if you need changes." >&2
  echo "--------------------------------------------------------------------" >&2
}

confirm_start() {
  if [[ -n "${DAGYCHU_INSTALL_ASSUME_YES:-}" ]]; then
    echo "DAGYCHU_INSTALL_ASSUME_YES is set; starting without prompt 4/4." >&2
    return 0
  fi
  if ! install_is_interactive; then
    echo "Non-interactive session: start aborted." >&2
    echo "Re-run from a terminal, or set DAGYCHU_INSTALL_ASSUME_YES=1 to start immediately." >&2
    exit 1
  fi
  echo "" >&2
  local ans yn
  while true; do
    ans="$(install_read_reply "[4/4] Pull images and start all Dagychu containers now? [y/N] ")"
    install_parse_yn "${ans}" 1
    yn=$?
    if [[ "${yn}" -eq 0 ]]; then
      return 0
    fi
    if [[ "${yn}" -eq 1 ]]; then
      echo "Start cancelled. Generated ${ENV_FILE} and runtime projects were kept; Docker was not started." >&2
      echo "When ready, set DAGYCHU_INSTALL_ASSUME_YES=1 and re-run ./install.sh only if no deployment exists yet," >&2
      echo "or start with: docker compose -f ${COMPOSE_FILE} --env-file ${ENV_FILE} up -d" >&2
      echo "(prefer ./update.sh once a deployment already exists)." >&2
      exit 0
    fi
    echo "Please answer y or n." >&2
  done
}

# --- Wizard: preview → 1/4 → 2/4 → 3/4 → generate .env → summary → 4/4 → Docker ---
# Resume skips wizard/.env rewrite and only retries pull + ordered start.

if [[ "${INSTALL_RESUME}" -eq 0 ]]; then
  print_install_plan
  prompt_begin_install
  prompt_worker_replicas
  prompt_runtime_path
  generate_env_and_apply_answers
fi

runtime_host_abs="$(resolve_runtime_host_abs)"
repo_host_abs="$(python3 -c "import pathlib; print(pathlib.Path('${ROOT_DIR}').resolve())")"
pipeline_yaml_dirs="$(env_get PIPELINE_YAML_DIRS)"

if [[ "${INSTALL_RESUME}" -eq 0 ]]; then
  ensure_runtime_layout "${runtime_host_abs}" "${pipeline_yaml_dirs}"
  ensure_snapshot_host_dir
  # Compose mounts DAGYCHU_RUNTIME_HOST → /srv/runtime; docker executor needs the same host path.
  if [[ -n "$(env_get DAGYCHU_RUNTIME_HOST)" ]]; then
    env_set_value "DAGYCHU_DOCKER_BIND_RUNTIME_HOST" "${runtime_host_abs}"
  else
    env_set_if_empty "DAGYCHU_DOCKER_BIND_RUNTIME_HOST" "${runtime_host_abs}"
  fi
  env_set_if_empty "DAGYCHU_DOCKER_BIND_REPO_HOST" "${repo_host_abs}"
  # First install: empty Postgres needs DDL. Compose defaults INIT_DB_STARTUP_MODE=verify
  # (read-only); without migrate (or API verify→migrate fallback) /ready never succeeds.
  env_set_if_empty "INIT_DB_STARTUP_MODE" "migrate"
fi

job_executor="$(env_get JOB_EXECUTOR)"
if [[ -z "${job_executor}" ]]; then
  job_executor="local"
fi
if [[ "${job_executor}" == "docker" ]]; then
  if [[ -f "${ROOT_DIR}/docker-compose.docker-sock.yml" ]]; then
    echo "JOB_EXECUTOR=docker → including docker-compose.docker-sock.yml (filtered docker_proxy)." >&2
    ensure_dagychu_docker_sock
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

if [[ "${INSTALL_RESUME}" -eq 0 ]]; then
  echo "" >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Dagychu files are ready. Docker has not been started yet." >&2
  echo "--------------------------------------------------------------------" >&2
  echo "Runtime projects:" >&2
  echo "  ${runtime_host_abs}/demo          (demo jobs + pipeline YAML)" >&2
  echo "  ${runtime_host_abs}/development   (empty pipelines/jobs)" >&2
  echo "  ${runtime_host_abs}/production    (empty pipelines/jobs)" >&2
  echo "Each project has dagychu-config.yaml." >&2
  echo "--------------------------------------------------------------------" >&2

  print_important_env
  confirm_start
fi

# Fresh containers already pick up image/env; force-recreate would mint new
# worker_ids and leave the previous rows as offline ghosts in the UI.
WORKER_SKIP_FORCE_RECREATE=1
export WORKER_SKIP_FORCE_RECREATE

pull_retries="$(env_get INSTALL_PULL_RETRIES)"
if [[ -z "${pull_retries}" ]] || ! [[ "${pull_retries}" =~ ^[0-9]+$ ]]; then
  pull_retries=3
fi
if ! compose_pull_with_retry "${pull_retries}"; then
  dump_install_failure_diagnostics
  exit 1
fi

echo "Starting services (ordered: infra → API ready → workers/UI)..." >&2
if ! compose_up_safe_install; then
  dump_install_failure_diagnostics
  exit 1
fi

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
    # Bind mounts from .env require recreate; ordered ready-check again.
    if compose_has_service api; then
      if ! _compose_start_api_with_ready_retries "$(resolve_api_ready_timeout)" 1; then
        dump_install_failure_diagnostics
        exit 1
      fi
    fi
    if ! _compose_start_app_tier 1; then
      dump_install_failure_diagnostics
      exit 1
    fi
    if ! wait_for_ui_backend_healthy; then
      dump_install_failure_diagnostics
      exit 1
    fi
  fi
fi

echo "Done. Current status:" >&2
compose_cmd ps
print_login_banner
echo "Projects: ${runtime_host_abs}/demo (seeded), development, production." >&2
echo "Connect projects in Administration → Projects before the first run." >&2
echo "After adding a group to PIPELINE_YAML_DIRS, run ./reload-projects.sh (does not restart Postgres/RabbitMQ/Redis)." >&2
