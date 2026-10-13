#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ipv4() {
  local octet
  [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  for octet in ${1//./ }; do
    (( 10#$octet <= 255 )) || return 1
  done
}

# Sets BIND_ADDRESS, the host address Odoo and pgAdmin web ports publish on:
# localhost only, or an address the user enters (0.0.0.0 for all interfaces).
# A saved choice from .env becomes the default on reruns.
choose_bind_address() {
  local saved_address="" default_address default_choice choice entered

  if [[ -f .env ]]; then saved_address="$(get_env_value BIND_ADDRESS)"; fi
  if [[ "$DEPLOYMENT_MODE" == "testing" ]]; then default_address="127.0.0.1"; else default_address="0.0.0.0"; fi
  if [[ -n "$saved_address" ]] && valid_ipv4 "$saved_address"; then default_address="$saved_address"; fi
  if [[ "$default_address" == "127.0.0.1" ]]; then default_choice="1"; else default_choice="2"; fi

  echo
  printf '%b\n' "${COLOR_BOLD}Network bind address${COLOR_RESET}"
  echo "  1) localhost only (127.0.0.1) - reachable only from this machine"
  echo "  2) Enter an IP address - a server IP, or 0.0.0.0 for all interfaces"
  read_choice choice "Choose a bind address option [$default_choice]: " "$default_choice" "1 2"
  if [[ "$choice" == "1" ]]; then
    BIND_ADDRESS="127.0.0.1"
    return
  fi

  [[ "$default_address" == "127.0.0.1" ]] && default_address="0.0.0.0"
  echo "IPv4 addresses on this machine: $(hostname -I 2>/dev/null | xargs || echo unknown)"
  while true; do
    read -r -p "Bind IP address [$default_address]: " entered
    entered="${entered:-$default_address}"
    entered="${entered//[[:space:]]/}"
    if ! valid_ipv4 "$entered"; then
      echo "Please enter an IPv4 address such as 192.168.1.10 or 0.0.0.0."
      continue
    fi
    # Docker can only publish on an address assigned to this host.
    if [[ "$entered" != "0.0.0.0" && "$entered" != "127.0.0.1" ]] &&
       ! hostname -I 2>/dev/null | tr ' ' '\n' | grep -Fxq "$entered"; then
      echo "$entered is not assigned to this machine, so Docker could not publish on it."
      continue
    fi
    BIND_ADDRESS="$entered"
    return
  done
}

# Human-readable description of BIND_ADDRESS for the review and summary.
bind_address_label() {
  case "$BIND_ADDRESS" in
    127.0.0.1) echo "localhost only (127.0.0.1)" ;;
    0.0.0.0) echo "all host interfaces (0.0.0.0)" ;;
    *) echo "$BIND_ADDRESS only" ;;
  esac
}

# Pinned official image tag for each selectable Odoo release.
odoo_image_for_version() {
  case "$1" in
    19.0) echo "odoo:19.0-20260908" ;;
    20.0) echo "odoo:20.0-20260926" ;;
    *) return 1 ;;
  esac
}

set_odoo_version() {
  ODOO_VERSION="$1"
  ODOO_MAJOR_VERSION="${ODOO_VERSION%%.*}"
  DEFAULT_ODOO_IMAGE="$(odoo_image_for_version "$ODOO_VERSION")"
  ODOO_HOST_ROOT="/opt/odoo/odoo$ODOO_MAJOR_VERSION"
  ODOO_HOST_ENTERPRISE_DIR="$ODOO_HOST_ROOT/enterprise"
  ODOO_HOST_CUSTOM_ROOT="$ODOO_HOST_ROOT/custom_addons"
}

# The version an existing .env was installed with. Files written before
# ODOO_VERSION was recorded fall back to the image tag, then to 19.0.
detect_installed_odoo_version() {
  local version="" image=""
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    version="$(get_env_value ODOO_VERSION)"
    if [[ -z "$version" ]]; then
      image="$(get_env_value ODOO_IMAGE)"
      if [[ "$image" =~ :([0-9]+\.0) ]]; then version="${BASH_REMATCH[1]}"; fi
    fi
  fi
  odoo_image_for_version "$version" >/dev/null 2>&1 || version="19.0"
  echo "$version"
}

