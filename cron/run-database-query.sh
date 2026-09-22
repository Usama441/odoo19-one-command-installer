#!/usr/bin/env bash
# Execute cron/database-query.sql in one of this stack's PostgreSQL containers.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/database-query.conf"
LOCK_FILE="${TMPDIR:-/tmp}/odoo19-database-query.lock"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Copy database-query.conf.example and configure it." >&2
  exit 1
fi

# The configuration file contains simple KEY=value settings maintained locally.
# shellcheck disable=SC1090
source "$CONFIG_FILE"

case "${DB_CRON_TARGET:-}" in
  community)
    DEFAULT_CONTAINER="odoo19-dual-db-community-1"
    ;;
  enterprise)
    DEFAULT_CONTAINER="odoo19-dual-db-enterprise-1"
    ;;
  *)
    echo "DB_CRON_TARGET must be either community or enterprise." >&2
    exit 1
    ;;
esac

if [[ -z "${DB_CRON_DATABASE:-}" || "$DB_CRON_DATABASE" == "replace_with_your_odoo_database_name" ]]; then
  echo "Set DB_CRON_DATABASE in $CONFIG_FILE before running this job." >&2
  exit 1
fi

if [[ ! "$DB_CRON_DATABASE" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; then
  echo "DB_CRON_DATABASE contains unsupported characters." >&2
  exit 1
fi

DB_CONTAINER="${DB_CRON_CONTAINER:-$DEFAULT_CONTAINER}"
DOCKER_COMMAND=(docker)
if [[ -n "${DB_CRON_DOCKER_HOST:-}" ]]; then
  DOCKER_COMMAND+=(--host "$DB_CRON_DOCKER_HOST")
fi

if ! "${DOCKER_COMMAND[@]}" container inspect "$DB_CONTAINER" >/dev/null 2>&1; then
  echo "PostgreSQL container $DB_CONTAINER is not available on the selected Docker engine." >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/logs"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Database-query job is already running; skipping this invocation." >&2
  exit 0
fi

# -i streams the local SQL file into psql. It is supported by both this
# machine's older native Docker engine and Docker Desktop, unlike `exec -T`.
"${DOCKER_COMMAND[@]}" exec -i "$DB_CONTAINER" \
  psql --no-psqlrc -X -v ON_ERROR_STOP=1 -U odoo -d "$DB_CRON_DATABASE" \
  < "$SCRIPT_DIR/database-query.sql"
