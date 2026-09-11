#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" ]] &&
   command -v clear >/dev/null 2>&1; then
  clear || true
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_PURPLE=$'\033[38;5;97m'
  COLOR_CYAN=$'\033[38;5;37m'
  COLOR_GREEN=$'\033[38;5;34m'
  COLOR_YELLOW=$'\033[38;5;214m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_PURPLE=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

print_banner() {
  printf '%b' "$COLOR_PURPLE$COLOR_BOLD"
  cat <<'EOF'

============================================================
             ODOO 19 DEPLOYMENT CONTROL CENTER
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

if [[ ! -r /etc/os-release ]]; then
  echo "Unsupported system: Ubuntu 22.04 or 24.04 is required."
  exit 1
fi
. /etc/os-release
if [[ "${ID}" != "ubuntu" || ( "${VERSION_ID}" != "22.04" && "${VERSION_ID}" != "24.04" ) ]]; then
  echo "Unsupported system: detected ${PRETTY_NAME:-unknown}."
  exit 1
fi

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
  install_apt_packages ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  APT_INDEX_READY="true"
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
        -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ]]; then
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
  printf '  %-22s %s\n' "Docker CLI" "$docker_status"
  printf '  %-22s %s\n' "Enterprise addons" "$enterprise_status"
  printf '  %-22s %s\n' "Installer state" "$installation_status"
  echo
  echo "Choose an action below. Press Enter for the recommended default."
}

run_uninstaller() {
  section "UNINSTALL" "Remove this Odoo installation"
  echo "Docker itself and your source-code folders will not be removed."

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed, so there are no Docker-based Odoo services to remove."
    return
  fi

  local docker_command=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
      docker_command=(sudo docker)
    else
      echo "Docker is installed but its engine is not running. Start Docker, then choose uninstall again."
      return
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
  echo "  1) Remove containers but keep databases and filestores (recommended)"
  echo "  2) Permanently delete containers, databases, filestores, and pgAdmin data"
  echo "  3) Cancel"
  local uninstall_choice confirmation
  read_choice uninstall_choice "Choose an uninstall option [1]: " "1" "1 2 3"

  case "$uninstall_choice" in
    1)
      "${docker_command[@]}" compose --profile pgadmin down
      echo
      printf '%b\n' "${COLOR_GREEN}Odoo containers were removed. Persistent data was kept.${COLOR_RESET}"
      echo "Run this installer again whenever you want to recreate the services."
      ;;
    2)
      printf '%b\n' "${COLOR_YELLOW}WARNING: This permanently deletes all installer-managed Docker data.${COLOR_RESET}"
      read -r -p "Type DELETE to confirm permanent data removal: " confirmation
      if [[ "$confirmation" != "DELETE" ]]; then
        echo "Permanent uninstall cancelled; nothing was removed."
        return
      fi
      "${docker_command[@]}" compose --profile pgadmin down --volumes
      rm -f .env installation-info.txt \
        config/community/odoo.conf config/enterprise/odoo.conf \
        config/pgadmin/servers.json config/pgadmin/pgpass
      echo
      printf '%b\n' "${COLOR_GREEN}Odoo containers and persistent Docker data were removed.${COLOR_RESET}"
      echo "Enterprise source, copied addons, and custom-addon folders were preserved."
      ;;
    3)
      echo "Uninstall cancelled; nothing was removed."
      ;;
  esac
}

show_control_center_status
section "MENU" "What would you like to do?"
menu_item "1" "Install Odoo Community only"
menu_item "2" "Install Odoo Enterprise only"
menu_item "3" "Install both Community and Enterprise"
menu_item "4" "Check Ubuntu updates and missing dependencies"
menu_item "5" "Uninstall Odoo"
menu_item "6" "Exit"
read_choice MAIN_CHOICE "Choose an option [1]: " "1" "1 2 3 4 5 6"