choose_odoo_version() {
  local version choice default_index="" index=1 allowed="" label
  local default_version="${SUPPORTED_ODOO_VERSIONS[-1]}"

  [[ -f "$SCRIPT_DIR/.env" ]] && default_version="$ODOO_VERSION"
  echo
  printf '%b\n' "${COLOR_BOLD}Which Odoo version do you want to install?${COLOR_RESET}"
  for version in "${SUPPORTED_ODOO_VERSIONS[@]}"; do
    label="Odoo $version"
    if [[ -f "$SCRIPT_DIR/.env" && "$version" == "$ODOO_VERSION" ]]; then
      label+=" (current installation)"
    elif [[ "$version" == "${SUPPORTED_ODOO_VERSIONS[-1]}" ]]; then
      label+=" (latest)"
    fi
    printf '  %s) %s\n' "$index" "$label"
    [[ "$version" == "$default_version" ]] && default_index="$index"
    allowed+=" $index $version ${version%%.*}"
    index=$((index + 1))
  done
  read_choice choice "Choose an Odoo version [$default_index]: " "$default_index" "$allowed"
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SUPPORTED_ODOO_VERSIONS[@]} )); then
    version="${SUPPORTED_ODOO_VERSIONS[choice - 1]}"
  else
    version="${choice%%.*}.0"
  fi
  set_odoo_version "$version"
  printf 'Odoo %s selected (image %s).\n' "$ODOO_VERSION" "$DEFAULT_ODOO_IMAGE"
}

# Databases created by one major version cannot be opened by another, so a
# version switch is only allowed once the old databases are gone.
verify_odoo_version_change() {
  local installed_version

  [[ -f .env ]] || return 0
  installed_version="$(detect_installed_odoo_version)"
  [[ "$installed_version" != "$ODOO_VERSION" ]] || return 0
  if [[ "$COMMUNITY_DB_VOLUME_EXISTS" == "true" || "$ENTERPRISE_DB_VOLUME_EXISTS" == "true" ]]; then
    echo
    printf '%b\n' "${COLOR_YELLOW}This system already has Odoo $installed_version databases.${COLOR_RESET}"
    echo "Odoo $ODOO_VERSION cannot open them; a major-version upgrade needs Odoo's database migration."
    echo "Back up the databases (menu option 5), uninstall with database deletion (option 6),"
    echo "then run the installer again and choose Odoo $ODOO_VERSION."
    exit 1
  fi
  echo "Switching the existing configuration from Odoo $installed_version to Odoo $ODOO_VERSION (no databases exist yet)."
}

# Bundled licensed Enterprise source for the selected version, checked in
# order: installed copy, extracted checkout folder, then legacy unversioned
# locations that only ever held Odoo 19.
enterprise_source_candidates() {
  printf '%s\n' "$ODOO_HOST_ENTERPRISE_DIR" "$SCRIPT_DIR/enterprise-$ODOO_VERSION"
  if [[ "$ODOO_VERSION" == "19.0" ]]; then
    printf '%s\n' "$SCRIPT_DIR/addons/enterprise" "$SCRIPT_DIR/enterprise"
  fi
}

ensure_unzip_available() {
  if command -v unzip >/dev/null 2>&1; then return 0; fi
  echo "Installing the unzip utility to extract the Enterprise archive..."
  if ! install_apt_packages unzip || ! command -v unzip >/dev/null 2>&1; then
    echo "The unzip package could not be installed."
    return 1
  fi
  track_installer_packages unzip
}

