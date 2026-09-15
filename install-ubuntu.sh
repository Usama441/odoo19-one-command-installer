#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_VERSION="1.0.0"
ODOO_HOST_ROOT="/opt/odoo/odoo19"
ODOO_HOST_ENTERPRISE_DIR="$ODOO_HOST_ROOT/enterprise"
ODOO_HOST_CUSTOM_ROOT="$ODOO_HOST_ROOT/custom_addons"
ODOO_HOST_CUSTOM_ADDONS_DIR=""
cd "$SCRIPT_DIR"

if [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" ]] &&
   command -v clear >/dev/null 2>&1; then
  clear || true
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_PURPLE=$'\033[38;5;97m'
  COLOR_CYAN=$'\033[38;5;37m'
  COLOR_BLUE=$'\033[38;5;81m'
  COLOR_GREEN=$'\033[38;5;34m'
  COLOR_RED=$'\033[38;5;196m'
  COLOR_YELLOW=$'\033[38;5;214m'
  COLOR_WHITE=$'\033[38;5;255m'
  COLOR_MUTED=$'\033[38;5;110m'
  COLOR_MAGENTA_BG=$'\033[48;5;97m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_PURPLE=""
  COLOR_CYAN=""
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_YELLOW=""
  COLOR_WHITE=""
  COLOR_MUTED=""
  COLOR_MAGENTA_BG=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

print_banner() {
  printf '%b' "$COLOR_PURPLE$COLOR_BOLD"
  cat <<EOF

============================================================
             ODOO 19 DEPLOYMENT CONTROL CENTER
                    Installer v$INSTALLER_VERSION
     Community • Enterprise • PostgreSQL • pgAdmin
                  Script by TI ASSOCIATES
              Developed by USAMA ARSHAD
============================================================
EOF
  printf '%b' "$COLOR_RESET"
}

section() {
  printf '\n%b[%s] %s%b\n' "$COLOR_CYAN$COLOR_BOLD" "$1" "$2" "$COLOR_RESET"
  printf '%s\n' "------------------------------------------------------------"
}

menu_item() {
  printf '  %b[%s]%b %s\n' "$COLOR_GREEN$COLOR_BOLD" "$1" "$COLOR_RESET" "$2"
}

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

os_release_key() {
  [[ "$1" =~ ^([0-9]+)\.([0-9]+) ]] || return 1
  printf '%d' $((10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]}))
}

ubuntu_release_for_codename() {
  case "$1" in
    trusty) printf '14.04' ;;
    xenial) printf '16.04' ;;
    bionic) printf '18.04' ;;
    focal) printf '20.04' ;;
    groovy) printf '20.10' ;;
    hirsute) printf '21.04' ;;
    impish) printf '21.10' ;;
    jammy) printf '22.04' ;;
    lunar) printf '23.04' ;;
    mantic) printf '23.10' ;;
    noble) printf '24.04' ;;
    oracular) printf '24.10' ;;
    plucky) printf '25.04' ;;
    questing) printf '25.10' ;;
    resolute) printf '26.04' ;;
    *) return 1 ;;
  esac
}

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

detect_system_specs() {
  local disk_details

  SYSTEM_CPU_COUNT="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  [[ "$SYSTEM_CPU_COUNT" =~ ^[0-9]+$ ]] || SYSTEM_CPU_COUNT="Unknown"

  SYSTEM_RAM_TOTAL="$(
    awk '/^MemTotal:/ {
      gib = $2 / 1048576
      if (gib >= 10) printf "%.0f GiB", gib
      else printf "%.1f GiB", gib
      exit
    }' /proc/meminfo 2>/dev/null || true
  )"
  SYSTEM_RAM_TOTAL="${SYSTEM_RAM_TOTAL:-Unknown}"
  SYSTEM_RAM_MIB="$(awk '/^MemTotal:/ { printf "%.0f", $2 / 1024; exit }' /proc/meminfo 2>/dev/null || true)"
  [[ "$SYSTEM_RAM_MIB" =~ ^[0-9]+$ ]] || SYSTEM_RAM_MIB="2048"

  disk_details="$(df -hP / 2>/dev/null | awk 'NR == 2 { print $2 "|" $4 }' || true)"
  SYSTEM_DISK_TOTAL="${disk_details%%|*}"
  SYSTEM_DISK_FREE="${disk_details#*|}"
  if [[ -z "$disk_details" || "$disk_details" != *"|"* ]]; then
    SYSTEM_DISK_TOTAL="Unknown"
    SYSTEM_DISK_FREE="Unknown"
  fi

  SYSTEM_ARCHITECTURE="$(dpkg --print-architecture 2>/dev/null || uname -m 2>/dev/null || true)"
  SYSTEM_ARCHITECTURE="${SYSTEM_ARCHITECTURE:-Unknown}"
  SYSTEM_SPEC_SUMMARY="${SYSTEM_CPU_COUNT} CPU  •  ${SYSTEM_RAM_TOTAL} RAM  •  ${SYSTEM_DISK_TOTAL} disk (${SYSTEM_DISK_FREE} free)  •  ${SYSTEM_ARCHITECTURE}"
}

detect_system_specs

APT_INDEX_READY="false"

ask_yes_no() {
  local prompt="$1" default_answer="$2" answer
  while true; do
    read -r -p "$prompt" answer
    answer="${answer:-$default_answer}"
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please enter y for yes or n for no." ;;
    esac
  done
}

read_choice() {
  local target="$1" prompt="$2" default_answer="$3" allowed="$4" answer
  while true; do
    read -r -p "$prompt" answer
    answer="${answer:-$default_answer}"
    answer="${answer,,}"
    if [[ " $allowed " == *" $answer "* ]]; then
      printf -v "$target" '%s' "$answer"
      return
    fi
    echo "Please choose one of the listed options."
  done
}

refresh_apt_index() {
  if [[ "$APT_INDEX_READY" != "true" ]]; then
    sudo apt-get update
    APT_INDEX_READY="true"
  fi
}

install_apt_packages() {
  refresh_apt_index
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

INSTALLER_STATE_FILE="$SCRIPT_DIR/.installer-state"
INSTALLER_MANAGED_PACKAGES=()
INSTALLER_CREATED_DOCKER_SOURCE="false"
INSTALLER_CREATED_DOCKER_KEY="false"
INSTALLER_DOCKER_GROUP_USER=""

installer_package_is_supported() {
  case "$1" in
    ca-certificates|curl|openssl|rar|sqlite3|docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|docker-buildx-plugin|docker-compose-plugin) return 0 ;;
    *) return 1 ;;
  esac
}

installer_state_has_package() {
  local wanted="$1" package
  for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
    [[ "$package" == "$wanted" ]] && return 0
  done
  return 1
}

load_installer_state() {
  local key value
  [[ -f "$INSTALLER_STATE_FILE" ]] || return 0

  while IFS='=' read -r key value; do
    case "$key" in
      PACKAGE)
        if installer_package_is_supported "$value" && ! installer_state_has_package "$value"; then
          INSTALLER_MANAGED_PACKAGES+=("$value")
        fi
        ;;
      DOCKER_SOURCE_CREATED)
        [[ "$value" == "true" ]] && INSTALLER_CREATED_DOCKER_SOURCE="true"
        ;;
      DOCKER_KEY_CREATED)
        [[ "$value" == "true" ]] && INSTALLER_CREATED_DOCKER_KEY="true"
        ;;
      DOCKER_GROUP_USER)
        if [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_-]*[$]?$ ]]; then
          INSTALLER_DOCKER_GROUP_USER="$value"
        fi
        ;;
    esac
  done < "$INSTALLER_STATE_FILE"
}

save_installer_state() {
  local package temporary_state="${INSTALLER_STATE_FILE}.tmp"
  (
    umask 077
    {
      for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
        printf 'PACKAGE=%s\n' "$package"
      done
      printf 'DOCKER_SOURCE_CREATED=%s\n' "$INSTALLER_CREATED_DOCKER_SOURCE"
      printf 'DOCKER_KEY_CREATED=%s\n' "$INSTALLER_CREATED_DOCKER_KEY"
      if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
        printf 'DOCKER_GROUP_USER=%s\n' "$INSTALLER_DOCKER_GROUP_USER"
      fi
    } > "$temporary_state"
  )
  mv -f "$temporary_state" "$INSTALLER_STATE_FILE"
  chmod 600 "$INSTALLER_STATE_FILE"
}

track_installer_packages() {
  local package changed="false"
  for package in "$@"; do
    if installer_package_is_supported "$package" && ! installer_state_has_package "$package"; then
      INSTALLER_MANAGED_PACKAGES+=("$package")
      changed="true"
    fi
  done
  [[ "$changed" == "true" ]] && save_installer_state
  return 0
}

load_installer_state

refresh_prerequisite_status() {
  if package_installed ca-certificates; then HAS_CA_CERTIFICATES="true"; else HAS_CA_CERTIFICATES="false"; fi
  if command -v curl >/dev/null 2>&1; then HAS_CURL="true"; else HAS_CURL="false"; fi
  if command -v openssl >/dev/null 2>&1; then HAS_OPENSSL="true"; else HAS_OPENSSL="false"; fi
  if command -v docker >/dev/null 2>&1; then HAS_DOCKER="true"; else HAS_DOCKER="false"; fi
  if [[ "$HAS_DOCKER" == "true" ]] && docker compose version >/dev/null 2>&1; then
    HAS_COMPOSE="true"
  else
    HAS_COMPOSE="false"
  fi
}

status_word() {
  if [[ "$1" == "true" ]]; then printf 'INSTALLED'; else printf 'MISSING'; fi
}

show_prerequisite_status() {
  echo
  echo "Ubuntu prerequisite status"
  printf '  %-28s %s\n' "CA certificates" "$(status_word "$HAS_CA_CERTIFICATES")"
  printf '  %-28s %s\n' "curl" "$(status_word "$HAS_CURL")"
  printf '  %-28s %s\n' "OpenSSL" "$(status_word "$HAS_OPENSSL")"
  printf '  %-28s %s\n' "Docker Engine / CLI" "$(status_word "$HAS_DOCKER")"
  printf '  %-28s %s\n' "Docker Compose plugin" "$(status_word "$HAS_COMPOSE")"
  if systemctl is-active --quiet docker.service 2>/dev/null; then
    printf '  %-28s %s\n' "Docker system service" "RUNNING"
  elif [[ "$HAS_DOCKER" == "true" ]]; then
    printf '  %-28s %s\n' "Docker system service" "STOPPED OR INACCESSIBLE"
  else
    printf '  %-28s %s\n' "Docker system service" "NOT INSTALLED"
  fi
}

setup_docker_repository() {
  local source_was_missing="false" key_was_missing="false"
  [[ ! -e /etc/apt/sources.list.d/docker.list ]] && source_was_missing="true"
  [[ ! -e /etc/apt/keyrings/docker.asc ]] && key_was_missing="true"

  install_apt_packages ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$UBUNTU_REPO_CODENAME"
  if [[ -z "$codename" ]]; then
    echo "The Ubuntu codename could not be determined, so the Docker repository cannot be configured."
    echo "Install Docker Engine and the Compose plugin manually, then rerun this installer."
    exit 1
  fi
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  APT_INDEX_READY="true"

  if [[ "$source_was_missing" == "true" ]]; then INSTALLER_CREATED_DOCKER_SOURCE="true"; fi
  if [[ "$key_was_missing" == "true" ]]; then INSTALLER_CREATED_DOCKER_KEY="true"; fi
  save_installer_state
}

