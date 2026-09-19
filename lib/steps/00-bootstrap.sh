#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

step_bootstrap_and_menu() {
  print_banner
  printf '%b\n' "${COLOR_BOLD}Welcome to your all-in-one Odoo 19 deployment workspace.${COLOR_RESET}"
  echo "Install, inspect, maintain, or safely remove your stack from one place."

  if [[ "${EUID}" -eq 0 ]]; then
    echo "Run this script as your normal sudo-enabled user, not as root."
    exit 1
  fi

  OS_MIN_SUPPORTED="22.04"
  OS_MAX_TESTED="26.04"
  UBUNTU_REPO_CODENAME=""

  if [[ ! -r /etc/os-release ]]; then
    echo "Unsupported system: Ubuntu $OS_MIN_SUPPORTED or newer is required."
    exit 1
  fi
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" && " ${ID_LIKE:-} " != *" ubuntu "* ]]; then
    echo "Unsupported system: detected ${PRETTY_NAME:-unknown}."
    echo "Ubuntu $OS_MIN_SUPPORTED or newer, or an Ubuntu-based distribution, is required."
    exit 1
  fi

  # The Docker repository is published per Ubuntu codename, so derivatives must use
  # the Ubuntu codename they inherit rather than their own VERSION_CODENAME.
  UBUNTU_REPO_CODENAME="${UBUNTU_CODENAME:-}"
  if [[ -z "$UBUNTU_REPO_CODENAME" && "${ID:-}" == "ubuntu" ]]; then
    UBUNTU_REPO_CODENAME="${VERSION_CODENAME:-}"
  fi

  # Derivatives ship their own VERSION_ID (Linux Mint 22, Pop!_OS 22.04), so resolve
  # the underlying Ubuntu release from that inherited codename instead.
  DETECTED_UBUNTU_RELEASE=""
  if [[ "${ID:-}" == "ubuntu" ]]; then
    DETECTED_UBUNTU_RELEASE="${VERSION_ID:-}"
  elif [[ -n "$UBUNTU_REPO_CODENAME" ]]; then
    DETECTED_UBUNTU_RELEASE="$(ubuntu_release_for_codename "$UBUNTU_REPO_CODENAME" || true)"
  fi

  if DETECTED_RELEASE_KEY="$(os_release_key "$DETECTED_UBUNTU_RELEASE")"; then
    if (( DETECTED_RELEASE_KEY < $(os_release_key "$OS_MIN_SUPPORTED") )); then
      echo "Unsupported system: detected ${PRETTY_NAME:-unknown}."
      echo "Ubuntu $OS_MIN_SUPPORTED or newer is required."
      exit 1
    fi
    if (( DETECTED_RELEASE_KEY > $(os_release_key "$OS_MAX_TESTED") )); then
      echo "Note: ${PRETTY_NAME:-this release} is newer than Ubuntu $OS_MAX_TESTED, the newest release this installer was tested against."
      echo "The installation will continue; report anything that misbehaves."
    fi
  else
    echo "Note: the Ubuntu release behind ${PRETTY_NAME:-this system} could not be determined."
    echo "The installation will continue, assuming Ubuntu $OS_MIN_SUPPORTED or newer."
  fi

  detect_system_specs

  APT_INDEX_READY="false"

  INSTALLER_STATE_FILE="$SCRIPT_DIR/.installer-state"
  INSTALLER_MANAGED_PACKAGES=()
  INSTALLER_CREATED_DOCKER_SOURCE="false"
  INSTALLER_CREATED_DOCKER_KEY="false"
  INSTALLER_DOCKER_GROUP_USER=""

  load_installer_state

  DASHBOARD_MIN_WIDTH=112
  DASHBOARD_MAX_WIDTH=132
  DASHBOARD_MIN_HEIGHT=33
  DASHBOARD_MAX_HEIGHT=42
  DASHBOARD_CONTENT_HEIGHT=32
  DASHBOARD_WIDTH="$DASHBOARD_MIN_WIDTH"
  DASHBOARD_CONTENT_WIDTH=$((DASHBOARD_WIDTH - 6))
  DASHBOARD_LEFT=0
  DASHBOARD_TOP=0
  DASHBOARD_MENU_ROW=20
  TERMINAL_COLUMNS=0
  TERMINAL_ROWS=0

  INTERACTIVE_ALT_SCREEN="false"
  INTERACTIVE_STTY_STATE=""

  BACKUP_DOCKER_COMMAND=()
  BACKUP_STARTED_CONTAINERS=()
  BACKUP_STARTED_PG_CLUSTERS=()
  BACKUP_STARTED_MYSQL_SERVICES=()
  BACKUP_CATALOG_ENGINES=()
  BACKUP_CATALOG_SOURCE_KINDS=()
  BACKUP_CATALOG_SOURCE_LABELS=()
  BACKUP_CATALOG_SOURCE_REFS=()
  BACKUP_CATALOG_USERS=()
  BACKUP_CATALOG_SECRETS=()
  BACKUP_CATALOG_CLIENTS=()
  BACKUP_CATALOG_DATABASES=()
  BACKUP_CATALOG_SIZES=()
  BACKUP_SELECTED_INDEXES=()
  BACKUP_SQLITE_FILTERED_COUNT=0
  BACKUP_WORK_DIR=""
  BACKUP_SCAN_FILE=""
  BACKUP_ARCHIVE_PATH=""
  BACKUP_ARCHIVE_COMPLETE="false"

  UNINSTALL_DOCKER_COMMAND=()
  UNINSTALL_TARGET_SERVICES=()
  UNINSTALL_TARGET_VOLUMES=()
  UNINSTALL_GENERATED_FILES=()
  UNINSTALL_VERIFIED_VOLUMES=()
  UNINSTALL_SOURCE_TARGETS=()
  UNINSTALL_VERIFIED_SOURCE_PATHS=()
  UNINSTALL_FOREIGN_DOCKER_RESOURCES=()
  UNINSTALL_DATABASE_DELETE_APPROVED="false"
  UNINSTALL_SCOPE_NAME=""

  if enterprise_addons_ready; then
    DEFAULT_MAIN_CHOICE="3"
  else
    DEFAULT_MAIN_CHOICE="1"
  fi

  if interactive_terminal_supported; then
    if configure_dashboard_geometry || wait_for_dashboard_size; then
      read_interactive_main_choice "$DEFAULT_MAIN_CHOICE"
    else
      echo "Goodbye."
      exit 0
    fi
  else
    show_control_center_status
    section "MENU" "What would you like to do?"
    menu_item "1" "Install Odoo Community only"
    menu_item "2" "Install Odoo Enterprise only"
    menu_item "3" "Install both Community and Enterprise"
    menu_item "4" "Check Ubuntu updates and missing dependencies"
    menu_item "5" "Back up databases across this system"
    menu_item "6" "Uninstall Odoo"
    menu_item "7" "Exit"
    read_choice MAIN_CHOICE "Choose an option [$DEFAULT_MAIN_CHOICE]: " "$DEFAULT_MAIN_CHOICE" "1 2 3 4 5 6 7"
  fi

  INSTALL_ACTION="install"
  START_COMMUNITY="false"
  START_ENTERPRISE="false"
  case "$MAIN_CHOICE" in
    1) START_COMMUNITY="true" ;;
    2) START_ENTERPRISE="true" ;;
    3) START_COMMUNITY="true"; START_ENTERPRISE="true" ;;
    4) INSTALL_ACTION="dependencies" ;;
    5) run_backup_manager; exit 0 ;;
    6) run_uninstaller; exit 0 ;;
    7) echo "Goodbye."; exit 0 ;;
  esac
}
