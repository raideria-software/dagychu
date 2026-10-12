#!/usr/bin/env bash
# Resolve the Docker Engine socket path for the *current* docker CLI context.
# Prefer rootless / DOCKER_HOST unix sockets over a stale /var/run/docker.sock
# (common failure: rootless context + Permission denied on system sock).
#
# Usage:
#   scripts/detect_docker_sock.sh           # print path to stdout
#   source scripts/detect_docker_sock.sh    # defines detect_docker_sock
set -euo pipefail

detect_docker_sock() {
  local candidate="" host="" uid=""

  if [[ -n "${DAGYCHU_DOCKER_SOCK:-}" && -S "${DAGYCHU_DOCKER_SOCK}" ]]; then
    printf '%s\n' "${DAGYCHU_DOCKER_SOCK}"
    return 0
  fi

  host="${DOCKER_HOST:-}"
  if [[ -z "${host}" ]] && command -v docker >/dev/null 2>&1; then
    host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  fi
  if [[ "${host}" == unix://* ]]; then
    candidate="${host#unix://}"
    if [[ -S "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/docker.sock" ]]; then
    printf '%s\n' "${XDG_RUNTIME_DIR}/docker.sock"
    return 0
  fi

  uid="$(id -u 2>/dev/null || true)"
  if [[ -n "${uid}" && -S "/run/user/${uid}/docker.sock" ]]; then
    printf '%s\n' "/run/user/${uid}/docker.sock"
    return 0
  fi

  if [[ -S /var/run/docker.sock ]]; then
    printf '%s\n' /var/run/docker.sock
    return 0
  fi

  echo "detect_docker_sock: no usable Docker socket found (checked DOCKER_HOST, XDG_RUNTIME_DIR, /run/user/\$UID, /var/run/docker.sock)" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_docker_sock
fi