show_control_center_status() {
  local docker_status enterprise_status installation_status
  if command -v docker >/dev/null 2>&1; then
    docker_status="Available"
  else
    docker_status="Not installed"
  fi
  if [[ -f "$SCRIPT_DIR/enterprise-19.0/web_enterprise/__manifest__.py" ||
        -f "$SCRIPT_DIR/enterprise/web_enterprise/__manifest__.py" ||
        -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ||
        -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]; then
    enterprise_status="Ready"
  else
    enterprise_status="Not detected"
  fi
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    installation_status="Existing configuration found"
  else
    installation_status="New installation"
  fi

  echo
  printf '%b\n' "${COLOR_BOLD}Quick system snapshot${COLOR_RESET}"
  printf '  %-22s %s\n' "Ubuntu" "${PRETTY_NAME:-Unknown}"
  printf '  %-22s %s\n' "Hardware" "$SYSTEM_SPEC_SUMMARY"
  printf '  %-22s %s\n' "Docker CLI" "$docker_status"
  printf '  %-22s %s\n' "Enterprise addons" "$enterprise_status"
  printf '  %-22s %s\n' "Installer state" "$installation_status"
  echo
  echo "Choose an action below. Press Enter for the recommended default."
}

enterprise_addons_ready() {
  [[ -f "$SCRIPT_DIR/enterprise-19.0/web_enterprise/__manifest__.py" ||
     -f "$SCRIPT_DIR/enterprise/web_enterprise/__manifest__.py" ||
     -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ||
     -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]
}

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

repeat_character() {
  local character="$1" count="$2" repeated
  printf -v repeated '%*s' "$count" ''
  printf '%s' "${repeated// /$character}"
}

print_padded_text() {
  local LC_ALL=C
  local content="$1" width="$2" content_width=0 padding index byte byte_value

  # Bash printf measures %-Ns fields in bytes under some Ubuntu locales.
  # Count UTF-8 leading bytes instead so terminal borders remain aligned.
  for (( index = 0; index < ${#content}; index++ )); do
    byte="${content:index:1}"
    printf -v byte_value '%d' "'$byte"
    if (( (byte_value & 0xC0) != 0x80 )); then
      content_width=$((content_width + 1))
    fi
  done

  printf '%s' "$content"
  if (( content_width < width )); then
    padding=$((width - content_width))
    printf '%*s' "$padding" ''
  fi
}

dashboard_indent() {
  printf '%*s' "$DASHBOARD_LEFT" ''
}

dashboard_centered_text() {
  local color="$1" content="$2" content_width left_padding
  content_width="${#content}"
  left_padding=$(((DASHBOARD_WIDTH - content_width) / 2))
  (( left_padding < 0 )) && left_padding=0
  printf '%*s%b%s%b\n' "$((DASHBOARD_LEFT + left_padding))" '' "$color" "$content" "$COLOR_RESET"
}

dashboard_border() {
  dashboard_indent
  printf '%b%s' "$COLOR_PURPLE" "$1"
  repeat_character '─' "$((DASHBOARD_WIDTH - 2))"
  printf '%s%b\n' "$2" "$COLOR_RESET"
}

dashboard_line() {
  local color="$1" content="$2"
  dashboard_indent
  printf '│  %b' "$color"
  print_padded_text "$content" "$DASHBOARD_CONTENT_WIDTH"
  printf '%b  │\n' "$COLOR_RESET"
}

dashboard_header_row() {
  local left_color="$1" left="$2" center_color="$3" center="$4" right_color="$5" right="$6"
  local center_width=$((DASHBOARD_CONTENT_WIDTH - 51))
  dashboard_indent
  printf '%b│%b  %b' "$COLOR_PURPLE" "$COLOR_RESET" "$left_color"
  print_padded_text "$left" 18
  printf '%b %b│%b %b' "$COLOR_RESET" "$COLOR_MUTED" "$COLOR_RESET" "$center_color"
  print_padded_text "$center" "$center_width"
  printf '%b %b│%b %b' "$COLOR_RESET" "$COLOR_MUTED" "$COLOR_RESET" "$right_color"
  print_padded_text "$right" 27
  printf '%b  %b│%b\n' "$COLOR_RESET" "$COLOR_PURPLE" "$COLOR_RESET"
}

dashboard_snapshot_row() {
  local icon="$1" label="$2" value="$3" value_color="$4"
  local value_width=$((DASHBOARD_CONTENT_WIDTH - 34))
  dashboard_indent
  printf '│  %b' "$COLOR_BLUE$COLOR_BOLD"
  print_padded_text "$icon" 4
  printf '%b' "$COLOR_WHITE"
  print_padded_text "$label" 30
  printf '%b' "$value_color"
  print_padded_text "$value" "$value_width"
  printf '%b  │\n' "$COLOR_RESET"
}

draw_interactive_dashboard() {
  local selected="$1" recommended="$2"
  local docker_status enterprise_status installation_status

  if command -v docker >/dev/null 2>&1; then
    docker_status="●  Available"
  else
    docker_status="●  Not installed"
  fi
  if enterprise_addons_ready; then
    enterprise_status="●  Ready"
  else
    enterprise_status="●  Not detected"
  fi
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    installation_status="●  Existing configuration found"
  else
    installation_status="●  New installation"
  fi

  dashboard_border '╭' '╮'
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "odoo 19" \
    "$COLOR_WHITE$COLOR_BOLD" "ODOO 19 DEPLOYMENT CONTROL CENTER  •  v$INSTALLER_VERSION" \
    "$COLOR_GREEN$COLOR_BOLD" "      ✓  READY"
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "" \
    "$COLOR_BLUE" "Community  •  Enterprise  •  PostgreSQL  •  pgAdmin" \
    "$COLOR_MUTED" "Script by TI ASSOCIATES"
  dashboard_header_row \
    "$COLOR_PURPLE$COLOR_BOLD" "" \
    "$COLOR_BLUE" "" \
    "$COLOR_MUTED" "Developed by USAMA ARSHAD"
  dashboard_border '╰' '╯'
  echo
  dashboard_centered_text "$COLOR_WHITE$COLOR_BOLD" "Welcome to your all-in-one Odoo 19 deployment workspace."
  dashboard_centered_text "$COLOR_MUTED" "Install, inspect, maintain, or safely remove your stack from one place."
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_CYAN$COLOR_BOLD" "▣  SYSTEM SNAPSHOT  ─────────────────────────────────────────────────────────────────────────────────"
  dashboard_snapshot_row "⚙" "Ubuntu" "${PRETTY_NAME:-Unknown}" "$COLOR_WHITE"
  dashboard_snapshot_row "◫" "Hardware" "$SYSTEM_SPEC_SUMMARY" "$COLOR_WHITE"
  if [[ "$docker_status" == *Available ]]; then
    dashboard_snapshot_row "▦" "Docker CLI" "$docker_status" "$COLOR_GREEN"
  else
    dashboard_snapshot_row "▦" "Docker CLI" "$docker_status" "$COLOR_YELLOW"
  fi
  if [[ "$enterprise_status" == *Ready ]]; then
    dashboard_snapshot_row "◇" "Enterprise addons" "$enterprise_status" "$COLOR_GREEN"
  else
    dashboard_snapshot_row "◇" "Enterprise addons" "$enterprise_status" "$COLOR_YELLOW"
  fi
  dashboard_snapshot_row "▤" "Installer state" "$installation_status" "$COLOR_GREEN"
  dashboard_border '╰' '╯'
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_PURPLE$COLOR_BOLD" "☷  SELECT AN ACTION                         Use ↑/↓ to move  •  Enter to select  •  ★ Recommended"

  draw_interactive_menu_rows "$selected" "$recommended"
  dashboard_border '╰' '╯'
  echo
  dashboard_border '╭' '╮'
  dashboard_line "$COLOR_MUTED" "Enter  Select        ↑↓  Navigate        Esc  Exit        Ctrl+C  Exit"
  dashboard_border '╰' '╯'
}

draw_interactive_menu_rows() {
  local selected="$1" recommended="$2"
  local index label icon tag row_color selector line label_width

  label_width=$((DASHBOARD_CONTENT_WIDTH - 36))

  for index in 1 2 3 4 5 6 7; do
    case "$index" in
      1) icon="⇩"; label="Install Odoo Community only" ;;
      2) icon="⇩"; label="Install Odoo Enterprise only" ;;
      3) icon="⇩"; label="Install both Community and Enterprise" ;;
      4) icon="⚙"; label="Check Ubuntu updates and missing dependencies" ;;
      5) icon="⇧"; label="Back up databases across this system" ;;
      6) icon="♲"; label="Uninstall Odoo" ;;
      7) icon="↩"; label="Exit" ;;
    esac
    tag=""
    if (( index == recommended )); then tag="★ RECOMMENDED"; fi
    selector=" "
    row_color="$COLOR_WHITE"
    if (( index == selected )); then
      selector="›"
      row_color="$COLOR_MAGENTA_BG$COLOR_WHITE$COLOR_BOLD"
    fi
    printf -v line '%s  [%s]  %-3s %-*s %s' "$selector" "$index" "$icon" "$label_width" "$label" "$tag"
    dashboard_line "$row_color" "$line"
  done
}

interactive_terminal_supported() {
  [[ -t 0 && -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]] || return 1
  command -v tput >/dev/null 2>&1 || return 1
  tput clear >/dev/null 2>&1 || return 1
  tput cup 0 0 >/dev/null 2>&1 || return 1
  tput civis >/dev/null 2>&1 || return 1
  tput cnorm >/dev/null 2>&1 || return 1
  tput smcup >/dev/null 2>&1 || return 1
  tput rmcup >/dev/null 2>&1 || return 1
}

read_terminal_dimensions() {
  TERMINAL_COLUMNS="$(tput cols 2>/dev/null || printf '0')"
  TERMINAL_ROWS="$(tput lines 2>/dev/null || printf '0')"
  [[ "$TERMINAL_COLUMNS" =~ ^[0-9]+$ && "$TERMINAL_ROWS" =~ ^[0-9]+$ ]] || return 1
  (( TERMINAL_COLUMNS > 0 && TERMINAL_ROWS > 0 ))
}

configure_dashboard_geometry() {
  local viewport_height
  read_terminal_dimensions || return 1
  (( TERMINAL_COLUMNS >= DASHBOARD_MIN_WIDTH && TERMINAL_ROWS >= DASHBOARD_MIN_HEIGHT )) || return 1

  DASHBOARD_WIDTH="$TERMINAL_COLUMNS"
  (( DASHBOARD_WIDTH > DASHBOARD_MAX_WIDTH )) && DASHBOARD_WIDTH="$DASHBOARD_MAX_WIDTH"
  DASHBOARD_CONTENT_WIDTH=$((DASHBOARD_WIDTH - 6))
  DASHBOARD_LEFT=$(((TERMINAL_COLUMNS - DASHBOARD_WIDTH) / 2))

  viewport_height="$TERMINAL_ROWS"
  (( viewport_height > DASHBOARD_MAX_HEIGHT )) && viewport_height="$DASHBOARD_MAX_HEIGHT"
  DASHBOARD_TOP=$(((TERMINAL_ROWS - viewport_height) / 2 + (viewport_height - DASHBOARD_CONTENT_HEIGHT) / 2))
  DASHBOARD_MENU_ROW=$((DASHBOARD_TOP + 20))
}

