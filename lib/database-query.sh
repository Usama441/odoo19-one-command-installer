#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.
#
# Main menu option: configure, run, and schedule cron/run-database-query.sh,
# which runs cron/database-query.sql against one edition's Odoo database.
# The schedule is an entry in the user's crontab; the uninstaller removes it
# (odoo_cron_runner_path and friends in lib/uninstall.sh).

DB_QUERY_CONFIG="cron/database-query.conf"
DB_QUERY_SQL="cron/database-query.sql"
DB_QUERY_LOG="logs/database-query.log"

db_query_config_value() {
  local key="$1"
  [[ -f "$SCRIPT_DIR/$DB_QUERY_CONFIG" ]] || return 0
  awk -v key="$key" 'index($0, key "=") == 1 { value = substr($0, length(key) + 2); sub(/\r$/, "", value); print value; exit }' \
    "$SCRIPT_DIR/$DB_QUERY_CONFIG"
}

db_query_container_for() {
  printf 'odoo19-dual-db-%s-1\n' "$1"
}

# The crontab line for the runner, empty when it is not scheduled.
db_query_cron_line() {
  command -v crontab >/dev/null 2>&1 || return 0
  crontab -l 2>/dev/null | grep -F "$(odoo_cron_runner_path)" | grep -v '^[[:space:]]*#' | head -n 1 || true
}

# "day 25 of every month at 00:00" from the first three crontab fields.
db_query_schedule_summary() {
  local line="$1" minute hour day
  read -r minute hour day _ <<< "$line"
  if [[ "$minute" =~ ^[0-9]+$ && "$hour" =~ ^[0-9]+$ && "$day" =~ ^[0-9]+$ ]]; then
    printf 'monthly, day %s at %02d:%02d' "$day" "$((10#$hour))" "$((10#$minute))"
  else
    printf 'custom (%s)' "$(cut -d' ' -f1-5 <<< "$line")"
  fi
}

show_database_query_status() {
  local target database line last_run
  target="$(db_query_config_value DB_CRON_TARGET)"
  database="$(db_query_config_value DB_CRON_DATABASE)"
  section "DATABASE QUERY" "Scheduled SQL against an Odoo database"
  if [[ -n "$target" && -n "$database" && "$database" != "replace_with_your_odoo_database_name" ]]; then
    printf '  %-26s %s\n' "Target" "$database ($target)"
  else
    printf '  %-26s %s\n' "Target" "not set (option 1)"
  fi
  if [[ -s "$SCRIPT_DIR/$DB_QUERY_SQL" ]]; then
    printf '  %-26s %s\n' "SQL file" "$DB_QUERY_SQL ($(grep -cv '^[[:space:]]*\(--.*\)\?$' "$SCRIPT_DIR/$DB_QUERY_SQL") lines of SQL)"
  else
    printf '  %-26s %s\n' "SQL file" "not created yet (option 2)"
  fi
  line="$(db_query_cron_line)"
  if [[ -n "$line" ]]; then
    printf '  %-26s %s\n' "Schedule" "$(db_query_schedule_summary "$line")"
  else
    printf '  %-26s %s\n' "Schedule" "not scheduled"
  fi
  if [[ -s "$SCRIPT_DIR/$DB_QUERY_LOG" ]]; then
    last_run="$(grep '^=== ' "$SCRIPT_DIR/$DB_QUERY_LOG" | tail -n 1 | sed 's/^=== //; s/ ===$//' || true)"
    printf '  %-26s %s\n' "Last run" "${last_run:-see $DB_QUERY_LOG}"
  else
    printf '  %-26s %s\n' "Last run" "never"
  fi
}

# Lists the Odoo databases in one edition's PostgreSQL container.
list_odoo_databases() {
  "${DOCKER[@]}" exec "$(db_query_container_for "$1")" \
    psql --no-psqlrc -X -U odoo -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname"
}