# Extracts enterprise-<version>.zip into enterprise-<version>/ next to the
# installer. A staging folder keeps an interrupted extraction from looking
# like a complete source folder.
extract_enterprise_archive() {
  local archive="$1" target="$SCRIPT_DIR/enterprise-$ODOO_VERSION" staging
  local top_folder="enterprise-$ODOO_VERSION"

  if [[ -e "$target" ]]; then
    echo "$target exists but is not a complete Enterprise folder. Move it aside so $(basename -- "$archive") can be extracted."
    return 1
  fi
  ensure_unzip_available || return 1
  staging="$(mktemp -d "$SCRIPT_DIR/.enterprise-extract.XXXXXX")"
  echo "Extracting $(basename -- "$archive"). This may take a moment..."
  if ! unzip -q "$archive" "$top_folder/*" -d "$staging"; then
    rm -rf -- "$staging"
    echo "Extraction failed. Check that $(basename -- "$archive") is complete."
    return 1
  fi
  if [[ ! -f "$staging/$top_folder/web_enterprise/__manifest__.py" ]]; then
    rm -rf -- "$staging"
    echo "$(basename -- "$archive") does not contain $top_folder/web_enterprise."
    return 1
  fi
  mv -- "$staging/$top_folder" "$target"
  rm -rf -- "$staging"
  echo "Extracted Enterprise addons to $target"
}