resize_screen_center_text() {
  local row="$1" color="$2" content="$3" column
  column=$(((TERMINAL_COLUMNS - ${#content}) / 2))
  (( column < 0 )) && column=0
  tput cup "$row" "$column"
  printf '%b%s%b' "$color" "$content" "$COLOR_RESET"
}

draw_resize_window() {
  local box_left=1 box_top=1 box_width box_bottom row title fill_count center_row hint
  box_width=$((TERMINAL_COLUMNS - 2))
  box_bottom=$((TERMINAL_ROWS - 2))
  title='[ resize window ]'
  hint='Resize terminal  |  Q/Esc exit'

  tput clear
  if (( TERMINAL_COLUMNS < 20 || TERMINAL_ROWS < 6 )); then
    tput cup 0 0
    printf '%bNeed %sx%s%b' "$COLOR_RED$COLOR_BOLD" "$DASHBOARD_MIN_WIDTH" "$DASHBOARD_MIN_HEIGHT" "$COLOR_RESET"
    return
  fi
  if (( TERMINAL_COLUMNS < 40 || TERMINAL_ROWS < 12 )); then
    resize_screen_center_text 1 "$COLOR_RED$COLOR_BOLD" "TERMINAL TOO SMALL"
    resize_screen_center_text 3 "$COLOR_WHITE" "Current: ${TERMINAL_COLUMNS}x${TERMINAL_ROWS}"
    resize_screen_center_text 4 "$COLOR_GREEN" "Required: ${DASHBOARD_MIN_WIDTH}x${DASHBOARD_MIN_HEIGHT}"
    return
  fi

  tput cup "$box_top" "$box_left"
  printf '%b┌─%s' "$COLOR_RED" "$title"
  fill_count=$((box_width - ${#title} - 3))
  (( fill_count > 0 )) && repeat_character '─' "$fill_count"
  printf '┐%b' "$COLOR_RESET"

  for (( row = box_top + 1; row < box_bottom; row++ )); do
    tput cup "$row" "$box_left"
    printf '%b│%b' "$COLOR_RED" "$COLOR_RESET"
    tput cup "$row" "$((box_left + box_width - 1))"
    printf '%b│%b' "$COLOR_RED" "$COLOR_RESET"
  done

  tput cup "$box_bottom" "$box_left"
  printf '%b└' "$COLOR_RED"
  repeat_character '─' "$((box_width - 2))"
  printf '┘%b' "$COLOR_RESET"

  center_row=$((TERMINAL_ROWS / 2 - 2))
  resize_screen_center_text "$center_row" "$COLOR_WHITE$COLOR_BOLD" "Current size:"
  resize_screen_center_text "$((center_row + 1))" "$COLOR_RED$COLOR_BOLD" "${TERMINAL_COLUMNS}x${TERMINAL_ROWS}"
  resize_screen_center_text "$((center_row + 3))" "$COLOR_WHITE$COLOR_BOLD" "Need to be at least:"
  resize_screen_center_text "$((center_row + 4))" "$COLOR_GREEN$COLOR_BOLD" "${DASHBOARD_MIN_WIDTH}x${DASHBOARD_MIN_HEIGHT}"
  resize_screen_center_text "$((box_bottom - 1))" "$COLOR_MUTED" "$hint"
}

INTERACTIVE_ALT_SCREEN="false"
INTERACTIVE_STTY_STATE=""

enable_interactive_input_mode() {
  if [[ -t 0 && -z "$INTERACTIVE_STTY_STATE" ]]; then
    INTERACTIVE_STTY_STATE="$(stty -g 2>/dev/null || true)"
    if [[ -n "$INTERACTIVE_STTY_STATE" ]]; then
      # Keep echo disabled for the whole dashboard session. A touchpad can send
      # several arrow sequences between individual `read -s` calls otherwise.
      stty -echo -icanon min 1 time 0 2>/dev/null || true
    fi
  fi
}

read_dashboard_escape_sequence() {
  local target="$1" first="" character="" escape_data="" index

  IFS= read -rsn1 -t 0.08 first || true
  case "$first" in
    '[')
      escape_data='['
      while (( ${#escape_data} < 32 )); do
        character=""
        IFS= read -rsn1 -t 0.02 character || true
        [[ -n "$character" ]] || break
        escape_data+="$character"
        if [[ "$character" =~ [@-~] ]]; then
          break
        fi
      done
      # Legacy X10 mouse reports contain three coordinate bytes after CSI M.
      if [[ "$escape_data" == '[M' ]]; then
        for index in 1 2 3; do
          character=""
          IFS= read -rsn1 -t 0.02 character || true
          [[ -n "$character" ]] || break
          escape_data+="$character"
        done
      fi
      ;;
    'O')
      character=""
      IFS= read -rsn1 -t 0.02 character || true
      escape_data="O$character"
      ;;
    *) escape_data="$first" ;;
  esac

  printf -v "$target" '%s' "$escape_data"
}

close_interactive_dashboard() {
  printf '%b' "$COLOR_RESET"
  if [[ -n "$INTERACTIVE_STTY_STATE" ]]; then
    stty "$INTERACTIVE_STTY_STATE" 2>/dev/null || true
    INTERACTIVE_STTY_STATE=""
  fi
  tput cnorm 2>/dev/null || printf '\033[?25h'
  if [[ "$INTERACTIVE_ALT_SCREEN" == "true" ]]; then
    tput rmcup 2>/dev/null || true
    INTERACTIVE_ALT_SCREEN="false"
  fi
}

wait_for_dashboard_size() {
  local key sequence last_columns=-1 last_rows=-1

  tput smcup
  INTERACTIVE_ALT_SCREEN="true"
  tput civis
  enable_interactive_input_mode
  trap 'close_interactive_dashboard' EXIT
  trap 'exit 130' INT TERM HUP

  while true; do
    if configure_dashboard_geometry; then
      # Keep the input mode active while handing control to the main menu so a
      # still-running touchpad gesture cannot leak bytes during the transition.
      trap - EXIT INT TERM HUP
      return 0
    fi

    read_terminal_dimensions || {
      close_interactive_dashboard
      trap - EXIT INT TERM HUP
      return 1
    }
    if (( TERMINAL_COLUMNS != last_columns || TERMINAL_ROWS != last_rows )); then
      draw_resize_window
      last_columns="$TERMINAL_COLUMNS"
      last_rows="$TERMINAL_ROWS"
    fi

    key=""
    IFS= read -rsn1 -t 0.25 key || true
    case "$key" in
      q|Q)
        close_interactive_dashboard
        trap - EXIT INT TERM HUP
        return 1
        ;;
      $'\033')
        sequence=""
        read_dashboard_escape_sequence sequence
        if [[ -z "$sequence" ]]; then
          close_interactive_dashboard
          trap - EXIT INT TERM HUP
          return 1
        fi
        ;;
    esac
  done
}

read_interactive_main_choice() {
  local selected="$1" recommended="$1" previous_selected key sequence

  if [[ "$INTERACTIVE_ALT_SCREEN" != "true" ]]; then
    tput smcup
    INTERACTIVE_ALT_SCREEN="true"
  fi
  tput civis
  enable_interactive_input_mode
  trap 'close_interactive_dashboard' EXIT
  trap 'exit 130' INT TERM HUP

  tput clear
  tput cup "$DASHBOARD_TOP" 0
  draw_interactive_dashboard "$selected" "$recommended"

  while true; do
    previous_selected="$selected"
    IFS= read -rsn1 key || true
    case "$key" in
      '') MAIN_CHOICE="$selected"; break ;;
      [1-7]) MAIN_CHOICE="$key"; break ;;
      k|K) (( selected > 1 )) && selected=$((selected - 1)) ;;
      j|J) (( selected < 7 )) && selected=$((selected + 1)) ;;
      q|Q) MAIN_CHOICE="7"; break ;;
      $'\033')
        sequence=""
        read_dashboard_escape_sequence sequence
        case "$sequence" in
          '[A'|'OA') (( selected > 1 )) && selected=$((selected - 1)) ;;
          '[B'|'OB') (( selected < 7 )) && selected=$((selected + 1)) ;;
          '') MAIN_CHOICE="7"; break ;;
        esac
        ;;
    esac

    if (( selected != previous_selected )); then
      # Update only the option rows at their adaptive screen position.
      tput cup "$DASHBOARD_MENU_ROW" 0
      draw_interactive_menu_rows "$selected" "$recommended"
    fi
  done

  close_interactive_dashboard
  trap - EXIT INT TERM HUP
}

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
  local candidate_ids=() candidate_images=() candidate_names=() candidate_states=() candidate_engines=()

  echo "  • Docker PostgreSQL, MySQL and MariaDB containers"
  if ! command -v docker >/dev/null 2>&1; then
    echo "    Docker is not installed; continuing with native and file databases."
    return 0
  fi
  BACKUP_DOCKER_COMMAND=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
      BACKUP_DOCKER_COMMAND=(sudo docker)
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

uninstall_list_contains() {
  local wanted="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$wanted" ]] && return 0
  done
  return 1
}

discover_foreign_docker_resources() {
  local resource_name project_label network_name

  UNINSTALL_FOREIGN_DOCKER_RESOURCES=()
  while IFS='|' read -r resource_name project_label; do
    [[ -n "$resource_name" ]] || continue
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("container: $resource_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
      --format '{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )

  while IFS='|' read -r resource_name project_label; do
    [[ -n "$resource_name" ]] || continue
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("volume: $resource_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" volume ls \
      --format '{{.Name}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )

  while IFS='|' read -r network_name project_label; do
    [[ -n "$network_name" ]] || continue
    case "$network_name" in
      bridge|host|none) continue ;;
    esac
    if [[ "$project_label" != "odoo19-dual" ]]; then
      UNINSTALL_FOREIGN_DOCKER_RESOURCES+=("network: $network_name")
    fi
  done < <(
    "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
      --format '{{.Name}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null || true
  )
}

verify_installed_source_targets() {
  local source_path resolved_path

  UNINSTALL_VERIFIED_SOURCE_PATHS=()
  for source_path in "${UNINSTALL_SOURCE_TARGETS[@]}"; do
    [[ -e "$source_path" ]] || continue
    resolved_path="$(realpath -m -- "$source_path")"
    case "$resolved_path" in
      "$ODOO_HOST_ENTERPRISE_DIR"|"$ODOO_HOST_CUSTOM_ROOT")
        UNINSTALL_VERIFIED_SOURCE_PATHS+=("$resolved_path")
        ;;
      *)
        printf '  [SKIP]  %s (outside the installer-managed source boundary)\n' "$source_path"
        ;;
    esac
  done
}

