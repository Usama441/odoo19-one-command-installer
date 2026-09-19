#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

backup_list_contains() {
  local wanted="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

backup_restore_original_state() {
  local container_id cluster_entry pg_version pg_cluster service

  for container_id in "${BACKUP_STARTED_CONTAINERS[@]}"; do
    "${BACKUP_DOCKER_COMMAND[@]}" stop --time 30 "$container_id" >/dev/null 2>&1 || true
  done
  for cluster_entry in "${BACKUP_STARTED_PG_CLUSTERS[@]}"; do
    IFS='|' read -r pg_version pg_cluster <<< "$cluster_entry"
    sudo pg_ctlcluster "$pg_version" "$pg_cluster" stop >/dev/null 2>&1 || true
  done
  for service in "${BACKUP_STARTED_MYSQL_SERVICES[@]}"; do
    sudo systemctl stop "$service" >/dev/null 2>&1 || true
  done
  if [[ -n "$BACKUP_SCAN_FILE" && "$BACKUP_SCAN_FILE" == /tmp/odoo19-database-scan.* ]]; then
    rm -f -- "$BACKUP_SCAN_FILE"
  fi
  if [[ -n "$BACKUP_WORK_DIR" &&
        "$BACKUP_WORK_DIR" == "$SCRIPT_DIR/backups/.backup-work."* &&
        -d "$BACKUP_WORK_DIR" ]]; then
    rm -rf -- "$BACKUP_WORK_DIR"
  fi
  if [[ "$BACKUP_ARCHIVE_COMPLETE" != "true" &&
        -n "$BACKUP_ARCHIVE_PATH" &&
        "$BACKUP_ARCHIVE_PATH" == "$SCRIPT_DIR/backups/system-databases-"*.rar ]]; then
    rm -f -- "$BACKUP_ARCHIVE_PATH"
  fi
  BACKUP_STARTED_CONTAINERS=()
  BACKUP_STARTED_PG_CLUSTERS=()
  BACKUP_STARTED_MYSQL_SERVICES=()
  BACKUP_WORK_DIR=""
  BACKUP_SCAN_FILE=""
}

ensure_rar_available() {
  if command -v rar >/dev/null 2>&1; then return 0; fi

  echo
  echo "The RAR utility is required to create the requested .rar backup archive."
  if ! ask_yes_no "Install the Ubuntu rar package now? [Y/n]: " "y"; then
    return 1
  fi
  echo "Installing the RAR utility..."
  if ! install_apt_packages rar; then
    echo "The rar package could not be installed. Enable Ubuntu's multiverse repository, then retry."
    return 1
  fi
  if ! command -v rar >/dev/null 2>&1; then
    echo "The rar command is still unavailable after installation."
    return 1
  fi
  track_installer_packages rar
}

ensure_sqlite_available() {
  if command -v sqlite3 >/dev/null 2>&1; then return 0; fi

  echo
  echo "The sqlite3 utility is required for the selected SQLite database backup."
  if ! ask_yes_no "Install the Ubuntu sqlite3 package now? [Y/n]: " "y"; then
    return 1
  fi
  install_apt_packages sqlite3
  command -v sqlite3 >/dev/null 2>&1 || return 1
  track_installer_packages sqlite3
}

backup_read_secret() {
  local target="$1" prompt="$2" secret
  read -r -s -p "$prompt" secret
  echo
  printf -v "$target" '%s' "$secret"
}

backup_reset_catalog() {
  BACKUP_CATALOG_ENGINES=()
  BACKUP_CATALOG_SOURCE_KINDS=()
  BACKUP_CATALOG_SOURCE_LABELS=()
  BACKUP_CATALOG_SOURCE_REFS=()
  BACKUP_CATALOG_USERS=()
  BACKUP_CATALOG_SECRETS=()
  BACKUP_CATALOG_CLIENTS=()
  BACKUP_CATALOG_DATABASES=()
  BACKUP_CATALOG_SIZES=()
  BACKUP_SQLITE_FILTERED_COUNT=0
}

backup_catalog_add() {
  local engine="$1" source_kind="$2" source_label="$3" source_ref="$4"
  local user="$5" secret="$6" client="$7" database_name="$8" database_size="$9" index

  [[ -n "$database_name" ]] || return 0
  for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
    if [[ "${BACKUP_CATALOG_ENGINES[index]}" == "$engine" &&
          "${BACKUP_CATALOG_SOURCE_KINDS[index]}" == "$source_kind" &&
          "${BACKUP_CATALOG_SOURCE_REFS[index]}" == "$source_ref" &&
          "${BACKUP_CATALOG_DATABASES[index]}" == "$database_name" ]]; then
      return 0
    fi
  done

  BACKUP_CATALOG_ENGINES+=("$engine")
  BACKUP_CATALOG_SOURCE_KINDS+=("$source_kind")
  BACKUP_CATALOG_SOURCE_LABELS+=("$source_label")
  BACKUP_CATALOG_SOURCE_REFS+=("$source_ref")
  BACKUP_CATALOG_USERS+=("$user")
  BACKUP_CATALOG_SECRETS+=("$secret")
  BACKUP_CATALOG_CLIENTS+=("$client")
  BACKUP_CATALOG_DATABASES+=("$database_name")
  BACKUP_CATALOG_SIZES+=("${database_size:-unknown}")
}

backup_append_postgres_rows() {
  local output="$1" source_kind="$2" source_label="$3" source_ref="$4"
  local user="$5" secret="$6" client="$7" database_name database_size

  while IFS=$'\t' read -r database_name database_size; do
    [[ -n "$database_name" ]] || continue
    backup_catalog_add "PostgreSQL" "$source_kind" "$source_label" "$source_ref" \
      "$user" "$secret" "$client" "$database_name" "$database_size"
  done <<< "$output"
}

backup_append_mysql_rows() {
  local output="$1" engine="$2" source_kind="$3" source_label="$4" source_ref="$5"
  local user="$6" secret="$7" client="$8" database_name database_size

  while IFS=$'\t' read -r database_name database_size; do
    [[ -n "$database_name" ]] || continue
    backup_catalog_add "$engine" "$source_kind" "$source_label" "$source_ref" \
      "$user" "$secret" "$client" "$database_name" "$database_size"
  done <<< "$output"
}

discover_native_postgresql() {
  local clusters_output pg_version pg_cluster port status owner data_dir log_file
  local psql_client pg_dump_client database_output source_label
  local postgres_sql="SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> 'postgres' ORDER BY datname;"

  echo "  • Native PostgreSQL clusters"
  if ! command -v pg_lsclusters >/dev/null 2>&1; then
    echo "    Not detected."
    return 0
  fi
  clusters_output="$(pg_lsclusters --no-header 2>/dev/null || true)"
  if [[ -z "$clusters_output" ]]; then
    echo "    No PostgreSQL clusters found."
    return 0
  fi

  while read -r pg_version pg_cluster port status owner data_dir log_file; do
    [[ -n "$pg_version" && -n "$pg_cluster" && "$port" =~ ^[0-9]+$ ]] || continue
    if [[ "$status" != online* ]]; then
      if [[ -t 0 ]] && ask_yes_no "    Cluster $pg_version/$pg_cluster is stopped. Start it temporarily? [Y/n]: " "y"; then
        if sudo pg_ctlcluster "$pg_version" "$pg_cluster" start; then
          BACKUP_STARTED_PG_CLUSTERS+=("$pg_version|$pg_cluster")
        else
          echo "    Could not start $pg_version/$pg_cluster; skipping it."
          continue
        fi
      else
        echo "    Skipping stopped cluster $pg_version/$pg_cluster."
        continue
      fi
    fi

    psql_client="/usr/lib/postgresql/$pg_version/bin/psql"
    pg_dump_client="/usr/lib/postgresql/$pg_version/bin/pg_dump"
    [[ -x "$psql_client" ]] || psql_client="$(command -v psql 2>/dev/null || true)"
    [[ -x "$pg_dump_client" ]] || pg_dump_client="$(command -v pg_dump 2>/dev/null || true)"
    if [[ -z "$psql_client" || -z "$pg_dump_client" ]]; then
      echo "    PostgreSQL client tools are missing for $pg_version/$pg_cluster; skipping it."
      continue
    fi
    if ! database_output="$(sudo -u postgres "$psql_client" --no-psqlrc -X -A -t -F $'\t' \
      -p "$port" -d postgres -c "$postgres_sql" 2>/dev/null)"; then
      echo "    Cannot access cluster $pg_version/$pg_cluster as postgres; skipping it."
      continue
    fi
    source_label="Native $pg_version/$pg_cluster :$port"
    backup_append_postgres_rows "$database_output" "native" "$source_label" "$port" \
      "postgres" "" "$pg_dump_client"
  done <<< "$clusters_output"
}

backup_mysql_query_native() {
  local client="$1" auth_mode="$2" user="$3" secret="$4" sql="$5"
  case "$auth_mode" in
    current) "$client" --batch --skip-column-names -e "$sql" ;;
    sudo) sudo "$client" --batch --skip-column-names -e "$sql" ;;
    password) MYSQL_PWD="$secret" "$client" -u "$user" --batch --skip-column-names -e "$sql" ;;
    *) return 1 ;;
  esac
}

