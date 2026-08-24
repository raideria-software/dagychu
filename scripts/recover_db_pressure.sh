#!/usr/bin/env bash
# Emergency: Postgres "too many clients" / Core API stuck on startup.
# Stops app containers (no volume deletes) so pooled connections are released.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -f "${ROOT_DIR}/scripts/compose_helpers.sh" ]]; then
  echo "Run from Dagychu install root (scripts/compose_helpers.sh missing)." >&2
  exit 1
fi

COMPOSE_FILE=""
if [[ -f "docker-compose.yml" ]]; then
  COMPOSE_FILE="docker-compose.yml"
elif [[ -f "docker-compose.prod.yml" ]]; then
  COMPOSE_FILE="docker-compose.prod.yml"
else
  echo "Missing docker-compose.yml" >&2
  exit 1
fi

ENV_FILE=".env"
# shellcheck source=scripts/compose_helpers.sh
source "${ROOT_DIR}/scripts/compose_helpers.sh"

echo "Stopping app tier to release Postgres connections (data volumes untouched)..." >&2
stop_app_tier_for_migrate

echo "Done. Verify Postgres accepts connections:" >&2
echo "  docker compose exec postgres psql -U \"\${POSTGRES_USER}\" -d \"\${POSTGRES_DB}\" -c 'SELECT 1'" >&2
echo "Then run ./update.sh to bring the stack back safely." >&2