audit_uninstall_targets() {
  local service container_details container_line volume volume_details project_label volume_label mountpoint
  local discovered_volume file_path package networks network_line project_containers source_path protected_path
  local foreign_resource found_protected="false"

  UNINSTALL_VERIFIED_VOLUMES=()
  section "UNINSTALL AUDIT" "Read-only discovery before removal"
  echo "Scope: $UNINSTALL_SCOPE_NAME"
  echo "Safety boundary: Compose project label 'odoo19-dual', installer state, and known generated paths."
  echo
  echo "Containers:"
  for service in "${UNINSTALL_TARGET_SERVICES[@]}"; do
    container_details="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --filter "label=com.docker.compose.service=$service" \
        --format '{{.Names}} | {{.Status}}' 2>/dev/null || true
    )"
    if [[ -n "$container_details" ]]; then
      while IFS= read -r container_line; do
        printf '  [FOUND] %-18s %s\n' "$service" "$container_line"
      done <<< "$container_details"
    else
      printf '  [NONE]  %s\n' "$service"
    fi
  done
  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    project_containers="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" ps -a \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Names}} | service={{.Label "com.docker.compose.service"}} | {{.Status}}' 2>/dev/null || true
    )"
    echo "  Complete project-label scan (includes possible orphan containers):"
    if [[ -n "$project_containers" ]]; then
      while IFS= read -r container_line; do printf '    [FOUND] %s\n' "$container_line"; done <<< "$project_containers"
    else
      echo "    [NONE]"
    fi
  fi

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    while IFS= read -r discovered_volume; do
      [[ -n "$discovered_volume" ]] || continue
      if ! uninstall_list_contains "$discovered_volume" "${UNINSTALL_TARGET_VOLUMES[@]}"; then
        UNINSTALL_TARGET_VOLUMES+=("$discovered_volume")
      fi
    done < <(
      "${UNINSTALL_DOCKER_COMMAND[@]}" volume ls \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Name}}' 2>/dev/null || true
    )
  fi

  echo
  echo "Persistent Docker volumes:"
  for volume in "${UNINSTALL_TARGET_VOLUMES[@]}"; do
    volume_details="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" volume inspect \
        --format '{{ index .Labels "com.docker.compose.project" }}|{{ index .Labels "com.docker.compose.volume" }}|{{ .Mountpoint }}' \
        "$volume" 2>/dev/null || true
    )"
    if [[ -z "$volume_details" ]]; then
      printf '  [NONE]  %s\n' "$volume"
      continue
    fi
    IFS='|' read -r project_label volume_label mountpoint <<< "$volume_details"
    if [[ "$project_label" != "odoo19-dual" ]]; then
      printf '  [SKIP]  %s (project ownership label does not match)\n' "$volume"
      continue
    fi
    if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" &&
          "$volume_label" != "${volume#odoo19-dual_}" ]]; then
      printf '  [SKIP]  %s (volume ownership label does not match)\n' "$volume"
      continue
    fi
    UNINSTALL_VERIFIED_VOLUMES+=("$volume")
    printf '  [FOUND] %s\n' "$volume"
    printf '          mount: %s\n' "${mountpoint:-managed by Docker}"
  done

  echo
  echo "Generated host files:"
  for file_path in "${UNINSTALL_GENERATED_FILES[@]}"; do
    if [[ -e "$file_path" ]]; then
      printf '  [FOUND] %s\n' "$file_path"
    else
      printf '  [NONE]  %s\n' "$file_path"
    fi
  done
  if [[ "$UNINSTALL_SCOPE_NAME" != "complete installer stack" ]]; then
    printf '  [KEEP]  %s and %s (shared by remaining services)\n' \
      "$SCRIPT_DIR/.env" "$SCRIPT_DIR/installation-info.txt"
  fi

  if [[ "$UNINSTALL_SCOPE_NAME" == "complete installer stack" ]]; then
    networks="$(
      "${UNINSTALL_DOCKER_COMMAND[@]}" network ls \
        --filter "label=com.docker.compose.project=odoo19-dual" \
        --format '{{.Name}}' 2>/dev/null || true
    )"
    echo
    echo "Project networks:"
    if [[ -n "$networks" ]]; then
      while IFS= read -r network_line; do printf '  [FOUND] %s\n' "$network_line"; done <<< "$networks"
    else
      echo "  [NONE]"
    fi

    echo
    echo "Installer-tracked system setup:"
    if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )); then
      for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
        if package_installed "$package"; then
          printf '  [FOUND] package %s\n' "$package"
        else
          printf '  [NONE]  package %s\n' "$package"
        fi
      done
    else
      echo "  [REVIEW] no installer-owned package record; older Docker installs need separate confirmation"
    fi
    if [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]]; then
      if [[ -e /etc/apt/sources.list.d/docker.list ]]; then
        echo "  [FOUND] /etc/apt/sources.list.d/docker.list (installer-created)"
      else
        echo "  [NONE]  tracked Docker APT source is already absent"
      fi
    fi
    if [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ]]; then
      if [[ -e /etc/apt/keyrings/docker.asc ]]; then
        echo "  [FOUND] /etc/apt/keyrings/docker.asc (installer-created)"
      else
        echo "  [NONE]  tracked Docker APT signing key is already absent"
      fi
    fi
    if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
      printf '  [FOUND] tracked Docker group access for %s\n' "$INSTALLER_DOCKER_GROUP_USER"
    fi

    discover_foreign_docker_resources
    echo
    echo "Docker resources outside this Odoo installer:"
    if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} > 0 )); then
      for foreign_resource in "${UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]}"; do
        printf '  [KEEP]  %s\n' "$foreign_resource"
      done
      echo "  Docker Engine removal will be blocked to protect these resources."
    else
      echo "  [NONE]  no non-Odoo containers, volumes, or custom networks were found"
    fi
  fi

  echo
  echo "Installed source/addon copies eligible for optional cleanup:"
  verify_installed_source_targets
  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    for source_path in "${UNINSTALL_VERIFIED_SOURCE_PATHS[@]}"; do
      printf '  [FOUND] %s\n' "$source_path"
    done
  else
    echo "  [NONE]"
  fi

  echo
  echo "Original checkout source paths (always preserved):"
  for protected_path in \
    "$SCRIPT_DIR/enterprise-19.0" \
    "$SCRIPT_DIR/addons/enterprise" \
    "$SCRIPT_DIR/addons/community" \
    "$SCRIPT_DIR/addons/enterprise-custom"; do
    if [[ -e "$protected_path" ]]; then
      printf '  [KEEP]  %s\n' "$protected_path"
      found_protected="true"
    fi
  done
  [[ "$found_protected" == "true" ]] || echo "  [NONE]"
  echo
  echo "Anything outside this verified inventory is not a deletion target."
}