discover_native_mysql() {
  local client dump_client engine database_output auth_mode="" auth_user="" auth_secret=""
  local service="" service_candidate
  local mysql_sql="SELECT s.schema_name, CONCAT(COALESCE(ROUND(SUM(t.data_length + t.index_length) / 1024 / 1024, 2), 0), ' MiB') FROM information_schema.schemata s LEFT JOIN information_schema.tables t ON t.table_schema = s.schema_name WHERE s.schema_name NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY s.schema_name ORDER BY s.schema_name;"

  echo "  • Native MySQL/MariaDB server"
  client="$(command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null || true)"
  dump_client="$(command -v mariadb-dump 2>/dev/null || command -v mysqldump 2>/dev/null || true)"
  if [[ -z "$client" || -z "$dump_client" ]]; then
    echo "    Not detected."
    return 0
  fi
  for service_candidate in mariadb mysql; do
    if systemctl is-active --quiet "$service_candidate"; then
      service="$service_candidate"
      break
    fi
  done
  for service_candidate in mariadb mysql; do
    [[ -n "$service" ]] && break
    if systemctl list-unit-files "$service_candidate.service" --no-legend 2>/dev/null | grep -q "^$service_candidate.service"; then
      service="$service_candidate"
      break
    fi
  done
  if [[ -n "$service" ]] && ! systemctl is-active --quiet "$service"; then
    if [[ -t 0 ]] && ask_yes_no "    Native $service is stopped. Start it temporarily? [Y/n]: " "y"; then
      if sudo systemctl start "$service"; then
        BACKUP_STARTED_MYSQL_SERVICES+=("$service")
      else
        echo "    Could not start $service; skipping it."
        return 0
      fi
    else
      echo "    Native $service is stopped; skipping it."
      return 0
    fi
  fi
  if sudo -n true >/dev/null 2>&1 &&
     database_output="$(backup_mysql_query_native "$client" sudo "" "" "$mysql_sql" 2>/dev/null)"; then
    auth_mode="sudo"
    auth_user="root via sudo"
  elif [[ -t 0 ]] && ask_yes_no "    Try local MySQL/MariaDB administrative access with sudo? [Y/n]: " "y" &&
       database_output="$(backup_mysql_query_native "$client" sudo "" "" "$mysql_sql" 2>/dev/null)"; then
    auth_mode="sudo"
    auth_user="root via sudo"
  elif database_output="$(backup_mysql_query_native "$client" current "" "" "$mysql_sql" 2>/dev/null)"; then
    auth_mode="current"
    auth_user="current login defaults"
  elif [[ -t 0 ]]; then
    read -r -p "    MySQL/MariaDB username (blank skips this server): " auth_user
    if [[ -z "$auth_user" ]]; then
      echo "    Skipped because credentials were not provided."
      return 0
    fi
    backup_read_secret auth_secret "    Password for $auth_user: "
    if database_output="$(backup_mysql_query_native "$client" password "$auth_user" "$auth_secret" "$mysql_sql" 2>/dev/null)"; then
      auth_mode="password"
    else
      echo "    Authentication failed; skipping the native MySQL/MariaDB server."
      return 0
    fi
  else
    echo "    Server detected but authentication is unavailable in non-interactive mode."
    return 0
  fi

  if "${client}" --version 2>/dev/null | grep -qi mariadb; then engine="MariaDB"; else engine="MySQL"; fi
  backup_append_mysql_rows "$database_output" "$engine" "native" "Native $engine" "$auth_mode" \
    "$auth_user" "$auth_secret" "$dump_client"
}