valid_custom_addons_folder() {
  local folder_name="$1"
  [[ "$folder_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] &&
    [[ "$folder_name" != "." && "$folder_name" != ".." ]]
}

configure_custom_addons_directory() {
  local saved_path="${1:-}" default_name="" entered_name folder_name

  if [[ "$saved_path" == "$ODOO_HOST_CUSTOM_ROOT/"* ]]; then
    folder_name="${saved_path#"$ODOO_HOST_CUSTOM_ROOT/"}"
    if [[ "$folder_name" != */* ]] && valid_custom_addons_folder "$folder_name"; then
      default_name="$folder_name"
    fi
  fi

  echo
  printf '%b\n' "${COLOR_BOLD}Custom addons workspace${COLOR_RESET}"
  echo "Choose the folder that will contain your custom Odoo modules."
  echo "It will be created inside $ODOO_HOST_CUSTOM_ROOT and shared by the selected editions."
  echo "Use letters, numbers, dots, underscores, or hyphens; spaces become underscores."

  while true; do
    if [[ -n "$default_name" ]]; then
      read -r -p "Custom addons folder name [$default_name]: " entered_name
      entered_name="${entered_name:-$default_name}"
    else
      read -r -p "Custom addons folder name (example: TI_Associates): " entered_name
    fi

    entered_name="${entered_name#"${entered_name%%[![:space:]]*}"}"
    entered_name="${entered_name%"${entered_name##*[![:space:]]}"}"
    folder_name="${entered_name//[[:space:]]/_}"

    if [[ -z "$folder_name" ]]; then
      echo "A folder name is required."
      continue
    fi
    if ! valid_custom_addons_folder "$folder_name"; then
      echo "Enter 1-64 characters using letters, numbers, dots, underscores, or hyphens."
      echo "The name must start with a letter or number and cannot contain a path separator."
      continue
    fi

    ODOO_HOST_CUSTOM_ADDONS_DIR="$ODOO_HOST_CUSTOM_ROOT/$folder_name"
    if [[ "$folder_name" != "$entered_name" ]]; then
      echo "Folder name normalized to: $folder_name"
    fi
    printf 'Custom addons will be stored in: %s\n' "$ODOO_HOST_CUSTOM_ADDONS_DIR"
    return
  done
}

valid_integer_in_range() {
  local value="$1" minimum="$2" maximum="$3"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  (( ${#value} <= 18 )) || return 1
  (( 10#$value >= minimum && 10#$value <= maximum ))
}

read_integer() {
  local target="$1" prompt="$2" default_value="$3" minimum="$4" maximum="$5" entered_value
  while true; do
    read -r -p "$prompt" entered_value
    entered_value="${entered_value:-$default_value}"
    if valid_integer_in_range "$entered_value" "$minimum" "$maximum"; then
      printf -v "$target" '%s' "$((10#$entered_value))"
      return
    fi
    echo "Please enter a whole number from $minimum to $maximum."
  done
}

recommended_workers_for_users() {
  local expected_users="$1" workers
  workers=$(((expected_users + 5) / 6))
  (( workers < 2 )) && workers=2
  printf '%s' "$workers"
}

calculate_worker_budget() {
  local worker_memory_mib="${1:-768}"
  local detected_cpu selected_services cpu_limit reserved_ram usable_ram ram_limit

  detected_cpu="$SYSTEM_CPU_COUNT"
  [[ "$detected_cpu" =~ ^[0-9]+$ ]] || detected_cpu=2
  selected_services=0
  [[ "$START_COMMUNITY" == "true" ]] && selected_services=$((selected_services + 1))
  [[ "$START_ENTERPRISE" == "true" ]] && selected_services=$((selected_services + 1))
  (( selected_services > 0 )) || selected_services=1

  cpu_limit=$((detected_cpu * 2 + 1 - selected_services * ODOO_MAX_CRON_THREADS))
  (( cpu_limit < selected_services )) && cpu_limit="$selected_services"

  reserved_ram=$((SYSTEM_RAM_MIB / 4))
  (( reserved_ram < 2048 )) && reserved_ram=2048
  usable_ram=$((SYSTEM_RAM_MIB - reserved_ram))
  (( usable_ram < 0 )) && usable_ram=0
  ram_limit=$((usable_ram / worker_memory_mib))
  (( ram_limit < selected_services )) && ram_limit="$selected_services"

  PERFORMANCE_CPU_WORKER_LIMIT="$cpu_limit"
  PERFORMANCE_RAM_WORKER_LIMIT="$ram_limit"
  if (( cpu_limit < ram_limit )); then
    PERFORMANCE_WORKER_BUDGET="$cpu_limit"
    PERFORMANCE_LIMIT_REASON="CPU"
  else
    PERFORMANCE_WORKER_BUDGET="$ram_limit"
    PERFORMANCE_LIMIT_REASON="RAM"
  fi
}

fit_recommended_workers_to_budget() {
  local total_workers
  while true; do
    total_workers=$((COMMUNITY_WORKERS + ENTERPRISE_WORKERS))
    (( total_workers <= PERFORMANCE_WORKER_BUDGET )) && return

    if [[ "$START_ENTERPRISE" == "true" && "$ENTERPRISE_WORKERS" -ge "$COMMUNITY_WORKERS" &&
          "$ENTERPRISE_WORKERS" -gt 1 ]]; then
      ENTERPRISE_WORKERS=$((ENTERPRISE_WORKERS - 1))
    elif [[ "$START_COMMUNITY" == "true" && "$COMMUNITY_WORKERS" -gt 1 ]]; then
      COMMUNITY_WORKERS=$((COMMUNITY_WORKERS - 1))
    elif [[ "$START_ENTERPRISE" == "true" && "$ENTERPRISE_WORKERS" -gt 1 ]]; then
      ENTERPRISE_WORKERS=$((ENTERPRISE_WORKERS - 1))
    else
      return
    fi
  done
}

configure_performance_profile() {
  local performance_choice default_choice=1 community_users_default=12 enterprise_users_default=24
  local community_workers_default enterprise_workers_default cron_default=1
  local soft_limit_mib=768 hard_limit_mib=1536 total_workers total_expected_users

  PERFORMANCE_MODE="testing"
  COMMUNITY_EXPECTED_USERS=0
  ENTERPRISE_EXPECTED_USERS=0
  COMMUNITY_WORKERS=0
  ENTERPRISE_WORKERS=0
  ODOO_MAX_CRON_THREADS=1
  ODOO_LIMIT_MEMORY_SOFT=0
  ODOO_LIMIT_MEMORY_HARD=0
  ESTIMATED_CONCURRENT_CAPACITY=0

  if [[ "$DEPLOYMENT_MODE" != "production" ]]; then
    echo
    echo "Testing profile selected: Odoo will use its lightweight threaded server (workers = 0)."
    echo "Choose Production on a future run to use the hardware-aware performance advisor."
    return
  fi

  if valid_integer_in_range "${SAVED_COMMUNITY_EXPECTED_USERS:-}" 1 10000; then
    community_users_default="$SAVED_COMMUNITY_EXPECTED_USERS"
  fi
  if valid_integer_in_range "${SAVED_ENTERPRISE_EXPECTED_USERS:-}" 1 10000; then
    enterprise_users_default="$SAVED_ENTERPRISE_EXPECTED_USERS"
  fi

  section "PERFORMANCE" "Hardware-aware Odoo performance advisor"
  printf '  %-28s %s\n' "Detected Ubuntu" "${PRETTY_NAME:-Unknown}"
  printf '  %-28s %s\n' "Detected hardware" "$SYSTEM_SPEC_SUMMARY"
  echo
  echo "Enter simultaneous users, not the total number of registered accounts."
  echo "Odoo's sizing guideline estimates about six simultaneous users per HTTP worker."

  if [[ "$START_COMMUNITY" == "true" ]]; then
    read_integer COMMUNITY_EXPECTED_USERS \
      "Expected simultaneous Community users [$community_users_default]: " \
      "$community_users_default" 1 10000
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    read_integer ENTERPRISE_EXPECTED_USERS \
      "Expected simultaneous Enterprise users [$enterprise_users_default]: " \
      "$enterprise_users_default" 1 10000
  fi

  ODOO_MAX_CRON_THREADS=1
  calculate_worker_budget
  if [[ "$START_COMMUNITY" == "true" ]]; then
    COMMUNITY_WORKERS="$(recommended_workers_for_users "$COMMUNITY_EXPECTED_USERS")"
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    ENTERPRISE_WORKERS="$(recommended_workers_for_users "$ENTERPRISE_EXPECTED_USERS")"
  fi
  fit_recommended_workers_to_budget
  community_workers_default="$COMMUNITY_WORKERS"
  enterprise_workers_default="$ENTERPRISE_WORKERS"

  echo
  printf '%b\n' "${COLOR_BOLD}Recommended production settings${COLOR_RESET}"
  printf '  %-28s %s\n' "Safe combined worker budget" "$PERFORMANCE_WORKER_BUDGET ($PERFORMANCE_LIMIT_REASON limit)"
  if [[ "$START_COMMUNITY" == "true" ]]; then
    printf '  %-28s %s\n' "Community HTTP workers" "$COMMUNITY_WORKERS (~$((COMMUNITY_WORKERS * 6)) simultaneous users)"
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    printf '  %-28s %s\n' "Enterprise HTTP workers" "$ENTERPRISE_WORKERS (~$((ENTERPRISE_WORKERS * 6)) simultaneous users)"
  fi
  printf '  %-28s %s\n' "Cron threads" "1 per selected edition"
  printf '  %-28s %s\n' "Memory limits per worker" "768 MiB soft / 1536 MiB hard"
  echo
  echo "  1) Apply the automatic recommendation (recommended)"
  echo "  2) Enter custom worker and memory settings"
  echo "  3) Use the safe minimum (one worker per selected edition)"

  case "${SAVED_PERFORMANCE_MODE:-}" in
    custom) default_choice=2 ;;
    safe) default_choice=3 ;;
  esac
  read_choice performance_choice "Choose a performance option [$default_choice]: " "$default_choice" "1 2 3 automatic custom safe"

  case "${performance_choice,,}" in
    1|automatic)
      PERFORMANCE_MODE="automatic"
      ODOO_MAX_CRON_THREADS=1
      ODOO_LIMIT_MEMORY_SOFT=$((768 * 1024 * 1024))
      ODOO_LIMIT_MEMORY_HARD=$((1536 * 1024 * 1024))
      ;;
    2|custom)
      PERFORMANCE_MODE="custom"
      if valid_integer_in_range "${SAVED_COMMUNITY_WORKERS:-}" 1 64; then
        community_workers_default="$SAVED_COMMUNITY_WORKERS"
      fi
      if valid_integer_in_range "${SAVED_ENTERPRISE_WORKERS:-}" 1 64; then
        enterprise_workers_default="$SAVED_ENTERPRISE_WORKERS"
      fi
      if valid_integer_in_range "${SAVED_ODOO_MAX_CRON_THREADS:-}" 1 4; then
        cron_default="$SAVED_ODOO_MAX_CRON_THREADS"
      fi
      if valid_integer_in_range "${SAVED_ODOO_LIMIT_MEMORY_SOFT:-}" 268435456 68719476736; then
        soft_limit_mib=$((SAVED_ODOO_LIMIT_MEMORY_SOFT / 1024 / 1024))
      fi
      if valid_integer_in_range "${SAVED_ODOO_LIMIT_MEMORY_HARD:-}" 536870912 68719476736; then
        hard_limit_mib=$((SAVED_ODOO_LIMIT_MEMORY_HARD / 1024 / 1024))
      fi

      read_integer ODOO_MAX_CRON_THREADS "Cron threads per selected edition [$cron_default]: " "$cron_default" 1 4
      while true; do
        read_integer soft_limit_mib "Soft memory limit per worker in MiB [$soft_limit_mib]: " "$soft_limit_mib" 256 65536
        read_integer hard_limit_mib "Hard memory limit per worker in MiB [$hard_limit_mib]: " "$hard_limit_mib" 512 65536
        if (( hard_limit_mib > soft_limit_mib )); then
          break
        fi
        echo "The hard memory limit must be greater than the soft memory limit."
      done
      ODOO_LIMIT_MEMORY_SOFT=$((soft_limit_mib * 1024 * 1024))
      ODOO_LIMIT_MEMORY_HARD=$((hard_limit_mib * 1024 * 1024))
      calculate_worker_budget "$soft_limit_mib"
      printf '  %-28s %s\n' "Custom safe worker budget" \
        "$PERFORMANCE_WORKER_BUDGET ($PERFORMANCE_LIMIT_REASON limit at ${soft_limit_mib} MiB per worker)"
      while true; do
        if [[ "$START_COMMUNITY" == "true" ]]; then
          read_integer COMMUNITY_WORKERS "Community HTTP workers [$community_workers_default]: " "$community_workers_default" 1 64
        fi
        if [[ "$START_ENTERPRISE" == "true" ]]; then
          read_integer ENTERPRISE_WORKERS "Enterprise HTTP workers [$enterprise_workers_default]: " "$enterprise_workers_default" 1 64
        fi
        total_workers=$((COMMUNITY_WORKERS + ENTERPRISE_WORKERS))
        if (( total_workers <= PERFORMANCE_WORKER_BUDGET )); then
          break
        fi
        printf '%b\n' "${COLOR_YELLOW}The custom total ($total_workers) exceeds the detected safe budget ($PERFORMANCE_WORKER_BUDGET).${COLOR_RESET}"
        if ask_yes_no "Use this overcommitted worker count anyway? [y/N]: " "n"; then
          break
        fi
        echo "Enter lower worker counts."
      done
      ;;
    3|safe)
      PERFORMANCE_MODE="safe"
      [[ "$START_COMMUNITY" == "true" ]] && COMMUNITY_WORKERS=1
      [[ "$START_ENTERPRISE" == "true" ]] && ENTERPRISE_WORKERS=1
      ODOO_MAX_CRON_THREADS=1
      ODOO_LIMIT_MEMORY_SOFT=$((768 * 1024 * 1024))
      ODOO_LIMIT_MEMORY_HARD=$((1536 * 1024 * 1024))
      ;;
  esac

  total_workers=$((COMMUNITY_WORKERS + ENTERPRISE_WORKERS))
  total_expected_users=$((COMMUNITY_EXPECTED_USERS + ENTERPRISE_EXPECTED_USERS))
  ESTIMATED_CONCURRENT_CAPACITY=$((total_workers * 6))
  if (( ESTIMATED_CONCURRENT_CAPACITY < total_expected_users )); then
    printf '%b\n' "${COLOR_YELLOW}Note: the selected workers provide estimated capacity for $ESTIMATED_CONCURRENT_CAPACITY of $total_expected_users expected simultaneous users.${COLOR_RESET}"
  fi
}

has_enterprise_addons() {
  local source="$1"
  [[ -d "$source" ]] &&
    find "$source" -mindepth 2 -maxdepth 2 -type f -name '__manifest__.py' -print -quit | grep -q .
}

prepare_persistent_addons_layout() {
  local directory host_parent primary_group
  host_parent="$(dirname -- "$ODOO_HOST_ROOT")"
  primary_group="$(id -gn "$USER")"

  echo "Preparing the persistent Odoo source and custom-addons layout under $ODOO_HOST_ROOT..."
  for directory in \
    "$host_parent" \
    "$ODOO_HOST_ROOT" \
    "$ODOO_HOST_ENTERPRISE_DIR" \
    "$ODOO_HOST_CUSTOM_ROOT" \
    "$ODOO_HOST_CUSTOM_ADDONS_DIR"; do
    if [[ -e "$directory" && ! -d "$directory" ]]; then
      echo "$directory exists but is not a directory. Move it aside, then rerun the installer."
      return 1
    fi
    if [[ ! -d "$directory" ]]; then
      sudo install -d -m 0755 -o "$USER" -g "$primary_group" "$directory"
    fi
  done

  for directory in "$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ADDONS_DIR"; do
    if [[ ! -r "$directory" || ! -w "$directory" || ! -x "$directory" ]]; then
      echo "Granting $USER access to the installer-managed directory $directory..."
      sudo chown "$USER:$primary_group" "$directory"
      sudo chmod 0755 "$directory"
    fi
  done
}

migrate_legacy_custom_addons() {
  local legacy_directory manifest module_directory module_name target_directory
  for legacy_directory in "$SCRIPT_DIR/addons/community" "$SCRIPT_DIR/addons/enterprise-custom"; do
    [[ -d "$legacy_directory" ]] || continue
    while IFS= read -r -d '' manifest; do
      module_directory="$(dirname -- "$manifest")"
      module_name="$(basename -- "$module_directory")"
      target_directory="$ODOO_HOST_CUSTOM_ADDONS_DIR/$module_name"
      if [[ -e "$target_directory" ]]; then
        echo "Keeping existing custom module: $target_directory"
      else
        echo "Migrating custom module to persistent storage: $module_name"
        cp -a "$module_directory" "$ODOO_HOST_CUSTOM_ADDONS_DIR/"
      fi
    done < <(find "$legacy_directory" -mindepth 2 -maxdepth 2 -type f -name '__manifest__.py' -print0)
  done
}

read_enterprise_source() {
  local suggested_path="$1" entered_path
  suggested_path="${suggested_path:-$SCRIPT_DIR/enterprise-$ODOO_VERSION}"
  while true; do
    echo "Default Enterprise path based on the current installer location:"
    echo "  $suggested_path"
    read -r -p "Enterprise addons folder [$suggested_path]: " entered_path
    entered_path="${entered_path:-$suggested_path}"
    entered_path="${entered_path#\"}"
    entered_path="${entered_path%\"}"
    if ! has_enterprise_addons "$entered_path"; then
      echo "That folder does not contain Odoo addon manifests. Please select the folder whose direct subfolders are Enterprise modules."
      continue
    fi
    if [[ ! -f "$entered_path/web_enterprise/__manifest__.py" ]]; then
      echo "The web_enterprise module was not found. Please select a complete Odoo $ODOO_VERSION Enterprise addon folder."
      continue
    fi
    ENTERPRISE_SOURCE="$entered_path"
    return
  done
}

get_env_value() {
  local key="$1"
  awk -v key="$key" 'index($0, key "=") == 1 { value = substr($0, length(key) + 2); sub(/\r$/, "", value); print value; exit }' .env
}

get_config_value() {
  local path="$1" key="$2"
  [[ -f "$path" ]] || return 0
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$path"
}

write_config() {
  local target="$1" db_host="$2" db_password="$3" admin_password="$4" addons_path="$5"
  local workers="$6" cron_threads="$7" memory_soft="$8" memory_hard="$9"
  cat > "$target" <<EOF
[options]
admin_passwd = $admin_password
db_host = $db_host
db_port = 5432
db_user = odoo
db_password = $db_password
addons_path = $addons_path
data_dir = /var/lib/odoo
list_db = True
proxy_mode = False
workers = $workers
max_cron_threads = $cron_threads
limit_memory_hard = $memory_hard
limit_memory_soft = $memory_soft
EOF
}