remove_installer_managed_dependencies() {
  local package confirmation docker_source_path has_tracked_state="false" remove_detected_docker="false"
  local docker_package_was_tracked="false"
  local detected_docker_key="false"
  local installed_packages=() detected_docker_packages=() detected_docker_source_paths=()

  for package in \
    docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io \
    docker-buildx-plugin docker-compose-plugin; do
    if package_installed "$package"; then
      detected_docker_packages+=("$package")
    fi
  done
  for docker_source_path in \
    /etc/apt/sources.list.d/docker.list \
    /etc/apt/sources.list.d/docker.sources; do
    if [[ -f "$docker_source_path" ]] &&
       grep -Fqs 'download.docker.com/linux/ubuntu' "$docker_source_path"; then
      detected_docker_source_paths+=("$docker_source_path")
    fi
  done
  if (( ${#detected_docker_source_paths[@]} > 0 )) &&
     [[ -e /etc/apt/keyrings/docker.asc ]]; then
    detected_docker_key="true"
  fi

  if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )) ||
     [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ||
        "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
        -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
    has_tracked_state="true"
  fi

  echo
  printf '%b\n' "${COLOR_YELLOW}Dependency cleanup can affect other Docker-based applications.${COLOR_RESET}"
  if [[ "$has_tracked_state" == "true" ]]; then
    echo "Packages recorded as installed by this installer:"
    if (( ${#INSTALLER_MANAGED_PACKAGES[@]} > 0 )); then
      for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
        printf '  - %s\n' "$package"
        case "$package" in
          docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|docker-buildx-plugin|docker-compose-plugin)
            docker_package_was_tracked="true"
            ;;
        esac
      done
    else
      echo "  - no packages"
    fi
  else
    echo "No installer ownership record was found (for example, this may be an older installation)."
    if (( ${#detected_docker_packages[@]} == 0 )) &&
       (( ${#detected_docker_source_paths[@]} == 0 )) &&
       [[ "$detected_docker_key" != "true" ]]; then
      echo "No removable Docker Engine packages or official repository files were detected."
      return 0
    fi
    if (( ${#detected_docker_packages[@]} > 0 )); then
      echo "Detected Docker Engine packages:"
      for package in "${detected_docker_packages[@]}"; do
        printf '  - %s\n' "$package"
      done
    fi
    for docker_source_path in "${detected_docker_source_paths[@]}"; do
      printf '  - detected official Docker APT source: %s\n' "$docker_source_path"
    done
    [[ "$detected_docker_key" == "true" ]] && echo "  - detected official Docker APT signing key"
  fi
  [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]] && echo "  - Docker APT source created by this installer"
  [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ]] && echo "  - Docker APT signing key created by this installer"
  if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]]; then
    printf '  - Docker group access added for %s\n' "$INSTALLER_DOCKER_GROUP_USER"
  fi
  if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} > 0 )) &&
     { (( ${#detected_docker_packages[@]} > 0 )) ||
       [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ||
          "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
          -n "$INSTALLER_DOCKER_GROUP_USER" ]]; }; then
    echo
    echo "Docker Engine will NOT be removed because non-Odoo Docker resources were found:"
    for package in "${UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]}"; do
      printf '  - %s\n' "$package"
    done
    echo "Remove or migrate those workloads first, then rerun complete uninstall."
    echo "No Docker packages, repository files, or group access were changed."
    return 0
  elif [[ "$has_tracked_state" == "false" ]]; then
    echo "Ownership cannot be proven, but no non-Odoo Docker resources were detected."
    read -r -p "Type REMOVE DETECTED DOCKER to remove the listed Docker components: " confirmation
    if [[ "$confirmation" == "REMOVE DETECTED DOCKER" ]]; then
      remove_detected_docker="true"
    else
      echo "Detected Docker components were preserved."
      return 0
    fi
  else
    echo "Only installer-recorded items will be removed; untracked software is preserved."
    read -r -p "Type REMOVE DEPENDENCIES to continue: " confirmation
    if [[ "$confirmation" != "REMOVE DEPENDENCIES" ]]; then
      echo "Docker and dependency cleanup skipped."
      return 0
    fi
    if [[ "$docker_package_was_tracked" != "true" ]] &&
       (( ${#detected_docker_packages[@]} > 0 )); then
      echo
      echo "The Docker Engine packages were detected but are not present in the ownership record."
      echo "This can happen when an older installer created Docker before package tracking was added."
      read -r -p "Type REMOVE DETECTED DOCKER to remove those Docker packages too: " confirmation
      if [[ "$confirmation" == "REMOVE DETECTED DOCKER" ]]; then
        remove_detected_docker="true"
      else
        echo "Untracked Docker Engine packages will be preserved."
      fi
    fi
  fi

  if [[ -n "$INSTALLER_DOCKER_GROUP_USER" ]] && getent group docker >/dev/null 2>&1; then
    sudo gpasswd -d "$INSTALLER_DOCKER_GROUP_USER" docker >/dev/null 2>&1 || true
  fi

  for package in "${INSTALLER_MANAGED_PACKAGES[@]}"; do
    if package_installed "$package"; then
      case "$package" in
        docker-ce|docker-ce-cli|docker-ce-rootless-extras|containerd.io|docker-buildx-plugin|docker-compose-plugin)
          if (( ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} == 0 )); then
            installed_packages+=("$package")
          fi
          ;;
        *) installed_packages+=("$package") ;;
      esac
    fi
  done
  if [[ "$remove_detected_docker" == "true" ||
        ( "$docker_package_was_tracked" == "true" && ${#UNINSTALL_FOREIGN_DOCKER_RESOURCES[@]} -eq 0 ) ]]; then
    for package in "${detected_docker_packages[@]}"; do
      if ! uninstall_list_contains "$package" "${installed_packages[@]}"; then
        installed_packages+=("$package")
      fi
    done
  fi
  if (( ${#installed_packages[@]} > 0 )); then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed_packages[@]}"
  fi
  if [[ "$INSTALLER_CREATED_DOCKER_SOURCE" == "true" ]]; then
    sudo rm -f /etc/apt/sources.list.d/docker.list
  fi
  if [[ "$remove_detected_docker" == "true" ]]; then
    for docker_source_path in "${detected_docker_source_paths[@]}"; do
      sudo rm -f -- "$docker_source_path"
    done
  fi
  if [[ "$INSTALLER_CREATED_DOCKER_KEY" == "true" ||
        ( "$remove_detected_docker" == "true" && "$detected_docker_key" == "true" ) ]]; then
    sudo rm -f /etc/apt/keyrings/docker.asc
  fi

  INSTALLER_MANAGED_PACKAGES=()
  INSTALLER_CREATED_DOCKER_SOURCE="false"
  INSTALLER_CREATED_DOCKER_KEY="false"
  INSTALLER_DOCKER_GROUP_USER=""
  rm -f "$INSTALLER_STATE_FILE"
  printf '%b\n' "${COLOR_GREEN}Approved Docker components and installer-tracked dependencies were removed.${COLOR_RESET}"
}

remove_verified_installed_sources() {
  local source_path

  for source_path in "${UNINSTALL_VERIFIED_SOURCE_PATHS[@]}"; do
    case "$source_path" in
      "$ODOO_HOST_ENTERPRISE_DIR"|"$ODOO_HOST_CUSTOM_ROOT")
        sudo rm -rf -- "$source_path"
        ;;
      *)
        printf 'Skipping unverified source path: %s\n' "$source_path"
        ;;
    esac
  done
  sudo rmdir "$ODOO_HOST_ROOT" 2>/dev/null || true
  sudo rmdir "$(dirname -- "$ODOO_HOST_ROOT")" 2>/dev/null || true
}

offer_backup_before_database_deletion() {
  local backup_choice backup_result_file completed_backup_path

  UNINSTALL_DATABASE_DELETE_APPROVED="false"
  while true; do
    echo
    echo "Before deleting databases and filestores:"
    echo "  1) Scan databases, select one or more, and create a RAR backup (recommended)"
    echo "  2) Continue without a backup"
    echo "  3) Cancel database deletion"
    read_choice backup_choice "Choose a backup option [1]: " "1" "1 2 3 backup skip cancel"
    case "${backup_choice,,}" in
      1|backup)
        backup_result_file="$(mktemp /tmp/odoo19-uninstall-backup.XXXXXX)"
        run_backup_manager "$backup_result_file"
        load_installer_state
        if [[ -s "$backup_result_file" ]]; then
          IFS= read -r completed_backup_path < "$backup_result_file"
          if [[ "$completed_backup_path" == "$SCRIPT_DIR/backups/system-databases-"*.rar &&
                -s "$completed_backup_path" ]]; then
            rm -f -- "$backup_result_file"
            echo
            printf '%b\n' "${COLOR_GREEN}Pre-uninstall database backup completed.${COLOR_RESET}"
            printf 'Verified archive: %s\n' "$completed_backup_path"
            UNINSTALL_DATABASE_DELETE_APPROVED="true"
            return 0
          fi
        fi
        rm -f -- "$backup_result_file"
        echo "No backup archive was created. Database deletion has not been approved."
        ;;
      2|skip)
        printf '%b\n' "${COLOR_YELLOW}WARNING: Continuing without a backup can cause permanent data loss.${COLOR_RESET}"
        if ask_yes_no "Continue to the permanent-delete confirmation without a backup? [y/N]: " "n"; then
          UNINSTALL_DATABASE_DELETE_APPROVED="true"
          return 0
        fi
        ;;
      3|cancel)
        echo "Database deletion cancelled. Nothing has been removed."
        return 0
        ;;
    esac
  done
}

cleanup_local_artifacts_without_docker() {
  local confirmation file_path found_local_artifact="false"
  local remaining_files=(
    "$SCRIPT_DIR/.env"
    "$SCRIPT_DIR/installation-info.txt"
    "$SCRIPT_DIR/config/community/odoo.conf"
    "$SCRIPT_DIR/config/enterprise/odoo.conf"
    "$SCRIPT_DIR/config/pgadmin/servers.json"
    "$SCRIPT_DIR/config/pgadmin/pgpass"
  )

  UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ROOT")
  verify_installed_source_targets
  echo
  echo "Remaining generated files:"
  for file_path in "${remaining_files[@]}"; do
    if [[ -e "$file_path" ]]; then
      printf '  [FOUND] %s\n' "$file_path"
      found_local_artifact="true"
    fi
  done
  [[ "$found_local_artifact" == "true" ]] || echo "  [NONE]"
  echo "Remaining installed source/addon copies:"
  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    found_local_artifact="true"
    for file_path in "${UNINSTALL_VERIFIED_SOURCE_PATHS[@]}"; do
      printf '  [FOUND] %s\n' "$file_path"
    done
  else
    echo "  [NONE]"
  fi
  echo "Original folders inside this Git checkout will be preserved."

  if [[ "$found_local_artifact" != "true" ]]; then
    echo "No remaining installer-generated local Odoo files were found."
    return 0
  fi

  if ! ask_yes_no "Permanently remove these remaining local Odoo files? [y/N]: " "n"; then
    echo "Remaining local Odoo files were preserved."
    return 0
  fi
  read -r -p "Type DELETE LOCAL ODOO FILES to confirm: " confirmation
  if [[ "$confirmation" != "DELETE LOCAL ODOO FILES" ]]; then
    echo "Local file cleanup cancelled; nothing was removed."
    return 0
  fi
  rm -f "${remaining_files[@]}"
  remove_verified_installed_sources
  printf '%b\n' "${COLOR_GREEN}Verified generated files and installed /opt addon copies were removed.${COLOR_RESET}"
}

run_uninstaller() {
  section "UNINSTALL" "Choose exactly what should be removed"
  echo "The audit runs first. Data, installed addon copies, and Docker require separate confirmations."

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed, so there are no Docker-based Odoo containers to remove."
    cleanup_local_artifacts_without_docker
    if ask_yes_no "Remove any remaining installer-tracked dependencies? [y/N]: " "n"; then
      remove_installer_managed_dependencies
    fi
    return
  fi

  local docker_command=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
      docker_command=(sudo docker)
    else
      echo "Docker is installed, but its engine is not currently available."
      if systemctl cat docker.service >/dev/null 2>&1 &&
         ask_yes_no "Start Docker temporarily so its resources can be audited and removed? [Y/n]: " "y"; then
        sudo systemctl start docker.service
      fi
      if docker info >/dev/null 2>&1; then
        docker_command=(docker)
      elif sudo docker info >/dev/null 2>&1; then
        docker_command=(sudo docker)
      else
        echo "Docker could not be started. Nothing was removed because its containers and volumes could not be audited safely."
        return
      fi
    fi
  fi
  if ! "${docker_command[@]}" compose version >/dev/null 2>&1; then
    echo "Docker Compose is unavailable, so the installer services cannot be removed safely."
    return
  fi

  export COMMUNITY_DB_PASSWORD="${COMMUNITY_DB_PASSWORD:-unused}"
  export ENTERPRISE_DB_PASSWORD="${ENTERPRISE_DB_PASSWORD:-unused}"
  export COMMUNITY_PORT="${COMMUNITY_PORT:-8069}"
  export ENTERPRISE_PORT="${ENTERPRISE_PORT:-8070}"
  export PGADMIN_PORT="${PGADMIN_PORT:-5050}"
  export PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@example.com}"
  export PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-unused}"

  echo
  echo "Current installer-managed containers:"
  "${docker_command[@]}" compose --profile pgadmin ps -a || true
  echo
  echo "What do you want to uninstall?"
  echo "  1) Community only"
  echo "  2) Enterprise only"
  echo "  3) Both Odoo editions (keep pgAdmin)"
  echo "  4) Complete stack + optional installed files and Docker cleanup"
  echo "  5) Cancel"

  local uninstall_scope data_choice source_choice confirmation confirmation_text
  local remove_dependencies="false" remove_installed_sources="false"
  local services=() volumes=() generated_files=()
  read_choice uninstall_scope "Choose an uninstall scope [5]: " "5" "1 2 3 4 5 community enterprise both all cancel"
  case "${uninstall_scope,,}" in
    1|community)
      services=(community db-community)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data)
      generated_files=("$SCRIPT_DIR/config/community/odoo.conf")
      UNINSTALL_SCOPE_NAME="Community only"
      confirmation_text="DELETE COMMUNITY"
      UNINSTALL_SOURCE_TARGETS=()
      ;;
    2|enterprise)
      services=(enterprise db-enterprise)
      volumes=(odoo19-dual_enterprise-db odoo19-dual_enterprise-data)
      generated_files=("$SCRIPT_DIR/config/enterprise/odoo.conf")
      UNINSTALL_SCOPE_NAME="Enterprise only"
      confirmation_text="DELETE ENTERPRISE"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR")
      ;;
    3|both)
      services=(community db-community enterprise db-enterprise)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data odoo19-dual_enterprise-db odoo19-dual_enterprise-data)
      generated_files=("$SCRIPT_DIR/config/community/odoo.conf" "$SCRIPT_DIR/config/enterprise/odoo.conf")
      UNINSTALL_SCOPE_NAME="both Odoo editions; pgAdmin preserved"
      confirmation_text="DELETE BOTH"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ROOT")
      ;;
    4|all)
      services=(community db-community enterprise db-enterprise pgadmin)
      volumes=(odoo19-dual_community-db odoo19-dual_community-data odoo19-dual_enterprise-db odoo19-dual_enterprise-data odoo19-dual_pgadmin-data)
      generated_files=(
        "$SCRIPT_DIR/.env"
        "$SCRIPT_DIR/installation-info.txt"
        "$SCRIPT_DIR/config/community/odoo.conf"
        "$SCRIPT_DIR/config/enterprise/odoo.conf"
        "$SCRIPT_DIR/config/pgadmin/servers.json"
        "$SCRIPT_DIR/config/pgadmin/pgpass"
      )
      UNINSTALL_SCOPE_NAME="complete installer stack"
      confirmation_text="DELETE ALL"
      remove_dependencies="true"
      UNINSTALL_SOURCE_TARGETS=("$ODOO_HOST_ENTERPRISE_DIR" "$ODOO_HOST_CUSTOM_ROOT")
      ;;
    5|cancel)
      echo "Uninstall cancelled; nothing was removed."
      return
      ;;
  esac

  UNINSTALL_DOCKER_COMMAND=("${docker_command[@]}")
  UNINSTALL_TARGET_SERVICES=("${services[@]}")
  UNINSTALL_TARGET_VOLUMES=("${volumes[@]}")
  UNINSTALL_GENERATED_FILES=("${generated_files[@]}")
  audit_uninstall_targets

  echo
  echo "What should happen to the selected databases and filestores?"
  echo "  1) Keep databases and filestores; remove only selected containers (recommended)"
  echo "  2) Back up optionally, then permanently delete selected databases and filestores"
  echo "  3) Cancel"
  read_choice data_choice "Choose a data option [1]: " "1" "1 2 3 keep delete cancel"
  case "${data_choice,,}" in
    1|keep) data_choice="keep" ;;
    2|delete)
      printf '%b\n' "${COLOR_YELLOW}WARNING: Selected database and filestore volumes will be permanently deleted.${COLOR_RESET}"
      offer_backup_before_database_deletion
      if [[ "$UNINSTALL_DATABASE_DELETE_APPROVED" != "true" ]]; then
        echo "Uninstall cancelled; nothing was removed."
        return
      fi
      read -r -p "Type $confirmation_text to confirm: " confirmation
      if [[ "$confirmation" != "$confirmation_text" ]]; then
        echo "Permanent uninstall cancelled; nothing was removed."
        return
      fi
      data_choice="delete"
      ;;
    3|cancel)
      echo "Uninstall cancelled; nothing was removed."
      return
      ;;
  esac

  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    echo
    echo "What should happen to the installed source/addon copies listed in the audit?"
    echo "  1) Keep installed copies under $ODOO_HOST_ROOT (recommended)"
    echo "  2) Permanently delete the listed installed copies"
    echo "  3) Cancel"
    echo "Your original licensed source inside this Git checkout will not be deleted."
    read_choice source_choice "Choose a source option [1]: " "1" "1 2 3 keep delete cancel"
    case "${source_choice,,}" in
      1|keep) ;;
      2|delete)
        printf '%b\n' "${COLOR_YELLOW}WARNING: Every file in the listed /opt folders will be permanently deleted.${COLOR_RESET}"
        read -r -p "Type DELETE INSTALLED SOURCE to confirm: " confirmation
        if [[ "$confirmation" != "DELETE INSTALLED SOURCE" ]]; then
          echo "Permanent source cleanup cancelled; nothing was removed."
          return
        fi
        remove_installed_sources="true"
        ;;
      3|cancel)
        echo "Uninstall cancelled; nothing was removed."
        return
        ;;
    esac
  fi

  if ! ask_yes_no "Proceed with this verified uninstall plan? [y/N]: " "n"; then
    echo "Uninstall cancelled; nothing was removed."
    return
  fi

  if [[ "${uninstall_scope,,}" == "4" || "${uninstall_scope,,}" == "all" ]]; then
    "${docker_command[@]}" compose --profile pgadmin down --remove-orphans
  else
    "${docker_command[@]}" compose --profile pgadmin stop "${services[@]}" || true
    "${docker_command[@]}" compose --profile pgadmin rm -f "${services[@]}" || true
  fi
  if [[ "$data_choice" == "delete" ]]; then
    local volume
    for volume in "${UNINSTALL_VERIFIED_VOLUMES[@]}"; do
      "${docker_command[@]}" volume rm "$volume"
    done
    rm -f "${UNINSTALL_GENERATED_FILES[@]}"
  fi
  if [[ "$remove_installed_sources" == "true" ]]; then
    remove_verified_installed_sources
  fi

  echo
  if [[ "$data_choice" == "delete" ]]; then
    printf '%b\n' "${COLOR_GREEN}Verified selected containers, volumes, and generated files were removed.${COLOR_RESET}"
  else
    printf '%b\n' "${COLOR_GREEN}Selected containers were removed; databases, filestores, and generated files were preserved.${COLOR_RESET}"
  fi
  if (( ${#UNINSTALL_VERIFIED_SOURCE_PATHS[@]} > 0 )); then
    if [[ "$remove_installed_sources" == "true" ]]; then
      printf '%b\n' "${COLOR_GREEN}Verified installed source/addon copies under /opt were removed.${COLOR_RESET}"
    else
      echo "Installed Enterprise/custom-addon copies under /opt were preserved."
    fi
  fi

  if [[ "$remove_dependencies" == "true" ]]; then
    echo
    if ask_yes_no "Also remove Docker and dependencies installed by this installer? [y/N]: " "n"; then
      remove_installer_managed_dependencies
    else
      echo "Docker and Ubuntu dependencies were preserved."
    fi
  fi
  echo "Original source folders in this Git checkout were preserved."
}

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

section "1/6" "Prepare Ubuntu and check requirements"
echo "Ubuntu package maintenance"
echo "This updates installed packages only; it does not change the Ubuntu release."
if ask_yes_no "Refresh package lists and upgrade installed Ubuntu packages now? [y/N]: " "n"; then
  sudo apt-get update
  APT_INDEX_READY="true"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  if [[ -f /var/run/reboot-required ]]; then
    echo
    echo "Ubuntu reports that a reboot is required after the package upgrade."
    if ! ask_yes_no "Continue this installation before rebooting? [y/N]: " "n"; then
      echo "Restart Ubuntu, then run this installer again."
      exit 0
    fi
  fi
else
  echo "Skipping the optional Ubuntu package upgrade."
fi

refresh_prerequisite_status
show_prerequisite_status

MISSING_COUNT=0
for installed in "$HAS_CA_CERTIFICATES" "$HAS_CURL" "$HAS_OPENSSL" "$HAS_DOCKER" "$HAS_COMPOSE"; do
  if [[ "$installed" != "true" ]]; then MISSING_COUNT=$((MISSING_COUNT + 1)); fi
done

if (( MISSING_COUNT > 0 )); then
  echo
  echo "Missing prerequisites were found."
  echo "  1) Install all missing requirements (recommended)"
  echo "  2) Review and approve each requirement"
  echo "  3) Cancel"
  read_choice PREREQUISITE_MODE "Choose an option [1]: " "1" "1 2 3 a all o one one-by-one q quit cancel"

  INSTALL_CA_CERTIFICATES="false"
  INSTALL_CURL="false"
  INSTALL_OPENSSL="false"
  INSTALL_DOCKER="false"
  INSTALL_COMPOSE="false"

  case "${PREREQUISITE_MODE,,}" in
    1|a|all)
      [[ "$HAS_CA_CERTIFICATES" != "true" ]] && INSTALL_CA_CERTIFICATES="true"
      [[ "$HAS_CURL" != "true" ]] && INSTALL_CURL="true"
      [[ "$HAS_OPENSSL" != "true" ]] && INSTALL_OPENSSL="true"
      [[ "$HAS_DOCKER" != "true" ]] && INSTALL_DOCKER="true"
      [[ "$HAS_COMPOSE" != "true" ]] && INSTALL_COMPOSE="true"
      ;;
    2|o|one|one-by-one)
      if [[ "$HAS_CA_CERTIFICATES" != "true" ]] &&
         ask_yes_no "Install CA certificates? [y/N]: " "n"; then INSTALL_CA_CERTIFICATES="true"; fi
      if [[ "$HAS_CURL" != "true" ]] &&
         ask_yes_no "Install curl? [y/N]: " "n"; then INSTALL_CURL="true"; fi
      if [[ "$HAS_OPENSSL" != "true" ]] &&
         ask_yes_no "Install OpenSSL? [y/N]: " "n"; then INSTALL_OPENSSL="true"; fi
      if [[ "$HAS_DOCKER" != "true" ]] &&
         ask_yes_no "Install Docker Engine (includes required repository packages)? [y/N]: " "n"; then INSTALL_DOCKER="true"; fi
      if [[ "$HAS_COMPOSE" != "true" ]] &&
         ask_yes_no "Install the Docker Compose plugin (includes required repository packages)? [y/N]: " "n"; then INSTALL_COMPOSE="true"; fi
      ;;
    3|q|quit|cancel)
      echo "Installation cancelled; no missing prerequisites were installed."
      exit 0
      ;;
    *)
      echo "Choose 1, 2, or 3."
      exit 1
      ;;
  esac

  if [[ "$INSTALL_DOCKER" == "true" || "$INSTALL_COMPOSE" == "true" ]]; then
    INSTALL_CA_CERTIFICATES="true"
    INSTALL_CURL="true"
  fi

  if [[ "${PREREQUISITE_MODE,,}" == "1" || "${PREREQUISITE_MODE,,}" == "a" || "${PREREQUISITE_MODE,,}" == "all" ]]; then
    SUPPORT_PACKAGES=()
    TRACK_SUPPORT_PACKAGES=()
    [[ "$INSTALL_CA_CERTIFICATES" == "true" ]] && SUPPORT_PACKAGES+=(ca-certificates)
    [[ "$INSTALL_CURL" == "true" ]] && SUPPORT_PACKAGES+=(curl)
    [[ "$INSTALL_OPENSSL" == "true" ]] && SUPPORT_PACKAGES+=(openssl)
    [[ "$INSTALL_CA_CERTIFICATES" == "true" && "$HAS_CA_CERTIFICATES" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(ca-certificates)
    [[ "$INSTALL_CURL" == "true" && "$HAS_CURL" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(curl)
    [[ "$INSTALL_OPENSSL" == "true" && "$HAS_OPENSSL" != "true" ]] && TRACK_SUPPORT_PACKAGES+=(openssl)
    if (( ${#SUPPORT_PACKAGES[@]} > 0 )); then
      install_apt_packages "${SUPPORT_PACKAGES[@]}"
      if (( ${#TRACK_SUPPORT_PACKAGES[@]} > 0 )); then
        track_installer_packages "${TRACK_SUPPORT_PACKAGES[@]}"
      fi
    fi
  else
    if [[ "$INSTALL_CA_CERTIFICATES" == "true" ]]; then
      install_apt_packages ca-certificates
      if [[ "$HAS_CA_CERTIFICATES" != "true" ]]; then
        track_installer_packages ca-certificates
      fi
    fi
    if [[ "$INSTALL_CURL" == "true" ]]; then
      install_apt_packages curl
      if [[ "$HAS_CURL" != "true" ]]; then
        track_installer_packages curl
      fi
    fi
    if [[ "$INSTALL_OPENSSL" == "true" ]]; then
      install_apt_packages openssl
      if [[ "$HAS_OPENSSL" != "true" ]]; then
        track_installer_packages openssl
      fi
    fi
  fi

  if [[ "$INSTALL_DOCKER" == "true" || "$INSTALL_COMPOSE" == "true" ]]; then
    setup_docker_repository
  fi
  if [[ "$INSTALL_DOCKER" == "true" ]]; then
    echo "Installing Docker Engine..."
    install_apt_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    track_installer_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    if package_installed docker-ce-rootless-extras; then
      track_installer_packages docker-ce-rootless-extras
    fi
    if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq docker; then
      sudo usermod -aG docker "$USER"
      INSTALLER_DOCKER_GROUP_USER="$USER"
      save_installer_state
    fi
  fi
  if [[ "$INSTALL_COMPOSE" == "true" ]]; then
    echo "Installing the Docker Compose plugin..."
    if ! install_apt_packages docker-compose-plugin; then
      echo "Docker Compose could not be installed. Check the Docker repository configuration, then rerun this installer."
      exit 1
    fi
    track_installer_packages docker-compose-plugin
  fi
fi

refresh_prerequisite_status
show_prerequisite_status
if [[ "$HAS_OPENSSL" != "true" || "$HAS_DOCKER" != "true" || "$HAS_COMPOSE" != "true" ]]; then
  echo "OpenSSL, Docker Engine, and Docker Compose are required. Rerun the installer and approve the missing items."
  exit 1
fi

if systemctl cat docker.service >/dev/null 2>&1; then
  echo "Enabling Docker to start automatically at boot..."
  if ! sudo systemctl enable --now docker.service; then
    echo "Docker could not be enabled and started. Fix the Docker system service, then rerun this installer."
    exit 1
  fi
else
  echo "Warning: docker.service was not found, so automatic Docker startup could not be configured."
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "Docker is installed, but its engine is not running. Start Docker and rerun this installer."
    exit 1
  fi
fi

if ! "${DOCKER[@]}" compose version >/dev/null 2>&1; then
  echo "Docker Compose is unavailable. Rerun the installer and approve the Compose plugin installation."
  exit 1
fi
COMPOSE_UP_HELP="$("${DOCKER[@]}" compose up --help 2>&1)"
if [[ "$COMPOSE_UP_HELP" != *"--wait-timeout"* ]]; then
  echo "This installer requires a newer Docker Compose plugin with --wait support. Update Docker Engine/Compose, then rerun it."
  exit 1
fi

if [[ "$INSTALL_ACTION" == "dependencies" ]]; then
  echo
  printf '%b\n' "${COLOR_GREEN}Dependency check complete. Ubuntu is ready for the Odoo installer.${COLOR_RESET}"
  exit 0
fi

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
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

section "2/6" "Choose how Odoo should run"
echo "Select a setup profile:"
echo "  1) Testing (recommended for evaluation and development)"
echo "  2) Production (opens the hardware-aware performance advisor)"
read_choice DEPLOYMENT_CHOICE "Choose a profile [1]: " "1" "1 2 testing production"
case "${DEPLOYMENT_CHOICE,,}" in
  1|testing) DEPLOYMENT_MODE="testing" ;;
  2|production) DEPLOYMENT_MODE="production" ;;
  *) echo "Choose 1 for testing or 2 for production."; exit 1 ;;
esac

echo
COMMUNITY_PORT="8069"
ENTERPRISE_PORT="8070"
if [[ "$START_COMMUNITY" == "true" ]]; then
  echo "The Community web port is used in the browser URL."
  while true; do
    read -r -p "Community web port [8069]: " COMMUNITY_PORT
    COMMUNITY_PORT="${COMMUNITY_PORT:-8069}"
    if valid_port "$COMMUNITY_PORT"; then break; fi
    echo "Please enter a port number from 1 to 65535."
  done
  COMMUNITY_PORT="$((10#$COMMUNITY_PORT))"
else
  echo "Community was not selected, so its port question is skipped."
fi

COMMUNITY_DB_VOLUME_EXISTS="false"
ENTERPRISE_DB_VOLUME_EXISTS="false"
PGADMIN_VOLUME_EXISTS="false"
if "${DOCKER[@]}" volume inspect odoo19-dual_community-db >/dev/null 2>&1; then COMMUNITY_DB_VOLUME_EXISTS="true"; fi
if "${DOCKER[@]}" volume inspect odoo19-dual_enterprise-db >/dev/null 2>&1; then ENTERPRISE_DB_VOLUME_EXISTS="true"; fi
if "${DOCKER[@]}" volume inspect odoo19-dual_pgadmin-data >/dev/null 2>&1; then PGADMIN_VOLUME_EXISTS="true"; fi
if [[ ! -f .env &&
      ( "$COMMUNITY_DB_VOLUME_EXISTS" == "true" || "$ENTERPRISE_DB_VOLUME_EXISTS" == "true" || "$PGADMIN_VOLUME_EXISTS" == "true" ) ]]; then
  echo "Existing installer data volumes were found, but .env is missing. Restore .env from backup; generated replacement credentials would not unlock the existing data."
  exit 1
fi

mkdir -p config/community config/enterprise config/pgadmin addons/community addons/enterprise addons/enterprise-custom

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
  suggested_path="${suggested_path:-$SCRIPT_DIR/enterprise-19.0}"
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
      echo "The web_enterprise module was not found. Please select a complete Odoo 19 Enterprise addon folder."
      continue
    fi
    ENTERPRISE_SOURCE="$entered_path"
    return
  done
}

section "3/6" "Prepare the selected Odoo edition"
ENTERPRISE_SOURCE=""
BUNDLED_ENTERPRISE_SOURCE=""
for candidate in \
  "$ODOO_HOST_ENTERPRISE_DIR" \
  "$SCRIPT_DIR/addons/enterprise" \
  "$SCRIPT_DIR/enterprise-19.0" \
  "$SCRIPT_DIR/enterprise"; do
  if has_enterprise_addons "$candidate" && [[ -f "$candidate/web_enterprise/__manifest__.py" ]]; then
    BUNDLED_ENTERPRISE_SOURCE="$candidate"
    break
  fi
done

if [[ "$START_ENTERPRISE" == "true" ]]; then
  if has_enterprise_addons "$ODOO_HOST_ENTERPRISE_DIR" &&
     [[ -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]; then
    echo "Reusing the complete Enterprise addons already installed in $ODOO_HOST_ENTERPRISE_DIR."
  elif [[ -n "$BUNDLED_ENTERPRISE_SOURCE" ]]; then
    ENTERPRISE_SOURCE="$BUNDLED_ENTERPRISE_SOURCE"
    echo "Complete Enterprise addons were detected automatically:"
    printf '  %b%s%b\n' "$COLOR_GREEN" "$ENTERPRISE_SOURCE" "$COLOR_RESET"
  else
    echo "Enterprise requires your licensed Odoo 19 Enterprise addon folder."
    read_enterprise_source ""
  fi
else
  echo "Community-only installation selected; no licensed Enterprise files are required."
fi

if [[ "$START_ENTERPRISE" == "true" ]]; then
  while true; do
    read -r -p "Enterprise web port [8070]: " ENTERPRISE_PORT
    ENTERPRISE_PORT="${ENTERPRISE_PORT:-8070}"
    if ! valid_port "$ENTERPRISE_PORT"; then
      echo "Please enter a port number from 1 to 65535."
      continue
    fi
    ENTERPRISE_PORT="$((10#$ENTERPRISE_PORT))"
    if [[ "$START_COMMUNITY" == "true" && "$COMMUNITY_PORT" == "$ENTERPRISE_PORT" ]]; then
      echo "Community and Enterprise need different web ports."
      continue
    fi
    break
  done
fi

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

ODOO_IMAGE="odoo:19.0-20260908"
POSTGRES_IMAGE="postgres:15.19"
PGADMIN_IMAGE="dpage/pgadmin4:9.17"
PGADMIN_ENABLED="false"
PGADMIN_PORT="5050"
PGADMIN_EMAIL="admin@example.com"
PGADMIN_CREDENTIALS_MISSING="false"
SAVED_PERFORMANCE_MODE=""
SAVED_COMMUNITY_EXPECTED_USERS=""
SAVED_ENTERPRISE_EXPECTED_USERS=""
SAVED_COMMUNITY_WORKERS=""
SAVED_ENTERPRISE_WORKERS=""
SAVED_ODOO_MAX_CRON_THREADS=""
SAVED_ODOO_LIMIT_MEMORY_SOFT=""
SAVED_ODOO_LIMIT_MEMORY_HARD=""
SAVED_CUSTOM_ADDONS_PATH=""
if [[ -f .env ]]; then
  COMMUNITY_DB_PASSWORD="$(get_env_value COMMUNITY_DB_PASSWORD)"
  ENTERPRISE_DB_PASSWORD="$(get_env_value ENTERPRISE_DB_PASSWORD)"
  if [[ -z "$COMMUNITY_DB_PASSWORD" || -z "$ENTERPRISE_DB_PASSWORD" ]]; then
    echo "The existing .env file is missing a database password. It was not overwritten because existing Docker volumes may still depend on it."
    exit 1
  fi
  COMMUNITY_ADMIN_PASSWORD="$(get_env_value COMMUNITY_ADMIN_PASSWORD)"
  ENTERPRISE_ADMIN_PASSWORD="$(get_env_value ENTERPRISE_ADMIN_PASSWORD)"
  COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(get_config_value config/community/odoo.conf admin_passwd)}"
  ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(get_config_value config/enterprise/odoo.conf admin_passwd)}"
  COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  ODOO_IMAGE="$(get_env_value ODOO_IMAGE)"
  POSTGRES_IMAGE="$(get_env_value POSTGRES_IMAGE)"
  ODOO_IMAGE="${ODOO_IMAGE:-odoo:19.0-20260908}"
  POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15.19}"
  SAVED_PGADMIN_IMAGE="$(get_env_value PGADMIN_IMAGE)"
  SAVED_PGADMIN_ENABLED="$(get_env_value PGADMIN_ENABLED)"
  SAVED_PGADMIN_PORT="$(get_env_value PGADMIN_PORT)"
  SAVED_PGADMIN_EMAIL="$(get_env_value PGADMIN_EMAIL)"
  SAVED_PGADMIN_PASSWORD="$(get_env_value PGADMIN_PASSWORD)"
  SAVED_PERFORMANCE_MODE="$(get_env_value PERFORMANCE_MODE)"
  SAVED_COMMUNITY_EXPECTED_USERS="$(get_env_value COMMUNITY_EXPECTED_USERS)"
  SAVED_ENTERPRISE_EXPECTED_USERS="$(get_env_value ENTERPRISE_EXPECTED_USERS)"
  SAVED_COMMUNITY_WORKERS="$(get_env_value COMMUNITY_WORKERS)"
  SAVED_ENTERPRISE_WORKERS="$(get_env_value ENTERPRISE_WORKERS)"
  SAVED_ODOO_MAX_CRON_THREADS="$(get_env_value ODOO_MAX_CRON_THREADS)"
  SAVED_ODOO_LIMIT_MEMORY_SOFT="$(get_env_value ODOO_LIMIT_MEMORY_SOFT)"
  SAVED_ODOO_LIMIT_MEMORY_HARD="$(get_env_value ODOO_LIMIT_MEMORY_HARD)"
  SAVED_CUSTOM_ADDONS_PATH="$(get_env_value COMMUNITY_CUSTOM_ADDONS_PATH)"
  SAVED_CUSTOM_ADDONS_PATH="${SAVED_CUSTOM_ADDONS_PATH:-$(get_env_value ENTERPRISE_CUSTOM_ADDONS_PATH)}"
  PGADMIN_IMAGE="${SAVED_PGADMIN_IMAGE:-$PGADMIN_IMAGE}"
  if [[ "$SAVED_PGADMIN_ENABLED" == "true" ]]; then PGADMIN_ENABLED="true"; fi
  PGADMIN_PORT="${SAVED_PGADMIN_PORT:-$PGADMIN_PORT}"
  PGADMIN_EMAIL="${SAVED_PGADMIN_EMAIL:-$PGADMIN_EMAIL}"
  if [[ "$PGADMIN_VOLUME_EXISTS" == "true" &&
        ( -z "$SAVED_PGADMIN_EMAIL" || -z "$SAVED_PGADMIN_PASSWORD" ) ]]; then
    PGADMIN_CREDENTIALS_MISSING="true"
  fi
  PGADMIN_PASSWORD="${SAVED_PGADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  echo "Existing installation detected; database and Odoo master passwords will be reused."
else
  COMMUNITY_DB_PASSWORD="$(openssl rand -hex 24)"
  ENTERPRISE_DB_PASSWORD="$(openssl rand -hex 24)"
  COMMUNITY_ADMIN_PASSWORD="$(openssl rand -hex 24)"
  ENTERPRISE_ADMIN_PASSWORD="$(openssl rand -hex 24)"
  PGADMIN_PASSWORD="$(openssl rand -hex 24)"
fi

configure_custom_addons_directory "$SAVED_CUSTOM_ADDONS_PATH"
configure_performance_profile

section "4/6" "Choose optional pgAdmin"
echo "pgAdmin is an optional browser-based database manager."
echo "Odoo works normally without it."
if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  if ask_yes_no "Keep pgAdmin enabled? [Y/n]: " "y"; then
    PGADMIN_ENABLED="true"
  else
    PGADMIN_ENABLED="false"
  fi
else
  if ask_yes_no "Add pgAdmin to this installation? [y/N]: " "n"; then
    PGADMIN_ENABLED="true"
  else
    PGADMIN_ENABLED="false"
  fi
fi

if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  if [[ "$PGADMIN_CREDENTIALS_MISSING" == "true" ]]; then
    echo "The existing pgAdmin data volume was found, but its saved login credentials are missing from .env. Restore .env from backup before enabling pgAdmin."
    exit 1
  fi
  while true; do
    read -r -p "pgAdmin web port [$PGADMIN_PORT]: " PGADMIN_PORT_INPUT
    PGADMIN_PORT="${PGADMIN_PORT_INPUT:-$PGADMIN_PORT}"
    if ! valid_port "$PGADMIN_PORT"; then
      echo "Please enter a port number from 1 to 65535."
      continue
    fi
    PGADMIN_PORT="$((10#$PGADMIN_PORT))"
    if [[ ( "$START_COMMUNITY" == "true" && "$PGADMIN_PORT" == "$COMMUNITY_PORT" ) ||
          ( "$START_ENTERPRISE" == "true" && "$PGADMIN_PORT" == "$ENTERPRISE_PORT" ) ]]; then
      echo "The pgAdmin port must be different from the enabled Odoo web ports."
      continue
    fi
    break
  done
  if [[ "$PGADMIN_VOLUME_EXISTS" == "true" ]]; then
    echo "Reusing existing pgAdmin login email: $PGADMIN_EMAIL"
  else
    echo "This email is used only to sign in to the local pgAdmin web page."
    while true; do
      read -r -p "pgAdmin login email [$PGADMIN_EMAIL]: " PGADMIN_EMAIL_INPUT
      PGADMIN_EMAIL="${PGADMIN_EMAIL_INPUT:-$PGADMIN_EMAIL}"
      if [[ "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then break; fi
      echo "Please enter a valid email address, for example admin@example.com."
    done
  fi
  if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "The saved pgAdmin login email is invalid. Correct PGADMIN_EMAIL in .env, then rerun the installer."
    exit 1
  fi
fi

if ! valid_port "$PGADMIN_PORT"; then PGADMIN_PORT="5050"; fi
if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then PGADMIN_EMAIL="admin@example.com"; fi
if [[ ! "$ODOO_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
      ! "$POSTGRES_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
      ! "$PGADMIN_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ]]; then
  echo "An image reference in .env is invalid."
  exit 1
fi

section "5/6" "Review the installation plan"
printf '  %-24s %s\n' "Profile" "$DEPLOYMENT_MODE"
printf '  %-24s %s\n' "Performance mode" "$PERFORMANCE_MODE"
if [[ "$START_COMMUNITY" == "true" ]]; then
  printf '  %-24s %s\n' "Community" "enabled on port $COMMUNITY_PORT"
  printf '  %-24s %s\n' "Community custom addons" "$ODOO_HOST_CUSTOM_ADDONS_DIR"
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    printf '  %-24s %s\n' "Community workers" "$COMMUNITY_WORKERS (~$((COMMUNITY_WORKERS * 6)) simultaneous users)"
  else
    printf '  %-24s %s\n' "Community server" "threaded testing mode (workers = 0)"
  fi
else
  printf '  %-24s %s\n' "Community" "not selected"
fi
if [[ "$START_ENTERPRISE" == "true" ]]; then
  printf '  %-24s %s\n' "Enterprise" "enabled on port $ENTERPRISE_PORT"
  printf '  %-24s %s\n' "Enterprise storage" "$ODOO_HOST_ENTERPRISE_DIR"
  printf '  %-24s %s\n' "Enterprise custom addons" "$ODOO_HOST_CUSTOM_ADDONS_DIR"
  if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
    printf '  %-24s %s\n' "Enterprise workers" "$ENTERPRISE_WORKERS (~$((ENTERPRISE_WORKERS * 6)) simultaneous users)"
  else
    printf '  %-24s %s\n' "Enterprise server" "threaded testing mode (workers = 0)"
  fi
  if [[ -n "$ENTERPRISE_SOURCE" ]]; then
    printf '  %-24s %s\n' "Enterprise addons" "import from $ENTERPRISE_SOURCE"
  else
    printf '  %-24s %s\n' "Enterprise addons" "reuse installed addons"
  fi
else
  printf '  %-24s %s\n' "Enterprise" "not selected"
fi
if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  printf '  %-24s %s\n' "pgAdmin" "enabled on port $PGADMIN_PORT"
  printf '  %-24s %s\n' "pgAdmin login" "$PGADMIN_EMAIL"
else
  printf '  %-24s %s\n' "pgAdmin" "not selected"
fi
printf '  %-24s %s\n' "Cron threads" "$ODOO_MAX_CRON_THREADS per selected edition"
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  printf '  %-24s %s\n' "Worker memory limits" "$((ODOO_LIMIT_MEMORY_SOFT / 1024 / 1024)) MiB soft / $((ODOO_LIMIT_MEMORY_HARD / 1024 / 1024)) MiB hard"
fi
printf '  %-24s %s\n' "Automatic restart" "enabled"
echo
if ! ask_yes_no "Start this installation now? [Y/n]: " "y"; then
  echo "Installation cancelled. No Odoo configuration or Enterprise addons were changed."
  exit 0
fi

prepare_persistent_addons_layout
migrate_legacy_custom_addons

if [[ -n "$ENTERPRISE_SOURCE" &&
      "$(realpath "$ENTERPRISE_SOURCE")" != "$(realpath "$ODOO_HOST_ENTERPRISE_DIR")" ]]; then
  echo "Copying Enterprise addons into $ODOO_HOST_ENTERPRISE_DIR. This may take a moment..."
  cp -a "$ENTERPRISE_SOURCE"/. "$ODOO_HOST_ENTERPRISE_DIR/"
fi
sudo chmod -R u+rwX,go+rX "$ODOO_HOST_CUSTOM_ADDONS_DIR"
if [[ "$START_ENTERPRISE" == "true" ]]; then
  sudo chmod -R u+rwX,go+rX "$ODOO_HOST_ENTERPRISE_DIR"
fi

echo "Generating private configuration and credentials..."

umask 077
cat > .env <<EOF
ODOO_IMAGE=$ODOO_IMAGE
POSTGRES_IMAGE=$POSTGRES_IMAGE
PGADMIN_IMAGE=$PGADMIN_IMAGE
COMMUNITY_PORT=$COMMUNITY_PORT
ENTERPRISE_PORT=$ENTERPRISE_PORT
COMMUNITY_DB_PASSWORD=$COMMUNITY_DB_PASSWORD
ENTERPRISE_DB_PASSWORD=$ENTERPRISE_DB_PASSWORD
COMMUNITY_ADMIN_PASSWORD=$COMMUNITY_ADMIN_PASSWORD
ENTERPRISE_ADMIN_PASSWORD=$ENTERPRISE_ADMIN_PASSWORD
PGADMIN_ENABLED=$PGADMIN_ENABLED
PGADMIN_PORT=$PGADMIN_PORT
PGADMIN_EMAIL=$PGADMIN_EMAIL
PGADMIN_PASSWORD=$PGADMIN_PASSWORD
PERFORMANCE_MODE=$PERFORMANCE_MODE
COMMUNITY_EXPECTED_USERS=$COMMUNITY_EXPECTED_USERS
ENTERPRISE_EXPECTED_USERS=$ENTERPRISE_EXPECTED_USERS
COMMUNITY_WORKERS=$COMMUNITY_WORKERS
ENTERPRISE_WORKERS=$ENTERPRISE_WORKERS
ODOO_MAX_CRON_THREADS=$ODOO_MAX_CRON_THREADS
ODOO_LIMIT_MEMORY_SOFT=$ODOO_LIMIT_MEMORY_SOFT
ODOO_LIMIT_MEMORY_HARD=$ODOO_LIMIT_MEMORY_HARD
COMMUNITY_CUSTOM_ADDONS_PATH=$ODOO_HOST_CUSTOM_ADDONS_DIR
ENTERPRISE_ADDONS_PATH=$ODOO_HOST_ENTERPRISE_DIR
ENTERPRISE_CUSTOM_ADDONS_PATH=$ODOO_HOST_CUSTOM_ADDONS_DIR
EOF

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
write_config config/community/odoo.conf db-community "$COMMUNITY_DB_PASSWORD" "$COMMUNITY_ADMIN_PASSWORD" \
  "/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons" \
  "$COMMUNITY_WORKERS" "$ODOO_MAX_CRON_THREADS" "$ODOO_LIMIT_MEMORY_SOFT" "$ODOO_LIMIT_MEMORY_HARD"
write_config config/enterprise/odoo.conf db-enterprise "$ENTERPRISE_DB_PASSWORD" "$ENTERPRISE_ADMIN_PASSWORD" \
  "/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons" \
  "$ENTERPRISE_WORKERS" "$ODOO_MAX_CRON_THREADS" "$ODOO_LIMIT_MEMORY_SOFT" "$ODOO_LIMIT_MEMORY_HARD"

if [[ "$START_COMMUNITY" == "true" && "$START_ENTERPRISE" == "true" ]]; then
  cat > config/pgadmin/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Odoo 19 Community PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    },
    "2": {
      "Name": "Odoo 19 Enterprise PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-enterprise",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
elif [[ "$START_ENTERPRISE" == "true" ]]; then
  cat > config/pgadmin/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Odoo 19 Enterprise PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-enterprise",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
else
  cat > config/pgadmin/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Odoo 19 Community PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
fi
cat > config/pgadmin/pgpass <<EOF
db-community:5432:*:odoo:$COMMUNITY_DB_PASSWORD
db-enterprise:5432:*:odoo:$ENTERPRISE_DB_PASSWORD
EOF
chmod 600 .env config/community/odoo.conf config/enterprise/odoo.conf config/pgadmin/servers.json config/pgadmin/pgpass

COMPOSE_PROFILE=()
if [[ "$PGADMIN_ENABLED" == "true" ]]; then COMPOSE_PROFILE=(--profile pgadmin); fi
echo "Downloading the required Docker images..."
"${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" pull

# Keep the configuration private from other host users while making it readable
# by the non-root odoo user in the official container image.
ODOO_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$ODOO_IMAGE" -g)"
if [[ "$ODOO_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
  sudo chgrp "$ODOO_CONTAINER_GID" config/community/odoo.conf config/enterprise/odoo.conf
  chmod 640 config/community/odoo.conf config/enterprise/odoo.conf
fi
if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
    -v "$SCRIPT_DIR/config/community/odoo.conf:/tmp/odoo.conf:ro" \
    "$ODOO_IMAGE" -c 'test -r /tmp/odoo.conf'; then
  echo "Warning: using mode 644 for Odoo configuration because this Docker setup remaps container users."
  chmod 644 config/community/odoo.conf config/enterprise/odoo.conf
fi

if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
      -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
      "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
    PGADMIN_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$PGADMIN_IMAGE" -g)"
    if [[ ! "$PGADMIN_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
      echo "Could not determine the pgAdmin container group."
      exit 1
    fi
    sudo chgrp "$PGADMIN_CONTAINER_GID" config/pgadmin/servers.json config/pgadmin/pgpass
    chmod 640 config/pgadmin/servers.json config/pgadmin/pgpass
    if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
        -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
        "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
      echo "pgAdmin cannot securely read its generated password file on this Docker setup."
      exit 1
    fi
  fi
fi

if [[ "$START_COMMUNITY" != "true" ]] &&
   { [[ -n "$("${DOCKER[@]}" compose ps -q community)" ]] ||
     [[ -n "$("${DOCKER[@]}" compose ps -q db-community)" ]]; }; then
  echo "Stopping the previously running Community services because they were not selected..."
  "${DOCKER[@]}" compose stop community db-community
fi
if [[ "$START_ENTERPRISE" != "true" ]] &&
   { [[ -n "$("${DOCKER[@]}" compose ps -q enterprise)" ]] ||
     [[ -n "$("${DOCKER[@]}" compose ps -q db-enterprise)" ]]; }; then
  echo "Stopping the previously running Enterprise services because they were not selected..."
  "${DOCKER[@]}" compose stop enterprise db-enterprise
fi
if [[ "$PGADMIN_ENABLED" != "true" ]] &&
   [[ -n "$("${DOCKER[@]}" compose --profile pgadmin ps -q pgadmin)" ]]; then
  echo "Stopping pgAdmin because it was not selected..."
  "${DOCKER[@]}" compose --profile pgadmin stop pgadmin
fi
START_SERVICES=()
if [[ "$START_COMMUNITY" == "true" ]]; then START_SERVICES+=(db-community community); fi
if [[ "$START_ENTERPRISE" == "true" ]]; then START_SERVICES+=(db-enterprise enterprise); fi
if [[ "$PGADMIN_ENABLED" == "true" ]]; then START_SERVICES+=(pgadmin); fi
"${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" up -d --wait --wait-timeout 300 "${START_SERVICES[@]}"

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q '^Status: active'; then
  if [[ "$START_COMMUNITY" == "true" ]]; then
    sudo ufw allow "${COMMUNITY_PORT}/tcp"
  fi
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    sudo ufw allow "${ENTERPRISE_PORT}/tcp"
  fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    sudo ufw allow "${PGADMIN_PORT}/tcp"
  fi
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
HOST_IP="${HOST_IP:-127.0.0.1}"
if [[ -e installation-info.txt ]]; then
  chmod 600 installation-info.txt
fi
(
umask 077
{
cat <<EOF
Mode: $DEPLOYMENT_MODE
Performance mode: $PERFORMANCE_MODE
Detected hardware: $SYSTEM_SPEC_SUMMARY
Cron threads per selected edition: $ODOO_MAX_CRON_THREADS
Automatic startup: enabled (Docker at boot; containers restart unless manually stopped)
EOF
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
cat <<EOF
Worker memory limits: $((ODOO_LIMIT_MEMORY_SOFT / 1024 / 1024)) MiB soft / $((ODOO_LIMIT_MEMORY_HARD / 1024 / 1024)) MiB hard
EOF
fi
if [[ "$START_COMMUNITY" == "true" ]]; then
cat <<EOF
Community: http://$HOST_IP:$COMMUNITY_PORT
Community Odoo master password: $COMMUNITY_ADMIN_PASSWORD
EOF
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
cat <<EOF
Community expected simultaneous users: $COMMUNITY_EXPECTED_USERS
Community workers: $COMMUNITY_WORKERS (estimated $((COMMUNITY_WORKERS * 6)) simultaneous users)
EOF
else
  echo "Community server: threaded testing mode (workers = 0)"
fi
else
  echo "Community: not started"
fi
if [[ "$START_ENTERPRISE" == "true" ]]; then
cat <<EOF
Enterprise: http://$HOST_IP:$ENTERPRISE_PORT
Enterprise Odoo master password: $ENTERPRISE_ADMIN_PASSWORD
EOF
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
cat <<EOF
Enterprise expected simultaneous users: $ENTERPRISE_EXPECTED_USERS
Enterprise workers: $ENTERPRISE_WORKERS (estimated $((ENTERPRISE_WORKERS * 6)) simultaneous users)
EOF
else
  echo "Enterprise server: threaded testing mode (workers = 0)"
fi
else
  echo "Enterprise: not started"
fi
if [[ "$PGADMIN_ENABLED" == "true" ]]; then
cat <<EOF
pgAdmin: http://$HOST_IP:$PGADMIN_PORT
pgAdmin login email: $PGADMIN_EMAIL
pgAdmin login password: $PGADMIN_PASSWORD
EOF
else
  echo "pgAdmin: not started"
fi
cat <<EOF
Odoo image: $ODOO_IMAGE
PostgreSQL image: $POSTGRES_IMAGE
Enterprise addons path: $ODOO_HOST_ENTERPRISE_DIR
Shared custom addons path: $ODOO_HOST_CUSTOM_ADDONS_DIR
EOF
if [[ "$PGADMIN_ENABLED" == "true" ]]; then echo "pgAdmin image: $PGADMIN_IMAGE"; fi
} > installation-info.txt
)
chmod 600 .env installation-info.txt

section "6/6" "Installation complete"
cat installation-info.txt
echo
echo "Next steps:"
if [[ "$START_COMMUNITY" == "true" ]]; then
  echo "  - Open the Community URL and use its master password on the database creation page."
fi
if [[ "$START_ENTERPRISE" == "true" ]]; then
  echo "  - Open the Enterprise URL and use its master password on the database creation page."
fi
if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  echo "  - Sign in to pgAdmin with the email and password shown above."
fi
echo "Credentials are stored in $SCRIPT_DIR/installation-info.txt (owner-readable only)."
echo "Place custom modules in $ODOO_HOST_CUSTOM_ADDONS_DIR, then update the Apps list in Odoo."