backup_docker_env_value() {
  local container_id="$1" wanted_key="$2" line
  while IFS= read -r line; do
    if [[ "$line" == "$wanted_key="* ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done < <("${BACKUP_DOCKER_COMMAND[@]}" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_id" 2>/dev/null)
  return 1
}

backup_docker_postgres_query() {
  local container_id="$1" user="$2" secret="$3" sql="$4"
  if [[ -n "$secret" ]]; then
    "${BACKUP_DOCKER_COMMAND[@]}" exec -e "PGPASSWORD=$secret" "$container_id" \
      psql --no-psqlrc -X -A -t -F $'\t' -U "$user" -d postgres -c "$sql"
  else
    "${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" \
      psql --no-psqlrc -X -A -t -F $'\t' -U "$user" -d postgres -c "$sql"
  fi
}

discover_docker_postgresql() {
  local container_id="$1" container_name="$2" user secret database_output entered_user
  local postgres_sql="SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> 'postgres' ORDER BY datname;"

  user="$(backup_docker_env_value "$container_id" POSTGRES_USER || true)"
  secret="$(backup_docker_env_value "$container_id" POSTGRES_PASSWORD || true)"
  user="${user:-postgres}"
  if ! database_output="$(backup_docker_postgres_query "$container_id" "$user" "$secret" "$postgres_sql" 2>/dev/null)"; then
    if [[ ! -t 0 ]]; then
      echo "    $container_name: PostgreSQL authentication failed; skipped."
      return 0
    fi
    echo "    PostgreSQL credentials from container settings did not work for $container_name."
    read -r -p "    PostgreSQL username [$user] (blank keeps default, S skips): " entered_user
    [[ "${entered_user,,}" == "s" ]] && return 0
    user="${entered_user:-$user}"
    backup_read_secret secret "    Password for $user: "
    if ! database_output="$(backup_docker_postgres_query "$container_id" "$user" "$secret" "$postgres_sql" 2>/dev/null)"; then
      echo "    Authentication failed; skipping $container_name."
      return 0
    fi
  fi
  backup_append_postgres_rows "$database_output" "docker" "Docker: $container_name" "$container_id" \
    "$user" "$secret" "pg_dump"
}

backup_docker_mysql_query() {
  local container_id="$1" client="$2" user="$3" secret="$4" sql="$5"
  if [[ -n "$secret" ]]; then
    "${BACKUP_DOCKER_COMMAND[@]}" exec -e "MYSQL_PWD=$secret" "$container_id" \
      "$client" -u "$user" --batch --skip-column-names -e "$sql"
  else
    "${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" \
      "$client" -u "$user" --batch --skip-column-names -e "$sql"
  fi
}

discover_docker_mysql() {
  local container_id="$1" container_name="$2" image_name="$3"
  local client dump_client engine user secret configured_user configured_secret database_output entered_user
  local mysql_sql="SELECT s.schema_name, CONCAT(COALESCE(ROUND(SUM(t.data_length + t.index_length) / 1024 / 1024, 2), 0), ' MiB') FROM information_schema.schemata s LEFT JOIN information_schema.tables t ON t.table_schema = s.schema_name WHERE s.schema_name NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY s.schema_name ORDER BY s.schema_name;"

  client="$("${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" sh -c \
    'command -v mariadb 2>/dev/null || command -v mysql 2>/dev/null' 2>/dev/null || true)"
  dump_client="$("${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" sh -c \
    'command -v mariadb-dump 2>/dev/null || command -v mysqldump 2>/dev/null' 2>/dev/null || true)"
  if [[ -z "$client" || -z "$dump_client" ]]; then
    echo "    $container_name: database client tools not found; skipped."
    return 0
  fi
  if [[ "${image_name,,}" == *mariadb* ]]; then engine="MariaDB"; else engine="MySQL"; fi

  user="root"
  secret="$(backup_docker_env_value "$container_id" MARIADB_ROOT_PASSWORD || true)"
  [[ -n "$secret" ]] || secret="$(backup_docker_env_value "$container_id" MYSQL_ROOT_PASSWORD || true)"
  if ! database_output="$(backup_docker_mysql_query "$container_id" "$client" "$user" "$secret" "$mysql_sql" 2>/dev/null)"; then
    configured_user="$(backup_docker_env_value "$container_id" MARIADB_USER || true)"
    [[ -n "$configured_user" ]] || configured_user="$(backup_docker_env_value "$container_id" MYSQL_USER || true)"
    configured_secret="$(backup_docker_env_value "$container_id" MARIADB_PASSWORD || true)"
    [[ -n "$configured_secret" ]] || configured_secret="$(backup_docker_env_value "$container_id" MYSQL_PASSWORD || true)"
    if [[ -n "$configured_user" ]] &&
       database_output="$(backup_docker_mysql_query "$container_id" "$client" "$configured_user" "$configured_secret" "$mysql_sql" 2>/dev/null)"; then
      user="$configured_user"
      secret="$configured_secret"
    elif [[ -t 0 ]]; then
      echo "    MySQL/MariaDB credentials from container settings did not work for $container_name."
      read -r -p "    Database username [root] (blank keeps default, S skips): " entered_user
      [[ "${entered_user,,}" == "s" ]] && return 0
      user="${entered_user:-root}"
      backup_read_secret secret "    Password for $user: "
      if ! database_output="$(backup_docker_mysql_query "$container_id" "$client" "$user" "$secret" "$mysql_sql" 2>/dev/null)"; then
        echo "    Authentication failed; skipping $container_name."
        return 0
      fi
    else
      echo "    $container_name: authentication failed; skipped."
      return 0
    fi
  fi
  backup_append_mysql_rows "$database_output" "$engine" "docker" "Docker: $container_name" "$container_id" \
    "$user" "$secret" "$dump_client"
}

backup_wait_for_started_container() {
  local container_id="$1" engine="$2" attempt
  for (( attempt = 1; attempt <= 45; attempt++ )); do
    case "$engine" in
      postgresql)
        "${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" pg_isready >/dev/null 2>&1 && return 0
        ;;
      mysql)
        "${BACKUP_DOCKER_COMMAND[@]}" exec "$container_id" sh -c \
          'mysqladmin ping --silent >/dev/null 2>&1 || mariadb-admin ping --silent >/dev/null 2>&1' && return 0
        ;;
    esac
    sleep 1
  done
  return 1
}

discover_docker_databases() {
  local container_output container_id image_name container_name running_state engine index stopped_count=0
  local start_stopped="false"
  local docker_endpoint_args=()
  local candidate_ids=() candidate_images=() candidate_names=() candidate_states=() candidate_engines=()

  echo "  • Docker PostgreSQL, MySQL and MariaDB containers"
  if ! command -v docker >/dev/null 2>&1; then
    echo "    Docker is not installed; continuing with native and file databases."
    return 0
  fi
  if [[ -n "${INSTALL_DOCKER_ENDPOINT:-}" ]]; then
    docker_endpoint_args=(--host "$INSTALL_DOCKER_ENDPOINT")
  fi
  BACKUP_DOCKER_COMMAND=(docker "${docker_endpoint_args[@]}")
  if ! "${BACKUP_DOCKER_COMMAND[@]}" info >/dev/null 2>&1; then
    if sudo docker "${docker_endpoint_args[@]}" info >/dev/null 2>&1; then
      BACKUP_DOCKER_COMMAND=(sudo docker "${docker_endpoint_args[@]}")
    else
      echo "    Docker engine is unavailable; Docker databases were skipped."
      return 0
    fi
  fi
  container_output="$("${BACKUP_DOCKER_COMMAND[@]}" ps -aq 2>/dev/null || true)"
  [[ -n "$container_output" ]] || { echo "    No containers found."; return 0; }

  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    image_name="$("${BACKUP_DOCKER_COMMAND[@]}" inspect --format '{{.Config.Image}}' "$container_id" 2>/dev/null || true)"
    container_name="$("${BACKUP_DOCKER_COMMAND[@]}" inspect --format '{{.Name}}' "$container_id" 2>/dev/null || true)"
    container_name="${container_name#/}"
    running_state="$("${BACKUP_DOCKER_COMMAND[@]}" inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || true)"
    case "${image_name,,}" in
      *exporter*|*operator*|*database-backup*|*db-backup*) continue ;;
    esac
    case "${image_name,,}" in
      *postgres*|*postgis*|*timescale*) engine="postgresql" ;;
      *mysql*|*mariadb*|*percona*) engine="mysql" ;;
      *) continue ;;
    esac
    candidate_ids+=("$container_id")
    candidate_images+=("$image_name")
    candidate_names+=("${container_name:-${container_id:0:12}}")
    candidate_states+=("$running_state")
    candidate_engines+=("$engine")
    [[ "$running_state" == "true" ]] || stopped_count=$((stopped_count + 1))
  done <<< "$container_output"

  if (( ${#candidate_ids[@]} == 0 )); then
    echo "    No supported database containers found."
    return 0
  fi
  if (( stopped_count > 0 )) && [[ -t 0 ]] &&
     ask_yes_no "    Start $stopped_count stopped database container(s) temporarily for discovery? [Y/n]: " "y"; then
    start_stopped="true"
  fi

  for (( index = 0; index < ${#candidate_ids[@]}; index++ )); do
    container_id="${candidate_ids[index]}"
    if [[ "${candidate_states[index]}" != "true" ]]; then
      if [[ "$start_stopped" != "true" ]]; then
        echo "    ${candidate_names[index]}: stopped; skipped."
        continue
      fi
      echo "    Starting ${candidate_names[index]} temporarily..."
      if ! "${BACKUP_DOCKER_COMMAND[@]}" start "$container_id" >/dev/null; then
        echo "    Could not start ${candidate_names[index]}; skipped."
        continue
      fi
      BACKUP_STARTED_CONTAINERS+=("$container_id")
      if ! backup_wait_for_started_container "$container_id" "${candidate_engines[index]}"; then
        echo "    ${candidate_names[index]} did not become ready; skipped."
        continue
      fi
    fi
    case "${candidate_engines[index]}" in
      postgresql) discover_docker_postgresql "$container_id" "${candidate_names[index]}" ;;
      mysql) discover_docker_mysql "$container_id" "${candidate_names[index]}" "${candidate_images[index]}" ;;
    esac
  done
}

discover_sqlite_databases() {
  local use_sudo="false" sqlite_path header_hex database_size root
  local search_roots=() find_expression=() home_root

  echo "  • Primary SQLite project/deployment databases"
  for root in /var/lib /var/www /opt /srv /usr/local /mnt /media /data; do
    [[ -d "$root" ]] && search_roots+=("$root")
  done
  for home_root in /home/* /root; do
    [[ -d "$home_root" ]] || continue
    for root in \
      "$home_root/Projects" "$home_root/projects" \
      "$home_root/Desktop" "$home_root/Documents" \
      "$home_root/apps" "$home_root/Apps" \
      "$home_root/www" "$home_root/workspace" "$home_root/Workspace"; do
      [[ -d "$root" ]] && search_roots+=("$root")
    done
  done
  (( ${#search_roots[@]} > 0 )) || { echo "    No search roots available."; return 0; }

  BACKUP_SCAN_FILE="$(mktemp /tmp/odoo19-database-scan.XXXXXX)"
  find_expression=(
    \( -path "$SCRIPT_DIR/backups" -o -path "$SCRIPT_DIR/backups/*" -o
       -path '*/.cache/*' -o -path '*/cache/*' -o -path '*/Cache/*' -o
       -path '*/node_modules/*' -o -path '*/vendor/bundle/*' -o
       -path '*/.venv/*' -o -path '*/venv/*' -o -path '*/site-packages/*' -o
       -path '*/__pycache__/*' -o -path '*/tmp/*' -o -path '*/temp/*' -o
       -path '*/.git/*' -o -path '*/logs/*' -o
       -path '/var/lib/command-not-found/*' -o -path '/var/lib/PackageKit/*' -o
       -path '/var/lib/colord/*' -o -path '/var/lib/fwupd/*' -o
       -path '/var/lib/apt/*' -o -path '/var/lib/dpkg/*' -o
       -path '/var/lib/snapd/*' \) -prune -o
    -type f \( -iname '*.sqlite' -o -iname '*.sqlite3' -o -iname '*.db' \)
    -size +0c -print0
  )
  if [[ -t 0 ]] && ask_yes_no "    Use sudo to include protected system locations in the SQLite scan? [Y/n]: " "y"; then
    use_sudo="true"
  fi
  echo "    Searching common application-data locations; this may take some time..."
  if [[ "$use_sudo" == "true" ]]; then
    sudo find "${search_roots[@]}" -xdev "${find_expression[@]}" > "$BACKUP_SCAN_FILE" 2>/dev/null || true
  else
    find "${search_roots[@]}" -xdev "${find_expression[@]}" > "$BACKUP_SCAN_FILE" 2>/dev/null || true
  fi

  while IFS= read -r -d '' sqlite_path; do
    case "${sqlite_path,,}" in
      */cache.db|*/cache.sqlite|*/cache.sqlite3|*/*_cache.db|*/*-cache.db|\
      */load_statistics.db|*/first_party_sets.db|*/heavy_ad_intervention_opt_out.db|\
      */cookies.db|*/history.db|*/favicons.db|*/hsts-storage.sqlite|\
      */session.db|*/session-store.db|*/segments_database.db|\
      */test.db|*/test.sqlite|*/test.sqlite3|*/*_test.db|*/*_test.sqlite|*/*_test.sqlite3)
        BACKUP_SQLITE_FILTERED_COUNT=$((BACKUP_SQLITE_FILTERED_COUNT + 1))
        continue
        ;;
    esac
    if [[ "$use_sudo" == "true" ]]; then
      header_hex="$(sudo od -An -tx1 -N16 -- "$sqlite_path" 2>/dev/null | tr -d '[:space:]' || true)"
      database_size="$(sudo du -h -- "$sqlite_path" 2>/dev/null | awk '{print $1}' || true)"
    else
      header_hex="$(od -An -tx1 -N16 -- "$sqlite_path" 2>/dev/null | tr -d '[:space:]' || true)"
      database_size="$(du -h -- "$sqlite_path" 2>/dev/null | awk '{print $1}' || true)"
    fi
    [[ "$header_hex" == "53514c69746520666f726d6174203300" ]] || continue
    backup_catalog_add "SQLite" "file" "File: $sqlite_path" "$sqlite_path" \
      "" "" "sqlite3" "$(basename -- "$sqlite_path")" "${database_size:-unknown}"
  done < "$BACKUP_SCAN_FILE"
  rm -f -- "$BACKUP_SCAN_FILE"
  BACKUP_SCAN_FILE=""
}

show_primary_database_summary() {
  local index postgresql_count=0 mysql_count=0 sqlite_count=0
  for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
    case "${BACKUP_CATALOG_ENGINES[index]}" in
      PostgreSQL) postgresql_count=$((postgresql_count + 1)) ;;
      MySQL|MariaDB) mysql_count=$((mysql_count + 1)) ;;
      SQLite) sqlite_count=$((sqlite_count + 1)) ;;
    esac
  done
  echo
  echo "Primary database summary:"
  printf '  %-32s %s\n' "PostgreSQL server databases" "$postgresql_count"
  printf '  %-32s %s\n' "MySQL/MariaDB server databases" "$mysql_count"
  printf '  %-32s %s\n' "SQLite project/deployment files" "$sqlite_count"
  printf '  %-32s %s\n' "Cache/test/system SQLite data" "excluded"
}

sort_backup_catalog_by_category() {
  local category index
  local engines=() source_kinds=() source_labels=() source_refs=()
  local users=() secrets=() clients=() databases=() sizes=()

  for category in postgresql mysql sqlite; do
    for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
      case "$category:${BACKUP_CATALOG_ENGINES[index]}" in
        postgresql:PostgreSQL|mysql:MySQL|mysql:MariaDB|sqlite:SQLite)
          engines+=("${BACKUP_CATALOG_ENGINES[index]}")
          source_kinds+=("${BACKUP_CATALOG_SOURCE_KINDS[index]}")
          source_labels+=("${BACKUP_CATALOG_SOURCE_LABELS[index]}")
          source_refs+=("${BACKUP_CATALOG_SOURCE_REFS[index]}")
          users+=("${BACKUP_CATALOG_USERS[index]}")
          secrets+=("${BACKUP_CATALOG_SECRETS[index]}")
          clients+=("${BACKUP_CATALOG_CLIENTS[index]}")
          databases+=("${BACKUP_CATALOG_DATABASES[index]}")
          sizes+=("${BACKUP_CATALOG_SIZES[index]}")
          ;;
      esac
    done
  done

  BACKUP_CATALOG_ENGINES=("${engines[@]}")
  BACKUP_CATALOG_SOURCE_KINDS=("${source_kinds[@]}")
  BACKUP_CATALOG_SOURCE_LABELS=("${source_labels[@]}")
  BACKUP_CATALOG_SOURCE_REFS=("${source_refs[@]}")
  BACKUP_CATALOG_USERS=("${users[@]}")
  BACKUP_CATALOG_SECRETS=("${secrets[@]}")
  BACKUP_CATALOG_CLIENTS=("${clients[@]}")
  BACKUP_CATALOG_DATABASES=("${databases[@]}")
  BACKUP_CATALOG_SIZES=("${sizes[@]}")
}

scan_system_databases() {
  backup_reset_catalog
  echo
  echo "Searching the system for application databases..."
  echo "Supported engines: PostgreSQL, MySQL, MariaDB and SQLite (native, Docker and files)."
  echo "Maintenance, template, cache, test and system databases are filtered out."
  discover_native_postgresql
  discover_native_mysql
  discover_docker_databases
  discover_sqlite_databases
  sort_backup_catalog_by_category
  show_primary_database_summary

  if (( ${#BACKUP_CATALOG_DATABASES[@]} == 0 )); then
    echo
    echo "No accessible application databases were found."
    echo "Stopped or password-protected instances that were skipped are shown in the scan output above."
    return 1
  fi
}

select_multiple_backup_databases() {
  local selection normalized token range_start_text range_end_text range_start range_end selected_index
  local selection_valid index category category_title category_count
  BACKUP_SELECTED_INDEXES=()

  echo
  echo "Primary databases found across the system:"
  for category in postgresql mysql sqlite; do
    case "$category" in
      postgresql) category_title="POSTGRESQL SERVER DATABASES" ;;
      mysql) category_title="MYSQL / MARIADB SERVER DATABASES" ;;
      sqlite) category_title="SQLITE PROJECT / DEPLOYMENT DATABASES" ;;
    esac
    category_count=0
    for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
      case "$category:${BACKUP_CATALOG_ENGINES[index]}" in
        postgresql:PostgreSQL|mysql:MySQL|mysql:MariaDB|sqlite:SQLite)
          category_count=$((category_count + 1))
          ;;
      esac
    done
    (( category_count > 0 )) || continue
    echo
    printf '  %b%s (%s)%b\n' "$COLOR_CYAN$COLOR_BOLD" "$category_title" "$category_count" "$COLOR_RESET"
    printf '  %-5s %-12s %-42s %-28s %s\n' "No." "Engine" "Source" "Database/file" "Size"
    for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
      case "$category:${BACKUP_CATALOG_ENGINES[index]}" in
        postgresql:PostgreSQL|mysql:MySQL|mysql:MariaDB|sqlite:SQLite)
          printf '  [%2s]  %-12.12s %-42.42s %-28.28s %s\n' "$((index + 1))" \
            "${BACKUP_CATALOG_ENGINES[index]}" \
            "${BACKUP_CATALOG_SOURCE_LABELS[index]}" \
            "${BACKUP_CATALOG_DATABASES[index]}" \
            "${BACKUP_CATALOG_SIZES[index]}"
          ;;
      esac
    done
  done
  echo
  echo "Select multiple entries with commas/spaces (example: 1,3,4), a range (1-3), or A for all."

  while true; do
    read -r -p "Database selection [A]: " selection
    selection="${selection:-A}"
    case "${selection,,}" in
      a|all)
        for (( index = 0; index < ${#BACKUP_CATALOG_DATABASES[@]}; index++ )); do
          BACKUP_SELECTED_INDEXES+=("$index")
        done
        return 0
        ;;
      c|cancel) return 1 ;;
    esac

    normalized="${selection//,/ }"
    BACKUP_SELECTED_INDEXES=()
    selection_valid="true"
    for token in $normalized; do
      if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        range_start_text="${BASH_REMATCH[1]}"
        range_end_text="${BASH_REMATCH[2]}"
        if (( ${#range_start_text} > 9 || ${#range_end_text} > 9 )); then
          selection_valid="false"
          break
        fi
        range_start=$((10#$range_start_text))
        range_end=$((10#$range_end_text))
        if (( range_start < 1 || range_end < range_start || range_end > ${#BACKUP_CATALOG_DATABASES[@]} )); then
          selection_valid="false"
          break
        fi
        for (( selected_index = range_start - 1; selected_index <= range_end - 1; selected_index++ )); do
          if ! backup_list_contains "$selected_index" "${BACKUP_SELECTED_INDEXES[@]}"; then
            BACKUP_SELECTED_INDEXES+=("$selected_index")
          fi
        done
      elif [[ "$token" =~ ^[0-9]+$ && ${#token} -le 9 ]]; then
        selected_index=$((10#$token - 1))
        if (( selected_index < 0 || selected_index >= ${#BACKUP_CATALOG_DATABASES[@]} )); then
          selection_valid="false"
          break
        fi
        if ! backup_list_contains "$selected_index" "${BACKUP_SELECTED_INDEXES[@]}"; then
          BACKUP_SELECTED_INDEXES+=("$selected_index")
        fi
      else
        selection_valid="false"
        break
      fi
    done
    if [[ "$selection_valid" == "true" && ${#BACKUP_SELECTED_INDEXES[@]} -gt 0 ]]; then
      return 0
    fi
    echo "Invalid selection. Use numbers such as 1,3,4, a range such as 1-3, A for all, or C to cancel."
  done
}

backup_has_selected_engine() {
  local wanted_engine="$1" selected_index
  for selected_index in "${BACKUP_SELECTED_INDEXES[@]}"; do
    [[ "${BACKUP_CATALOG_ENGINES[selected_index]}" == "$wanted_engine" ]] && return 0
  done
  return 1
}

backup_postgresql_database() {
  local source_kind="$1" source_ref="$2" user="$3" secret="$4" client="$5"
  local database_name="$6" output_file="$7"
  if [[ "$source_kind" == "native" ]]; then
    sudo -u postgres "$client" --format=custom --port="$source_ref" --file=- --dbname="$database_name" > "$output_file"
  elif [[ -n "$secret" ]]; then
    "${BACKUP_DOCKER_COMMAND[@]}" exec -e "PGPASSWORD=$secret" "$source_ref" \
      "$client" -U "$user" --format=custom --file=- --dbname="$database_name" > "$output_file"
  else
    "${BACKUP_DOCKER_COMMAND[@]}" exec "$source_ref" \
      "$client" -U "$user" --format=custom --file=- --dbname="$database_name" > "$output_file"
  fi
}

backup_mysql_database() {
  local source_kind="$1" source_ref="$2" user="$3" secret="$4" client="$5"
  local database_name="$6" output_file="$7"
  local dump_options=(--single-transaction --quick --routines --events --triggers --databases -- "$database_name")

  if [[ "$source_kind" == "docker" ]]; then
    if [[ -n "$secret" ]]; then
      "${BACKUP_DOCKER_COMMAND[@]}" exec -e "MYSQL_PWD=$secret" "$source_ref" \
        "$client" -u "$user" "${dump_options[@]}" > "$output_file"
    else
      "${BACKUP_DOCKER_COMMAND[@]}" exec "$source_ref" \
        "$client" -u "$user" "${dump_options[@]}" > "$output_file"
    fi
  else
    case "$source_ref" in
      sudo) sudo "$client" "${dump_options[@]}" > "$output_file" ;;
      current) "$client" "${dump_options[@]}" > "$output_file" ;;
      password) MYSQL_PWD="$secret" "$client" -u "$user" "${dump_options[@]}" > "$output_file" ;;
      *) return 1 ;;
    esac
  fi
}

backup_sqlite_database() {
  local source_path="$1" destination_dir="$2" output_file
  output_file="$destination_dir/database.sqlite"
  rm -f -- "$output_file"
  if (cd "$destination_dir" && sqlite3 "$source_path" ".backup 'database.sqlite'"); then
    return 0
  fi
  rm -f -- "$output_file"
  (cd "$destination_dir" && sudo sqlite3 "$source_path" ".backup 'database.sqlite'")
}

backup_catalog_entry() {
  local selected_index="$1" output_root="$2" display_number="$3"
  local engine="${BACKUP_CATALOG_ENGINES[selected_index]}"
  local source_kind="${BACKUP_CATALOG_SOURCE_KINDS[selected_index]}"
  local source_label="${BACKUP_CATALOG_SOURCE_LABELS[selected_index]}"
  local source_ref="${BACKUP_CATALOG_SOURCE_REFS[selected_index]}"
  local user="${BACKUP_CATALOG_USERS[selected_index]}"
  local secret="${BACKUP_CATALOG_SECRETS[selected_index]}"
  local client="${BACKUP_CATALOG_CLIENTS[selected_index]}"
  local database_name="${BACKUP_CATALOG_DATABASES[selected_index]}"
  local engine_dir database_dir dump_format dump_file

  engine_dir="${engine,,}"
  database_dir="$output_root/databases/$engine_dir/database-$(printf '%03d' "$display_number")"
  mkdir -p "$database_dir"
  echo "Backing up $engine database: $database_name ($source_label)"
  case "$engine" in
    PostgreSQL)
      dump_file="$database_dir/database.dump"
      dump_format="PostgreSQL custom-format dump"
      backup_postgresql_database "$source_kind" "$source_ref" "$user" "$secret" "$client" \
        "$database_name" "$dump_file"
      ;;
    MySQL|MariaDB)
      dump_file="$database_dir/database.sql"
      dump_format="$engine SQL dump"
      backup_mysql_database "$source_kind" "$source_ref" "$user" "$secret" "$client" \
        "$database_name" "$dump_file"
      ;;
    SQLite)
      dump_file="$database_dir/database.sqlite"
      dump_format="SQLite online-backup copy"
      backup_sqlite_database "$source_ref" "$database_dir"
      ;;
    *) echo "Unsupported backup engine: $engine"; return 1 ;;
  esac
  if [[ ! -s "$dump_file" ]]; then
    echo "The generated backup is empty for $engine/$database_name."
    return 1
  fi

  cat > "$database_dir/backup-info.txt" <<EOF
Engine: $engine
Database/file: $database_name
Source: $source_label
Created: $(date --iso-8601=seconds)
Dump format: $dump_format
EOF
}

run_backup_manager() (
  local result_file="${1:-}" timestamp archive_path selected_index display_number=0

  umask 077
  BACKUP_ARCHIVE_COMPLETE="false"

  section "BACKUP" "System-wide database discovery and archive"
  echo "This scan is not limited to Odoo, Community, Enterprise, or this installer."
  echo "It discovers accessible application databases from supported engines across Ubuntu and Docker."

  trap 'backup_restore_original_state' EXIT
  trap 'exit 130' INT TERM HUP

  if ! scan_system_databases; then
    echo "Backup could not start because no accessible database was found."
    return 0
  fi
  if ! select_multiple_backup_databases; then
    echo "Backup cancelled."
    return 0
  fi
  if ! ensure_rar_available; then
    echo "Backup cancelled because a RAR archive cannot be created."
    return 0
  fi
  if backup_has_selected_engine SQLite && ! ensure_sqlite_available; then
    echo "Backup cancelled because sqlite3 is unavailable."
    return 0
  fi

  echo
  echo "Selected databases:"
  for selected_index in "${BACKUP_SELECTED_INDEXES[@]}"; do
    printf '  - %-12s %-30s %s (%s)\n' \
      "${BACKUP_CATALOG_ENGINES[selected_index]}" \
      "${BACKUP_CATALOG_SOURCE_LABELS[selected_index]}" \
      "${BACKUP_CATALOG_DATABASES[selected_index]}" \
      "${BACKUP_CATALOG_SIZES[selected_index]}"
  done
  echo "Logical/online dumps will be used; unrelated application services will not be stopped."
  if ! ask_yes_no "Create one RAR archive containing all selected database backups? [Y/n]: " "y"; then
    echo "Backup cancelled."
    return 0
  fi

  mkdir -p "$SCRIPT_DIR/backups"
  chmod 700 "$SCRIPT_DIR/backups"
  BACKUP_WORK_DIR="$(mktemp -d "$SCRIPT_DIR/backups/.backup-work.XXXXXX")"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive_path="$SCRIPT_DIR/backups/system-databases-${timestamp}.rar"
  if [[ -e "$archive_path" ]]; then archive_path="${archive_path%.rar}-$$.rar"; fi
  BACKUP_ARCHIVE_PATH="$archive_path"

  cat > "$BACKUP_WORK_DIR/backup-info.txt" <<EOF
System database backup bundle
Created: $(date --iso-8601=seconds)
Selected databases: ${#BACKUP_SELECTED_INDEXES[@]}
Engines: PostgreSQL custom dumps, MySQL/MariaDB SQL dumps, and SQLite online-backup copies
Security: database passwords are used only in memory and are not written into this archive.
EOF

  for selected_index in "${BACKUP_SELECTED_INDEXES[@]}"; do
    display_number=$((display_number + 1))
    backup_catalog_entry "$selected_index" "$BACKUP_WORK_DIR" "$display_number"
  done

  echo "Creating RAR archive..."
  rar a -idq -m3 -ep1 -r "$archive_path" "$BACKUP_WORK_DIR/backup-info.txt" "$BACKUP_WORK_DIR/databases"
  chmod 600 "$archive_path"
  BACKUP_ARCHIVE_COMPLETE="true"

  backup_restore_original_state
  trap - EXIT INT TERM HUP
  echo
  printf '%b\n' "${COLOR_GREEN}Backup completed successfully.${COLOR_RESET}"
  printf 'Archive: %s\n' "$archive_path"
  echo "Permissions: owner read/write only (600). Copy it to secure off-machine storage."
  if [[ -n "$result_file" && "$result_file" == /tmp/odoo19-uninstall-backup.* ]]; then
    printf '%s\n' "$archive_path" > "$result_file"
  fi
)