INSTALL_ACTION="install"
START_COMMUNITY="false"
START_ENTERPRISE="false"
case "$MAIN_CHOICE" in
  1) START_COMMUNITY="true" ;;
  2) START_ENTERPRISE="true" ;;
  3) START_COMMUNITY="true"; START_ENTERPRISE="true" ;;
  4) INSTALL_ACTION="dependencies" ;;
  5) run_uninstaller; exit 0 ;;
  6) echo "Goodbye."; exit 0 ;;
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
    [[ "$INSTALL_CA_CERTIFICATES" == "true" ]] && SUPPORT_PACKAGES+=(ca-certificates)
    [[ "$INSTALL_CURL" == "true" ]] && SUPPORT_PACKAGES+=(curl)
    [[ "$INSTALL_OPENSSL" == "true" ]] && SUPPORT_PACKAGES+=(openssl)
    if (( ${#SUPPORT_PACKAGES[@]} > 0 )); then install_apt_packages "${SUPPORT_PACKAGES[@]}"; fi
  else
    if [[ "$INSTALL_CA_CERTIFICATES" == "true" ]]; then install_apt_packages ca-certificates; fi
    if [[ "$INSTALL_CURL" == "true" ]]; then install_apt_packages curl; fi
    if [[ "$INSTALL_OPENSSL" == "true" ]]; then install_apt_packages openssl; fi
  fi

  if [[ "$INSTALL_DOCKER" == "true" || "$INSTALL_COMPOSE" == "true" ]]; then
    setup_docker_repository
  fi
  if [[ "$INSTALL_DOCKER" == "true" ]]; then
    echo "Installing Docker Engine..."
    install_apt_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    sudo usermod -aG docker "$USER"
  fi
  if [[ "$INSTALL_COMPOSE" == "true" ]]; then
    echo "Installing the Docker Compose plugin..."
    if ! install_apt_packages docker-compose-plugin; then
      echo "Docker Compose could not be installed. Check the Docker repository configuration, then rerun this installer."
      exit 1
    fi
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

section "2/6" "Choose how Odoo should run"
echo "Select a setup profile:"
echo "  1) Testing (recommended for evaluation and development)"
echo "  2) Production (enables two Odoo workers and memory limits)"
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
for candidate in "$SCRIPT_DIR/enterprise-19.0" "$SCRIPT_DIR/enterprise"; do
  if has_enterprise_addons "$candidate" && [[ -f "$candidate/web_enterprise/__manifest__.py" ]]; then
    BUNDLED_ENTERPRISE_SOURCE="$candidate"
    break
  fi
done

if [[ "$START_ENTERPRISE" == "true" ]]; then
  if has_enterprise_addons "$SCRIPT_DIR/addons/enterprise" &&
     [[ -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ]]; then
    echo "Reusing the complete Enterprise addons already installed in addons/enterprise."
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
if [[ "$START_COMMUNITY" == "true" ]]; then
  printf '  %-24s %s\n' "Community" "enabled on port $COMMUNITY_PORT"
else
  printf '  %-24s %s\n' "Community" "not selected"
fi
if [[ "$START_ENTERPRISE" == "true" ]]; then
  printf '  %-24s %s\n' "Enterprise" "enabled on port $ENTERPRISE_PORT"
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
printf '  %-24s %s\n' "Automatic restart" "enabled"
echo
if ! ask_yes_no "Start this installation now? [Y/n]: " "y"; then
  echo "Installation cancelled. No Odoo configuration or Enterprise addons were changed."
  exit 0
fi

if [[ -n "$ENTERPRISE_SOURCE" && "$(realpath "$ENTERPRISE_SOURCE")" != "$(realpath addons/enterprise)" ]]; then
  echo "Copying Enterprise addons into this installation. This may take a moment..."
  cp -a "$ENTERPRISE_SOURCE"/. addons/enterprise/
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
EOF

WORKERS="0"
LIMIT_MEMORY_HARD="0"
LIMIT_MEMORY_SOFT="0"
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  WORKERS="2"
  LIMIT_MEMORY_HARD="2684354560"
  LIMIT_MEMORY_SOFT="2147483648"
fi

write_config() {
  local target="$1" db_host="$2" db_password="$3" admin_password="$4" addons_path="$5"
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
workers = $WORKERS
max_cron_threads = 1
limit_memory_hard = $LIMIT_MEMORY_HARD
limit_memory_soft = $LIMIT_MEMORY_SOFT
EOF
}
write_config config/community/odoo.conf db-community "$COMMUNITY_DB_PASSWORD" "$COMMUNITY_ADMIN_PASSWORD" "/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"
write_config config/enterprise/odoo.conf db-enterprise "$ENTERPRISE_DB_PASSWORD" "$ENTERPRISE_ADMIN_PASSWORD" "/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"

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
{
cat <<EOF
Mode: $DEPLOYMENT_MODE
Automatic startup: enabled (Docker at boot; containers restart unless manually stopped)
EOF
if [[ "$START_COMMUNITY" == "true" ]]; then
cat <<EOF
Community: http://$HOST_IP:$COMMUNITY_PORT
Community Odoo master password: $COMMUNITY_ADMIN_PASSWORD
EOF
else
  echo "Community: not started"
fi
if [[ "$START_ENTERPRISE" == "true" ]]; then
cat <<EOF
Enterprise: http://$HOST_IP:$ENTERPRISE_PORT
Enterprise Odoo master password: $ENTERPRISE_ADMIN_PASSWORD
EOF
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
EOF
if [[ "$PGADMIN_ENABLED" == "true" ]]; then echo "pgAdmin image: $PGADMIN_IMAGE"; fi
} > installation-info.txt
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