configure_database_query_target() {
  local editions=() edition target databases=() database index choice allowed
  for edition in community enterprise; do
    "${DOCKER[@]}" container inspect "$(db_query_container_for "$edition")" >/dev/null 2>&1 && editions+=("$edition")
  done
  if (( ${#editions[@]} == 0 )); then
    echo "No Odoo PostgreSQL container was found. Start Odoo first (docker compose up -d)."
    return 1
  fi
  if (( ${#editions[@]} == 1 )); then
    target="${editions[0]}"
    echo "Edition: $target (the only one installed)"
  else
    echo "Which edition's database should the query run against?"
    echo "  1) community"
    echo "  2) enterprise"
    read_choice choice "Choose an option [2]: " "" "1 2"
    target="${editions[choice - 1]}"
  fi

  if ! mapfile -t databases < <(list_odoo_databases "$target" 2>/dev/null) || (( ${#databases[@]} == 0 )); then
    echo "No Odoo database was found in $target, or its PostgreSQL container is stopped."
    echo "Create a database in Odoo first, or start the stack (docker compose up -d)."
    return 1
  fi
  echo "Odoo databases in $target:"
  allowed=""
  for index in "${!databases[@]}"; do
    printf '  %s) %s\n' "$((index + 1))" "${databases[index]}"
    allowed+=" $((index + 1))"
  done
  read_choice choice "Choose a database [1]: " "" "$allowed"
  database="${databases[choice - 1]}"

  (umask 077 && cat > "$SCRIPT_DIR/$DB_QUERY_CONFIG" <<EOF
# Written by the installer (main menu option 8). See database-query.conf.example.
DB_CRON_TARGET=$target
DB_CRON_DATABASE=$database
DB_CRON_DOCKER_HOST=$INSTALL_DOCKER_ENDPOINT
EOF
  )
  printf '%b\n' "${COLOR_GREEN}Saved.${COLOR_RESET} The query will run against $database ($target)."
}

edit_database_query_sql() {
  local editor
  if [[ ! -f "$SCRIPT_DIR/$DB_QUERY_SQL" ]]; then
    cp -- "$SCRIPT_DIR/cron/database-query.sql.example" "$SCRIPT_DIR/$DB_QUERY_SQL"
    chmod 600 "$SCRIPT_DIR/$DB_QUERY_SQL"
  fi
  for editor in "${VISUAL:-}" "${EDITOR:-}" nano vi; do
    [[ -n "$editor" ]] && command -v "${editor%% *}" >/dev/null 2>&1 && break
    editor=""
  done
  if [[ -z "$editor" ]]; then
    echo "No text editor was found. Paste your SQL into $SCRIPT_DIR/$DB_QUERY_SQL"
    return 1
  fi
  echo "Opening $DB_QUERY_SQL. Paste or write your SQL, then save and close the editor."
  $editor "$SCRIPT_DIR/$DB_QUERY_SQL"
  echo "Saved $DB_QUERY_SQL. Use \"Run the query now\" to test it."
}

user_can_reach_docker() {
  docker --host "$INSTALL_DOCKER_ENDPOINT" info >/dev/null 2>&1
}

database_query_ready() {
  local database
  database="$(db_query_config_value DB_CRON_DATABASE)"
  if [[ -z "$database" || "$database" == "replace_with_your_odoo_database_name" ]]; then
    echo "Choose the database first (option 1)."
    return 1
  fi
  if [[ ! -s "$SCRIPT_DIR/$DB_QUERY_SQL" ]]; then
    echo "Write the SQL first (option 2)."
    return 1
  fi
}

# Runs the job the same way cron does and keeps the output in the log too.
run_database_query_now() {
  local status=0 runner prefix=()
  database_query_ready || return 1
  runner="$(odoo_cron_runner_path)"
  mkdir -p "$SCRIPT_DIR/logs"
  # Docker group membership needs a new login; fall back to sudo until then.
  user_can_reach_docker || prefix=(sudo)
  echo "Running the query..."
  echo
  "${prefix[@]}" bash "$runner" 2>&1 | tee -a "$SCRIPT_DIR/$DB_QUERY_LOG" || status="${PIPESTATUS[0]}"
  echo
  if (( status == 0 )); then
    printf '%b\n' "${COLOR_GREEN}The query finished successfully.${COLOR_RESET} Output was added to $DB_QUERY_LOG."
  else
    printf '%b\n' "${COLOR_RED}The query failed (exit code $status).${COLOR_RESET} See the messages above."
  fi
  return "$status"
}

enable_database_query_schedule() {
  local day time hour minute runner log current
  database_query_ready || return 1
  if ! command -v crontab >/dev/null 2>&1; then
    echo "crontab is not installed. Install it with: sudo apt-get install cron"
    return 1
  fi
  read_integer day "Day of the month to run (1-28) [25]: " "" 1 28
  while true; do
    read_value time "Time to run, 24-hour HH:MM [00:00]: "
    if [[ "$time" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
      hour="$((10#${BASH_REMATCH[1]}))"
      minute="$((10#${BASH_REMATCH[2]}))"
      break
    fi
    echo "Please enter a time such as 00:00, 02:30 or 23:15."
  done

  runner="$(odoo_cron_runner_path)"
  log="$SCRIPT_DIR/$DB_QUERY_LOG"
  mkdir -p "$SCRIPT_DIR/logs"
  current="$(crontab -l 2>/dev/null || true)"
  if ! { grep -Fv "$runner" <<< "$current" || true
         printf '%s %s %s * * "%s" >> "%s" 2>&1\n' "$minute" "$hour" "$day" "$runner" "$log"
       } | crontab -; then
    echo "Could not update your crontab."
    return 1
  fi
  printf '%b\n' "${COLOR_GREEN}Scheduled:${COLOR_RESET} day $day of every month at $(printf '%02d:%02d' "$hour" "$minute")."
  echo "The server must be on at that time; a run missed while it is off is skipped."
  if ! user_can_reach_docker; then
    printf '%b\n' "${COLOR_YELLOW}Your user cannot use Docker without sudo yet, so the scheduled run would fail.${COLOR_RESET}"
    echo "Log out and back in (or reboot) so your docker group membership applies, then check with: docker ps"
  fi
}

disable_database_query_schedule() {
  remove_odoo_cron_entries
}

show_database_query_log() {
  if [[ ! -s "$SCRIPT_DIR/$DB_QUERY_LOG" ]]; then
    echo "The query has not run yet."
    return 0
  fi
  echo "Last 40 lines of $DB_QUERY_LOG:"
  echo "------------------------------------------------------------"
  tail -n 40 "$SCRIPT_DIR/$DB_QUERY_LOG"
  echo "------------------------------------------------------------"
}

run_database_query_manager() {
  local choice
  cd "$SCRIPT_DIR" || return 1
  if ! odoo_installation_present; then
    echo "Odoo is not installed yet. Install Odoo first; the query runs against an Odoo database."
    return 1
  fi
  resolve_certificate_docker_command || return 1

  while true; do
    show_database_query_status
    echo
    echo "What would you like to do?"
    echo "  1) Choose the edition and database"
    echo "  2) Write or edit the SQL query"
    echo "  3) Run the query now"
    if [[ -n "$(db_query_cron_line)" ]]; then
      echo "  4) Turn off the monthly schedule"
    else
      echo "  4) Turn on the monthly schedule (cron job)"
    fi
    echo "  5) Show the recent log"
    echo "  6) Exit"
    read_choice choice "Choose an option [3]: " "" "1 2 3 4 5 6"
    echo
    case "$choice" in
      1) configure_database_query_target || true ;;
      2) edit_database_query_sql || true ;;
      3) run_database_query_now || true ;;
      4)
        if [[ -n "$(db_query_cron_line)" ]]; then
          disable_database_query_schedule
        else
          enable_database_query_schedule || true
        fi
        ;;
      5) show_database_query_log ;;
      6) return 0 ;;
    esac
  done
}
