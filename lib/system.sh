#!/usr/bin/env bash
# Sourced by install-ubuntu.sh -- not meant to run standalone.

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

refresh_prerequisite_status() {
  if package_installed ca-certificates; then HAS_CA_CERTIFICATES="true"; else HAS_CA_CERTIFICATES="false"; fi
  if command -v curl >/dev/null 2>&1; then HAS_CURL="true"; else HAS_CURL="false"; fi
  if command -v openssl >/dev/null 2>&1; then HAS_OPENSSL="true"; else HAS_OPENSSL="false"; fi
  if command -v docker >/dev/null 2>&1; then HAS_DOCKER_CLI="true"; else HAS_DOCKER_CLI="false"; fi
  if command -v dockerd >/dev/null 2>&1; then HAS_DOCKER_ENGINE="true"; else HAS_DOCKER_ENGINE="false"; fi
  # The client can remain installed after Docker Desktop/Engine is removed.
  # A stopped Engine is still installed and should be started, not reinstalled.
  HAS_DOCKER="false"
  if [[ "$HAS_DOCKER_CLI" == "true" && "$HAS_DOCKER_ENGINE" == "true" ]]; then
    HAS_DOCKER="true"
  fi
  if [[ "$HAS_DOCKER_CLI" == "true" ]] && docker compose version >/dev/null 2>&1; then
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
  printf '  %-28s %s\n' "Docker CLI (client only)" "$(status_word "$HAS_DOCKER_CLI")"
  printf '  %-28s %s\n' "Local Docker Engine" "$(status_word "$HAS_DOCKER_ENGINE")"
  printf '  %-28s %s\n' "Docker Compose plugin" "$(status_word "$HAS_COMPOSE")"
  if systemctl is-active --quiet docker.service 2>/dev/null; then
    printf '  %-28s %s\n' "Docker system service" "RUNNING"
  elif systemctl cat docker.service >/dev/null 2>&1; then
    printf '  %-28s %s\n' "Docker system service" "STOPPED OR INACCESSIBLE"
  else
    printf '  %-28s %s\n' "Docker system service" "NOT FOUND OR INACCESSIBLE"
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

enterprise_addons_ready() {
  [[ -f "$SCRIPT_DIR/enterprise-19.0/web_enterprise/__manifest__.py" ||
     -f "$SCRIPT_DIR/enterprise/web_enterprise/__manifest__.py" ||
     -f "$SCRIPT_DIR/addons/enterprise/web_enterprise/__manifest__.py" ||
     -f "$ODOO_HOST_ENTERPRISE_DIR/web_enterprise/__manifest__.py" ]]
}

resolve_install_docker_endpoint() {
  local context endpoint
  context="$(docker context show)" || return 1
  if [[ -z "${DOCKER_CONTEXT:-}" && -n "${DOCKER_HOST:-}" ]]; then
    context=""
    endpoint="$DOCKER_HOST"
  else
    endpoint="$(docker context inspect "$context" --format '{{.Endpoints.docker.Host}}')" || return 1
  fi
  if [[ "$context" == desktop-* || "$endpoint" == *'/desktop/'* || "$endpoint" == *'/docker-desktop/'* ]]; then
    echo "Docker Desktop is not supported by the Ubuntu installer."
    echo "It runs Docker in a VM and may deny access to $ODOO_HOST_ROOT."
    echo "Use native Docker Engine on this Ubuntu host. Review 'docker context ls',"
    echo "unset DOCKER_HOST and DOCKER_CONTEXT overrides, then explicitly select the local Engine context."
    echo "Contexts have separate containers and volumes; existing Desktop data is not migrated automatically."
    return 1
  fi
  if [[ "$endpoint" != unix:///* ]]; then
    echo "The Ubuntu installer requires a local Docker Engine reached through a Unix socket."
    echo "Remote/TCP Docker endpoints cannot be used with this installer's local addon and configuration paths."
    echo "Review 'docker context ls' and DOCKER_HOST/DOCKER_CONTEXT, then select the intended local Engine."
    return 1
  fi
  # Pin the endpoint so sudo cannot silently select a different daemon/context.
  INSTALL_DOCKER_ENDPOINT="$endpoint"
}

select_ubuntu_docker_runtime() {
  local desktop_available="false"

  if command -v docker >/dev/null 2>&1 &&
     docker context inspect desktop-linux >/dev/null 2>&1; then
    desktop_available="true"
  elif command -v docker-desktop >/dev/null 2>&1 ||
       command -v com.docker.cli >/dev/null 2>&1 ||
       dpkg-query -W -f='${Status}' docker-desktop 2>/dev/null | grep -q 'ok installed'; then
    desktop_available="true"
  fi

  echo
  echo "Docker runtime for this Ubuntu deployment"
  echo "  1) Native Docker Engine (supported and recommended)"
  echo "  2) Docker Desktop (skip native installation and exit)"
  if [[ "$desktop_available" == "true" ]]; then
    echo "Docker Desktop was detected. Its containers and volumes are separate from native Docker Engine."
  fi
  echo "This Ubuntu installer deploys Odoo only with Native Docker Engine."
  read_choice DOCKER_RUNTIME_CHOICE "Choose a runtime [1]: " "1" "1 2 native desktop"

  case "${DOCKER_RUNTIME_CHOICE,,}" in
    1|native)
      INSTALLER_DOCKER_RUNTIME="native"
      ;;
    2|desktop)
      echo "Docker Desktop was selected. Native Docker Engine will not be installed or used."
      echo "This Ubuntu installer cannot continue with Docker Desktop because it requires native host bind mounts."
      echo "Use Docker Desktop separately, or rerun this installer and select Native Docker Engine."
      exit 0
      ;;
  esac
}

activate_native_docker_context() {
  local endpoint

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI is unavailable; Native Docker Engine cannot be selected."
    return 1
  fi

  endpoint="$(env -u DOCKER_HOST -u DOCKER_CONTEXT docker context inspect default --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  if [[ "$endpoint" != unix:///var/run/docker.sock ]]; then
    echo "The default Docker context does not point to the local Native Docker Engine."
    echo "Expected unix:///var/run/docker.sock, got ${endpoint:-an unavailable endpoint}."
    return 1
  fi

  if ! env -u DOCKER_HOST -u DOCKER_CONTEXT docker context use default >/dev/null; then
    echo "Could not make the Native Docker Engine the default Docker context."
    return 1
  fi

  INSTALL_DOCKER_ENDPOINT="$endpoint"
  echo "Native Docker Engine is now the default Docker context."
  if [[ -n "${DOCKER_HOST:-}" || -n "${DOCKER_CONTEXT:-}" ]]; then
    echo "This shell has a Docker endpoint override; the installer will still pin native Docker directly."
  fi
}

verify_install_docker_engine() {
  local identity
  identity="$("${DOCKER[@]}" info --format '{{.OSType}}|{{.OperatingSystem}}|{{.Name}}')" || return 1
  if [[ "$identity" != linux\|* || "${identity,,}" == *'docker desktop'* ||
        "${identity,,}" == *'docker-desktop'* ]]; then
    echo "The Ubuntu installer requires native Linux Docker Engine; this daemon is unsupported."
    echo "Select the intended local Engine explicitly. Existing containers and volumes are not migrated."
    return 1
  fi
}

verify_install_addon_mounts() {
  local -a mounts=(--mount "type=bind,source=$ODOO_HOST_CUSTOM_ADDONS_DIR,target=/mnt/extra-addons,readonly")
  local check='test -r /mnt/extra-addons && test -x /mnt/extra-addons'
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    mounts+=(--mount "type=bind,source=$ODOO_HOST_ENTERPRISE_DIR,target=/mnt/enterprise-addons,readonly")
    check+=' && test -r /mnt/enterprise-addons/web_enterprise/__manifest__.py'
  fi
  if ! "${DOCKER[@]}" run --rm --network none --entrypoint /bin/sh \
      "${mounts[@]}" "$ODOO_IMAGE" -c "$check"; then
    echo "Docker could not mount/read the required addons. Odoo services have not been started."
    echo "Check host directory permissions and Docker access to $ODOO_HOST_ROOT, then rerun the installer."
    return 1
  fi
}
